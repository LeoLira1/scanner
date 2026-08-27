/// Espelho seletivo do banco: as tabelas e colunas que o app realmente lê.
///
/// O cache local do app era uma *embedded replica* do libSQL, e o `sync()`
/// dela copia o banco INTEIRO do camda-estoque — inclusive o que o scanner
/// nunca consulta: fotos de avaria e de pendência de entrega guardadas em
/// base64 na mesma base (`avaria_fotos`, `pendencias_entrega`, sem retenção),
/// `vendas_historico`, `contagem_itens`, `mapa_posicoes`. Dezenas de MB
/// baixados para usar menos de 1 MB.
///
/// Aqui ficam as partes puras do espelhamento — as tabelas, o SQL de página,
/// o SQL de inserção e a impressão digital. São puras de propósito: dá para
/// testá-las sem banco nenhum, como o resto de `consulta.dart`.
library;

/// Tipo declarado da coluna no espelho. Decide o `TEXT`/`NUMERIC` do DDL e a
/// conversão do valor lido do remoto — o driver não garante devolver o tipo
/// do esquema, e um valor que muda de tipo no meio do caminho vira consulta
/// que não casa (`produto_id` 5 ≠ '5').
enum TipoColuna { texto, numero }

class ColunaEspelho {
  final String nome;
  final TipoColuna tipo;

  const ColunaEspelho(this.nome, this.tipo);

  String get ddl => '$nome ${tipo == TipoColuna.texto ? 'TEXT' : 'NUMERIC'}';

  /// Valor pronto para gravar no espelho. NULL é preservado: em
  /// `mapa_produtos.codigo` ele é significativo (a consulta filtra por
  /// `codigo IS NOT NULL`).
  Object? converter(dynamic v) {
    if (v == null) return null;
    if (tipo == TipoColuna.texto) return v.toString();
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }
}

/// Teto conservador de parâmetros por statement. O SQLite antigo compila com
/// `SQLITE_MAX_VARIABLE_NUMBER` 999; ficar abaixo disso evita depender da
/// versão embarcada no aparelho.
const int maxParametrosPorStatement = 900;

/// Linhas pedidas por página ao remoto.
const int linhasPorPagina = 1000;

/// Nome do rowid na página — o cursor da paginação por keyset.
const String colunaCursor = '_rid';

class EspelhoTabela {
  final String nome;
  final List<ColunaEspelho> colunas;

  /// Expressões indexadas no espelho. As consultas do app comparam por
  /// `UPPER(TRIM(codigo))`, e um índice comum sobre `codigo` não serve para
  /// isso — o índice precisa ser sobre a mesma expressão.
  final List<String> indices;

  /// Agregado que identifica o conteúdo da tabela no remoto, ou null quando
  /// a tabela é sempre baixada inteira.
  final String? sqlImpressao;

  const EspelhoTabela({
    required this.nome,
    required this.colunas,
    this.indices = const [],
    this.sqlImpressao,
  });

  List<String> get nomesColunas => [for (final c in colunas) c.nome];

  String ddl(String alvo) =>
      'CREATE TABLE $alvo (${colunas.map((c) => c.ddl).join(', ')})';

  List<String> ddlIndices(String alvo) => [
        for (var i = 0; i < indices.length; i++)
          'CREATE INDEX IF NOT EXISTS ix_${nome}_$i ON $alvo (${indices[i]})',
      ];

  /// Uma página do remoto, por keyset em `rowid`.
  ///
  /// Não é `LIMIT/OFFSET`: com OFFSET o servidor relê todas as linhas
  /// anteriores a cada página, o que multiplica o *rows read* cobrado pelo
  /// Turso e fica mais lento a cada página. As quatro tabelas espelhadas são
  /// rowid tables no primário, então a regra vale para todas.
  String get sqlPagina =>
      'SELECT rowid AS $colunaCursor, ${nomesColunas.join(', ')} '
      'FROM $nome WHERE rowid > ? ORDER BY rowid LIMIT ?';

