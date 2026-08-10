import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_camda/consulta.dart';

void main() {
  group('normalizarCodigo', () {
    test('aplica UPPER(TRIM())', () {
      expect(normalizarCodigo('  us254185 '), 'US254185');
      expect(normalizarCodigo('254185'), '254185');
    });

    test('vazio vira null', () {
      expect(normalizarCodigo(null), isNull);
      expect(normalizarCodigo(''), isNull);
      expect(normalizarCodigo('   '), isNull);
    });
  });

  group('extrairCodigo', () {
    test('código puro passa direto, normalizado', () {
      expect(extrairCodigo('US254185'), 'US254185');
      expect(extrairCodigo(' us254185 '), 'US254185');
      expect(extrairCodigo('254185'), '254185');
    });

    test('URL com p= extrai o parâmetro', () {
      expect(
        extrairCodigo('https://camda.app/estoque?p=US254185'),
        'US254185',
      );
      expect(
        extrairCodigo('https://camda.app/e?x=1&p=254185&y=2'),
        '254185',
      );
    });

    test('URL com p= percent-encoded decodifica', () {
      expect(
        extrairCodigo('https://camda.app/e?p=US%20254185'),
        'US 254185',
      );
    });

    test('p= sem URL válida ainda extrai', () {
      expect(extrairCodigo('camda.app/e?p=US254185'), 'US254185');
    });

    test('leitura vazia vira null', () {
      expect(extrairCodigo(''), isNull);
      expect(extrairCodigo('   '), isNull);
    });
  });

  group('montarResultado — soma multi-código', () {
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
      categoria: 'DEFENSIVOS',
      qtdSistema: 403,
      ultimaContagem: '2026-07-28',
    );

    test('bipar US254185 soma os dois códigos: 201 + 403 = 604', () {
      final r = montarResultado(
        codigoLido: 'US254185',
        linhas: const [linha201, linha403],
        codigosVinculados: const ['254185', 'US254185'],
        nomeMapa: 'Herbicida Boral',
        unidadePad: 'L',
      );
      expect(r.total, 604);
      expect(r.vinculado, isTrue);
      expect(r.avisoNaoVinculado, isFalse);
      expect(r.codigosSomados, '254185 + US254185');
      expect(r.nomeProduto, 'HERBICIDA BORAL 500 SC 20L');
      expect(r.unidadePad, 'L');
      // Última contagem é a mais recente do grupo.
      expect(r.ultimaContagem, '2026-07-28');
    });

    test('código não vinculado: linha única + aviso', () {
      final r = montarResultado(
        codigoLido: 'US254185',
        linhas: const [linha403],
        codigosVinculados: const [],
      );
      expect(r.total, 403);
      expect(r.vinculado, isFalse);
      expect(r.avisoNaoVinculado, isTrue);
      expect(r.codigosSomados, 'US254185');
    });

    test('código vinculado sem linha no estoque aparece em codigosSemSaldo',
        () {
      final r = montarResultado(
        codigoLido: '254185',
        linhas: const [linha201],
        codigosVinculados: const ['254185', 'US254185'],
      );
      expect(r.total, 201);
      expect(r.codigosSemSaldo, ['US254185']);
    });

    test('nome prefere a linha do código lido', () {
      const outraGrafiaLinha = CodigoSaldo(
        codigo: 'US254185',
        produto: 'BORAL 500 SC BALDE 20L (US)',
        qtdSistema: 403,
      );
      final r = montarResultado(
        codigoLido: 'US254185',
        linhas: const [linha201, outraGrafiaLinha],
        codigosVinculados: const ['254185', 'US254185'],
        nomeMapa: 'Herbicida Boral',
      );
      expect(r.nomeProduto, 'BORAL 500 SC BALDE 20L (US)');
    });

    test('sem linha nenhuma usa nome do mapa e total 0', () {
      final r = montarResultado(
        codigoLido: '999999',
        linhas: const [],
        codigosVinculados: const ['999999'],
        nomeMapa: 'Produto Novo Sem Estoque',
      );
      expect(r.total, 0);
      expect(r.nomeProduto, 'Produto Novo Sem Estoque');
      expect(r.codigosSemSaldo, ['999999']);
    });
  });

  group('irmãos por nome — código fora do mapa', () {
    // Na prateleira existe uma pilha só: o produto tem dois códigos ativos,
    // cada um com sua linha de saldo em estoque_mestre.
    const phosfix = [
      CodigoSaldo(
        codigo: '222534',
        produto: 'ADJUVANTE PHOSFIX NORTOX 5L',
        categoria: 'ADJUVANTES',
        qtdSistema: 11,
      ),
      CodigoSaldo(
        codigo: 'US222534',
        produto: 'ADJUVANTE PHOSFIX NORTOX 5L',
        categoria: 'ADJUVANTES',
        qtdSistema: 73,
      ),
    ];
    const ultimato = [
      CodigoSaldo(
        codigo: '237191',
        produto: 'HERBICIDA ULTIMATO SC 20L',
        qtdSistema: 40,
      ),
      CodigoSaldo(
        codigo: '100237191',
        produto: 'HERBICIDA ULTIMATO SC 20L',
        qtdSistema: 125,
      ),
    ];
    const outro = CodigoSaldo(
      codigo: '900001',
      produto: 'INSETICIDA ORQUÍDEA 5L',
      qtdSistema: 4,
    );
    const todas = [...phosfix, ...ultimato, outro];

    double somar(List<CodigoSaldo> linhas) =>
        linhas.fold(0.0, (s, l) => s + l.qtdSistema);

    test('ULTIMATO: prefixo 100 é somado por qualquer um dos dois códigos',
        () {
      for (final lido in ['237191', '100237191']) {
        final grupo = irmaosPorNome(lido, todas);
        expect(
          grupo.map((l) => l.codigo).toList(),
          ['100237191', '237191'],
          reason: 'lendo $lido',
        );
        expect(somar(grupo), 165, reason: 'lendo $lido');
      }
    });

    test('PHOSFIX: o par US continua somando 11 + 73 = 84', () {
      for (final lido in ['222534', 'US222534']) {
        final grupo = irmaosPorNome(lido, todas);
        expect(
          grupo.map((l) => l.codigo).toList(),
          ['222534', 'US222534'],
          reason: 'lendo $lido',
        );
        expect(somar(grupo), 84, reason: 'lendo $lido');
      }
    });

    test('nome vazio não agrupa', () {
      const semNome = [
        CodigoSaldo(codigo: '111111', produto: '', qtdSistema: 5),
        CodigoSaldo(codigo: '222222', produto: '   ', qtdSistema: 7),
      ];
      final grupo = irmaosPorNome('111111', semNome);
      expect(grupo.map((l) => l.codigo).toList(), ['111111']);
      expect(somar(grupo), 5, reason: 'somaria produtos sem relação nenhuma');
    });

    test('caixa e espaço no código não criam grupos separados', () {
      const cruas = [
        CodigoSaldo(
          codigo: ' us222534 ',
          produto: 'Adjuvante  Phosfix Nortox 5L',
          qtdSistema: 73,
        ),
        CodigoSaldo(
          codigo: '222534',
          produto: 'ADJUVANTE PHOSFIX NORTOX 5L',
          qtdSistema: 11,
        ),
      ];
      final grupo = irmaosPorNome(' us222534 ', cruas);
      expect(grupo, hasLength(2));
      expect(somar(grupo), 84);
      // O mesmo grupo sai lendo o código já normalizado.
      expect(somar(irmaosPorNome('US222534', cruas)), 84);
    });

    test('acento e espaço repetido no nome não separam o irmão', () {
      const grafias = [
        CodigoSaldo(
          codigo: '900001',
          produto: 'INSETICIDA ORQUÍDEA 5L',
          qtdSistema: 4,
        ),
        CodigoSaldo(
          codigo: 'US900001',
          produto: '  inseticida  orquidea 5l ',
          qtdSistema: 6,
        ),
      ];
      expect(somar(irmaosPorNome('900001', grafias)), 10);
    });

    test('o mapa manda mais que o nome: irmão cadastrado em outro produto '
        'fica de fora', () {
      const homonimo = CodigoSaldo(
        codigo: '999999',
        produto: 'ADJUVANTE PHOSFIX NORTOX 5L',
        qtdSistema: 500,
      );
      final grupo = irmaosPorNome(
        '222534',
        const [...phosfix, homonimo],
        codigosNoMapa: const {'999999'},
      );
      expect(grupo.map((l) => l.codigo).toList(), ['222534', 'US222534']);
      expect(somar(grupo), 84, reason: 'o homônimo do mapa não entra na soma');
    });

    test('código sem linha em estoque_mestre: não encontrado', () {
      expect(irmaosPorNome('404404', todas), isEmpty);
      expect(irmaosPorNome('   ', todas), isEmpty);
    });

    test('produto de nome único fica sozinho', () {
      final grupo = irmaosPorNome('900001', todas);
      expect(grupo.map((l) => l.codigo).toList(), ['900001']);
    });

    test('o total do grupo por nome vira o saldo da tela, com a ressalva '
        'reescrita', () {
      final grupo = irmaosPorNome('237191', todas);
      final r = montarResultado(
        codigoLido: '237191',
        linhas: grupo,
        codigosVinculados: const [],
      );
      expect(r.total, 165);
      expect(r.nomeProduto, 'HERBICIDA ULTIMATO SC 20L');
      expect(r.codigosSomados, '100237191 + 237191');
      expect(r.vinculado, isFalse, reason: 'nome não é cadastro');
      expect(r.avisoNaoVinculado, isTrue);
      expect(
        r.textoAvisoNaoVinculado,
        'códigos somados pelo nome · sem vínculo no mapa, '
        'o total pode estar incompleto',
      );
    });

    test('linha única fora do mapa mantém a ressalva antiga', () {
      final r = montarResultado(
        codigoLido: '900001',
        linhas: irmaosPorNome('900001', todas),
        codigosVinculados: const [],
      );
      expect(
        r.textoAvisoNaoVinculado,
        'código não vinculado no mapa · o total pode estar incompleto',
      );
    });

    test('código vinculado no mapa não tem ressalva', () {
      final r = montarResultado(
        codigoLido: '222534',
        linhas: phosfix,
        codigosVinculados: const ['222534', 'US222534'],
      );
      expect(r.total, 84);
      expect(r.textoAvisoNaoVinculado, isNull);
    });
  });

  group('lista de vencimentos — lote a carregar primeiro', () {
    test('chaveValidade tira prefixo do BI, acento e espaço extra', () {
      expect(
        chaveValidade('100235440 - FUNGICIDA FOX XPRO 20L'),
        'FUNGICIDA FOX XPRO 20L',
      );
      expect(
        chaveValidade('  herbicida  ultimato sc 20l '),
        'HERBICIDA ULTIMATO SC 20L',
      );
      expect(chaveValidade('INSETICIDA ORQUÍDEA 5L'), 'INSETICIDA ORQUIDEA 5L');
      // Nome sem prefixo não é mutilado por conter hífen no meio.
      expect(chaveValidade('HERBICIDA 2,4-D 20L'), 'HERBICIDA 2,4-D 20L');
    });

    test('nomesCombinam aceita nome contido no outro, não pedaço curto', () {
      expect(
        nomesCombinam('HERBICIDA ULTIMATO SC 20L', 'HERBICIDA ULTIMATO SC 20L'),
        isTrue,
      );
      expect(
        nomesCombinam(
            'HERBICIDA ULTIMATO SC 20L BALDE', 'HERBICIDA ULTIMATO SC 20L'),
        isTrue,
      );
      expect(nomesCombinam('20L', 'HERBICIDA ULTIMATO SC 20L'), isFalse);
      expect(nomesCombinam('', 'HERBICIDA ULTIMATO SC 20L'), isFalse);
    });

    test('ordena por validade mais próxima; sem data vai para o fim', () {
      final ordenados = ordenarLotesPorVencimento(const [
        LoteValidade(lote: 'C', vencimento: '2027-01-20'),
        LoteValidade(lote: 'D', vencimento: ''),
        LoteValidade(lote: 'A', vencimento: '2026-09-12'),
        LoteValidade(lote: 'B', vencimento: '2026-12-14'),
      ]);
      expect(ordenados.map((l) => l.lote).toList(), ['A', 'B', 'C', 'D']);
    });

    test('loteParaCarregar é o de validade mais próxima', () {
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
        lotes: const [
          LoteValidade(lote: '2503B', vencimento: '2026-12-14', quantidade: 40),
          LoteValidade(lote: '2411A', vencimento: '2026-09-12', quantidade: 35),
        ],
      );
      expect(r.loteParaCarregar!.lote, '2411A');
      expect(r.outrosLotes, 1);
    });

    test('lote sem data não é apontado como o primeiro a vencer', () {
      final r = montarResultado(
        codigoLido: '237191',
        linhas: const [],
        codigosVinculados: const ['237191'],
        nomeMapa: 'HERBICIDA ULTIMATO SC 20L',
        lotes: const [LoteValidade(lote: '2411A', vencimento: '')],
      );
      expect(r.lotes, hasLength(1));
      expect(r.loteParaCarregar, isNull);
    });

    test('diasAte: vencido é negativo, hoje é zero', () {
      final hoje = DateTime(2026, 8, 4);
      expect(
        const LoteValidade(lote: 'A', vencimento: '2026-08-04').diasAte(hoje),
        0,
      );
      expect(
        const LoteValidade(lote: 'A', vencimento: '2026-09-12').diasAte(hoje),
        39,
      );
      expect(
        const LoteValidade(lote: 'A', vencimento: '2026-08-01').diasAte(hoje),
        -3,
      );
      expect(
        const LoteValidade(lote: 'A', vencimento: '').diasAte(hoje),
        isNull,
      );
    });

    test('copiarComLotes preserva o resultado e ordena os lotes', () {
      final base = montarResultado(
        codigoLido: '237191',
        linhas: const [
          CodigoSaldo(
            codigo: '237191',
            produto: 'HERBICIDA ULTIMATO SC 20L',
            qtdSistema: 75,
            ultimaContagem: '2026-08-04 15:01',
          ),
        ],
        codigosVinculados: const ['237191'],
      );
      final comLotes = base.copiarComLotes(const [
        LoteValidade(lote: '2503B', vencimento: '2026-12-14'),
        LoteValidade(lote: '2411A', vencimento: '2026-09-12'),
      ]);
      expect(comLotes.total, 75);
      expect(comLotes.nomeProduto, 'HERBICIDA ULTIMATO SC 20L');
      expect(comLotes.ultimaContagem, '2026-08-04 15:01');
      expect(comLotes.lotes.first.lote, '2411A');
      expect(comLotes.lotesIndisponiveis, isFalse);

      final semLista = base.copiarComLotes(const [], indisponivel: true);
      expect(semLista.lotes, isEmpty);
      expect(semLista.lotesIndisponiveis, isTrue);
    });
  });

  group('busca por nome', () {
    const linhas = [
      CodigoSaldo(
        codigo: '254185',
        produto: 'HERBICIDA BORAL 500 SC 20L',
        categoria: 'DEFENSIVOS',
        qtdSistema: 201,
      ),
      CodigoSaldo(
        codigo: 'US254185',
        produto: 'HERBICIDA BORAL 500 SC 20L',
        categoria: 'DEFENSIVOS',
        qtdSistema: 403,
      ),
      CodigoSaldo(
        codigo: '237191',
        produto: 'HERBICIDA ULTIMATO SC 20L',
        qtdSistema: 75,
      ),
      CodigoSaldo(
        codigo: '900001',
        produto: 'INSETICIDA ORQUÍDEA 5L',
        qtdSistema: 4,
      ),
    ];

    test('chaveBusca tira acento, caixa e espaço repetido', () {
      expect(chaveBusca('  inseticida  orquídea 5l '), 'INSETICIDA ORQUIDEA 5L');
      expect(chaveBusca(''), '');
    });

    test('pareceCodigo separa código de nome', () {
      expect(pareceCodigo('US254185'), isTrue);
      expect(pareceCodigo(' 254185 '), isTrue);
      expect(pareceCodigo('BORAL'), isFalse, reason: 'sem dígito');
      expect(pareceCodigo('fox xpro 20l'), isFalse, reason: 'tem espaço');
      expect(pareceCodigo(''), isFalse);
    });

    test('nomeCasaBusca: E entre as palavras, em qualquer ordem', () {
      expect(
        nomeCasaBusca('HERBICIDA BORAL 500 SC 20L', palavrasBusca('boral 20')),
        isTrue,
      );
      expect(
        nomeCasaBusca('HERBICIDA BORAL 500 SC 20L', palavrasBusca('boral fox')),
        isFalse,
      );
      expect(
        nomeCasaBusca('INSETICIDA ORQUÍDEA 5L', palavrasBusca('orquidea')),
        isTrue,
        reason: 'acento não pode esconder o produto',
      );
      expect(nomeCasaBusca('QUALQUER COISA', const []), isFalse);
    });

    test('os dois códigos do mesmo produto viram um item, com saldo somado',
        () {
      final achados = buscarNasLinhas('boral', linhas);
      expect(achados, hasLength(1));
      expect(achados.first.nome, 'HERBICIDA BORAL 500 SC 20L');
      expect(achados.first.total, 604);
      expect(achados.first.codigos, ['254185', 'US254185']);
      expect(achados.first.codigo, '254185', reason: 'o menor, para ser estável');
      expect(achados.first.categoria, 'DEFENSIVOS');
    });

    test('termo genérico traz vários; termo curto não busca', () {
      expect(buscarNasLinhas('herbicida', linhas), hasLength(2));
      expect(buscarNasLinhas('or', linhas), isEmpty);
      expect(buscarNasLinhas('xyz', linhas), isEmpty);
    });

    test('busca com acento acha o nome acentuado', () {
      final achados = buscarNasLinhas('orquídea', linhas);
      expect(achados, hasLength(1));
      expect(achados.first.codigo, '900001');
    });

    test('limite corta a lista', () {
      expect(buscarNasLinhas('herbicida', linhas, limite: 1), hasLength(1));
    });

    test('nome igual ao digitado vem antes do que só contém', () {
      final ordenados = ordenarPorRelevancia('herbicida ultimato sc 20l', const [
        ProdutoEncontrado(codigo: '1', nome: 'HERBICIDA ULTIMATO SC 20L BALDE'),
        ProdutoEncontrado(codigo: '2', nome: 'HERBICIDA ULTIMATO SC 20L'),
      ]);
      expect(ordenados.map((p) => p.codigo).toList(), ['2', '1']);
    });
  });

  group('formatarQuantidade', () {
    test('inteiros sem casas, com milhar', () {
      expect(formatarQuantidade(604), '604');
      expect(formatarQuantidade(0), '0');
      expect(formatarQuantidade(1800), '1.800');
      expect(formatarQuantidade(12080), '12.080');
    });

    test('frações com vírgula, sem zeros à direita', () {
      expect(formatarQuantidade(12.5), '12,5');
      expect(formatarQuantidade(30.25), '30,25');
    });

    test('negativos', () {
      expect(formatarQuantidade(-42), '-42');
      expect(formatarQuantidade(-1234), '-1.234');
    });
  });
}
