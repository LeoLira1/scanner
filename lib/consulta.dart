/// Lógica pura da consulta por código — sem dependência de Flutter/banco,
/// para ser testável em Dart puro (test/consulta_test.dart).
///
/// Reproduz o comportamento do db_mapa.py do camda-estoque:
/// - _norm_codigo: UPPER(TRIM()), vazio vira null;
/// - buscar_por_codigo / sync multi-código: um produto da CAMDA pode ter
///   mais de um código ativo ('254185' e 'US254185'), cada um com saldo
///   próprio em estoque_mestre — o saldo real é a SOMA de todos eles.
library;

/// Um lote da lista de vencimentos (`validade_lotes` do camda-estoque).
///
/// A tabela não tem coluna de código — o vínculo com `estoque_mestre` é pelo
/// NOME do produto, e os nomes vindos do BI carregam um prefixo de código
/// ("100235440 - FUNGICIDA FOX XPRO 20L"). Ver [chaveValidade].
class LoteValidade {
  /// Identificação do lote, como está gravada ('2411A').
  final String lote;

  /// Vencimento como está no banco — 'AAAA-MM-DD' (save_validade_lotes grava
  /// com strftime('%Y-%m-%d')) ou '' quando a planilha veio sem data.
  final String vencimento;

  /// Quantidade do lote, número cru da planilha de validade (mesma ressalva
  /// de unidade do qtd_sistema: não é convertida nem rotulada).
  final double quantidade;

  /// Nome do produto como está em `validade_lotes`, com o prefixo do BI.
  final String produto;

  const LoteValidade({
    required this.lote,
    required this.vencimento,
    this.quantidade = 0,
    this.produto = '',
  });

  /// Vencimento parseado, ou null quando a data está em branco/ilegível.
  DateTime? get data {
    final t = vencimento.trim();
    if (t.isEmpty) return null;
    return DateTime.tryParse(t.length > 10 ? t.substring(0, 10) : t);
  }

  /// Dias entre [hoje] e o vencimento: negativo = já vencido, 0 = vence hoje.
  /// Null quando não há data legível.
  int? diasAte(DateTime hoje) {
    final d = data;
    if (d == null) return null;
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    return DateTime(d.year, d.month, d.day).difference(h).inDays;
  }
}

const _comAcento = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ';
const _semAcento = 'AAAAAEEEEIIIIOOOOOUUUUCNAAAAAEEEEIIIIOOOOOUUUUCN';

/// Prefixo de código do BI nos nomes de `validade_lotes`:
/// "100235440 - FUNGICIDA FOX XPRO 20L" → "FUNGICIDA FOX XPRO 20L".
final RegExp _prefixoBi = RegExp(r'^\s*[A-Z0-9\-]{3,20}\s*[-–]\s*(.+)$');

