import 'package:flutter/material.dart';

import 'consulta.dart';
import 'estoque_service.dart';
import 'produto_page.dart';
import 'tema.dart';

/// Abre a tela do produto a partir de um código — injetável para o teste
/// rodar sem banco. Em produção é [EstoqueService.consultarPorCodigo].
typedef AbrirPorCodigo = Future<ResultadoConsulta?> Function(String codigo);

/// Resultados da busca por nome: uma lista para escolher o produto quando o
/// termo digitado casa com mais de um.
///
/// O saldo mostrado aqui é a soma das linhas de `estoque_mestre` com o mesmo
/// nome — uma prévia. Ao tocar, a consulta completa é refeita pelo código
/// (resolvendo mapa_produtos e a lista de vencimentos), e é esse número que
/// a tela do produto exibe.
class ResultadosPage extends StatefulWidget {
  const ResultadosPage({
    super.key,
    required this.termo,
    required this.achados,
    this.aoAbrir,
  });

  final String termo;
  final List<ProdutoEncontrado> achados;
  final AbrirPorCodigo? aoAbrir;

  @override
  State<ResultadosPage> createState() => _ResultadosPageState();
}

class _ResultadosPageState extends State<ResultadosPage> {
  /// Código sendo consultado agora — trava a lista e mostra o progresso no
  /// item tocado, para ninguém abrir dois produtos com o dedo nervoso.
  String? _abrindo;

  Future<void> _abrir(ProdutoEncontrado produto) async {
    if (_abrindo != null) return;
    setState(() => _abrindo = produto.codigo);

    final abrir = widget.aoAbrir ?? EstoqueService().consultarPorCodigo;
    ResultadoConsulta? resultado;
    String? erro;
    try {
      resultado = await abrir(produto.codigo);
      if (resultado == null) {
        erro = 'Produto ${produto.codigo} não encontrado no estoque.';
      }
    } on ConsultaException catch (e) {
      erro = e.mensagem;
    }

    if (!mounted) return;
    setState(() => _abrindo = null);

    final res = resultado;
    if (res != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProdutoPage(resultado: res)),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(erro!),
      backgroundColor: const Color(0xFF8B1A1A),
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.achados.length;
    return Scaffold(
      backgroundColor: TemaCamda.fundo,
      appBar: AppBar(
        title: Text(
          n == 1 ? '1 produto' : '$n produtos',
          style: TemaCamda.textoStyle(tamanho: 15),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                  child: Text(
                    'busca por "${widget.termo.trim()}"',
                    style: TemaCamda.textoStyle(
                      tamanho: 12,
                      cor: TemaCamda.textoFraco,
                    ),
                  ),
                ),
                if (n >= limiteBusca)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Text(
                      'mostrando os primeiros $limiteBusca — acrescente uma '
                      'palavra para afinar a busca',
                      style: TemaCamda.textoStyle(
                        tamanho: 11,
                        cor: TemaCamda.laranja,
                        altura: 1.35,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: n,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = widget.achados[i];
                      return _ItemProduto(
                        produto: p,
                        abrindo: _abrindo == p.codigo,
                        bloqueado: _abrindo != null && _abrindo != p.codigo,
                        onTap: () => _abrir(p),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemProduto extends StatelessWidget {
  const _ItemProduto({
    required this.produto,
    required this.abrindo,
    required this.bloqueado,
    required this.onTap,
  });

  final ProdutoEncontrado produto;
  final bool abrindo;
  final bool bloqueado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final categoria = (produto.categoria ?? '').trim();
    return Opacity(
      opacity: bloqueado ? 0.5 : 1,
      child: Material(
        color: TemaCamda.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: bloqueado ? null : onTap,
          child: Container(
            // Altura de toque generosa: uso de pé, com uma mão só.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TemaCamda.borda),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        produto.nome.isEmpty ? 'Produto sem nome' : produto.nome,
                        style: TemaCamda.textoStyle(
                          tamanho: 14,
                          peso: 600,
                          altura: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        produto.codigos.join(' + '),
                        style: TemaCamda.numeroStyle(
                          tamanho: 11,
                          cor: TemaCamda.textoFraco,
                          espacamento: 1,
                        ),
                      ),
                      if (categoria.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          categoria,
                          style: TemaCamda.textoStyle(
                            tamanho: 11,
                            cor: TemaCamda.textoFraco,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (abrindo)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: TemaCamda.laranja,
                    ),
                  )
                else
                  Text(
                    formatarQuantidade(produto.total),
                    style: TemaCamda.numeroStyle(
                      tamanho: 20,
                      negrito: true,
                      cor: TemaCamda.verde,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
