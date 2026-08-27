import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:libsql_dart/libsql_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'espelho.dart';

/// Como terminou uma sincronização — o que a tela precisa para dar a
/// resposta certa: "atualizado", "já estava atualizado" ou o motivo da falha.
class ResumoSync {
  final bool ok;
  final String? erro;
  final Duration duracao;

  /// Linhas baixadas por tabela. Tabela ausente aqui = pulada (a impressão
  /// digital do remoto era igual à da última sincronização) ou inexistente no
  /// banco. Mapa vazio com [ok] = nada mudou desde a última vez.
  final Map<String, int> linhasBaixadas;

  /// True quando o cache local está desligado: as consultas já vão direto ao
  /// banco, então não existe espelho para atualizar.
  final bool semEspelho;

  const ResumoSync._({
    required this.ok,
    required this.duracao,
    this.erro,
    this.linhasBaixadas = const {},
    this.semEspelho = false,
  });

  factory ResumoSync.sucesso(
    Map<String, int> linhas,
    Duration duracao, {
    bool semEspelho = false,
  }) =>
      ResumoSync._(
        ok: true,
        duracao: duracao,
        linhasBaixadas: linhas,
        semEspelho: semEspelho,
      );

  factory ResumoSync.falha(String erro, Duration duracao) =>
      ResumoSync._(ok: false, duracao: duracao, erro: erro);

  /// True quando alguma tabela foi de fato rebaixada.
  bool get houveMudanca => linhasBaixadas.isNotEmpty;

  /// Produtos no espelho depois desta sincronização, ou null se a tabela de
  /// saldo não foi tocada.
  int? get produtos => linhasBaixadas[tabelaEstoqueMestre.nome];

  /// Frase pronta para a tela. Fica aqui para a tela inicial e a de
  /// configuração dizerem exatamente a mesma coisa sobre o mesmo resultado.
  ///
  /// "Já estava atualizado" é dito com todas as letras de propósito: no
  /// caminho rápido a impressão digital do banco bateu com a da última
  /// atualização e nada foi baixado — sem isso, um ✓ instantâneo pareceria
  /// erro.
  String get mensagem {
    if (!ok) {
      return 'Não foi possível atualizar — ${erro ?? 'verifique a conexão'}';
    }
    if (semEspelho) {
      return 'Cache local desligado — as consultas já vão direto ao banco ✓';
    }
    if (!houveMudanca) return 'Já estava atualizado ✓';
    final n = produtos;
    return n != null ? 'Atualizado ✓ · $n produtos' : 'Atualizado ✓';
  }
}

/// O que o diagnóstico de ⚙️ mostra: o custo real da última atualização.
class DiagnosticoEspelho {
  final Duration? ultimaDuracao;
  final Map<String, int> linhas;
  final int bytes;

  const DiagnosticoEspelho({
    required this.linhas,
    required this.bytes,
    this.ultimaDuracao,
  });
}

/// Conexão com o banco Turso da CAMDA via libsql_dart, sem backend no meio.
///
/// Este app é SOMENTE LEITURA no que diz respeito ao banco online: nenhum
/// INSERT/UPDATE/DELETE e nenhum CREATE/ALTER lá — o esquema pertence ao
/// camda-estoque. Recomenda-se usar um token read-only do Turso: se o celular
/// for perdido, quem o achar não consegue alterar o estoque (ver README).
///
/// Cache local: em vez de replicar o banco inteiro, o app mantém um **espelho
/// seletivo** num arquivo do dispositivo — só as tabelas e colunas que ele
/// consulta (ver `espelho.dart`). A réplica embutida do libSQL copiava tudo,
/// inclusive fotos em base64 de avaria e de pendência de entrega guardadas na
/// mesma base, e por isso cada "Sincronizar" baixava dezenas de MB para usar
/// menos de 1 MB. O espelho é escrito pelo próprio app no arquivo local; o
/// banco online continua intocado.
class TursoService {
  static final TursoService _instance = TursoService._internal();
  factory TursoService() => _instance;
  TursoService._internal();

