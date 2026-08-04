import 'package:flutter/material.dart';

import 'configuracao_page.dart';
import 'consulta.dart';
import 'estoque_service.dart';
import 'produto_page.dart';
import 'tema.dart';
import 'turso_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _codigoCtrl = TextEditingController();

  bool    _configurado = false;
  bool    _carregando  = true;
  bool    _consultando = false;
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
                )
              : _SemConfiguracao(onConfigurar: _abrirConfiguracao),
    );
  }
}

/// Consulta por digitação manual — sempre acessível. É o fallback quando o
/// QR estiver sujo ou rasgado, e permite testar o app inteiro sem câmera.
class _Busca extends StatelessWidget {
  const _Busca({
    required this.codigoCtrl,
    required this.consultando,
    required this.erro,
    required this.onConsultar,
  });

  final TextEditingController codigoCtrl;
  final bool consultando;
  final String? erro;
  final void Function(String) onConsultar;

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
              const Icon(
                Icons.qr_code_scanner,
                size: 52,
                color: TemaCamda.textoFraco,
              ),
              const SizedBox(height: 18),
              Text(
                'Digite o código do produto',
                textAlign: TextAlign.center,
                style: TemaCamda.textoStyle(
                  tamanho: 15,
                  peso: 600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'O mesmo código da etiqueta — numérico ou US',
                textAlign: TextAlign.center,
                style: TemaCamda.textoStyle(
                  tamanho: 12,
                  cor: TemaCamda.textoFraco,
                ),
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

              // Botão grande — área de toque generosa para uso com uma mão.
              ElevatedButton.icon(
                onPressed:
                    consultando ? null : () => onConsultar(codigoCtrl.text),
                icon: consultando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search, size: 20),
                label: Text(
                  consultando ? 'Consultando...' : 'Consultar estoque',
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
