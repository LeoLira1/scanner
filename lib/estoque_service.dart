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
    final client = await _clientePronto(turso);

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
        // Código não vinculado a nenhum mapa_produtos. Aplica a convenção
        // US-prefix: todo produto com dois códigos tem um com 'US' na
        // frente ('254185' ↔ 'US254185'). Busca o par no estoque_mestre
        // para somar os dois saldos. Se o par não existir, _lerEstoque
        // devolve só o código que existe — sem erro.
        final par = _codigoPar(codigo);
        final codigos = par != null ? [codigo, par] : [codigo];
        final linhas = await _lerEstoque(client, codigos);
        if (linhas.isEmpty) return null;
        final base = montarResultado(
          codigoLido: codigo,
          linhas: linhas,
          codigosVinculados: const [],
          doCacheLocal: doCache,
          sincronizadoEm: sincronizadoEm,
        );
        return _comLotes(client, base);
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

      final base = montarResultado(
        codigoLido: codigo,
        linhas: linhas,
        codigosVinculados: codigos,
        nomeMapa: produto.nome,
        unidadePad: produto.unidadePad,
        doCacheLocal: doCache,
        sincronizadoEm: sincronizadoEm,
      );
      return _comLotes(client, base, nomeMapa: produto.nome);
    } on ConsultaException {
      rethrow;
    } catch (e) {
      throw ConsultaException('Falha na consulta: $e');
    }
  }

  /// Busca produtos pelo NOME — o caminho de quem tem o produto na mão mas
  /// não tem etiqueta legível (o mesmo campo de busca do app do galpão, o
  /// camdaapp, onde dá para procurar por "boral" em vez do código).
  ///
  /// As palavras do termo valem em qualquer ordem e acento não atrapalha
  /// ('orquidea' acha 'ORQUÍDEA'). Códigos do mesmo produto vêm agrupados
  /// numa linha só, com o saldo somado. Devolve lista vazia quando o termo
  /// é curto demais ([minLetrasBusca]) ou nada casa; lança
  /// [ConsultaException] quando não há conexão ou a consulta falha.
  Future<List<ProdutoEncontrado>> buscarPorNome(
    String termo, {
    int limite = limiteBusca,
  }) async {
    final palavras = palavrasBusca(termo);
    if (palavras.join().length < minLetrasBusca) return const [];

    final client = await _clientePronto(TursoService());
    try {
      // Filtro barato primeiro: a palavra mais longa do termo (a marca, em
      // geral) no SQL. Se ele não render casamento nenhum, varre a tabela —
      // o `LIKE` do SQLite não ignora acento, então 'ORQUIDEA' não acharia
      // 'ORQUÍDEA' e o produto sumiria da busca sem a varredura. O
      // casamento final é sempre em Dart, por [nomeCasaBusca].
      final maisLonga = palavras.reduce((a, b) => b.length > a.length ? b : a);
      if (maisLonga.length >= minLetrasBusca) {
        final linhas = await _lerEstoqueComoLike(client, maisLonga);
        final achados = buscarNasLinhas(termo, linhas, limite: limite);
        if (achados.isNotEmpty) return achados;
      }

      final stmt = await client.prepare(_colunasEstoque);
      final linhas = _mapearLinhas(await stmt.query());
      return buscarNasLinhas(termo, linhas, limite: limite);
    } on ConsultaException {
      rethrow;
    } catch (e) {
      throw ConsultaException('Falha na busca: $e');
    }
  }

  static const _colunasEstoque =
      'SELECT codigo, produto, categoria, qtd_sistema, ultima_contagem '
      'FROM estoque_mestre';

  Future<List<CodigoSaldo>> _lerEstoqueComoLike(
    LibsqlClient client,
    String pedaco,
  ) async {
    final stmt = await client.prepare(
      "$_colunasEstoque WHERE UPPER(TRIM(produto)) LIKE '%' || ? || '%'",
    );
    return _mapearLinhas(await stmt.query(positional: [pedaco]));
  }

  static List<CodigoSaldo> _mapearLinhas(Iterable<dynamic> rows) {
    final linhas = <CodigoSaldo>[];
    for (final r in rows) {
      final cod = normalizarCodigo(_texto(r['codigo']));
      if (cod == null) continue;
      linhas.add(CodigoSaldo(
        codigo: cod,
        produto: _texto(r['produto']),
        categoria: _texto(r['categoria']).trim(),
        qtdSistema: _numero(r['qtd_sistema']),
        ultimaContagem: _texto(r['ultima_contagem']),
      ));
    }
    return linhas;
  }

  /// Conexão viva e com dados prontos, ou [ConsultaException] com a
  /// mensagem que a tela mostra.
  Future<LibsqlClient> _clientePronto(TursoService turso) async {
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
    return turso.client!;
  }

  /// Acopla ao resultado os lotes do produto na lista de vencimentos.
  ///
  /// A lista é um extra sobre o saldo: se a leitura falhar (tabela ausente
  /// num banco sem o módulo de validade, erro de rede no meio da consulta),
  /// o saldo continua aparecendo e a tela avisa que a lista não veio — em
  /// vez de o app inteiro morrer por causa do lote.
  Future<ResultadoConsulta> _comLotes(
    LibsqlClient client,
    ResultadoConsulta base, {
    String? nomeMapa,
  }) async {
    try {
      final lotes = await _lerLotes(client, [base.nomeProduto, nomeMapa ?? '']);
      return base.copiarComLotes(lotes);
    } catch (_) {
      return base.copiarComLotes(const [], indisponivel: true);
    }
  }

  /// Lotes de `validade_lotes` que pertencem ao produto.
  ///
  /// `validade_lotes` NÃO tem coluna de código — o vínculo é pelo nome, e os
  /// nomes vêm do BI com prefixo de código ("100235440 - FUNGICIDA FOX XPRO
  /// 20L"). Por isso o casamento é por [chaveValidade]/[nomesCombinam], a
  /// mesma regra do dashboard.
  Future<List<LoteValidade>> _lerLotes(
    LibsqlClient client,
    List<String> nomes,
  ) async {
    final chaves = <String>{};
    for (final n in nomes) {
      final k = chaveValidade(n);
      // Nome curto demais casaria com meio catálogo — melhor não mostrar
      // lote nenhum do que apontar o lote de outro produto.
      if (k.length >= 6) chaves.add(k);
    }
    if (chaves.isEmpty) return const [];

    // Filtros baratos primeiro: o nome inteiro e depois a palavra mais longa
    // (a marca, em geral: 'ULTIMATO'). Só se os dois falharem é que a tabela
    // inteira é varrida — o LIKE do SQLite não ignora acento, então nome
    // acentuado costuma cair na varredura.
    final filtros = <String>[];
    for (final c in chaves) {
      filtros.add(c);
      final palavras = c.split(' ')..sort((a, b) => b.length.compareTo(a.length));
      if (palavras.isNotEmpty && palavras.first.length >= 5) {
        filtros.add(palavras.first);
      }
    }

    for (final filtro in filtros) {
      final stmt = await client.prepare(
        'SELECT produto, lote, vencimento, quantidade FROM validade_lotes '
        "WHERE UPPER(TRIM(produto)) LIKE '%' || ? || '%'",
      );
      final achados = _mapearLotes(await stmt.query(positional: [filtro]), chaves);
      if (achados.isNotEmpty) return achados;
    }

    final stmt = await client.prepare(
      'SELECT produto, lote, vencimento, quantidade FROM validade_lotes',
    );
    return _mapearLotes(await stmt.query(), chaves);
  }

  /// Converte as linhas lidas em lotes, ficando só com as que casam com o
  /// produto — o filtro do SQL é aproximado de propósito.
  static List<LoteValidade> _mapearLotes(
    Iterable<dynamic> rows,
    Set<String> chaves,
  ) {
    final lotes = <LoteValidade>[];
    for (final r in rows) {
      final produto = _texto(r['produto']);
      final chaveLinha = chaveValidade(produto);
      if (!chaves.any((c) => nomesCombinam(chaveLinha, c))) continue;
      final lote = _texto(r['lote']).trim();
      lotes.add(LoteValidade(
        lote: lote.isEmpty ? '—' : lote,
        vencimento: _texto(r['vencimento']).trim(),
        quantidade: _numero(r['quantidade']),
        produto: produto,
      ));
    }
    return lotes;
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
    final porCodigo = {for (final l in _mapearLinhas(rows)) l.codigo: l};

    // Na ordem canônica dos códigos, para a exibição ser estável.
    return [
      for (final c in codigos)
        if (porCodigo.containsKey(c)) porCodigo[c]!,
    ];
  }

  /// Par de código pela convenção US-prefix: 'US254185' → '254185',
  /// '254185' → 'US254185'. Retorna null se remover 'US' deixaria vazio.
  static String? _codigoPar(String codigo) {
    if (codigo.startsWith('US')) {
      final sem = codigo.substring(2);
      return sem.isEmpty ? null : sem;
    }
    return 'US$codigo';
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