  static const String keyDbUrl        = 'turso_db_url';
  static const String keyDbToken      = 'turso_db_token';
  static const String keyCacheLocal   = 'turso_cache_local';
  static const String keyUltimaSync   = 'turso_ultima_sync';
  static const String keyIntervaloMin = 'turso_intervalo_sync_min';

  static const String _keyDiagnostico    = 'turso_diagnostico';
  static const String _keyReplicaLimpa   = 'turso_replica_antiga_removida';
  static const String _prefixoImpressao  = 'turso_impressao_';
  static const String _prefixoBaixadaEm  = 'turso_baixada_em_';

  /// Minutos entre sincronizações automáticas. 0 = desligado.
  static const int intervaloPadraoMin = 15;
  static const List<int> intervalosDisponiveis = [0, 5, 15, 30];

  // Limites de tempo: nenhuma etapa de conexão/sincronização pode segurar o
  // app indefinidamente — estourou, cai no fallback (remoto) ou falha o
  // botão de sincronizar com aviso, mantendo o espelho local intacto.
  static const Duration _timeoutConexao = Duration(seconds: 20);
  static const Duration _timeoutPagina  = Duration(seconds: 45);
  static const Duration _timeoutEspelho = Duration(minutes: 3);

  LibsqlClient? _client;
  bool _connected = false;

  bool      _modoLocal = false;
  DateTime? _ultimaSincronizacao;
  String?   _ultimoErroSync;

  // Espelho recém-criado (arquivo ainda sem as tabelas): consultar antes da
  // primeira carga devolveria "não encontrado" para qualquer código — um erro
  // silencioso. Enquanto este flag estiver ligado, garantirDadosProntos()
  // espera a carga terminar.
  bool _cacheVazio = false;

  // Credenciais/modo da conexão ativa. Enquanto não mudarem, init()
  // reaproveita a conexão em vez de reconectar a cada abertura de página.
  String? _urlAtiva;
  String? _tokenAtivo;
  bool?   _cacheLocalAtivo;
  Future<void>? _initEmAndamento;

  Future<ResumoSync>? _syncEmAndamento;
  Timer? _timerAutomatico;

  bool get isConnected => _connected;

  LibsqlClient? get client => _client;

  /// True quando a conexão ativa usa o espelho local (arquivo no dispositivo).
  bool get modoLocal => _modoLocal;

  /// Ligado enquanto uma sincronização está no ar. É um notifier porque a
  /// sincronização roda em segundo plano: quem estiver na tela vê o ícone
  /// girar, e sair e voltar da tela não perde o estado.
  final ValueNotifier<bool> sincronizando = ValueNotifier<bool>(false);

  DateTime? get ultimaSincronizacao => _ultimaSincronizacao;

  /// Descrição curta (para o usuário) do motivo da última falha de
  /// sincronização, ou null se a última tentativa deu certo.
  String? get ultimoErroSync => _ultimoErroSync;

