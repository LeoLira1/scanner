import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_camda/espelho.dart';

void main() {
  group('sqlPagina', () {
    test('pagina por keyset em rowid, não por OFFSET', () {
      final sql = tabelaEstoqueMestre.sqlPagina;
      expect(sql, contains('rowid AS $colunaCursor'));
      expect(sql, contains('WHERE rowid > ?'));
      expect(sql, contains('ORDER BY rowid LIMIT ?'));
      // OFFSET relê as linhas anteriores a cada página: mais lento e mais
      // caro em rows read no Turso.
      expect(sql.toUpperCase(), isNot(contains('OFFSET')));
    });

    test('traz todas as colunas espelhadas e nada além delas', () {
      for (final tabela in tabelasEspelho) {
        final sql = tabela.sqlPagina;
        for (final coluna in tabela.nomesColunas) {
          expect(sql, contains(coluna), reason: '${tabela.nome}.$coluna');
        }
        expect(sql, contains('FROM ${tabela.nome}'));
      }
    });

    test('não puxa as colunas pesadas que o app nunca lê', () {
      // O motivo de tudo isto existir: a réplica antiga baixava o banco
      // inteiro, com as fotos em base64 do camda-estoque dentro.
      for (final tabela in tabelasEspelho) {
        expect(tabela.sqlPagina, isNot(contains('foto_base64')));
      }
      expect(
        tabelaEstoqueMestre.nomesColunas,
        isNot(contains('qtd_fisica')),
      );
    });
  });

  group('inserção em lote', () {
    test('respeita o teto de parâmetros por statement', () {
      for (final tabela in tabelasEspelho) {
        final parametros = tabela.linhasPorLote * tabela.colunas.length;
        expect(parametros, lessThanOrEqualTo(maxParametrosPorStatement),
            reason: tabela.nome);
        expect(tabela.linhasPorLote, greaterThan(0), reason: tabela.nome);
      }
    });

    test('estoque_mestre cabe 180 linhas por statement', () {
      // 5 colunas × 180 = 900, o teto exato.
      expect(tabelaEstoqueMestre.linhasPorLote, 180);
    });

    test('o SQL tem um grupo de marcadores por linha', () {
      final sql = tabelaMapaProdutosCodigos.sqlInsercaoLote('alvo', 3);
      expect(sql, 'INSERT INTO alvo (produto_id, codigo) '
          'VALUES (?, ?), (?, ?), (?, ?)');
    });

    test('os parâmetros saem achatados na ordem das colunas', () {
      final parametros = tabelaMapaProdutosCodigos.parametrosLote([
        {'codigo': 'US254185', 'produto_id': 'p1'},
        {'produto_id': 'p2', 'codigo': '254185'},
      ]);
      expect(parametros, ['p1', 'US254185', 'p2', '254185']);
    });

    test('NULL é preservado, não vira string vazia', () {
      // mapa_produtos.codigo nulo é significativo: a consulta do app filtra
      // por `codigo IS NOT NULL`.
      final parametros = tabelaMapaProdutos.parametrosLote([
        {'produto_id': 'p1', 'nome': 'BORAL', 'unidade_pad': 'L', 'codigo': null},
      ]);
      expect(parametros, ['p1', 'BORAL', 'L', null]);
    });

    test('coluna de texto aceita número do driver sem trocar de tipo', () {
      // produto_id chega como int e a consulta compara com String: sem a
      // conversão, `WHERE produto_id = ?` deixaria de casar e o saldo viria
      // pela metade.
      final parametros = tabelaMapaProdutosCodigos.parametrosLote([
        {'produto_id': 5, 'codigo': 254185},
      ]);
      expect(parametros, ['5', '254185']);
    });

    test('coluna numérica aceita texto do driver', () {
      final parametros = tabelaEstoqueMestre.parametrosLote([
        {
          'codigo': '254185',
          'produto': 'HERBICIDA BORAL 500 SC 20L',
          'categoria': 'HERBICIDA',
          'qtd_sistema': '604',
          'ultima_contagem': '2026-08-01',
        },
      ]);
      expect(parametros[3], 604);
    });

    test('valor ilegível vira zero em vez de derrubar a atualização', () {
      final parametros = tabelaEstoqueMestre.parametrosLote([
        {'qtd_sistema': 'oito'},
      ]);
      expect(parametros[3], 0);
    });
  });

  group('DDL do espelho', () {
    test('o CREATE TABLE usa o nome alvo, não o da tabela viva', () {
      final ddl = tabelaEstoqueMestre.ddl(
        tabelaEncenacao(tabelaEstoqueMestre.nome),
      );
      expect(ddl, startsWith('CREATE TABLE estoque_mestre__novo ('));
      expect(ddl, contains('codigo TEXT'));
      expect(ddl, contains('qtd_sistema NUMERIC'));
    });

    test('os índices são sobre a expressão que o app consulta', () {
      // As consultas comparam por UPPER(TRIM(codigo)); um índice comum sobre
      // `codigo` não seria usado.
      final indices = tabelaEstoqueMestre.ddlIndices('estoque_mestre');
      expect(indices, hasLength(1));
      expect(indices.first, contains('UPPER(TRIM(codigo))'));
      expect(indices.first, contains('ON estoque_mestre'));
    });

    test('nomes de índice não colidem entre tabelas', () {
      // Nome de índice é global no SQLite: dois iguais quebrariam a troca.
      final nomes = <String>[];
      for (final tabela in tabelasEspelho) {
        for (final ddl in tabela.ddlIndices(tabela.nome)) {
          nomes.add(RegExp(r'INDEX IF NOT EXISTS (\w+)').firstMatch(ddl)!.group(1)!);
        }
      }
      expect(nomes.toSet(), hasLength(nomes.length));
    });

    test('a tabela de encenação não é a viva', () {
      for (final tabela in tabelasEspelho) {
        expect(tabelaEncenacao(tabela.nome), isNot(tabela.nome));
      }
    });
  });

  group('Impressao', () {
    test('lê os agregados na ordem dos apelidos f0, f1, …', () {
      final impressao = Impressao.deLinha({'f0': 3412, 'f1': 91820, 'f2': ''});
      expect(impressao.valor, '3412|91820|');
    });

    test('valor nulo entra como vazio, sem furar a leitura', () {
      expect(Impressao.deLinha({'f0': 10, 'f1': null}).valor, '10|');
    });

    test('para no primeiro apelido ausente', () {
      // Sem isso, um agregado sem apelido sairia calado da impressão e uma
      // alteração no banco passaria batida.
      expect(Impressao.deLinha({'f0': 1, 'f2': 9}).valor, '1');
    });

    test('linha vazia vira impressão vazia', () {
      expect(Impressao.deLinha(const {}).vazia, isTrue);
    });

    test('impressões iguais são iguais; uma diferença invalida', () {
      final antes  = Impressao.deLinha({'f0': 3412, 'f1': 91820});
      final igual  = Impressao.deLinha({'f0': 3412, 'f1': 91820});
      final depois = Impressao.deLinha({'f0': 3412, 'f1': 91821});
      expect(antes, igual);
      expect(antes.hashCode, igual.hashCode);
      expect(antes, isNot(depois));
    });

    test('sobrevive à ida e volta pelo texto guardado nas preferências', () {
      final original = Impressao.deLinha({'f0': 3412, 'f1': 91820, 'f2': '2026-08-27'});
      // É assim que ela é gravada e relida em turso_service.
      expect(Impressao(original.valor), original);
    });
  });

  group('validade da impressão', () {
    final agora = DateTime(2026, 8, 27, 12, 0);

    test('recém-baixada vale', () {
      final baixada = agora.subtract(const Duration(minutes: 30));
      expect(
        impressaoAindaVale(baixada.toIso8601String(), agora: agora),
        isTrue,
      );
    });

    test('velha demais não vale — a tabela é rebaixada mesmo sem sinal de '
        'mudança', () {
      // É o que fecha sozinho o ponto cego da impressão: o upload incremental
      // do dashboard renomeia `produto` sem tocar em `criado_em`.
      final baixada = agora.subtract(validadeImpressao + const Duration(minutes: 1));
      expect(
        impressaoAindaVale(baixada.toIso8601String(), agora: agora),
        isFalse,
      );
    });

    test('nunca baixada não vale', () {
      expect(impressaoAindaVale(null, agora: agora), isFalse);
    });

    test('data ilegível não vale', () {
      expect(impressaoAindaVale('ontem de manhã', agora: agora), isFalse);
    });

    test('data no futuro não vale', () {
      // Relógio do aparelho andou para trás: confiar nisso seguraria dado
      // velho por tempo indefinido.
      final futuro = agora.add(const Duration(hours: 2));
      expect(
        impressaoAindaVale(futuro.toIso8601String(), agora: agora),
        isFalse,
      );
    });

    test('o teto é curto o bastante para caber num turno', () {
      expect(validadeImpressao, lessThanOrEqualTo(const Duration(hours: 8)));
      expect(validadeImpressao, greaterThan(const Duration(hours: 1)));
    });
  });

  group('SQL da impressão digital', () {
    test('os apelidos são f0..fN contíguos', () {
      // Impressao.deLinha para no primeiro buraco: um agregado sem apelido,
      // ou fora de sequência, sairia calado e uma mudança no banco não seria
      // percebida.
      for (final tabela in tabelasEspelho) {
        final sql = tabela.sqlImpressao;
        if (sql == null) continue;
        final apelidos = RegExp(r'AS (f\d+)')
            .allMatches(sql)
            .map((m) => m.group(1)!)
            .toList();
        expect(apelidos, isNotEmpty, reason: tabela.nome);
        expect(
          apelidos,
          [for (var i = 0; i < apelidos.length; i++) 'f$i'],
          reason: tabela.nome,
        );
      }
    });

    test('estoque_mestre marca reescrita, edição e exclusão', () {
      final sql = tabelaEstoqueMestre.sqlImpressao!;
      // Upload de planilha reescreve a tabela inteira → criado_em muda.
      expect(sql, contains('MAX(criado_em)'));
      // Edição pontual de quantidade → a soma muda.
      expect(sql, contains('SUM(qtd_sistema)'));
      // Troca de quantidade entre duas linhas → só o peso por rowid pega.
      expect(sql, contains('SUM(qtd_sistema * rowid)'));
      // Exclusão de produto → a contagem muda.
      expect(sql, contains('COUNT(*)'));
    });

    test('validade_lotes marca a reescrita em bloco', () {
      final sql = tabelaValidadeLotes.sqlImpressao!;
      expect(sql, contains('MAX(uploaded_em)'));
      expect(sql, contains('MAX(id)'));
    });

    test('as tabelas do mapa são sempre rebaixadas', () {
      // Não têm coluna de data que marque alteração, e são pequenas: baixar
      // inteiro sai mais barato que arriscar somar saldo com vínculo velho.
      expect(tabelaMapaProdutos.sqlImpressao, isNull);
      expect(tabelaMapaProdutosCodigos.sqlImpressao, isNull);
    });
  });
}
