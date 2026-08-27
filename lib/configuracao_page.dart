import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tema.dart';
import 'turso_service.dart';

/// Tela "Configuração do Banco" — mesmo padrão dos outros apps Flutter da
/// CAMDA (Gondolas): o próprio usuário digita Database URL e Token, com
/// botões "Salvar configuração" e "Testar conexão". As credenciais ficam
/// salvas localmente no dispositivo, nunca no repositório.
class ConfiguracaoPage extends StatefulWidget {
  const ConfiguracaoPage({super.key});

  @override
  State<ConfiguracaoPage> createState() => _ConfiguracaoPageState();
}

class _ConfiguracaoPageState extends State<ConfiguracaoPage> {
  final _urlCtrl   = TextEditingController();
  final _tokenCtrl = TextEditingController();

  bool    _testando      = false;
  String? _statusTeste;
  bool    _testeOk       = false;
  bool    _cacheLocal    = true;
  bool    _limpandoCache = false;
  int     _intervaloMin  = TursoService.intervaloPadraoMin;

  DiagnosticoEspelho? _diagnostico;

  @override
  void initState() {
    super.initState();
    _carregarCredenciais();
    _carregarDiagnostico();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarCredenciais() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text   = prefs.getString(TursoService.keyDbUrl)   ?? '';
      _tokenCtrl.text = prefs.getString(TursoService.keyDbToken) ?? '';
      _cacheLocal     = prefs.getBool(TursoService.keyCacheLocal) ?? true;
      _intervaloMin   = prefs.getInt(TursoService.keyIntervaloMin) ??
          TursoService.intervaloPadraoMin;
    });
  }

  Future<void> _carregarDiagnostico() async {
    final diag = await TursoService().diagnostico();
    if (!mounted) return;
    setState(() => _diagnostico = diag);
  }

  Future<void> _alterarCacheLocal(bool valor) async {
    setState(() => _cacheLocal = valor);
    await TursoService().definirCacheLocal(valor);
    if (mounted) setState(() {});
  }

  /// [completa] ignora as impressões digitais e rebaixa todas as tabelas —
  /// o caminho de quem desconfia que o número na tela está velho.
  Future<void> _sincronizarAgora({bool completa = false}) async {
    final servico = TursoService();
    if (servico.sincronizando.value) return;

    final resumo = await servico.sincronizar(completa: completa);
    await _carregarDiagnostico();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(resumo.mensagem),
      backgroundColor:
          resumo.ok ? const Color(0xFF2E6B46) : const Color(0xFF8B1A1A),
      duration: Duration(seconds: resumo.ok ? 2 : 6),
    ));
  }

  Future<void> _alterarIntervalo(int minutos) async {
    setState(() => _intervaloMin = minutos);
    await TursoService().definirIntervaloSync(minutos);
  }

  Future<void> _confirmarLimparCache() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TemaCamda.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(
          'Limpar cache local?',
          style: TemaCamda.textoStyle(tamanho: 15, peso: 600),
        ),
        content: Text(
          'Apaga o arquivo salvo neste dispositivo e baixa tudo de novo do '
          'banco online.\n\n'
          'Nada é perdido: o app só lê o estoque, então o arquivo local é '
          'sempre uma cópia do banco.',
          style: TemaCamda.textoStyle(
            tamanho: 13,
            cor: TemaCamda.textoFraco,
            altura: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TemaCamda.textoStyle(
                tamanho: 13,
                cor: TemaCamda.textoFraco,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Limpar e rebaixar',
              style: TemaCamda.textoStyle(
                tamanho: 13,
                cor: TemaCamda.vermelho,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmou == true) await _limparCacheLocal();
  }

  Future<void> _limparCacheLocal() async {
    setState(() => _limpandoCache = true);
    final servico = TursoService();
    final ok = await servico.limparCacheLocal();
    if (ok) await servico.init();
    await _carregarDiagnostico();
    if (!mounted) return;
    setState(() => _limpandoCache = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (servico.isConnected
              ? 'Cache local limpo — baixando do banco online ✓'
              : 'Cache local limpo — sem conexão para rebaixar agora')
          : 'Não foi possível limpar o cache local'),
      backgroundColor:
          ok ? const Color(0xFF2E6B46) : const Color(0xFF8B1A1A),
      duration: const Duration(seconds: 4),
    ));
  }

  String _textoUltimaSync() {
    final quando = TursoService().ultimaSincronizacao;
    if (quando == null) return 'Nunca atualizado';
    String dois(int n) => n.toString().padLeft(2, '0');
    return 'Última atualização: ${dois(quando.day)}/${dois(quando.month)}/'
        '${quando.year} ${dois(quando.hour)}:${dois(quando.minute)}';
  }

  static String _tempo(Duration d) {
    final s = d.inMilliseconds / 1000;
    return s < 10 ? '${s.toStringAsFixed(1)} s' : '${s.round()} s';
  }

  static String _tamanho(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  static String _rotuloIntervalo(int minutos) =>
      minutos <= 0 ? 'Desligado' : '$minutos min';

  Future<void> _salvarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(TursoService.keyDbUrl,   _urlCtrl.text.trim());
    await prefs.setString(TursoService.keyDbToken, _tokenCtrl.text.trim());
    // Reaplica as credenciais na conexão ativa.
    await TursoService().init();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuração salva'),
        backgroundColor: Color(0xFF2E6B46),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _testarConexao() async {
    setState(() {
      _testando    = true;
      _statusTeste = null;
    });

    final url   = _urlCtrl.text.trim();
    final token = _tokenCtrl.text.trim();

    if (url.isEmpty || token.isEmpty) {
      setState(() {
        _testando    = false;
        _statusTeste = 'Preencha URL e Token antes de testar.';
        _testeOk     = false;
      });
      return;
    }

    try {
      await TursoService.testarConexao(url, token);
      if (!mounted) return;
      setState(() {
        _testando    = false;
        _statusTeste = 'Conexão bem-sucedida ✓';
        _testeOk     = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testando    = false;
        _statusTeste = 'Erro: $e';
        _testeOk     = false;
      });
    }
  }

  /// Bloco de atualização do espelho: quando foi a última, quanto ela custou,
  /// os dois botões e de quanto em quanto tempo o app se atualiza sozinho.
  ///
  /// O estado de "atualizando" vem do serviço, não desta tela: a atualização
  /// roda em segundo plano e pode já estar no ar quando se entra aqui.
  Widget _blocoAtualizacao() {
    return ValueListenableBuilder<bool>(
      valueListenable: TursoService().sincronizando,
      builder: (context, sincronizando, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _textoUltimaSync(),
              style: TemaCamda.numeroStyle(
                tamanho: 11,
                cor: TemaCamda.textoFraco,
              ),
            ),
            if (TursoService().ultimoErroSync != null) ...[
              const SizedBox(height: 4),
              Text(
                'Última falha: ${TursoService().ultimoErroSync}',
                style: TemaCamda.textoStyle(
                  tamanho: 11,
                  cor: TemaCamda.vermelho,
                  altura: 1.3,
                ),
              ),
            ],
            _linhaDiagnostico(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: sincronizando ? null : () => _sincronizarAgora(),
                  icon: sincronizando
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF4A9D6A),
                          ),
                        )
                      : const Icon(Icons.sync, size: 15),
                  label: Text(sincronizando ? 'Atualizando...' : 'Atualizar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4A9D6A),
                    side: const BorderSide(color: Color(0xFF2E4A38)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: sincronizando
                      ? null
                      : () => _sincronizarAgora(completa: true),
                  icon: const Icon(Icons.cloud_download_outlined, size: 15),
                  label: const Text('Atualização completa'),
                  style: TextButton.styleFrom(
                    foregroundColor: TemaCamda.textoFraco,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Atualizar traz só o que mudou no banco. A completa rebaixa '
              'tudo — use quando desconfiar que o número na tela está velho.',
              style: TemaCamda.textoStyle(
                tamanho: 11,
                cor: TemaCamda.textoFraco,
                altura: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Atualizar sozinho',
              style: TemaCamda.textoStyle(tamanho: 12, peso: 600),
            ),
            const SizedBox(height: 2),
            Text(
              'Ao abrir o app e de tempos em tempos, em segundo plano. Sem '
              'novidade no banco, o app só confere e não baixa nada.',
              style: TemaCamda.textoStyle(
                tamanho: 11,
                cor: TemaCamda.textoFraco,
                altura: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutos in TursoService.intervalosDisponiveis)
                  ChoiceChip(
                    label: Text(_rotuloIntervalo(minutos)),
                    selected: _intervaloMin == minutos,
                    onSelected: (_) => _alterarIntervalo(minutos),
                    labelStyle: TemaCamda.textoStyle(
                      tamanho: 12,
                      cor: _intervaloMin == minutos
                          ? TemaCamda.texto
                          : TemaCamda.textoFraco,
                    ),
                    backgroundColor: TemaCamda.fundo,
                    selectedColor: const Color(0xFF1B3A2A),
                    side: BorderSide(
                      color: _intervaloMin == minutos
                          ? const Color(0xFF2E6B46)
                          : TemaCamda.borda,
                    ),
                    showCheckmark: false,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// O custo real da última atualização e o que o espelho guarda hoje. É com
  /// isto que dá para comparar o antes e o depois no próprio aparelho, sem PC
  /// nem ferramenta externa.
  Widget _linhaDiagnostico() {
    final diag = _diagnostico;
    if (diag == null) return const SizedBox.shrink();

    final custo = <String>[
      if (diag.ultimaDuracao != null) 'levou ${_tempo(diag.ultimaDuracao!)}',
      if (diag.bytes > 0) '${_tamanho(diag.bytes)} no aparelho',
    ];
    final porTabela = [
      for (final e in diag.linhas.entries) '${e.key} ${e.value}',
    ];
    if (custo.isEmpty && porTabela.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (custo.isNotEmpty)
            Text(
              custo.join(' · '),
              style: TemaCamda.numeroStyle(
                tamanho: 11,
                cor: TemaCamda.textoFraco,
              ),
            ),
          if (porTabela.isNotEmpty)
            Text(
              porTabela.join(' · '),
              style: TemaCamda.numeroStyle(
                tamanho: 10,
                cor: TemaCamda.textoFraco,
                altura: 1.6,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaCamda.fundo,
      appBar: AppBar(
        title: const Text('Configuração do Banco'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1A24),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1A3A50)),
              ),
              child: const Text(
                'Conexão direta via libsql_dart ao banco Turso CAMDA.\n'
                'As credenciais são salvas localmente no dispositivo.\n'
                'Este app é somente leitura — use um token read-only.',
                style: TextStyle(
                  color: Color(0xFF7A9AB8),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 28),

            _Campo(
              label: 'Database URL',
              controller: _urlCtrl,
              hint: 'libsql://camda-estoque-leolira1.aws-us-east-2.turso.io',
              obscure: false,
            ),
            const SizedBox(height: 16),

            _Campo(
              label: 'Token',
              controller: _tokenCtrl,
              hint: 'eyJ...',
              obscure: true,
            ),
            const SizedBox(height: 28),

            ElevatedButton.icon(
              onPressed: _salvarConfig,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Salvar configuração'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E6B46),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: _testando ? null : _testarConexao,
              icon: _testando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF4A9D6A),
                      ),
                    )
                  : const Icon(Icons.wifi_tethering_outlined, size: 16),
              label: Text(_testando ? 'Testando...' : 'Testar conexão'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4A9D6A),
                side: const BorderSide(color: Color(0xFF2E4A38)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

            // ── Cache local ─────────────────────────────────────────────
            // O arquivo guarda só as tabelas que o app consulta (ver
            // espelho.dart) — não a cópia do banco inteiro, que trazia junto
            // as fotos em base64 do camda-estoque a cada atualização.
            const SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TemaCamda.borda),
              ),
              child: Column(children: [
                SwitchListTile(
                  value: _cacheLocal,
                  onChanged: _alterarCacheLocal,
                  activeThumbColor: const Color(0xFF4A9D6A),
                  title: Text(
                    'Cache local',
                    style: TemaCamda.textoStyle(tamanho: 13),
                  ),
                  subtitle: Text(
                    'Guarda no aparelho uma cópia só do que o app consulta: '
                    'ele abre e responde na hora, mesmo com a internet ruim '
                    'do galpão. As novidades do banco entram sozinhas em '
                    'segundo plano, ou no botão Atualizar.',
                    style: TemaCamda.textoStyle(
                      tamanho: 11,
                      cor: TemaCamda.textoFraco,
                      altura: 1.4,
                    ),
                  ),
                ),
                if (_cacheLocal) _blocoAtualizacao(),
                if (_cacheLocal)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed:
                            _limpandoCache ? null : _confirmarLimparCache,
                        icon: _limpandoCache
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: TemaCamda.vermelho,
                                ),
                              )
                            : const Icon(Icons.delete_sweep_outlined, size: 15),
                        label: Text(
                          _limpandoCache ? 'Limpando...' : 'Limpar cache local',
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: TemaCamda.vermelho,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),

            if (_statusTeste != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testeOk
                      ? const Color(0xFF071A0E)
                      : const Color(0xFF1A0707),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testeOk
                        ? const Color(0xFF2E6B46)
                        : const Color(0xFF6B2E2E),
                  ),
                ),
                child: Text(
                  _statusTeste!,
                  style: TextStyle(
                    color: _testeOk
                        ? const Color(0xFF4A9D6A)
                        : TemaCamda.vermelho,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;

  const _Campo({
    required this.label,
    required this.controller,
    required this.hint,
    required this.obscure,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: TemaCamda.textoFraco,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF3A4A58),
              fontSize: 12,
            ),
            filled: true,
            fillColor: const Color(0xFF0D1117),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: TemaCamda.borda),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: TemaCamda.borda),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: Color(0xFF2E6B46), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}
