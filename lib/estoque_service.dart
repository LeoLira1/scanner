import 'package:libsql_dart/libsql_dart.dart';

import 'consulta.dart';
import 'turso_service.dart';

/// Falha de consulta com mensagem já pronta para o usuário.
class ConsultaException implements Exception {
  final String mensagem;
  const ConsultaException(this.mensagem);

  @override
  String toString() => mensagem;
}

/// Consultas de estoque — SOMENTE SELECTs, nenhuma escrita.
///
/// Reproduz em Dart o comportamento do db_mapa.py (buscar_por_codigo e o
/// sync multi-código): o código lido resolve o produto em mapa_produtos /
/// mapa_produtos_codigos e o saldo exibido é a SOMA do qtd_sistema de
/// todos os códigos vinculados ao produto.
class EstoqueService {
  static final EstoqueService _instance = EstoqueService._internal();
  factory EstoqueService() => _instance;
  EstoqueService._internal();

  /// Consulta uma leitura (código puro ou URL com p=).
  ///
  /// Retorna null quando o código não existe em lugar nenhum (nem no mapa,
  /// nem em estoque_mestre). Lança [ConsultaException] quando não há
  /// conexão ou a consulta falha.
  Future<ResultadoConsulta?> consultarPorCodigo(String leitura) async {
    final codigo = extrairCodigo(leitura);
    if (codigo == null) {
      throw const ConsultaException('Leitura vazia — digite ou escaneie um código.');
    }

    final turso = TursoService();
    if (!await turso.garantirConexao()) {
      final configurado = await turso.credenciaisConfiguradas();
      throw ConsultaException(configurado
          ? 'Sem conexão com o banco — verifique a internet.'
          : 'Configure URL e token do banco em ⚙️.');
    }
    // Cache local recém-criado: espera a carga inicial. Consultar a replica
    // vazia responderia "não encontrado" para qualquer código — erro
    // silencioso, justamente o que não pode acontecer aqui.
    if (!await turso.garantirDadosProntos()) {
      throw ConsultaException(
        'O cache local ainda está vazio e não deu para baixar os dados '
        '(${turso.ultimoErroSync ?? 'sem conexão'}). '
        'Conecte à internet e toque em Sincronizar em ⚙️.',
      );
    }
    final client = turso.client!;

    // Dado servido do arquivo local é rotulado na tela do produto com o
    // horário da última sincronização.
    final doCache = turso.modoLocal;
    final sincronizadoEm = turso.ultimaSincronizacao;

    try {
      // 1. Resolve o produto por QUALQUER um de seus códigos — principal
      //    (mapa_produtos.codigo) ou secundário (mapa_produtos_codigos).
      _ProdutoMapa? produto;
      try {
        produto = await _resolverProduto(client, codigo);
      } catch (e) {
        if (!_tabelaAusente(e)) rethrow;
        // Banco sem as tabelas do mapa: segue como código não vinculado.
        produto = null;
      }

      if (produto == null) {
        // Código não vinculado a nenhum mapa_produtos: não existe grupo de
        // códigos para somar. Mostra o saldo da linha única de
        // estoque_mestre — a UI exibe o aviso de total possivelmente
        // incompleto (silenciar isso recria o bug corrigido no dashboard).
        final linhas = await _lerEstoque(client, [codigo]);
        if (linhas.isEmpty) return null;
        return montarResultado(
          codigoLido: codigo,
          linhas: linhas,
          codigosVinculados: const [],
          doCacheLocal: doCache,
          sincronizadoEm: sincronizadoEm,
        );
      }

      // 2. Todos os códigos do produto (principal + secundários), na forma
      //    canônica e ordenados — como get_codigos_produto.
      final codigos = await _codigosDoProduto(
        client,
        produto.produtoId,
        produto.codigoPrincipal,
      );

      // 3. Soma o saldo de todos os códigos do grupo.
      final linhas = await _lerEstoque(client, codigos);
      if (linhas.isEmpty && produto.nome.isEmpty) return null;

      return montarResultado(
        codigoLido: codigo,
        linhas: linhas,
        codigosVinculados: codigos,
        nomeMapa: produto.nome,
        unidadePad: produto.unidadePad,
        doCacheLocal: doCache,
        sincronizadoEm: sincronizadoEm,
      );
    } on ConsultaException {
      rethrow;
    } catch (e) {
      throw ConsultaException('Falha na consulta: $e');
    }
  }

