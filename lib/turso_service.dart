import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:libsql_dart/libsql_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Conexão com o banco Turso da CAMDA via libsql_dart, sem backend no meio.
///
/// Este app é SOMENTE LEITURA: nenhum INSERT/UPDATE/DELETE e nenhum
/// CREATE/ALTER — o esquema pertence ao camda-estoque. Recomenda-se usar
/// um token read-only do Turso: se o celular for perdido, quem o achar
/// não consegue alterar o estoque (ver README).
///
/// Cache local (embedded replica): o banco vive num arquivo do dispositivo
/// e as consultas saem instantâneas mesmo com internet ruim. Como o app
/// nunca escreve, usamos `LibsqlClient.replica` (só puxa do primário) em
/// vez do modo offline-writes — não existe push, então não há conflito de
/// frame nem necessidade de token de escrita. O botão Sincronizar puxa as
/// novidades do Turso quando o usuário pedir.
class TursoService {
  static final TursoService _instance = TursoService._internal();
  factory TursoService() => _instance;
  TursoService._internal();

  static const String keyDbUrl      = 'turso_db_url';
  static const String keyDbToken    = 'turso_db_token';
  static const String keyCacheLocal = 'turso_cache_local';
  static const String keyUltimaSync = 'turso_ultima_sync';

  // Limites de tempo: nenhuma etapa de conexão/sincronização pode segurar o
  // app indefinidamente — estourou, cai no fallback (remoto) ou falha o
  // botão de sincronizar com aviso, mantendo o cache local intacto.
  static const Duration _timeoutConexao   = Duration(seconds: 20);
  static const Duration _timeoutBootstrap = Duration(seconds: 90);
  static const Duration _timeoutSync      = Duration(minutes: 3);

  LibsqlClient? _client;
  bool _connected = false;

  bool      _modoLocal           = false;
  bool      _sincronizando       = false;
  DateTime? _ultimaSincronizacao;
  String?   _ultimoErroSync;

  // Replica recém-criada (arquivo ainda sem as tabelas do camda-estoque):
  // consultar antes da primeira carga devolveria "não encontrado" para
  // qualquer código — um erro silencioso. Enquanto este flag estiver
  // ligado, garantirDadosProntos() espera a carga terminar.
  bool _cacheVazio = false;
  Future<bool>? _bootstrapEmAndamento;

  // Credenciais/modo da conexão ativa. Enquanto não mudarem, init()
  // reaproveita a conexão em vez de reconectar a cada abertura de página.
  String? _urlAtiva;
  String? _tokenAtivo;
  bool?   _cacheLocalAtivo;
  Future<void>? _initEmAndamento;

  bool get isConnected => _connected;

  LibsqlClient? get client => _client;

  /// True quando a conexão ativa usa o cache local (arquivo no dispositivo).
  bool get modoLocal => _modoLocal;

  bool get sincronizando => _sincronizando;

  DateTime? get ultimaSincronizacao => _ultimaSincronizacao;

  /// Descrição curta (para o usuário) do motivo da última falha de
  /// sincronização, ou null se a última tentativa deu certo.
  String? get ultimoErroSync => _ultimoErroSync;

