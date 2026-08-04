import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_camda/consulta.dart';
import 'package:scanner_camda/produto_page.dart';

Widget _envolver(ResultadoConsulta r) =>
    MaterialApp(home: ProdutoPage(resultado: r));

void main() {
  const linha201 = CodigoSaldo(
    codigo: '254185',
    produto: 'HERBICIDA BORAL 500 SC 20L',
    categoria: 'DEFENSIVOS',
    qtdSistema: 201,
    ultimaContagem: '2026-07-10',
  );
  const linha403 = CodigoSaldo(
    codigo: 'US254185',
    produto: 'HERBICIDA BORAL 500 SC 20L',
    qtdSistema: 403,
    ultimaContagem: '2026-07-28',
  );

  testWidgets('mostra nome, total somado e os códigos que entraram na soma',
      (tester) async {
    final r = montarResultado(
      codigoLido: 'US254185',
      linhas: const [linha201, linha403],
      codigosVinculados: const ['254185', 'US254185'],
      unidadePad: 'L',
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(find.text('HERBICIDA BORAL 500 SC 20L'), findsOneWidget);
    expect(find.text('604'), findsOneWidget);
    expect(find.text('254185 (201) + US254185 (403)'), findsOneWidget);
    expect(find.text('códigos somados'), findsOneWidget);
    // Última contagem mais recente do grupo.
    expect(find.textContaining('28/07/2026'), findsOneWidget);
  });

  testWidgets('código não vinculado exibe o aviso de total incompleto',
      (tester) async {
    final r = montarResultado(
      codigoLido: 'US254185',
      linhas: const [linha403],
      codigosVinculados: const [],
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(find.text('403'), findsOneWidget);
    expect(
      find.text('CÓDIGO NÃO VINCULADO — O TOTAL PODE ESTAR INCOMPLETO'),
      findsOneWidget,
    );
  });

  testWidgets('código vinculado não exibe o aviso', (tester) async {
    final r = montarResultado(
      codigoLido: '254185',
      linhas: const [linha201, linha403],
      codigosVinculados: const ['254185', 'US254185'],
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(
      find.text('CÓDIGO NÃO VINCULADO — O TOTAL PODE ESTAR INCOMPLETO'),
      findsNothing,
    );
  });

  testWidgets('dado do cache local é rotulado com o horário', (tester) async {
    final r = montarResultado(
      codigoLido: '254185',
      linhas: const [linha201],
      codigosVinculados: const ['254185'],
      doCacheLocal: true,
      sincronizadoEm: DateTime.now().subtract(const Duration(minutes: 4)),
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(find.textContaining('CACHE LOCAL'), findsOneWidget);
    expect(find.textContaining('há 4 min'), findsOneWidget);
  });

  testWidgets('dado ao vivo é rotulado como consultado agora', (tester) async {
    final r = montarResultado(
      codigoLido: '254185',
      linhas: const [linha201],
      codigosVinculados: const ['254185'],
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(find.text('consultado agora do banco'), findsOneWidget);
    expect(find.textContaining('CACHE LOCAL'), findsNothing);
  });

  testWidgets('a tela não mostra localização física do produto',
      (tester) async {
    final r = montarResultado(
      codigoLido: '254185',
      linhas: const [linha201],
      codigosVinculados: const ['254185'],
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    // Pedido do Leo: nada de corredor, estante, rua, face, coluna ou nível.
    for (final termo in [
      'CORREDOR',
      'Corredor',
      'ESTANTE',
      'Estante',
      'Rua',
      'RUA',
      'Face',
      'Coluna',
      'Nível',
      'NÍVEL',
    ]) {
      expect(find.textContaining(termo), findsNothing,
          reason: 'a tela do produto não deve exibir "$termo"');
    }
  });
}