  /// Incrementa a cada sincronização bem-sucedida. As telas ouvem para
  /// saber que os dados mudaram.
  final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);

  /// True quando o espelho local está ligado mas ainda não tem os dados.
  bool get cacheVazio => _modoLocal && _cacheVazio;

  // ── Conexão ───────────────────────────────────────────────────────────────

  /// Serializa os inits em vez de "pegar carona" no que está no ar: se um
  /// init antigo ainda roda com preferências velhas (ex.: o usuário acabou
  /// de desligar o cache local), o próximo espera e roda em seguida,
  /// aplicando as novas.
  Future<void> init() {
    final anterior = _initEmAndamento ?? Future<void>.value();
    final novo = anterior.catchError((_) {}).then<void>((_) => _init());
    _initEmAndamento = novo;
    return novo;
  }

  Future<void> _init() async {
    final prefs      = await SharedPreferences.getInstance();
    final url        = prefs.getString(keyDbUrl)   ?? '';
    final token      = prefs.getString(keyDbToken) ?? '';
    final cacheLocal = prefs.getBool(keyCacheLocal) ?? true;

    final ultimaSyncIso = prefs.getString(keyUltimaSync);
    _ultimaSincronizacao =
        ultimaSyncIso != null ? DateTime.tryParse(ultimaSyncIso) : null;

    if (_connected &&
        _client != null &&
        url == _urlAtiva &&
        token == _tokenAtivo &&
        cacheLocal == _cacheLocalAtivo) {
      return;
    }

    final clienteAntigo = _client;

    _connected       = false;
    _client          = null;
    _urlAtiva        = null;
    _tokenAtivo      = null;
    _cacheLocalAtivo = null;
    _modoLocal       = false;
    _cacheVazio      = false;

    if (clienteAntigo != null) {
      // Solta a conexão anterior (troca de credenciais ou de modo) sem
      // segurar o init novo.
      unawaited(clienteAntigo.dispose().catchError((_) {}));
    }

    if (url.isEmpty || token.isEmpty) return;

    LibsqlClient? client;
    var conectouLocal = false;

    if (cacheLocal) {
      await _removerReplicaAntiga(prefs);
      client        = await _conectarEspelhoLocal();
      conectouLocal = client != null;
    }
    // Sem espelho local (preferência desligada ou falha ao abrir o arquivo):
    // conexão direta ao remoto.
    client ??= await _conectarRemoto(url, token);
    if (client == null) return;

    _client          = client;
    _connected       = true;
    _modoLocal       = conectouLocal;
    _urlAtiva        = url;
    _tokenAtivo      = token;
    _cacheLocalAtivo = cacheLocal;

    if (conectouLocal) {
      // Arquivo recém-criado: dispara a carga inicial já, sem travar a
      // abertura do app. Quem consultar antes dela terminar espera em
      // garantirDadosProntos().
      _cacheVazio = await _espelhoVazio(client);
      if (_cacheVazio) {
        unawaited(sincronizar());
      } else {
        unawaited(sincronizarSeVelho());
      }
    }
  }

  Future<String> _caminhoEspelho() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/scanner_camda_espelho.db';
  }

  /// Arquivo da réplica embutida das versões anteriores.
  ///
  /// É apagado uma única vez, na primeira abertura desta versão: ele é a cópia
  /// do banco INTEIRO — com as fotos em base64 dentro — e ninguém mais o lê.
  /// Deixá-lo no aparelho só ocuparia espaço.
  Future<void> _removerReplicaAntiga(SharedPreferences prefs) async {
    if (prefs.getBool(_keyReplicaLimpa) ?? false) return;
    try {
      final dir = await getApplicationSupportDirectory();
      await _apagarArquivosDe('${dir.path}/scanner_camda_cache.db');
    } catch (_) {
      // Não conseguir apagar o arquivo velho não pode impedir o app de abrir.
    }
    // A data de sincronização e as impressões digitais eram da réplica antiga:
    // mantê-las faria o espelho novo, ainda vazio, se dizer atualizado.
    await _esquecerEstadoDeSync(prefs);
    await prefs.setBool(_keyReplicaLimpa, true);
  }

  Future<LibsqlClient?> _conectarEspelhoLocal() async {
    LibsqlClient? client;
    try {
      client = LibsqlClient.local(await _caminhoEspelho());
      await client.connect().timeout(_timeoutConexao);
      return client;
    } catch (_) {
      if (client != null) {
        unawaited(client.dispose().catchError((_) {}));
      }
      return null;
    }
  }

  Future<LibsqlClient?> _conectarRemoto(String url, String token) async {
    try {
      final client = LibsqlClient.remote(url, authToken: token);
      await client.connect().timeout(_timeoutConexao);
      return client;
    } catch (_) {
      return null;
    }
  }

  // Garante que existe conexão antes de uma consulta: se o init() da
  // abertura do app ainda não terminou (ou falhou), espera/tenta de novo em
  // vez de devolver resultado vazio silenciosamente.
  Future<bool> garantirConexao() async {
    if (_connected && _client != null) return true;
    await init();
    return _connected && _client != null;
  }

  /// Garante que há dados para consultar. No modo local com o espelho ainda
  /// vazio, espera a carga inicial — responder "não encontrado" com o espelho
  /// vazio seria um erro silencioso.
  ///
  /// Retorna false quando a carga inicial não conseguiu completar (sem
  /// internet na primeira execução).
  Future<bool> garantirDadosProntos() async {
    if (!await garantirConexao()) return false;
    if (!_modoLocal || !_cacheVazio) return true;
    final resumo = await sincronizar();
    return resumo.ok && !_cacheVazio;
  }

  // ── Preferências ──────────────────────────────────────────────────────────

  /// True quando URL e token já foram salvos na tela de configuração.
  Future<bool> credenciaisConfiguradas() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(keyDbUrl) ?? '').isNotEmpty &&
        (prefs.getString(keyDbToken) ?? '').isNotEmpty;
  }

  Future<bool> cacheLocalHabilitado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyCacheLocal) ?? true;
  }

  Future<void> definirCacheLocal(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyCacheLocal, valor);
    await init();
  }

  /// Minutos entre sincronizações automáticas; 0 = só no botão.
  Future<int> intervaloSyncMin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyIntervaloMin) ?? intervaloPadraoMin;
  }

  Future<void> definirIntervaloSync(int minutos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyIntervaloMin, minutos);
    await iniciarAutomatico();
  }

  // ── Sincronização automática ──────────────────────────────────────────────

  /// (Re)arma o relógio da sincronização automática. Chamado quando o app vai
  /// para o primeiro plano — o timer não fica vivo em segundo plano, para não
  /// gastar bateria e dados do celular do galpão sem ninguém olhando a tela.
  Future<void> iniciarAutomatico() async {
    _timerAutomatico?.cancel();
    _timerAutomatico = null;
    final minutos = await intervaloSyncMin();
    if (minutos <= 0) return;
    _timerAutomatico = Timer.periodic(
      Duration(minutes: minutos),
      (_) => unawaited(sincronizarSeVelho()),
    );
  }

  void pararAutomatico() {
    _timerAutomatico?.cancel();
    _timerAutomatico = null;
  }

  /// Sincroniza só se os dados já passaram do intervalo configurado. É o que
  /// roda na abertura do app e a cada volta ao primeiro plano: quando não há
  /// novidade, a impressão digital resolve em dois agregados e nada é baixado.
  Future<void> sincronizarSeVelho() async {
    final minutos = await intervaloSyncMin();
    if (minutos <= 0) return;
    final ultima = _ultimaSincronizacao;
    if (ultima != null &&
        DateTime.now().difference(ultima) < Duration(minutes: minutos)) {
      return;
    }
    await sincronizar();
  }

  /// Dispara a sincronização e devolve na hora. As consultas continuam
  /// respondendo com o espelho anterior enquanto o novo é montado.
  void sincronizarEmSegundoPlano({bool completa = false}) {
    unawaited(sincronizar(completa: completa));
  }

  // ── Sincronização ─────────────────────────────────────────────────────────

  /// Atualiza o espelho local com o banco online. Retorna o resumo: se deu
  /// certo, o que foi baixado e quanto demorou. Em caso de falha os dados
  /// locais ficam intactos e dá para tentar de novo. No modo remoto (espelho
  /// desligado) não há o que sincronizar: as consultas já vão direto ao banco.
  ///
  /// [completa] ignora as impressões digitais e rebaixa todas as tabelas — é o
  /// caminho de quem desconfia que o número na tela está velho.
  Future<ResumoSync> sincronizar({bool completa = false}) {
    final anterior = _syncEmAndamento;
    // Duas chamadas ao mesmo tempo não podem escrever no mesmo arquivo. Uma
    // sincronização rápida pega carona na que já está no ar; a completa
    // espera a vez, porque ela existe justamente para desconfiar do resultado
    // da outra.
    if (anterior != null && !completa) return anterior;

    final futuro = () async {
      if (anterior != null) {
        try {
          await anterior;
        } catch (_) {}
      }
      return _sincronizar(completa: completa);
    }();

    _syncEmAndamento = futuro;
    unawaited(futuro.whenComplete(() {
      if (identical(_syncEmAndamento, futuro)) _syncEmAndamento = null;
    }));
    return futuro;
  }

  Future<ResumoSync> _sincronizar({required bool completa}) async {
    final inicio = DateTime.now();
    Duration decorrido() => DateTime.now().difference(inicio);

    if (!await garantirConexao()) {
      final configurado = await credenciaisConfiguradas();
      _ultimoErroSync = configurado
          ? 'sem conexão com o banco — verifique a internet'
          : 'configure URL e token do banco em ⚙️';
      return ResumoSync.falha(_ultimoErroSync!, decorrido());
    }

    sincronizando.value = true;
    try {
      var baixadas = const <String, int>{};
      if (_modoLocal) {
        baixadas = await _espelhar(_client!, completa: completa)
            .timeout(_timeoutEspelho);
        _cacheVazio = await _espelhoVazio(_client!);
      }
      await _registrarSincronizacao();
      await _guardarDiagnostico(decorrido());
      _ultimoErroSync = null;
      dataRevision.value++;
      return ResumoSync.sucesso(baixadas, decorrido(), semEspelho: !_modoLocal);
    } catch (e) {
      _ultimoErroSync = _descreverErroSync(e);
      return ResumoSync.falha(_ultimoErroSync!, decorrido());
    } finally {
      sincronizando.value = false;
    }
  }

  /// Rebaixa para o espelho local as tabelas que mudaram no remoto.
  /// Devolve quantas linhas vieram de cada tabela tocada.
  Future<Map<String, int>> _espelhar(
    LibsqlClient local, {
    required bool completa,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    LibsqlClient? remoto;
    try {
      remoto = LibsqlClient.remote(_urlAtiva!, authToken: _tokenAtivo!);
      await remoto.connect().timeout(_timeoutConexao);

      final baixadas = <String, int>{};
      for (final tabela in tabelasEspelho) {
        final linhas = await _espelharTabela(
          local,
          remoto,
          tabela,
          prefs,
          completa: completa,
        );
        if (linhas != null) baixadas[tabela.nome] = linhas;
      }
      return baixadas;
    } finally {
      final r = remoto;
      if (r != null) unawaited(r.dispose().catchError((_) {}));
    }
  }

  /// Espelha uma tabela. Devolve as linhas baixadas, ou null quando nada foi
  /// baixado — porque a impressão digital era a mesma ou porque a tabela não
  /// existe no banco.
  Future<int?> _espelharTabela(
    LibsqlClient local,
    LibsqlClient remoto,
    EspelhoTabela tabela,
    SharedPreferences prefs, {
    required bool completa,
  }) async {
    final chave        = '$_prefixoImpressao${tabela.nome}';
    final chaveBaixada = '$_prefixoBaixadaEm${tabela.nome}';

    Impressao? impressao;
    final sqlImpressao = tabela.sqlImpressao;
    if (sqlImpressao != null) {
      final List<dynamic> linhas;
      try {
        linhas = await remoto.query(sqlImpressao).timeout(_timeoutPagina);
      } catch (e) {
        if (!_tabelaAusente(e)) rethrow;
        await _descartarTabela(local, tabela.nome);
        await prefs.remove(chave);
        await prefs.remove(chaveBaixada);
        return null;
      }
      if (linhas.isNotEmpty) {
        impressao = Impressao.deLinha(_comoMapa(linhas.first));
        // A impressão só vale se a tabela local existir de verdade (espelho
        // apagado com a impressão guardada pularia o download e deixaria a
        // consulta sem dado nenhum) e se ela não estiver velha demais — ver
        // _validadeImpressao.
        if (!completa &&
            impressao.valor == prefs.getString(chave) &&
            impressaoAindaVale(
              prefs.getString(chaveBaixada),
              agora: DateTime.now(),
            ) &&
            await _tabelaExiste(local, tabela.nome)) {
          return null;
        }
      }
    }

    final alvo = tabelaEncenacao(tabela.nome);
    await local.execute('DROP TABLE IF EXISTS $alvo');
    await local.execute(tabela.ddl(alvo));

    final stmt = await remoto.prepare(tabela.sqlPagina);
    var cursor = 0;
    var total  = 0;
    while (true) {
      final List<dynamic> pagina;
      try {
        pagina = await stmt
            .query(positional: [cursor, linhasPorPagina])
            .timeout(_timeoutPagina);
      } catch (e) {
        // Tabela do mapa ausente num banco onde o mapa nunca foi usado: o
        // espelho fica sem ela e a consulta cai no comportamento degradado de
        // sempre (ver EstoqueService._tabelaAusente).
        if (_tabelaAusente(e) && total == 0) {
          await local.execute('DROP TABLE IF EXISTS $alvo');
          await _descartarTabela(local, tabela.nome);
          await prefs.remove(chave);
          await prefs.remove(chaveBaixada);
          return null;
        }
        rethrow;
      }
      if (pagina.isEmpty) break;
      cursor = _inteiro(_comoMapa(pagina.last)[colunaCursor]);
      await _gravarPagina(local, tabela, alvo, pagina);
      total += pagina.length;
      if (pagina.length < linhasPorPagina) break;
    }

    await _trocarTabela(local, tabela, alvo);
    if (impressao != null) {
      await prefs.setString(chave, impressao.valor);
      await prefs.setString(chaveBaixada, DateTime.now().toIso8601String());
    } else {
      await prefs.remove(chave);
      await prefs.remove(chaveBaixada);
    }
    return total;
  }


  Future<void> _gravarPagina(
    LibsqlClient local,
    EspelhoTabela tabela,
    String alvo,
    List<dynamic> pagina,
  ) async {
    final porLote = tabela.linhasPorLote;
    for (var i = 0; i < pagina.length; i += porLote) {
      final fim  = (i + porLote < pagina.length) ? i + porLote : pagina.length;
      final lote = [for (final l in pagina.sublist(i, fim)) _comoMapa(l)];
      await local.execute(
        tabela.sqlInsercaoLote(alvo, lote.length),
        positional: tabela.parametrosLote(lote),
      );
    }
  }

  /// Troca a tabela viva pela recém-montada, de uma vez só.
  ///
  /// `batch` roda os comandos numa transação: ou o espelho inteiro passa a ser
  /// o novo, ou continua sendo o antigo. Nunca meio a meio — saldo pela metade
  /// na tela é pior que saldo velho, porque quem está no galpão acredita no
  /// número. Os índices vêm depois do rename porque nome de índice é global no
  /// SQLite: criá-los na tabela de encenação colidiria com os da tabela viva.
  Future<void> _trocarTabela(
    LibsqlClient local,
    EspelhoTabela tabela,
    String alvo,
  ) async {
    final passos = <String>[
      'DROP TABLE IF EXISTS ${tabela.nome}',
      'ALTER TABLE $alvo RENAME TO ${tabela.nome}',
      ...tabela.ddlIndices(tabela.nome),
    ];
    await local.batch('${passos.join(';\n')};');
  }

  Future<void> _descartarTabela(LibsqlClient local, String nome) async {
    try {
      await local.execute('DROP TABLE IF EXISTS $nome');
    } catch (_) {
      // Espelho sem a tabela é exatamente o estado desejado aqui.
    }
  }

  Future<bool> _tabelaExiste(LibsqlClient local, String nome) async {
    try {
      final rows = await local.query(
        "SELECT count(*) AS n FROM sqlite_master "
        "WHERE type = 'table' AND name = ?",
        positional: [nome],
      );
      return rows.isNotEmpty && _inteiro(_comoMapa(rows.first)['n']) > 0;
    } catch (_) {
      return false;
    }
  }

  /// True se o espelho ainda não tem saldo para consultar — tabela ausente ou
  /// sem uma linha sequer. Consultar nesse estado devolveria "não encontrado"
  /// para tudo.
  Future<bool> _espelhoVazio(LibsqlClient local) async {
    try {
      if (!await _tabelaExiste(local, tabelaEstoqueMestre.nome)) return true;
      final rows = await local.query(
        'SELECT EXISTS(SELECT 1 FROM ${tabelaEstoqueMestre.nome}) AS n',
      );
      if (rows.isEmpty) return true;
      return _inteiro(_comoMapa(rows.first)['n']) == 0;
    } catch (_) {
      // Na dúvida, trata como vazio: melhor esperar uma carga a mais do que
      // responder "não encontrado" com o espelho pela metade.
      return true;
    }
  }

  Future<void> _registrarSincronizacao() async {
    _ultimaSincronizacao = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyUltimaSync,
      _ultimaSincronizacao!.toIso8601String(),
    );
  }

  /// Traduz a exceção do sync numa dica curta e acionável — a causa real
  /// (token expirado ≠ sem internet ≠ demora da rede) muda o que o usuário
  /// precisa fazer para resolver.
  String _descreverErroSync(Object e) {
    if (e is TimeoutException) {
      return 'a rede demorou demais para responder — tente novamente';
    }
    final msg   = e.toString().replaceAll('\n', ' ').trim();
    final lower = msg.toLowerCase();
    if (lower.contains('401') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        lower.contains('auth')) {
      return 'token inválido ou expirado — confira em ⚙️';
    }
    if (lower.contains('dns') ||
        lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('connection refused') ||
        lower.contains('failed to connect') ||
        lower.contains('timed out')) {
      return 'sem conexão com o banco — verifique a internet';
    }
    return msg.length > 140 ? '${msg.substring(0, 140)}…' : msg;
  }

  /// True quando a exceção é "tabela não existe" — mesma checagem do
  /// EstoqueService, para um banco sem as tabelas do mapa não derrubar a
  /// sincronização inteira.
  static bool _tabelaAusente(Object e) =>
      e.toString().toLowerCase().contains('no such table');

  // ── Diagnóstico e limpeza ─────────────────────────────────────────────────

  Future<void> _guardarDiagnostico(Duration duracao) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyDiagnostico,
      jsonEncode({'ms': duracao.inMilliseconds}),
    );
  }

  /// O que o espelho custou e o que ele guarda hoje — é assim que dá para
  /// comparar o antes e o depois sem PC nem ferramenta externa.
  Future<DiagnosticoEspelho> diagnostico() async {
    final prefs = await SharedPreferences.getInstance();

    Duration? duracao;
    final bruto = prefs.getString(_keyDiagnostico);
    if (bruto != null) {
      try {
        final ms = (jsonDecode(bruto) as Map)['ms'];
        if (ms is int) duracao = Duration(milliseconds: ms);
      } catch (_) {
        // Diagnóstico é informativo: formato velho não pode virar erro.
      }
    }

    final linhas = <String, int>{};
    final local  = _modoLocal ? _client : null;
    if (local != null) {
      for (final tabela in tabelasEspelho) {
        if (!await _tabelaExiste(local, tabela.nome)) continue;
        try {
          final rows = await local.query('SELECT count(*) AS n FROM ${tabela.nome}');
          if (rows.isNotEmpty) {
            linhas[tabela.nome] = _inteiro(_comoMapa(rows.first)['n']);
          }
        } catch (_) {
          // Uma tabela ilegível não pode derrubar o diagnóstico das outras.
        }
      }
    }

    return DiagnosticoEspelho(
      linhas: linhas,
      bytes: await _bytesEspelho(),
      ultimaDuracao: duracao,
    );
  }

  Future<int> _bytesEspelho() async {
    var total = 0;
    try {
      final base = await _caminhoEspelho();
      for (final sufixo in _sufixosArquivo) {
        final arquivo = File('$base$sufixo');
        if (await arquivo.exists()) total += await arquivo.length();
      }
    } catch (_) {
      return total;
    }
    return total;
  }

  static const List<String> _sufixosArquivo = [
    '',
    '-wal',
    '-shm',
    '-journal',
    '-client_wal_index',
  ];

  Future<void> _apagarArquivosDe(String base) async {
    for (final sufixo in _sufixosArquivo) {
      final arquivo = File('$base$sufixo');
      if (await arquivo.exists()) await arquivo.delete();
    }
  }

  /// Zera tudo que diz "os dados locais estão em dia": a data da última
  /// sincronização e as impressões digitais. Sem isso, um espelho apagado
  /// continuaria se dizendo atualizado e nada seria baixado.
  Future<void> _esquecerEstadoDeSync(SharedPreferences prefs) async {
    _ultimaSincronizacao = null;
    await prefs.remove(keyUltimaSync);
    await prefs.remove(_keyDiagnostico);
    for (final tabela in tabelasEspelho) {
      await prefs.remove('$_prefixoImpressao${tabela.nome}');
      await prefs.remove('$_prefixoBaixadaEm${tabela.nome}');
    }
  }

  /// Apaga o arquivo do espelho e reseta a conexão, forçando o próximo
  /// init() a rebaixar tudo do zero do Turso. Como o app só lê, nada é
  /// perdido: o conteúdo do arquivo é sempre uma cópia do banco online.
  Future<bool> limparCacheLocal() async {
    // Uma atualização no ar estaria escrevendo justamente no arquivo que vai
    // ser apagado. Esperar ela terminar é mais barato que descobrir depois um
    // espelho meio apagado e meio escrito.
    final emAndamento = _syncEmAndamento;
    if (emAndamento != null) {
      try {
        await emAndamento;
      } catch (_) {}
    }

    final clienteAntigo = _client;

    _connected       = false;
    _client          = null;
    _urlAtiva        = null;
    _tokenAtivo      = null;
    _cacheLocalAtivo = null;
    _modoLocal       = false;
    _ultimoErroSync  = null;
    _cacheVazio      = false;

    if (clienteAntigo != null) {
      try {
        await clienteAntigo.dispose();
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    // Antes de apagar: um espelho apagado com as impressões digitais salvas
    // pularia o download inteiro na sincronização seguinte.
    await _esquecerEstadoDeSync(prefs);

    try {
      await _apagarArquivosDe(await _caminhoEspelho());
    } catch (_) {
      return false;
    }

    return true;
  }

  /// Testa credenciais digitadas sem mexer na conexão ativa do app.
  /// Lança exceção com a causa quando o teste falha.
  static Future<void> testarConexao(String url, String token) async {
    final client = LibsqlClient.remote(url, authToken: token);
    try {
      await client.connect().timeout(_timeoutConexao);
      await client.query('SELECT 1');
    } finally {
      unawaited(client.dispose().catchError((_) {}));
    }
  }

  // ── Leitura defensiva do driver ───────────────────────────────────────────

  /// Linha do driver como Map. Um cast rígido que falhasse transformaria toda
  /// sincronização em erro; as colunas são lidas por nome de qualquer forma.
  static Map<String, dynamic> _comoMapa(dynamic linha) {
    if (linha is Map<String, dynamic>) return linha;
    if (linha is Map) return linha.map((k, v) => MapEntry(k.toString(), v));
    return const {};
  }

  /// Lê um contador sem assumir o tipo devolvido pelo driver: no Android ele
  /// chega como PlatformInt64, não como int puro.
  static int _inteiro(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
