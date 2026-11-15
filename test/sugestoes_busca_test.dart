import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_camda/consulta.dart';
import 'package:scanner_camda/sugestoes_busca.dart';

void main() {
  const boral = ProdutoEncontrado(
    codigo: '254185',
    codigos: ['254185', 'US254185'],
    nome: 'HERBICIDA BORAL 500 SC 20L',
    total: 604,
  );
  const ultimato = ProdutoEncontrado(
    codigo: '237191',
    codigos: ['237191'],
    nome: 'HERBICIDA ULTIMATO SC 20L',
    total: 75,
  );

  Widget envolver(Widget w) => MaterialApp(home: Scaffold(body: w));

  testWidgets('mostra as sugestões com códigos e saldo, e o toque escolhe',
      (tester) async {
    ProdutoEncontrado? escolhido;
    await tester.pumpWidget(envolver(ListaSugestoes(
      termo: 'herb',
      sugestoes: const [boral, ultimato],
      carregando: false,
      onEscolher: (p) => escolhido = p,
    )));

    expect(find.text('HERBICIDA BORAL 500 SC 20L'),
        findsOneWidget);
    expect(find.text('254185 + US254185'), findsOneWidget);
    expect(find.text('604'), findsOneWidget);
    expect(find.text('75'), findsOneWidget);

    await tester.tap(find.text('HERBICIDA ULTIMATO SC 20L'));
    expect(escolhido?.codigo, '237191');
  });

  testWidgets('sem sugestões e sem busca em andamento, não ocupa espaço',
      (tester) async {
    await tester.pumpWidget(envolver(ListaSugestoes(
      termo: 'xyz',
      sugestoes: const [],
      carregando: false,
      onEscolher: (_) {},
    )));
    expect(find.byType(InkWell), findsNothing);
    expect(find.text('procurando…'), findsNothing);
  });

  testWidgets('primeira busca mostra que está procurando', (tester) async {
    await tester.pumpWidget(envolver(ListaSugestoes(
      termo: 'bor',
      sugestoes: const [],
      carregando: true,
      onEscolher: (_) {},
    )));
    expect(find.text('procurando…'), findsOneWidget);
  });
}
