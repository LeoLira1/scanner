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
  bool    _sincronizando = false;
  bool    _limpandoCache = false;

  @override
  void initState() {
    super.initState();
    _carregarCredenciais();
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
    });
  }

  Future<void> _alterarCacheLocal(bool valor) async {
    setState(() => _cacheLocal = valor);
    await TursoService().definirCacheLocal(valor);
    if (mounted) setState(() {});
  }

  Future<void> _sincronizarAgora() async {
    setState(() => _sincronizando = true);
    final ok = await TursoService().sincronizar();
    if (!mounted) return;
    setState(() => _sincronizando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Sincronizado com o banco online ✓'
          : 'Não foi possível sincronizar — '
              '${TursoService().ultimoErroSync ?? 'verifique a conexão'}'),
      backgroundColor:
          ok ? const Color(0xFF2E6B46) : const Color(0xFF8B1A1A),
      duration: Duration(seconds: ok ? 2 : 6),
    ));
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
          'Apaga o arquivo de dados salvo neste dispositivo e baixa tudo '
          'de novo do banco online.\n\n'
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
    if (quando == null) return 'Nunca sincronizado';
    String dois(int n) => n.toString().padLeft(2, '0');
    return 'Última sincronização: ${dois(quando.day)}/${dois(quando.month)}/'
        '${quando.year} ${dois(quando.hour)}:${dois(quando.minute)}';
  }

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
                    'Guarda uma cópia dos dados num arquivo do dispositivo: '
                    'o app abre e responde na hora, mesmo com internet '
                    'ruim. Use Sincronizar para trazer as novidades do '
                    'banco online.',
                    style: TemaCamda.textoStyle(
                      tamanho: 11,
                      cor: TemaCamda.textoFraco,
                      altura: 1.4,
                    ),
                  ),
                ),
                if (_cacheLocal)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Row(children: [
                      Expanded(
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
                                'Última falha: '
                                '${TursoService().ultimoErroSync}',
                                style: TemaCamda.textoStyle(
                                  tamanho: 11,
                                  cor: TemaCamda.vermelho,
                                  altura: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _sincronizando ? null : _sincronizarAgora,
                        icon: _sincronizando
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF4A9D6A),
                                ),
                              )
                            : const Icon(Icons.sync, size: 15),
                        label: Text(
                          _sincronizando ? 'Sincronizando...' : 'Sincronizar',
                        ),
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
                    ]),
                  ),
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