/// Texto em maiúsculo, sem acento e com os espaços colapsados — a forma em
/// que nomes de produto são comparados (busca e lista de vencimentos).
String chaveBusca(String texto) {
  final semAcentos = StringBuffer();
  for (final c in texto.trim().toUpperCase().split('')) {
    final i = _comAcento.indexOf(c);
    semAcentos.write(i >= 0 ? _semAcento[i] : c);
  }
  // Acento em forma decomposta (letra + marca combinante) não está na tabela
  // acima; a marca sai aqui.
  return semAcentos
      .toString()
      .replaceAll(RegExp('[\\u0300-\\u036F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Chave de comparação entre o nome de `estoque_mestre` e o de
/// `validade_lotes`: sem prefixo do BI, sem acento, maiúsculo e com os
/// espaços colapsados. Mesma regra do `_nome_validade_key` do dashboard.
String chaveValidade(String nome) {
  final s = chaveBusca(nome);
  final m = _prefixoBi.firstMatch(s);
  return m != null ? m.group(1)!.trim() : s;
}

/// True quando duas chaves de nome apontam para o mesmo produto.
///
/// Além da igualdade, aceita uma chave contida na outra (com no mínimo 6
/// caracteres, como o dashboard faz): a planilha de validade e a de estoque
/// abreviam o mesmo produto de formas ligeiramente diferentes.
bool nomesCombinam(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.length < 6 || b.length < 6) return false;
  return a.contains(b) || b.contains(a);
}

/// Ordena os lotes na ordem de carregamento (FEFO — *first expired, first
/// out*): validade mais próxima primeiro. Lotes sem data legível vão para o
/// fim, porque não dá para afirmar que vencem antes de ninguém.
List<LoteValidade> ordenarLotesPorVencimento(List<LoteValidade> lotes) {
  final comData = <LoteValidade>[];
  final semData = <LoteValidade>[];
  for (final l in lotes) {
    (l.data != null ? comData : semData).add(l);
  }
  comData.sort((a, b) {
    final c = a.data!.compareTo(b.data!);
    return c != 0 ? c : a.lote.compareTo(b.lote);
  });
  semData.sort((a, b) => a.lote.compareTo(b.lote));
  return [...comData, ...semData];
}

/// Normaliza um código de produto para a forma canônica: UPPER(TRIM()).
/// Retorna null para valores vazios — mesma regra do _norm_codigo.
String? normalizarCodigo(String? codigo) {
  if (codigo == null) return null;
  final texto = codigo.trim().toUpperCase();
  return texto.isEmpty ? null : texto;
}

/// Extrai o código de uma leitura de QR/barcode ou digitação.
///
/// Aceita tanto um código puro ('US254185', com espaços acidentais) quanto
/// uma URL que contenha o parâmetro `p=` (ex.:
/// 'https://camda.app/estoque?p=US254185'). Retorna o código já
/// normalizado, ou null se não há código na leitura.
String? extrairCodigo(String bruto) {
  final texto = bruto.trim();
  if (texto.isEmpty) return null;

  // URL com p= — o formato impresso nas folhas A4 do galpão.
  if (texto.contains('p=')) {
    final uri = Uri.tryParse(texto);
    if (uri != null && uri.queryParameters.containsKey('p')) {
      return normalizarCodigo(uri.queryParameters['p']);
    }
    // URL malformada para o parser mas com p= visível: extrai na unha.
    final m = RegExp(r'[?&#]p=([^&#\s]+)').firstMatch(texto);
    if (m != null) {
      return normalizarCodigo(Uri.decodeComponent(m.group(1)!));
    }
  }

  return normalizarCodigo(texto);
}

/// Mínimo de caracteres para uma busca por nome valer a pena: com menos de
/// três letras o galpão inteiro casa e a lista não ajuda ninguém.
const int minLetrasBusca = 3;

/// Teto de itens da busca por nome. Passar disso é sinal de termo genérico
/// ('herbicida'): a tela pede para refinar em vez de rolar o catálogo.
const int limiteBusca = 60;

/// Palavras de um termo de busca, normalizadas ([chaveBusca]) e sem os
/// pedaços vazios: 'boral  20l' → ['BORAL', '20L'].
List<String> palavrasBusca(String termo) {
  final chave = chaveBusca(termo);
  if (chave.isEmpty) return const [];
  return chave.split(' ').where((p) => p.isNotEmpty).toList(growable: false);
}

/// True quando o texto digitado tem cara de código de produto — uma só
/// palavra, com dígito e sem letra acentuada ('254185', 'US254185').
///
/// Serve para escolher o caminho da consulta: parecendo código, a busca vai
/// primeiro em `estoque_mestre`/mapa por código; senão vai direto para a
/// busca por nome. Um código que não existe ainda cai na busca por nome
/// depois — a heurística nunca é a última palavra.
bool pareceCodigo(String termo) {
  final t = chaveBusca(termo);
  if (t.isEmpty || t.contains(' ')) return false;
  if (!RegExp(r'^[A-Z0-9\-./]+$').hasMatch(t)) return false;
  return RegExp(r'[0-9]').hasMatch(t);
}

/// True quando TODAS as palavras do termo aparecem no nome do produto.
///
/// É um E entre as palavras, em qualquer ordem: 'boral 20' acha
/// 'HERBICIDA BORAL 500 SC 20L', e 'fox xpro' não traz o resto dos
/// fungicidas. Acento não atrapalha — os dois lados passam por
/// [chaveBusca].
bool nomeCasaBusca(String nome, List<String> palavras) {
  if (palavras.isEmpty) return false;
  final chave = chaveBusca(nome);
  if (chave.isEmpty) return false;
  return palavras.every(chave.contains);
}

/// Um produto achado pela busca por nome — já com os códigos do mesmo
/// nome agrupados e o saldo somado.
class ProdutoEncontrado {
  /// Código usado para abrir a tela do produto (o menor do grupo, para a
  /// escolha ser estável). A consulta completa é refeita por ele.
  final String codigo;

  /// Todos os códigos de `estoque_mestre` com este mesmo nome.
  final List<String> codigos;

  final String nome;
  final String? categoria;

  /// Soma de qtd_sistema dos códigos agrupados. É uma prévia da lista: o
  /// número que vale é o da tela do produto, que resolve o mapa de códigos.
  final double total;

  const ProdutoEncontrado({
    required this.codigo,
    required this.nome,
    this.codigos = const [],
    this.categoria,
    this.total = 0,
  });
}

/// Agrupa linhas de `estoque_mestre` por nome de produto, somando o saldo.
///
/// Um produto com dois códigos ('254185' e 'US254185') aparece uma vez só na
/// lista — repetir o mesmo nome duas vezes, cada um com metade do saldo,
/// é exatamente o erro que a regra de multi-código existe para evitar.
List<ProdutoEncontrado> agruparPorNome(List<CodigoSaldo> linhas) {
  final grupos = <String, List<CodigoSaldo>>{};
  for (final l in linhas) {
    final chave = chaveBusca(l.produto);
    if (chave.isEmpty) continue;
    grupos.putIfAbsent(chave, () => []).add(l);
  }

  final achados = <ProdutoEncontrado>[];
  for (final linhasDoGrupo in grupos.values) {
    final codigos = linhasDoGrupo.map((l) => l.codigo).toSet().toList()..sort();
    var total = 0.0;
    for (final l in linhasDoGrupo) {
      total += l.qtdSistema;
    }
    final categoria = linhasDoGrupo
        .map((l) => l.categoria)
        .firstWhere((c) => c != null && c.trim().isNotEmpty, orElse: () => null);
    achados.add(ProdutoEncontrado(
      codigo: codigos.first,
      codigos: codigos,
      nome: linhasDoGrupo.first.produto.trim(),
      categoria: categoria,
      total: total,
    ));
  }
  return achados;
}

/// Ordem de exibição da busca: nome igual ao digitado primeiro, depois os
/// que começam pelo termo, depois os que contêm o termo inteiro e por fim os
/// que só têm as palavras espalhadas. Empate resolve em ordem alfabética.
List<ProdutoEncontrado> ordenarPorRelevancia(
  String termo,
  List<ProdutoEncontrado> achados,
) {
  final chaveTermo = chaveBusca(termo);
  int peso(ProdutoEncontrado p) {
    final chave = chaveBusca(p.nome);
    if (chave == chaveTermo) return 0;
    if (chave.startsWith(chaveTermo)) return 1;
    if (chave.contains(chaveTermo)) return 2;
    return 3;
  }

  final lista = [...achados];
  lista.sort((a, b) {
    final c = peso(a).compareTo(peso(b));
    return c != 0 ? c : chaveBusca(a.nome).compareTo(chaveBusca(b.nome));
  });
  return lista;
}

/// Filtra e ordena linhas de `estoque_mestre` pelo nome digitado.
///
/// Termo com menos de [minLetrasBusca] caracteres devolve lista vazia — a
/// tela avisa em vez de despejar o catálogo inteiro.
List<ProdutoEncontrado> buscarNasLinhas(
  String termo,
  List<CodigoSaldo> linhas, {
  int limite = limiteBusca,
}) {
  final palavras = palavrasBusca(termo);
  if (palavras.join().length < minLetrasBusca) return const [];
  final casaram = linhas.where((l) => nomeCasaBusca(l.produto, palavras)).toList();
  final ordenados = ordenarPorRelevancia(termo, agruparPorNome(casaram));
  return ordenados.length > limite
      ? ordenados.sublist(0, limite)
      : ordenados;
}

/// Uma linha de estoque_mestre que entrou na soma.
class CodigoSaldo {
  final String codigo;
  final String produto;
  final String? categoria;
  final double qtdSistema;
  final String? ultimaContagem;

  const CodigoSaldo({
    required this.codigo,
    required this.produto,
    this.categoria,
    required this.qtdSistema,
    this.ultimaContagem,
  });
}

/// Resultado completo de uma consulta por código.
class ResultadoConsulta {
  final String codigoLido;
  final String nomeProduto;
  final String? categoria;

  /// Soma de qtd_sistema de todas as linhas em [saldos].
  final double total;

  /// Linhas de estoque_mestre somadas, na ordem dos códigos.
  final List<CodigoSaldo> saldos;

  /// True quando o código resolveu um produto em mapa_produtos /
  /// mapa_produtos_codigos. False = código não vinculado: só a linha única
  /// de estoque_mestre foi lida e o total pode estar incompleto.
  final bool vinculado;

  /// Unidade padrão do produto no mapa (mapa_produtos.unidade_pad), como
  /// está gravada no banco. Não é exibida na tela do produto (o espaço passou
  /// a ser do lote) e NENHUMA conversão é feita com ela enquanto a unidade
  /// real de qtd_sistema não for confirmada — ver Passo 0 no README.
  final String? unidadePad;

  /// Códigos vinculados ao produto que não têm linha em estoque_mestre.
  final List<String> codigosSemSaldo;

  /// Última contagem mais recente entre as linhas somadas.
  final String? ultimaContagem;

  /// Lotes do produto na lista de vencimentos (`validade_lotes`), já em
  /// ordem de carregamento: validade mais próxima primeiro.
  final List<LoteValidade> lotes;

  /// True quando a lista de vencimentos não pôde ser lida (tabela ausente
  /// ou consulta falhou). Diferente de [lotes] vazio, que significa "a lista
  /// existe e este produto não está nela".
  final bool lotesIndisponiveis;

  /// True quando o dado veio do cache local (etapa 4), com o horário da
  /// última sincronização em [sincronizadoEm].
  final bool doCacheLocal;
  final DateTime? sincronizadoEm;

  const ResultadoConsulta({
    required this.codigoLido,
    required this.nomeProduto,
    this.categoria,
    required this.total,
    required this.saldos,
    required this.vinculado,
    this.unidadePad,
    this.codigosSemSaldo = const [],
    this.ultimaContagem,
    this.lotes = const [],
    this.lotesIndisponiveis = false,
    this.doCacheLocal = false,
    this.sincronizadoEm,
  });

  /// 'Total pode estar incompleto': código sem vínculo no mapa de produtos.
  bool get avisoNaoVinculado => !vinculado;

  /// Ex.: '254185 + US254185' — os códigos que entraram na soma.
  String get codigosSomados => saldos.map((s) => s.codigo).join(' + ');

  /// O lote que deve sair primeiro: o de validade mais próxima (FEFO).
  ///
  /// Só lotes com data legível concorrem — um lote sem vencimento na
  /// planilha não pode ser apontado como "o mais próximo de vencer".
  LoteValidade? get loteParaCarregar {
    for (final l in lotes) {
      if (l.data != null) return l;
    }
    return null;
  }

  /// Quantos outros lotes deste produto estão na lista, além do primeiro.
  int get outrosLotes {
    final n = lotes.length - 1;
    return n > 0 ? n : 0;
  }

  /// Mesma consulta com os lotes da lista de vencimentos acoplados — o
  /// serviço só consegue buscá-los depois de saber o nome do produto.
  ResultadoConsulta copiarComLotes(
    List<LoteValidade> lotes, {
    bool indisponivel = false,
  }) =>
      ResultadoConsulta(
        codigoLido: codigoLido,
        nomeProduto: nomeProduto,
        categoria: categoria,
        total: total,
        saldos: saldos,
        vinculado: vinculado,
        unidadePad: unidadePad,
        codigosSemSaldo: codigosSemSaldo,
        ultimaContagem: ultimaContagem,
        lotes: ordenarLotesPorVencimento(lotes),
        lotesIndisponiveis: indisponivel,
        doCacheLocal: doCacheLocal,
        sincronizadoEm: sincronizadoEm,
      );
}

/// Monta o resultado a partir das linhas já lidas do banco.
///
/// [linhas]: linhas de estoque_mestre do grupo de códigos (ou a linha única,
/// quando não vinculado). [codigosVinculados]: todos os códigos do produto
/// no mapa (vazio quando não vinculado). [nomeMapa]/[unidadePad]: dados de
/// mapa_produtos, quando vinculado.
ResultadoConsulta montarResultado({
  required String codigoLido,
  required List<CodigoSaldo> linhas,
  required List<String> codigosVinculados,
  String? nomeMapa,
  String? unidadePad,
  List<LoteValidade> lotes = const [],
  bool lotesIndisponiveis = false,
  bool doCacheLocal = false,
  DateTime? sincronizadoEm,
}) {
  final vinculado = codigosVinculados.isNotEmpty;

  // Soma o saldo de TODOS os códigos do produto — bipar só o US254185 e
  // mostrar 403 está errado; o saldo real é 201 + 403 = 604.
  var total = 0.0;
  for (final l in linhas) {
    total += l.qtdSistema;
  }

  // Nome: prefere a linha do código lido (é o que está na folha impressa);
  // senão a primeira linha do grupo; por fim o nome do mapa.
  final linhaLida = linhas.where((l) => l.codigo == codigoLido).toList();
  final nome = linhaLida.isNotEmpty
      ? linhaLida.first.produto
      : linhas.isNotEmpty
          ? linhas.first.produto
          : (nomeMapa ?? '');

  final categoria = linhaLida.isNotEmpty
      ? linhaLida.first.categoria
      : linhas.isNotEmpty
          ? linhas.first.categoria
          : null;

  // Última contagem mais recente do grupo. Datas são ISO (criadas pelo
  // dashboard), então comparar como texto ordena certo; DateTime.tryParse
  // cobre variações.
  String? ultima;
  for (final l in linhas) {
    final u = l.ultimaContagem;
    if (u == null || u.trim().isEmpty) continue;
    if (ultima == null) {
      ultima = u;
      continue;
    }
    final da = DateTime.tryParse(ultima);
    final db = DateTime.tryParse(u);
    if (da != null && db != null) {
      if (db.isAfter(da)) ultima = u;
    } else if (u.compareTo(ultima) > 0) {
      ultima = u;
    }
  }

  final comSaldo = linhas.map((l) => l.codigo).toSet();
  final semSaldo = codigosVinculados
      .where((c) => !comSaldo.contains(c))
      .toList(growable: false);

  return ResultadoConsulta(
    codigoLido: codigoLido,
    nomeProduto: nome,
    categoria: categoria,
    total: total,
    saldos: linhas,
    vinculado: vinculado,
    unidadePad: unidadePad,
    codigosSemSaldo: semSaldo,
    ultimaContagem: ultima,
    lotes: ordenarLotesPorVencimento(lotes),
    lotesIndisponiveis: lotesIndisponiveis,
    doCacheLocal: doCacheLocal,
    sincronizadoEm: sincronizadoEm,
  );
}

/// Formata a quantidade crua para exibição: inteiro sem casas ('604'),
/// fração com até 2 casas ('12,5'), separador de milhar com ponto.
String formatarQuantidade(double v) {
  final ehInteiro = v == v.truncateToDouble();
  var texto = ehInteiro
      ? v.toInt().toString()
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  texto = texto.replaceAll('.', ',');

  // Separador de milhar na parte inteira.
  final partes = texto.split(',');
  final inteiro = partes[0];
  final sinal = inteiro.startsWith('-') ? '-' : '';
  final digitos = sinal.isEmpty ? inteiro : inteiro.substring(1);
  final sb = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) sb.write('.');
    sb.write(digitos[i]);
  }
  final inteiroFmt = '$sinal$sb';
  return partes.length > 1 ? '$inteiroFmt,${partes[1]}' : inteiroFmt;
}
