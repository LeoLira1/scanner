import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_camda/consulta.dart';
import 'package:scanner_camda/resultados_page.dart';

/// A lista de resultados com a consulta por código injetada — o teste roda
/// sem banco, como o resto da suíte.
Widget _envolver(
  List<ProdutoEncontrado> achados, {
  String termo = 'boral',
  AbrirPorCodigo? aoAbrir,
}) =>
    MaterialApp(
      home: ResultadosPage(termo: termo, achados: achados, aoAbrir: aoAbrir),
    );

void main() {
  const boral = ProdutoEncontrado(
    codigo: '254185',
    codigos: ['254185', 'US254185'],
    nome: 'HERBICIDA BORAL 500 SC 20L',
    categoria: 'DEFENSIVOS',
    total: 604,
  );
  const ultimato = ProdutoEncontrado(
    codigo: '237191',
    codigos: ['237191'],
    nome: 'HERBICIDA ULTIMATO SC 20L',
    total: 75,
  );

  testWidgets('mostra nome, códigos e o saldo somado de cada produto',
      (tester) async {
    await tester.pumpWidget(_envolver(const [boral, ultimato]));
    await tester.pumpAndSettle();

    expect(find.text('2 produtos'), findsOneWidget);
    expect(find.text('busca por "boral"'), findsOneWidget);
    expect(find.text('HERBICIDA BORAL 500 SC 20L'), findsOneWidget);
    expect(find.text('254185 + US254185'), findsOneWidget);
    expect(find.text('604'), findsOneWidget);
    expect(find.text('DEFENSIVOS'), findsOneWidget);
    expect(find.text('HERBICIDA ULTIMATO SC 20L'), findsOneWidget);
    expect(find.text('75'), findsOneWidget);
  });

  testWidgets('tocar num produto abre a tela do produto pelo código',
      (tester) async {
    String? consultado;
    await tester.pumpWidget(_envolver(
      const [boral, ultimato],
      aoAbrir: (codigo) async {
        consultado = codigo;
        return montarResultado(
          codigoLido: codigo,
          linhas: const [
            CodigoSaldo(
              codigo: '254185',
              produto: 'HERBICIDA BORAL 500 SC 20L',
              qtdSistema: 201,
            ),
            CodigoSaldo(
              codigo: 'US254185',
              produto: 'HERBICIDA BORAL 500 SC 20L',
              qtdSistema: 403,
            ),
          ],
          codigosVinculados: const ['254185', 'US254185'],
        );
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('HERBICIDA BORAL 500 SC 20L'));
    await tester.pumpAndSettle();

    // A consulta completa é refeita pelo código do item tocado — o saldo da
    // lista é só uma prévia.
    expect(consultado, '254185');
    expect(find.text('254185 (201) + US254185 (403)'), findsOneWidget);
  });

  testWidgets('produto que sumiu do estoque avisa em vez de abrir a tela',
      (tester) async {
    await tester.pumpWidget(_envolver(
      const [boral],
      aoAbrir: (_) async => null,
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 produto'), findsOneWidget);

    await tester.tap(find.text('HERBICIDA BORAL 500 SC 20L'));
    await tester.pumpAndSettle();

    expect(
      find.text('Produto 254185 não encontrado no estoque.'),
      findsOneWidget,
    );
  });
}