  /// Quantas linhas cabem num INSERT sem estourar o teto de parâmetros.
  int get linhasPorLote {
    final n = maxParametrosPorStatement ~/ colunas.length;
    return n < 1 ? 1 : n;
  }

  String sqlInsercaoLote(String alvo, int nLinhas) {
    final marcadores = '(${List.filled(colunas.length, '?').join(', ')})';
    return 'INSERT INTO $alvo (${nomesColunas.join(', ')}) '
        'VALUES ${List.filled(nLinhas, marcadores).join(', ')}';
  }

  /// Os valores das [linhas] achatados na ordem das colunas, prontos para
  /// [sqlInsercaoLote].
  List<Object?> parametrosLote(Iterable<Map<String, dynamic>> linhas) => [
        for (final linha in linhas)
          for (final c in colunas) c.converter(linha[c.nome]),
      ];
}

/// Identificação do conteúdo de uma tabela no remoto, para pular o download
/// quando nada mudou.
///
/// Não é hash criptográfico — é um punhado de agregados. Cobre os caminhos de
/// escrita reais do camda-estoque: o upload de planilha reescreve
/// `estoque_mestre` inteira (`DELETE` + `INSERT`), o que muda
/// `MAX(criado_em)`; edição pontual muda a soma; exclusão muda a contagem; e
/// `SUM(qtd_sistema*rowid)` pega até troca de quantidade entre duas linhas,
/// que passaria batida por uma soma simples. Ainda assim é heurística: por
/// isso ⚙️ tem **Atualização completa**, que ignora a impressão e rebaixa
/// tudo.
class Impressao {
  final String valor;

  const Impressao(this.valor);

  /// Lê a linha de agregados devolvida por [EspelhoTabela.sqlImpressao].
  ///
  /// As colunas são apelidadas `f0`, `f1`, … no SQL porque o driver devolve
  /// um Map, e Map não tem ordem garantida — ler por índice nomeado mantém a
  /// impressão estável entre execuções.
  factory Impressao.deLinha(Map<String, dynamic> linha) {
    final partes = <String>[];
    for (var i = 0; linha.containsKey('f$i'); i++) {
      partes.add(linha['f$i']?.toString() ?? '');
    }
    return Impressao(partes.join('|'));
  }

  bool get vazia => valor.isEmpty;

  @override
  bool operator ==(Object other) => other is Impressao && other.valor == valor;

  @override
  int get hashCode => valor.hashCode;

  @override
  String toString() => valor;
}

/// Por quanto tempo a impressão digital vale como prova de que a tabela não
/// mudou. Passado isso, a tabela é rebaixada mesmo com a impressão igual.
///
/// A impressão pega toda alteração de quantidade, de contagem de linhas e toda
/// reescrita da planilha — tudo que muda o número na tela. O que ela não pega
/// é uma edição só de texto que preserve os agregados: o upload incremental do
/// dashboard troca `produto` sem tocar em `criado_em`, então renomear um
/// produto para outro nome do mesmo tamanho não move a impressão. O buraco é
/// estreito e cosmético, mas existe — este teto faz com que ele se feche
/// sozinho, sem ninguém precisar apertar nada.
const Duration validadeImpressao = Duration(hours: 6);

/// True quando a tabela foi rebaixada há pouco o bastante para a impressão
/// digital ainda servir de prova. Data ausente ou ilegível = não serve, e a
/// tabela é rebaixada — o lado seguro do erro.
bool impressaoAindaVale(
  String? baixadaEmIso, {
  required DateTime agora,
  Duration validade = validadeImpressao,
}) {
  if (baixadaEmIso == null) return false;
  final quando = DateTime.tryParse(baixadaEmIso);
  if (quando == null) return false;
  final idade = agora.difference(quando);
  // Idade negativa = relógio do aparelho andou para trás depois da última
  // atualização. Confiar nisso seguraria dado velho por tempo indefinido.
  if (idade.isNegative) return false;
  return idade < validade;
}

