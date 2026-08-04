import 'package:flutter/material.dart';

import 'consulta.dart';
import 'tema.dart';

/// Tela do produto — layout da maquete tag-estoque.html, sem a linha de
/// localização (pedido do Leo: não mostrar corredor/estante/nível).
///
/// Ordem de destaque:
///   1. Nome do produto
///   2. Quantidade, grande (número cru — sem conversão de unidade enquanto
///      a unidade real de qtd_sistema não for confirmada no banco)
///   3. Quais códigos foram somados — é o que dá confiança no número
///   4. Data da última contagem
///   5. Origem do dado (banco ao vivo / cache local com horário)
class ProdutoPage extends StatelessWidget {
  const ProdutoPage({super.key, required this.resultado});

  final ResultadoConsulta resultado;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaCamda.fundo,
      appBar: AppBar(
        title: Text(
          resultado.codigoLido,
          style: TemaCamda.numeroStyle(
            tamanho: 13,
            cor: TemaCamda.textoFraco,
            espacamento: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Brilho quente atrás da leitura — único efeito ambiente da tela.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.35),
                    radius: 0.9,
                    colors: [
                      TemaCamda.laranja.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.7],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Cartao(resultado: resultado),
                      const SizedBox(height: 14),
                      Text(
                        'CAMDA · QUIRINÓPOLIS GO',
                        style: TemaCamda.numeroStyle(
                          tamanho: 10,
                          cor: const Color(0xFF4A5058),
                          espacamento: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.resultado});

  final ResultadoConsulta resultado;

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 34, 26, 28),
      decoration: BoxDecoration(
        color: TemaCamda.card,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: TemaCamda.borda),
      ),
      child: Column(
        children: [
          // 1. Nome do produto
          Text(
            r.nomeProduto.isEmpty ? 'Produto sem nome' : r.nomeProduto,
            textAlign: TextAlign.center,
            style: TemaCamda.textoStyle(
              tamanho: 19,
              peso: 600,
              altura: 1.3,
              espacamento: -0.19,
            ),
          ),
          if ((r.categoria ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.categoria!,
              textAlign: TextAlign.center,
              style: TemaCamda.numeroStyle(
                tamanho: 12,
                cor: TemaCamda.textoFraco,
              ),
            ),
          ],

          // 2. Quantidade, grande — número cru, unidade como está gravada.
          const SizedBox(height: 30),
          _Leitura(total: r.total, unidade: r.unidadePad),

          // Aviso: código sem vínculo no mapa — não existe grupo de códigos
          // para somar, então o total pode estar incompleto.
          if (r.avisoNaoVinculado) ...[
            const SizedBox(height: 14),
            Text(
              'CÓDIGO NÃO VINCULADO — O TOTAL PODE ESTAR INCOMPLETO',
              textAlign: TextAlign.center,
              style: TemaCamda.numeroStyle(
                tamanho: 11,
                cor: TemaCamda.laranja,
                espacamento: 1.2,
                altura: 1.5,
              ),
            ),
          ],

          // 3. Quais códigos foram somados — a confiança no número.
          const SizedBox(height: 18),
          _CodigosSomados(resultado: r),

          // 4. Data da última contagem
          if ((r.ultimaContagem ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'última contagem · ${_formatarData(r.ultimaContagem!)}',
              style: TemaCamda.numeroStyle(
                tamanho: 11.5,
                cor: TemaCamda.textoFraco,
              ),
            ),
          ],

          // 5. Origem do dado
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.only(top: 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: TemaCamda.borda)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        r.doCacheLocal ? TemaCamda.laranja : TemaCamda.verde,
                    boxShadow: [
                      BoxShadow(
                        color: (r.doCacheLocal
                                ? TemaCamda.laranja
                                : TemaCamda.verde)
                            .withValues(alpha: 0.45),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    r.doCacheLocal
                        ? 'CACHE LOCAL · sincronizado ${_formatarSync(r.sincronizadoEm)}'
                        : 'consultado agora do banco',
                    style: TemaCamda.numeroStyle(
                      tamanho: 11.5,
                      cor: r.doCacheLocal
                          ? TemaCamda.laranja
                          : TemaCamda.textoFraco,
                      espacamento: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// O número — cru, com a unidade como está gravada no banco (unidade_pad).
/// Nenhuma conversão é aplicada enquanto a unidade real de qtd_sistema não
/// for confirmada (Passo 0).
class _Leitura extends StatelessWidget {
  const _Leitura({required this.total, required this.unidade});

  final double total;
  final String? unidade;

  @override
  Widget build(BuildContext context) {
    final numero = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: total),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        // Anima só valores inteiros; fração aparece direto no valor final.
        final ehInteiro = total == total.truncateToDouble();
        final texto =
            ehInteiro ? formatarQuantidade(v.roundToDouble()) : formatarQuantidade(total);
        return Text(
          texto,
          style: TemaCamda.numeroStyle(
            tamanho: 96,
            negrito: true,
            altura: 0.9,
            espacamento: -4.5,
          ),
        );
      },
    );

    if ((unidade ?? '').isEmpty) {
      return FittedBox(fit: BoxFit.scaleDown, child: numero);
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          numero,
          const SizedBox(width: 12),
          Text(
            unidade!,
            style: TemaCamda.textoStyle(
              tamanho: 19,
              peso: 500,
              cor: TemaCamda.laranja,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodigosSomados extends StatelessWidget {
  const _CodigosSomados({required this.resultado});

  final ResultadoConsulta resultado;

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    final partes = <String>[];
    for (final s in r.saldos) {
      partes.add(r.saldos.length > 1
          ? '${s.codigo} (${formatarQuantidade(s.qtdSistema)})'
          : s.codigo);
    }
    final linha = partes.join(' + ');

    return Column(
      children: [
        Text(
          r.saldos.length > 1 ? 'códigos somados' : 'código',
          style: TemaCamda.numeroStyle(
            tamanho: 10,
            cor: const Color(0xFF4A5058),
            espacamento: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          linha,
          textAlign: TextAlign.center,
          style: TemaCamda.numeroStyle(
            tamanho: 13,
            cor: TemaCamda.texto,
            altura: 1.5,
          ),
        ),
        if (r.codigosSemSaldo.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${r.codigosSemSaldo.join(', ')} · sem linha no estoque',
            style: TemaCamda.numeroStyle(
              tamanho: 11,
              cor: TemaCamda.textoFraco,
            ),
          ),
        ],
      ],
    );
  }
}

String _dois(int n) => n.toString().padLeft(2, '0');

String _formatarData(String bruta) {
  final dt = DateTime.tryParse(bruta.trim());
  if (dt == null) return bruta;
  final data = '${_dois(dt.day)}/${_dois(dt.month)}/${dt.year}';
  if (dt.hour == 0 && dt.minute == 0) return data;
  return '$data ${_dois(dt.hour)}:${_dois(dt.minute)}';
}

String _formatarSync(DateTime? quando) {
  if (quando == null) return '—';
  final diff = DateTime.now().difference(quando);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours} h';
  return 'em ${_dois(quando.day)}/${_dois(quando.month)} ${_dois(quando.hour)}:${_dois(quando.minute)}';
}
