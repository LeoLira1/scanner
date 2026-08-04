import 'package:flutter/material.dart';

import 'configuracao_page.dart';
import 'tema.dart';
import 'turso_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _configurado = false;
  bool _carregando  = true;

  @override
  void initState() {
    super.initState();
    _verificarConfiguracao();
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
              ? _ProximaEtapa(onConfigurar: _abrirConfiguracao)
              : _SemConfiguracao(onConfigurar: _abrirConfiguracao),
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
                cor: TemaCamda.texto,
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

/// Banco configurado. A consulta por código chega na Etapa 2 — este bloco
/// existe só para a Etapa 1 ser testável de ponta a ponta.
class _ProximaEtapa extends StatelessWidget {
  const _ProximaEtapa({required this.onConfigurar});

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
              Icons.check_circle_outline,
              size: 56,
              color: TemaCamda.verde,
            ),
            const SizedBox(height: 20),
            Text(
              'Banco configurado',
              style: TemaCamda.textoStyle(
                tamanho: 16,
                peso: 600,
                cor: TemaCamda.texto,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Use "Testar conexão" em ⚙️ para validar as credenciais.\n'
              'A consulta por código entra na próxima etapa.',
              textAlign: TextAlign.center,
              style: TemaCamda.textoStyle(
                tamanho: 13,
                cor: TemaCamda.textoFraco,
                altura: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onConfigurar,
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Abrir configuração'),
              style: OutlinedButton.styleFrom(
                foregroundColor: TemaCamda.textoFraco,
                side: const BorderSide(color: TemaCamda.borda),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
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
