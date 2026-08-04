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