/// `estoque_mestre` — o saldo. Cinco das dez colunas do primário; `qtd_fisica`,
/// `diferenca`, `nota`, `status` e `criado_em` são do dashboard, não do app.
const tabelaEstoqueMestre = EspelhoTabela(
  nome: 'estoque_mestre',
  colunas: [
    ColunaEspelho('codigo', TipoColuna.texto),
    ColunaEspelho('produto', TipoColuna.texto),
    ColunaEspelho('categoria', TipoColuna.texto),
    ColunaEspelho('qtd_sistema', TipoColuna.numero),
    ColunaEspelho('ultima_contagem', TipoColuna.texto),
  ],
  indices: ['UPPER(TRIM(codigo))'],
  sqlImpressao: 'SELECT COUNT(*) AS f0, '
      'IFNULL(SUM(qtd_sistema), 0) AS f1, '
      'IFNULL(SUM(qtd_sistema * rowid), 0) AS f2, '
      'IFNULL(SUM(LENGTH(codigo) + LENGTH(produto) + LENGTH(categoria)), 0) AS f3, '
      "IFNULL(MAX(ultima_contagem), '') AS f4, "
      "IFNULL(MAX(criado_em), '') AS f5 "
      'FROM estoque_mestre',
);

/// `validade_lotes` — a lista de vencimentos (o lote a carregar primeiro).
///
/// A impressão aqui é exata, não heurística: a tabela só é escrita em bloco
/// (`DELETE FROM validade_lotes` + re-INSERT a cada upload do BI), então
/// contagem + `MAX(id)` + `MAX(uploaded_em)` mudam em toda reescrita.
const tabelaValidadeLotes = EspelhoTabela(
  nome: 'validade_lotes',
  colunas: [
    ColunaEspelho('produto', TipoColuna.texto),
    ColunaEspelho('lote', TipoColuna.texto),
    ColunaEspelho('vencimento', TipoColuna.texto),
    ColunaEspelho('quantidade', TipoColuna.numero),
  ],
  sqlImpressao: 'SELECT COUNT(*) AS f0, '
      'IFNULL(SUM(quantidade), 0) AS f1, '
      "IFNULL(MAX(uploaded_em), '') AS f2, "
      'IFNULL(MAX(id), 0) AS f3 '
      'FROM validade_lotes',
);

/// `mapa_produtos` e `mapa_produtos_codigos` — o vínculo entre códigos do
/// mesmo produto, o que decide a soma do saldo.
///
/// Sem impressão digital de propósito: são tabelas de centenas de linhas,
/// editadas à mão no dashboard e sem nenhuma coluna de data que marque a
/// alteração. Baixá-las inteiras a cada sincronização custa alguns KB —
/// menos que o risco de somar um saldo com um vínculo velho.
const tabelaMapaProdutos = EspelhoTabela(
  nome: 'mapa_produtos',
  colunas: [
    ColunaEspelho('produto_id', TipoColuna.texto),
    ColunaEspelho('nome', TipoColuna.texto),
    ColunaEspelho('unidade_pad', TipoColuna.texto),
    ColunaEspelho('codigo', TipoColuna.texto),
  ],
  indices: ['UPPER(TRIM(codigo))'],
);

const tabelaMapaProdutosCodigos = EspelhoTabela(
  nome: 'mapa_produtos_codigos',
  colunas: [
    ColunaEspelho('produto_id', TipoColuna.texto),
    ColunaEspelho('codigo', TipoColuna.texto),
  ],
  indices: ['produto_id', 'UPPER(TRIM(codigo))'],
);

/// As tabelas espelhadas, na ordem em que são baixadas: o saldo primeiro,
/// que é o que a tela do produto mostra em destaque.
const List<EspelhoTabela> tabelasEspelho = [
  tabelaEstoqueMestre,
  tabelaMapaProdutos,
  tabelaMapaProdutosCodigos,
  tabelaValidadeLotes,
];

/// Nome da tabela de encenação onde a página vai caindo. A troca pela tabela
/// viva é atômica e só acontece no fim — falha no meio deixa o espelho
/// anterior inteiro, em vez de um saldo pela metade na tela.
String tabelaEncenacao(String nome) => '${nome}__novo';