  /// True quando a exceção é "tabela não existe".
  ///
  /// `mapa_produtos` e `mapa_produtos_codigos` são criadas pelo dashboard
  /// (db_mapa.ensure_mapa_tables) e podem não existir num banco onde o
  /// mapa nunca foi usado. Nesse caso o certo é cair no saldo da linha
  /// única de estoque_mestre com o aviso de total incompleto — e não
  /// estourar um erro cru na cara de quem está no galpão.
  static bool _tabelaAusente(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('no such table');
  }

  Future<_ProdutoMapa?> _resolverProduto(
    LibsqlClient client,
    String codigo,
  ) async {
    final stmt = await client.prepare(
      'SELECT mp.produto_id, mp.nome, mp.unidade_pad, mp.codigo '
      'FROM mapa_produtos mp '
      'WHERE (mp.codigo IS NOT NULL AND UPPER(TRIM(mp.codigo)) = ?) '
      '   OR EXISTS (SELECT 1 FROM mapa_produtos_codigos mpc '
      '              WHERE mpc.produto_id = mp.produto_id '
      '                AND UPPER(TRIM(mpc.codigo)) = ?) '
      'LIMIT 1',
    );
    final rows = await stmt.query(positional: [codigo, codigo]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return _ProdutoMapa(
      produtoId: _texto(r['produto_id']),
      nome: _texto(r['nome']),
      unidadePad: _texto(r['unidade_pad']).trim(),
      codigoPrincipal: _texto(r['codigo']),
    );
  }

  Future<List<String>> _codigosDoProduto(
    LibsqlClient client,
    String produtoId,
    String? codigoPrincipal,
  ) async {
    final cods = <String>{};
    try {
      final stmt = await client.prepare(
        'SELECT codigo FROM mapa_produtos_codigos WHERE produto_id = ?',
      );
      final rows = await stmt.query(positional: [produtoId]);
      for (final row in rows) {
        final c = normalizarCodigo(_texto(row['codigo']));
        if (c != null) cods.add(c);
      }
    } catch (e) {
      // Sem a tabela de códigos secundários resta o principal — melhor que
      // derrubar a consulta inteira.
      if (!_tabelaAusente(e)) rethrow;
    }
    final principal = normalizarCodigo(codigoPrincipal);
    if (principal != null) cods.add(principal);
    final lista = cods.toList()..sort();
    return lista;
  }

  Future<List<CodigoSaldo>> _lerEstoque(
    LibsqlClient client,
    List<String> codigos,
  ) async {
    if (codigos.isEmpty) return const [];
    final placeholders = List.filled(codigos.length, '?').join(', ');
    final stmt = await client.prepare(
      'SELECT codigo, produto, categoria, qtd_sistema, ultima_contagem '
      'FROM estoque_mestre '
      'WHERE UPPER(TRIM(codigo)) IN ($placeholders)',
    );
    final rows = await stmt.query(positional: codigos);

    final porCodigo = <String, CodigoSaldo>{};
    for (final r in rows) {
      final cod = normalizarCodigo(_texto(r['codigo']));
      if (cod == null) continue;
      porCodigo[cod] = CodigoSaldo(
        codigo: cod,
        produto: _texto(r['produto']),
        categoria: _texto(r['categoria']).trim(),
        qtdSistema: _numero(r['qtd_sistema']),
        ultimaContagem: _texto(r['ultima_contagem']),
      );
    }

    // Na ordem canônica dos códigos, para a exibição ser estável.
    return [
      for (final c in codigos)
        if (porCodigo.containsKey(c)) porCodigo[c]!,
    ];
  }

  /// Lê uma coluna como texto sem assumir o tipo devolvido pelo driver.
  /// As colunas são TEXT no esquema, mas um cast rígido que falhasse
  /// transformaria toda consulta em "Falha na consulta" no meio do galpão.
  static String _texto(dynamic v) => v?.toString() ?? '';

  static double _numero(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

class _ProdutoMapa {
  final String produtoId;
  final String nome;
  final String? unidadePad;
  final String? codigoPrincipal;

  const _ProdutoMapa({
    required this.produtoId,
    required this.nome,
    this.unidadePad,
    this.codigoPrincipal,
  });
}
