import 'dart:async';

import 'package:libsql_dart/libsql_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Conexão com o banco Turso da CAMDA via libsql_dart, sem backend no meio.
///
/// Este app é SOMENTE LEITURA: nenhum INSERT/UPDATE/DELETE e nenhum
/// CREATE/ALTER — o esquema pertence ao camda-estoque. Recomenda-se usar
/// um token read-only do Turso: se o celular for perdido, quem o achar
/// não consegue alterar o estoque (ver README).
class TursoService {
  static final TursoService _instance = TursoService._internal();
  factory TursoService() => _instance;
  TursoService._internal();

  static const String keyDbUrl   = 'turso_db_url';
  static const String keyDbToken = 'turso_db_token';

  static const Duration _timeoutConexao = Duration(seconds: 20);

  LibsqlClient? _client;
  bool _connected = false;

  // Credenciais da conexão ativa. Enquanto não mudarem, init() reaproveita a
  // conexão em vez de reconectar a cada abertura de página.
  String? _urlAtiva;
  String? _tokenAtivo;
  Future<void>? _initEmAndamento;

  bool get isConnected => _connected;

  LibsqlClient? get client => _client;

  /// Serializa os inits em vez de "pegar carona" no que está no ar: se um
  /// init antigo ainda roda com credenciais velhas (o usuário acabou de
  /// salvar outras), o próximo espera e roda em seguida, aplicando as novas.
  Future<void> init() {
    final anterior = _initEmAndamento ?? Future<void>.value();
    final novo = anterior.catchError((_) {}).then<void>((_) => _init());
    _initEmAndamento = novo;
    return novo;
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final url   = prefs.getString(keyDbUrl)   ?? '';
    final token = prefs.getString(keyDbToken) ?? '';

    if (_connected &&
        _client != null &&
        url == _urlAtiva &&
        token == _tokenAtivo) {
      return;
    }

    final clienteAntigo = _client;
    _connected  = false;
    _client     = null;
    _urlAtiva   = null;
    _tokenAtivo = null;
    if (clienteAntigo != null) {
      unawaited(clienteAntigo.dispose().catchError((_) {}));
    }

    if (url.isEmpty || token.isEmpty) return;

    try {
      final client = LibsqlClient.remote(url, authToken: token);
      await client.connect().timeout(_timeoutConexao);
      _client     = client;
      _connected  = true;
      _urlAtiva   = url;
      _tokenAtivo = token;
    } catch (_) {
      _connected = false;
      _client    = null;
    }
  }

  /// True quando URL e token já foram salvos na tela de configuração.
  Future<bool> credenciaisConfiguradas() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(keyDbUrl) ?? '').isNotEmpty &&
        (prefs.getString(keyDbToken) ?? '').isNotEmpty;
  }

  // Garante que existe conexão antes de uma consulta: se o init() da
  // abertura do app ainda não terminou (ou falhou), espera/tenta de novo em
  // vez de devolver resultado vazio silenciosamente.
  Future<bool> garantirConexao() async {
    if (_connected && _client != null) return true;
    await init();
    return _connected && _client != null;
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
