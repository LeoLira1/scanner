import 'package:flutter/material.dart';

import 'configuracao_page.dart';
import 'consulta.dart';
import 'estoque_service.dart';
import 'produto_page.dart';
import 'scanner_page.dart';
import 'tema.dart';
import 'turso_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _codigoCtrl = TextEditingController();

  bool    _configurado   = false;
  bool    _carregando    = true;
  bool    _consultando   = false;
  bool    _sincronizando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _verificarConfiguracao();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _verificarConfiguracao() async {
    final ok = await TursoService().credenciaisConfiguradas();
    if (!mounted) return;
    setState(() {
      _configurado = ok;
      _carregando  = false;
    });
  }

  Future<void> _abrirConfiguracao() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConfiguracaoPage()),
    );
    _verificarConfiguracao();
  }

  /// Sincronizar direto da tela principal: atualizar o cache é a operação
  /// do dia a dia (o estoque muda o tempo todo), não uma configuração —
  /// não faz sentido obrigar a entrar em ⚙️ para isso.
  Future<void> _sincronizar() async {
    if (_sincronizando) return;
    setState(() => _sincronizando = true);

    final servico = TursoService();
    final ok = await servico.sincronizar();

    if (!mounted) return;
    setState(() => _sincronizando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Sincronizado com o banco online ✓'
          : 'Não foi possível sincronizar — '
              '${servico.ultimoErroSync ?? 'verifique a conexão'}'),
      backgroundColor:
          ok ? const Color(0xFF2E6B46) : const Color(0xFF8B1A1A),
      duration: Duration(seconds: ok ? 2 : 6),
    ));
  }

  /// O toque abre o menu de acessibilidade/tooltip com a data da última
  /// sincronização — a informação que decide se vale sincronizar de novo.
  String _tooltipSync() {
    if (_sincronizando) return 'Sincronizando...';
    final quando = TursoService().ultimaSincronizacao;
    if (quando == null) return 'Sincronizar (nunca sincronizado)';
    String dois(int n) => n.toString().padLeft(2, '0');
    return 'Sincronizar — última: ${dois(quando.day)}/${dois(quando.month)} '
        '${dois(quando.hour)}:${dois(quando.minute)}';
  }

  Future<void> _abrirScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
  }

  /// Consulta a leitura (digitada agora; da câmera na Etapa 3) e abre a
  /// tela do produto.
  Future<void> _consultar(String leitura) async {
    if (_consultando) return;
    setState(() {
      _consultando = true;
      _erro        = null;
    });

    ResultadoConsulta? resultado;
    String? erro;
    try {
      resultado = await EstoqueService().consultarPorCodigo(leitura);
      if (resultado == null) {
        final codigo = extrairCodigo(leitura);
        erro = 'Código $codigo não encontrado no estoque.';
      }
    } on ConsultaException catch (e) {
      erro = e.mensagem;
    }

    if (!mounted) return;
    setState(() {
      _consultando = false;
      _erro        = erro;
    });

    final res = resultado;
    if (res != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProdutoPage(resultado: res)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaCamda.fundo,
      appBar: AppBar(
        title: const Text('Scanner CAMDA'),
        actions: [
          if (_configurado)
            IconButton(
              icon: _sincronizando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TemaCamda.verde,
                      ),
                    )
                  : const Icon(Icons.sync, size: 20),
              tooltip: _tooltipSync(),
              onPressed: _sincronizando ? null : _sincronizar,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configuração do Banco',
            onPressed: _abrirConfiguracao,
          ),
        ],
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: TemaCamda.laranja),
            )
          : _configurado
              ? _Busca(
                  codigoCtrl: _codigoCtrl,
                  consultando: _consultando,
                  erro: _erro,
                  onConsultar: _consultar,
                  onEscanear: _abrirScanner,
                )
              : _SemConfiguracao(onConfigurar: _abrirConfiguracao),
    );
  }
}

/// Busca: câmera em destaque + digitação manual sempre acessível — o
/// fallback quando o QR estiver sujo ou rasgado, e a forma de testar o app
/// inteiro sem câmera.
class _Busca extends StatelessWidget {
  const _Busca({
    required this.codigoCtrl,
    required this.consultando,
    required this.erro,
    required this.onConsultar,
    required this.onEscanear,
  });

  final TextEditingController codigoCtrl;
  final bool consultando;
  final String? erro;
  final void Function(String) onConsultar;
  final VoidCallback onEscanear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Caminho principal: apontar a câmera para a etiqueta.
              ElevatedButton.icon(
                onPressed: consultando ? null : onEscanear,
                icon: const Icon(Icons.qr_code_scanner, size: 22),
                label: Text(
                  'Escanear com a câmera',
                  style: TemaCamda.textoStyle(
                    tamanho: 15,
                    peso: 600,
                    cor: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemaCamda.laranja,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      TemaCamda.laranja.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 28),
              Row(
                children: [
                  const Expanded(child: Divider(color: TemaCamda.borda)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'ou digite o código',
                      style: TemaCamda.textoStyle(
                        tamanho: 12,
                        cor: TemaCamda.textoFraco,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: TemaCamda.borda)),
                ],
              ),
              const SizedBox(height: 22),

              TextField(
                controller: codigoCtrl,
                enabled: !consultando,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                style: TemaCamda.numeroStyle(tamanho: 22, espacamento: 2),
                onSubmitted: onConsultar,
                decoration: InputDecoration(
                  hintText: '254185 ou US254185',
                  hintStyle: TemaCamda.numeroStyle(
                    tamanho: 16,
                    cor: const Color(0xFF3A4048),
                  ),
                  filled: true,
                  fillColor: TemaCamda.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: TemaCamda.borda),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: TemaCamda.borda),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: TemaCamda.laranja, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Área de toque generosa (uso de pé, com uma mão), em estilo
              // secundário: a câmera é o caminho principal.
              OutlinedButton.icon(
                onPressed:
                    consultando ? null : () => onConsultar(codigoCtrl.text),
                icon: consultando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TemaCamda.verde,
                        ),
                      )
                    : const Icon(Icons.search, size: 20),
                label: Text(
                  consultando ? 'Consultando...' : 'Consultar estoque',
                  style: TemaCamda.textoStyle(
                    tamanho: 15,
                    peso: 600,
                    cor: TemaCamda.verde,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TemaCamda.verde,
                  side: BorderSide(
                    color: TemaCamda.verde.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              if (erro != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0E07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: TemaCamda.laranja.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    erro!,
                    textAlign: TextAlign.center,
                    style: TemaCamda.textoStyle(
                      tamanho: 13,
                      cor: TemaCamda.laranja,
                      altura: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Primeira abertura: aponta direto para a tela de configuração.
class _SemConfiguracao extends StatelessWidget {
  const _SemConfiguracao({required this.onConfigurar});

  final VoidCallback onConfigurar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.qr_code_scanner,
              size: 64,
              color: TemaCamda.textoFraco,
            ),
            const SizedBox(height: 20),
            Text(
              'Consulta de estoque por QR code\ne código de barras',
              textAlign: TextAlign.center,
              style: TemaCamda.textoStyle(
                tamanho: 15,
                altura: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Para começar, configure a conexão\ncom o banco Turso da CAMDA.',
              textAlign: TextAlign.center,
              style: TemaCamda.textoStyle(
                tamanho: 13,
                cor: TemaCamda.textoFraco,
                altura: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onConfigurar,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Configurar banco'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TemaCamda.laranja,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
