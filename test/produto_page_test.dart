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

  testWidgets(
      'as frases de unidade saíram de baixo da quantidade (pedido do Leo)',
      (tester) async {
    final r = montarResultado(
      codigoLido: 'US254185',
      linhas: const [linha201, linha403],
      codigosVinculados: const ['254185', 'US254185'],
      unidadePad: 'L',
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    // O número segue cru — nada de "604 L" colado, que afirmaria litros
    // quando qtd_sistema conta embalagens (ver Passo 0 no README).
    expect(find.text('604'), findsOneWidget);
    expect(find.text('L'), findsNothing);
    expect(
      find.text('valor cru do sistema · conversão de unidade não confirmada'),
      findsNothing,
    );
    expect(find.textContaining('unidade gravada no mapa'), findsNothing);
    expect(
      find.text('CÓDIGO NÃO VINCULADO — O TOTAL PODE ESTAR INCOMPLETO'),
      findsNothing,
    );
  });

  testWidgets('mostra o lote de validade mais próxima como o primeiro a sair',
      (tester) async {
    final hoje = DateTime.now();
    final proximo = hoje.add(const Duration(days: 39));
    final depois = hoje.add(const Duration(days: 132));
    String iso(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final r = montarResultado(
      codigoLido: '237191',
      linhas: const [
        CodigoSaldo(
          codigo: '237191',
          produto: 'HERBICIDA ULTIMATO SC 20L',
          categoria: 'HERBICIDAS',
          qtdSistema: 75,
        ),
      ],
      codigosVinculados: const ['237191'],
      lotes: [
        LoteValidade(lote: '2503B', vencimento: iso(depois), quantidade: 40),
        LoteValidade(lote: '2411A', vencimento: iso(proximo), quantidade: 35),
      ],
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(find.text('CARREGAR PRIMEIRO'), findsOneWidget);
    expect(find.text('2411A'), findsOneWidget);
    expect(find.text('2503B'), findsNothing);
    expect(find.textContaining('faltam 39 dias'), findsOneWidget);
    expect(find.textContaining('mais 1 lote na lista'), findsOneWidget);
  });

  testWidgets('lote já vencido é mostrado como vencido', (tester) async {
    final ontem = DateTime.now().subtract(const Duration(days: 1));
    final r = montarResultado(
      codigoLido: '237191',
      linhas: const [
        CodigoSaldo(
          codigo: '237191',
          produto: 'HERBICIDA ULTIMATO SC 20L',
          qtdSistema: 75,
        ),
      ],
      codigosVinculados: const ['237191'],
      lotes: [
        LoteValidade(
          lote: '2308C',
          vencimento:
              '${ontem.year}-${ontem.month.toString().padLeft(2, '0')}-${ontem.day.toString().padLeft(2, '0')}',
        ),
      ],
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(find.text('2308C'), findsOneWidget);
    expect(find.textContaining('vencido há 1 dia'), findsOneWidget);
  });

  testWidgets('produto fora da lista de vencimentos diz isso por escrito',
      (tester) async {
    final r = montarResultado(
      codigoLido: '254185',
      linhas: const [linha201],
      codigosVinculados: const ['254185'],
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(
      find.text('produto não está na lista de vencimentos'),
      findsOneWidget,
    );
    expect(find.text('CARREGAR PRIMEIRO'), findsNothing);
  });

  testWidgets('falha ao ler a lista não é confundida com "sem lote"',
      (tester) async {
    final r = montarResultado(
      codigoLido: '254185',
      linhas: const [linha201],
      codigosVinculados: const ['254185'],
      lotesIndisponiveis: true,
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(find.text('lista de vencimentos indisponível'), findsOneWidget);
  });

  testWidgets('código não vinculado mantém a ressalva de total incompleto',
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
      find.text('código não vinculado no mapa · o total pode estar incompleto'),
      findsOneWidget,
    );
  });

  testWidgets('grupo montado por nome diz que a soma veio do nome',
      (tester) async {
    // Ultimato lido fora do mapa: os dois códigos entram pelo nome do
    // produto, e a ressalva não pode fingir que existe vínculo cadastrado.
    final r = montarResultado(
      codigoLido: '237191',
      linhas: const [
        CodigoSaldo(
          codigo: '100237191',
          produto: 'HERBICIDA ULTIMATO SC 20L',
          qtdSistema: 125,
        ),
        CodigoSaldo(
          codigo: '237191',
          produto: 'HERBICIDA ULTIMATO SC 20L',
          qtdSistema: 40,
        ),
      ],
      codigosVinculados: const [],
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(find.text('165'), findsOneWidget);
    expect(
      find.text('códigos somados pelo nome · sem vínculo no mapa, '
          'o total pode estar incompleto'),
      findsOneWidget,
    );
    expect(
      find.textContaining('código não vinculado no mapa'),
      findsNothing,
    );
  });

  testWidgets('código vinculado não exibe a ressalva', (tester) async {
    final r = montarResultado(
      codigoLido: '254185',
      linhas: const [linha201, linha403],
      codigosVinculados: const ['254185', 'US254185'],
    );

    await tester.pumpWidget(_envolver(r));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('o total pode estar incompleto'),
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

  group('carta que vira', () {
    ResultadoConsulta comDoisLotes() {
      final hoje = DateTime.now();
      String iso(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return montarResultado(
        codigoLido: '42200',
        linhas: const [
          CodigoSaldo(
            codigo: '42200',
            produto: 'HERBICIDA ROUNDUP ORIGINAL MAIS 20L',
            categoria: 'HERBICIDAS',
            qtdSistema: 10,
          ),
        ],
        codigosVinculados: const ['42200'],
        lotes: [
          LoteValidade(
              lote: 'L-PRIMEIRO',
              vencimento: iso(hoje.add(const Duration(days: 40))),
              quantidade: 6),
          LoteValidade(
              lote: 'L-SEGUNDO',
              vencimento: iso(hoje.add(const Duration(days: 400))),
              quantidade: 4),
        ],
      );
    }

    testWidgets('sem ícones de foto/câmera nos cantos', (tester) async {
      await tester.pumpWidget(_envolver(comDoisLotes()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.photo_outlined), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
    });

    testWidgets('tocar no card vira para a foto e tocar de novo desvira',
        (tester) async {
      await tester.pumpWidget(_envolver(comDoisLotes()));
      await tester.pumpAndSettle();
      expect(find.text('adicionar foto'), findsNothing);

      await tester.tap(find.text('HERBICIDA ROUNDUP ORIGINAL MAIS 20L'));
      await tester.pumpAndSettle();
      expect(find.text('adicionar foto'), findsOneWidget);

      // Fora do convite "adicionar foto": volta para a frente.
      await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('verso-carta'))) +
          const Offset(30, 30));
      await tester.pumpAndSettle();
      expect(find.text('adicionar foto'), findsNothing);
      expect(find.text('L-PRIMEIRO'), findsOneWidget);
    });

    testWidgets('"próximo lote" abre os lotes sem virar o card',
        (tester) async {
      await tester.pumpWidget(_envolver(comDoisLotes()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('próximo lote'));
      await tester.pumpAndSettle();

      expect(find.text('L-SEGUNDO'), findsOneWidget);
      expect(find.text('adicionar foto'), findsNothing);
    });
  });
}
