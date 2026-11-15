import 'package:flutter/material.dart';

import 'consulta.dart';
import 'tema.dart';

/// Lista do autocompletar, logo abaixo do campo de busca: aparece enquanto
/// a pessoa ainda digita, com o pedaço que casou em destaque.
///
/// O saldo é a mesma prévia da [ResultadosPage] (soma das linhas de
/// `estoque_mestre` com o mesmo nome); ao tocar, a consulta completa é
/// refeita pelo código e quem manda é a tela do produto.
class ListaSugestoes extends StatelessWidget {
  const ListaSugestoes({
    super.key,
    required this.termo,
    required this.sugestoes,
    required this.carregando,
    required this.onEscolher,
  });

  final String termo;
  final List<ProdutoEncontrado> sugestoes;
  final bool carregando;
  final ValueChanged<ProdutoEncontrado> onEscolher;

  @override
  Widget build(BuildContext context) {
    if (sugestoes.isEmpty && !carregando) return const SizedBox.shrink();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TemaCamda.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TemaCamda.borda),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fio de progresso no topo: a lista anterior continua tocável
          // enquanto a nova chega, em vez de sumir a cada letra.
          SizedBox(
            height: 2,
            child: carregando
                ? const LinearProgressIndicator(
                    color: TemaCamda.laranja,
                    backgroundColor: Colors.transparent,
                  )
                : null,
          ),
          for (var i = 0; i < sugestoes.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: TemaCamda.borda),
            _ItemSugestao(
              termo: termo,
              produto: sugestoes[i],
              onTap: () => onEscolher(sugestoes[i]),
            ),
          ],
          if (sugestoes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'procurando…',
                textAlign: TextAlign.center,
                style: TemaCamda.numeroStyle(
                  tamanho: 11,
                  cor: TemaCamda.textoFraco,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemSugestao extends StatelessWidget {
  const _ItemSugestao({
    required this.termo,
    required this.produto,
    required this.onTap,
  });

  final String termo;
  final ProdutoEncontrado produto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nome = produto.nome.isEmpty ? 'Produto sem nome' : produto.nome;
    final base = TemaCamda.textoStyle(
      tamanho: 13,
      peso: 500,
      altura: 1.3,
      cor: TemaCamda.textoFraco,
    );
    final destaque = TemaCamda.textoStyle(
      tamanho: 13,
      peso: 700,
      altura: 1.3,
      cor: TemaCamda.texto,
    );
    // Código digitado também ganha destaque na linha dos códigos.
    final alvoCodigo = pareceCodigo(termo) ? extrairCodigo(termo) : null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      for (final t in destacarBusca(nome, termo))
                        TextSpan(
                          text: t.texto,
                          style: t.destaque ? destaque : base,
                        ),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    produto.codigos.isEmpty
                        ? produto.codigo
                        : produto.codigos.join(' + '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TemaCamda.numeroStyle(
                      tamanho: 11,
                      cor: alvoCodigo != null &&
                              produto.codigos.any((c) =>
                                  c.startsWith(alvoCodigo) ||
                                  c.startsWith('US$alvoCodigo'))
                          ? TemaCamda.laranja
                          : TemaCamda.textoFraco,
                      espacamento: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatarQuantidade(produto.total),
              style: TemaCamda.numeroStyle(
                tamanho: 16,
                negrito: true,
                cor: produto.total > 0 ? TemaCamda.verde : TemaCamda.textoFraco,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
