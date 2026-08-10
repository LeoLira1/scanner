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
///   3. Lote a carregar primeiro — o de validade mais próxima (FEFO), vindo
///      da lista de vencimentos (pedido do Leo: é o que ele precisa saber
///      logo abaixo da quantidade, na hora de carregar)
///   4. Quais códigos foram somados — é o que dá confiança no número
///   5. Data da última contagem
///   6. Origem do dado (banco ao vivo / cache local com horário)
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

          // 2. Quantidade, grande — número cru de qtd_sistema.
          //
          // A unidade NÃO vai colada no número de propósito: o dashboard do
          // camda-estoque calcula litros como qtd_sistema × tamanho da
          // embalagem lido do nome (app_turso.py, extrair_litros), ou seja,
          // qtd_sistema conta EMBALAGENS, não litros. Já o unidade_pad do
          // mapa é um selectbox preenchido à mão, com default 'L'. Escrever
          // "604 L" ao lado do número afirmaria as duas coisas erradas de
          // uma vez — por isso o número segue cru, sem conversão, até o
          // Passo 0 ser confirmado no banco. As duas linhas que explicavam
          // isso saíram daqui a pedido do Leo (o espaço passou a ser do
          // lote); a ressalva continua registrada no README.
          const SizedBox(height: 30),
          _Leitura(total: r.total),

          // Logo abaixo do número, no lugar onde antes ficavam os avisos de
          // unidade: o lote que deve sair primeiro (FEFO), vindo da lista de
          // vencimentos. É a informação que o Leo usa de pé, na hora de
          // carregar — validade mais próxima é a que embarca antes.
          const SizedBox(height: 14),
          _LoteParaCarregar(resultado: r),
          if (r.outrosLotes > 0) ...[
            const SizedBox(height: 12),
            _BotaoProximoLote(resultado: r),
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

/// O número — cru, sem unidade colada e sem conversão, enquanto a unidade
/// real de qtd_sistema não for confirmada no banco (Passo 0).
class _Leitura extends StatelessWidget {
  const _Leitura({required this.total});

  final double total;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: total),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) {
          // Anima só valores inteiros; fração aparece direto no valor final.
          final ehInteiro = total == total.truncateToDouble();
          final texto = ehInteiro
              ? formatarQuantidade(v.roundToDouble())
              : formatarQuantidade(total);
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
      ),
    );
  }
}

/// O lote a carregar primeiro — FEFO: o de validade mais próxima sai antes.
///
/// Ocupa o espaço que antes trazia os avisos de unidade. Quando não há lote
/// para apontar, o motivo aparece escrito: "não está na lista" (a lista foi
/// lida e o produto não está nela) é diferente de "lista indisponível" (não
/// deu para ler) — some a linha e o galpão não sabe se pode confiar.
class _LoteParaCarregar extends StatelessWidget {
  const _LoteParaCarregar({required this.resultado});

  final ResultadoConsulta resultado;

  @override
  Widget build(BuildContext context) {
    final r = resultado;

    if (r.lotesIndisponiveis) {
      return _aviso('lista de vencimentos indisponível');
    }
    if (r.lotes.isEmpty) {
      return _aviso('produto não está na lista de vencimentos');
    }

    final lote = r.loteParaCarregar;
    if (lote == null) {
      // Há lote na lista, mas nenhum com data legível — dá para mostrar qual
      // é, não dá para afirmar que ele é o primeiro a vencer.
      return Column(
        children: [
          _rotulo('LOTE NA LISTA'),
          const SizedBox(height: 6),
          _numeroLote(r.lotes.first.lote, TemaCamda.texto),
          const SizedBox(height: 6),
          _detalhe('sem data de vencimento na lista'),
        ],
      );
    }

    final dias = lote.diasAte(DateTime.now())!;
    final cor = dias < 0
        ? TemaCamda.vermelho
        : dias <= 30
            ? TemaCamda.laranja
            : TemaCamda.texto;

    final segunda = StringBuffer('vence ${_formatarData(lote.vencimento)}');
    segunda.write(' · ${_situacaoValidade(dias)}');

    final terceira = <String>[];
    if (lote.quantidade > 0) {
      terceira.add('${formatarQuantidade(lote.quantidade)} no lote');
    }
    if (r.outrosLotes > 0) {
      terceira.add(r.outrosLotes == 1
          ? 'mais 1 lote na lista'
          : 'mais ${r.outrosLotes} lotes na lista');
    }

    return Column(
      children: [
        _rotulo('CARREGAR PRIMEIRO'),
        const SizedBox(height: 6),
        _numeroLote(lote.lote, cor),
        const SizedBox(height: 6),
        _detalhe(segunda.toString(), cor: dias <= 30 ? cor : null),
        if (terceira.isNotEmpty) ...[
          const SizedBox(height: 4),
          _detalhe(terceira.join(' · '), tamanho: 11),
        ],
      ],
    );
  }

  Widget _rotulo(String texto) => Text(
        texto,
        textAlign: TextAlign.center,
        style: TemaCamda.numeroStyle(
          tamanho: 10,
          cor: const Color(0xFF4A5058),
          espacamento: 1.2,
        ),
      );

