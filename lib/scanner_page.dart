import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'consulta.dart';
import 'estoque_service.dart';
import 'produto_page.dart';
import 'tema.dart';

/// Leitura ao vivo de QR code e código de barras 1D (mobile_scanner /
/// ML Kit). Aceita tanto um código puro ('US254185') quanto uma URL que
/// contenha 'p=' — mesmo tratamento da digitação manual.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    // Timeout entre detecções: evita rajada de leituras iguais enquanto a
    // câmera continua apontada para o mesmo QR.
    detectionTimeoutMs: 700,
  );

  bool    _consultando = false;
  String? _erro;

  // Cooldown do último código lido: o mesmo QR só reconsulta depois de uns
  // segundos, senão voltar da tela do produto dispararia a leitura de novo.
  String?   _ultimoCodigo;
  DateTime? _ultimaLeitura;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _aoDetectar(BarcodeCapture captura) async {
    if (_consultando || !mounted) return;

    String? codigo;
    for (final barcode in captura.barcodes) {
      codigo = extrairCodigo(barcode.rawValue ?? '');
      if (codigo != null) break;
    }
    if (codigo == null) return;

    final agora = DateTime.now();
    if (codigo == _ultimoCodigo &&
        _ultimaLeitura != null &&
        agora.difference(_ultimaLeitura!) < const Duration(seconds: 3)) {
      return;
    }
    _ultimoCodigo  = codigo;
    _ultimaLeitura = agora;

    setState(() {
      _consultando = true;
      _erro        = null;
    });

    ResultadoConsulta? resultado;
    String? erro;
    try {
      resultado = await EstoqueService().consultarPorCodigo(codigo);
      if (resultado == null) {
        erro = 'Código $codigo não encontrado no estoque.';
      }
    } on ConsultaException catch (e) {
      erro = e.mensagem;
    }

    if (!mounted) return;

    if (resultado != null) {
      // Pausa a câmera enquanto a tela do produto está aberta.
      await _controller.stop();
      if (!mounted) return;
      setState(() => _consultando = false);
      final res = resultado;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProdutoPage(resultado: res)),
      );
      if (!mounted) return;
      _ultimaLeitura = DateTime.now();
      await _controller.start();
      return;
    }

    setState(() {
      _consultando = false;
      _erro        = erro;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Escanear código'),
        actions: [
          // Lanterna — galpão tem canto escuro.
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, estado, _) {
              if (estado.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final ligada = estado.torchState == TorchState.on;
              return IconButton(
                icon: Icon(
                  ligada ? Icons.flash_on : Icons.flash_off,
                  color: ligada ? TemaCamda.laranja : TemaCamda.textoFraco,
                ),
                tooltip: 'Lanterna',
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _aoDetectar,
            errorBuilder: (context, erro) => _ErroCamera(erro: erro),
            placeholderBuilder: (context) => const ColoredBox(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(color: TemaCamda.laranja),
              ),
            ),
          ),

          // Moldura de mira — só guia visual; a leitura usa o quadro todo.
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _consultando
                        ? TemaCamda.verde
                        : TemaCamda.laranja.withValues(alpha: 0.85),
                    width: 2.5,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),

          // Rodapé: status/erro + atalho para a digitação manual.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_consultando)
                      const _Faixa(
                        cor: TemaCamda.verde,
                        texto: 'Consultando...',
                      )
                    else if (_erro != null)
                      _Faixa(cor: TemaCamda.laranja, texto: _erro!)
                    else
                      const _Faixa(
                        cor: TemaCamda.textoFraco,
                        texto: 'Aponte para o QR ou código de barras',
                      ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.keyboard_outlined, size: 18),
                      label: const Text('Digitar código'),
                      style: TextButton.styleFrom(
                        foregroundColor: TemaCamda.texto,
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Faixa extends StatelessWidget {
  const _Faixa({required this.cor, required this.texto});

  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: TemaCamda.textoStyle(tamanho: 13, cor: cor, altura: 1.4),
      ),
    );
  }
}

class _ErroCamera extends StatelessWidget {
  const _ErroCamera({required this.erro});

  final MobileScannerException erro;

  @override
  Widget build(BuildContext context) {
    final semPermissao =
        erro.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                semPermissao
                    ? Icons.no_photography_outlined
                    : Icons.videocam_off_outlined,
                size: 56,
                color: TemaCamda.textoFraco,
              ),
              const SizedBox(height: 18),
              Text(
                semPermissao
                    ? 'Sem permissão de câmera.\nLibere a câmera para o '
                        'Scanner CAMDA nas configurações do Android.'
                    : 'Não foi possível abrir a câmera.\n(${erro.errorCode.name})',
                textAlign: TextAlign.center,
                style: TemaCamda.textoStyle(
                  tamanho: 14,
                  cor: TemaCamda.texto,
                  altura: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.keyboard_outlined, size: 16),
                label: const Text('Usar digitação manual'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TemaCamda.laranja,
                  side: BorderSide(
                    color: TemaCamda.laranja.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
