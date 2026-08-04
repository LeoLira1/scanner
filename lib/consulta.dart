/// Lógica pura da consulta por código — sem dependência de Flutter/banco,
/// para ser testável em Dart puro (test/consulta_test.dart).
///
/// Reproduz o comportamento do db_mapa.py do camda-estoque:
/// - _norm_codigo: UPPER(TRIM()), vazio vira null;
/// - buscar_por_codigo / sync multi-código: um produto da CAMDA pode ter
///   mais de um código ativo ('254185' e 'US254185'), cada um com saldo
///   próprio em estoque_mestre — o saldo real é a SOMA de todos eles.
library;

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
  /// está gravada no banco. Exibida junto ao número cru — NENHUMA conversão
  /// é feita enquanto a unidade real de qtd_sistema não for confirmada.
  final String? unidadePad;

  /// Códigos vinculados ao produto que não têm linha em estoque_mestre.
  final List<String> codigosSemSaldo;

  /// Última contagem mais recente entre as linhas somadas.
  final String? ultimaContagem;

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
    this.doCacheLocal = false,
    this.sincronizadoEm,
  });

  /// 'Total pode estar incompleto': código sem vínculo no mapa de produtos.
  bool get avisoNaoVinculado => !vinculado;

  /// Ex.: '254185 + US254185' — os códigos que entraram na soma.
  String get codigosSomados => saldos.map((s) => s.codigo).join(' + ');
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