  Widget _numeroLote(String lote, Color cor) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          lote,
          textAlign: TextAlign.center,
          style: TemaCamda.numeroStyle(
            tamanho: 26,
            negrito: true,
            cor: cor,
            espacamento: 1,
          ),
        ),
      );

  Widget _detalhe(String texto, {Color? cor, double tamanho = 12}) => Text(
        texto,
        textAlign: TextAlign.center,
        style: TemaCamda.numeroStyle(
          tamanho: tamanho,
          cor: cor ?? TemaCamda.textoFraco,
          altura: 1.4,
        ),
      );

  Widget _aviso(String texto) => Text(
        texto,
        textAlign: TextAlign.center,
        style: TemaCamda.numeroStyle(
          tamanho: 12,
          cor: TemaCamda.textoFraco,
          altura: 1.4,
        ),
      );
}

/// Botão que abre o bottom sheet com os lotes seguintes ao que está sendo
/// carregado. Aparece apenas quando há mais de um lote na lista.
class _BotaoProximoLote extends StatelessWidget {
  const _BotaoProximoLote({required this.resultado});

  final ResultadoConsulta resultado;

  @override
  Widget build(BuildContext context) {
    final n = resultado.outrosLotes;
    return OutlinedButton.icon(
      onPressed: () => showModalBottomSheet(
        context: context,
        backgroundColor: TemaCamda.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        isScrollControlled: true,
        builder: (_) => _ProximosLotesSheet(resultado: resultado),
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
      label: Text(
        n == 1 ? 'próximo lote' : 'próximos $n lotes',
        style: TemaCamda.numeroStyle(tamanho: 12, espacamento: 0.4),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: TemaCamda.textoFraco,
        side: const BorderSide(color: TemaCamda.borda),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Bottom sheet com todos os lotes da lista, exceto o primeiro (que já está
/// exibido no card principal).
class _ProximosLotesSheet extends StatelessWidget {
  const _ProximosLotesSheet({required this.resultado});

  final ResultadoConsulta resultado;

  @override
  Widget build(BuildContext context) {
    final lotes = resultado.lotes.skip(1).toList();
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: TemaCamda.borda,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                lotes.length == 1 ? 'PRÓXIMO LOTE' : 'PRÓXIMOS LOTES',
                style: TemaCamda.numeroStyle(
                  tamanho: 10,
                  cor: TemaCamda.textoFraco,
                  espacamento: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ...lotes.map((lote) => _ItemLote(lote: lote)),
          ],
        ),
      ),
    );
  }
}

/// Uma linha de lote no bottom sheet: número do lote, vencimento e quantidade.
class _ItemLote extends StatelessWidget {
  const _ItemLote({required this.lote});

  final LoteValidade lote;

  @override
  Widget build(BuildContext context) {
    final dias = lote.diasAte(DateTime.now());
    final cor = dias == null
        ? TemaCamda.texto
        : dias < 0
            ? TemaCamda.vermelho
            : dias <= 30
                ? TemaCamda.laranja
                : TemaCamda.texto;

    final detalhe = <String>[];
    if (lote.vencimento.isNotEmpty) {
      detalhe.add('vence ${_formatarData(lote.vencimento)}');
    }
    if (dias != null) detalhe.add(_situacaoValidade(dias));

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lote.lote,
                  style: TemaCamda.numeroStyle(
                    tamanho: 20,
                    negrito: true,
                    cor: cor,
                    espacamento: 0.5,
                  ),
                ),
                if (detalhe.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detalhe.join(' · '),
                    style: TemaCamda.numeroStyle(
                      tamanho: 12,
                      cor: dias != null && dias <= 30 ? cor : TemaCamda.textoFraco,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (lote.quantidade > 0) ...[
            const SizedBox(width: 12),
            Text(
              formatarQuantidade(lote.quantidade),
              style: TemaCamda.numeroStyle(
                tamanho: 22,
                negrito: true,
                cor: TemaCamda.textoFraco,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 'vencido há 3 dias' / 'vence hoje' / 'faltam 39 dias'.
String _situacaoValidade(int dias) {
  if (dias < 0) {
    final d = -dias;
    return d == 1 ? 'vencido há 1 dia' : 'vencido há $d dias';
  }
  if (dias == 0) return 'vence hoje';
  if (dias == 1) return 'vence amanhã';
  return 'faltam $dias dias';
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
        // O banner laranja de "total incompleto" saiu do lugar de destaque
        // (agora ocupado pelo lote), mas a ressalva continua aqui embaixo,
        // discreta: sem vínculo no mapa o grupo de códigos foi montado pelo
        // nome do produto — heurística, não cadastro —, e o número grande
        // pode estar contando só uma parte. O texto diz qual dos dois casos
        // é (ver textoAvisoNaoVinculado).
        if (r.textoAvisoNaoVinculado != null) ...[
          const SizedBox(height: 6),
          Text(
            r.textoAvisoNaoVinculado!,
            textAlign: TextAlign.center,
            style: TemaCamda.numeroStyle(
              tamanho: 11,
              cor: TemaCamda.textoFraco,
              altura: 1.4,
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