  /// Incrementa a cada sincronização bem-sucedida. As telas ouvem para
  /// saber que os dados mudaram.
  final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);

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
    _bootstrapEmAndamento = null;

    if (clienteAntigo != null) {
      // Solta a conexão anterior (troca de credenciais ou de modo) sem
      // segurar o init novo.
      unawaited(clienteAntigo.dispose().catchError((_) {}));
    }

    if (url.isEmpty || token.isEmpty) return;

    LibsqlClient? client;
    var conectouLocal = false;

    if (cacheLocal) {
      client        = await _conectarComCacheLocal(url, token);
      conectouLocal = client != null;
    }
    // Sem cache local (preferência desligada ou falha ao abrir o arquivo):
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
      _cacheVazio = await _replicaVazia(client);
      if (_cacheVazio) unawaited(_bootstrap());
    }
  }

  Future<String> _caminhoCacheLocal() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/scanner_camda_cache.db';
  }

  Future<LibsqlClient?> _conectarComCacheLocal(String url, String token) async {
    LibsqlClient? client;
    try {
      final path = await _caminhoCacheLocal();
      // .replica (e não .offline): o app só lê, então não há gravação
      // local para empurrar de volta ao primário — sem push, não há
      // conflito de frame e um token read-only basta.
      client = LibsqlClient.replica(path, syncUrl: url, authToken: token);
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

  /// True se o arquivo local ainda não tem a tabela `estoque_mestre` —
  /// consultar nesse estado devolveria "não encontrado" para tudo.
  Future<bool> _replicaVazia(LibsqlClient client) async {
    try {
      final stmt = await client.prepare(
        "SELECT count(*) AS n FROM sqlite_master "
        "WHERE type = 'table' AND name = 'estoque_mestre'",
      );
      final rows = await stmt.query() as List<dynamic>;
      final n = (rows.first as Map<String, dynamic>)['n'] as int? ?? 0;
      return n == 0;
    } catch (_) {
      // Na dúvida, trata como vazia: melhor esperar uma carga a mais do
      // que responder "não encontrado" com o cache pela metade.
      return true;
    }
  }

  /// Carga inicial da replica local. Retorna true quando os dados estão
  /// disponíveis para consulta.
  Future<bool> _bootstrap() {
    final emAndamento = _bootstrapEmAndamento;
    if (emAndamento != null) return emAndamento;

    final futuro = () async {
      final client = _client;
      if (client == null) return false;
      try {
        await client.sync().timeout(_timeoutBootstrap);
        _cacheVazio = await _replicaVazia(client);
        await _registrarSincronizacao();
        _ultimoErroSync = null;
        dataRevision.value++;
        return !_cacheVazio;
      } catch (e) {
        _ultimoErroSync = _descreverErroSync(e);
        return false;
      } finally {
        _bootstrapEmAndamento = null;
      }
    }();

    _bootstrapEmAndamento = futuro;
    return futuro;
  }

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

  // Garante que existe conexão antes de uma consulta: se o init() da
  // abertura do app ainda não terminou (ou falhou), espera/tenta de novo em
  // vez de devolver resultado vazio silenciosamente.
  Future<bool> garantirConexao() async {
    if (_connected && _client != null) return true;
    await init();
    return _connected && _client != null;
  }

  /// Garante que há dados para consultar. No modo local com a replica
  /// ainda vazia, espera a carga inicial — responder "não encontrado" com
  /// o cache vazio seria um erro silencioso.
  ///
  /// Retorna false quando a carga inicial não conseguiu completar (sem
  /// internet na primeira execução).
  Future<bool> garantirDadosProntos() async {
    if (!await garantirConexao()) return false;
    if (!_modoLocal || !_cacheVazio) return true;
    return _bootstrap();
  }

  /// True quando o cache local está ligado mas ainda não tem os dados.
  bool get cacheVazio => _modoLocal && _cacheVazio;

  Future<void> _registrarSincronizacao() async {
    _ultimaSincronizacao = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyUltimaSync,
      _ultimaSincronizacao!.toIso8601String(),
    );
  }

  /// Sincroniza o cache local com o banco online (puxa as novidades do
  /// Turso). Retorna false quando não há conexão configurada ou a
  /// sincronização falhou — nesse caso os dados locais ficam intactos e dá
  /// para tentar de novo. No modo remoto não há o que sincronizar: as
  /// consultas já vão direto ao banco.
  Future<bool> sincronizar() async {
    if (_sincronizando) {
      _ultimoErroSync = 'já existe uma sincronização em andamento';
      return false;
    }
    if (!await garantirConexao()) {
      final configurado = await credenciaisConfiguradas();
      _ultimoErroSync = configurado
          ? 'sem conexão com o banco — verifique a internet'
          : 'configure URL e token do banco em ⚙️';
      return false;
    }
    _sincronizando = true;
    try {
      if (_modoLocal) {
        await _client!.sync().timeout(_timeoutSync);
        _cacheVazio = await _replicaVazia(_client!);
      }
      await _registrarSincronizacao();
      _ultimoErroSync = null;
      dataRevision.value++;
      return true;
    } catch (e) {
      _ultimoErroSync = _descreverErroSync(e);
      return false;
    } finally {
      _sincronizando = false;
    }
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

  /// Apaga o arquivo de cache local e reseta a conexão, forçando o próximo
  /// init() a rebaixar tudo do zero do Turso. Como o app só lê, nada é
  /// perdido: o conteúdo do arquivo é sempre uma cópia do banco online.
  Future<bool> limparCacheLocal() async {
    final clienteAntigo = _client;

    _connected       = false;
    _client          = null;
    _urlAtiva        = null;
    _tokenAtivo      = null;
    _cacheLocalAtivo = null;
    _modoLocal       = false;
    _ultimoErroSync  = null;
    _cacheVazio      = false;
    _bootstrapEmAndamento = null;

    if (clienteAntigo != null) {
      try {
        await clienteAntigo.dispose();
      } catch (_) {}
    }

    try {
      final base = await _caminhoCacheLocal();
      for (final sufixo in ['', '-wal', '-shm', '-journal', '-client_wal_index']) {
        final arquivo = File('$base$sufixo');
        if (await arquivo.exists()) await arquivo.delete();
      }
    } catch (_) {
      return false;
    }

    _ultimaSincronizacao = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyUltimaSync);

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
}
