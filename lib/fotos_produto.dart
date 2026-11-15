import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'consulta.dart';

/// Fotos dos produtos — SÓ LOCAIS: ficam em
/// `<documentos do app>/fotos/<codigo>.jpg` e nunca vão para o Turso, para o
/// espelho ou para o cache. O banco continua somente leitura.
class FotosProduto {
  FotosProduto._(this._pasta);

  final Directory _pasta;

  static Future<FotosProduto> abrir() async {
    final docs = await getApplicationDocumentsDirectory();
    final pasta = Directory(p.join(docs.path, 'fotos'));
    if (!pasta.existsSync()) pasta.createSync(recursive: true);
    return FotosProduto._(pasta);
  }

  /// Código sem o prefixo "US" (US254185 → 254185), em maiúsculas.
  static String codigoParaArquivo(String codigo) {
    final c = (normalizarCodigo(codigo) ?? '');
    return RegExp(r'^US\d').hasMatch(c) ? c.substring(2) : c;
  }

  /// Todos os códigos do produto (lido + vinculados), já normalizados.
  static List<String> codigosDe(ResultadoConsulta r) {
    final todos = <String>{
      codigoParaArquivo(r.codigoLido),
      for (final s in r.saldos) codigoParaArquivo(s.codigo),
      for (final c in r.codigosSemSaldo) codigoParaArquivo(c),
    }..remove('');
    return todos.toList();
  }

  File _arquivo(String codigo) =>
      File(p.join(_pasta.path, '${codigoParaArquivo(codigo)}.jpg'));

  /// Foto de qualquer um dos códigos, ou null.
  File? existente(ResultadoConsulta r) {
    for (final c in codigosDe(r)) {
      final f = _arquivo(c);
      if (f.existsSync()) return f;
    }
    return null;
  }

  /// Escolhe (câmera/galeria) e grava. Devolve false se o usuário cancelou.
  Future<bool> salvar(ResultadoConsulta r, ImageSource origem) async {
    final x = await ImagePicker().pickImage(
      source: origem,
      maxWidth: 900,
      imageQuality: 80,
    );
    if (x == null) return false;
    // Foto nova substitui a antiga, esteja ela em qual código estiver.
    await remover(r);
    await x.saveTo(_arquivo(r.codigoLido).path);
    return true;
  }

  Future<void> remover(ResultadoConsulta r) async {
    for (final c in codigosDe(r)) {
      final f = _arquivo(c);
      if (f.existsSync()) await f.delete();
    }
  }
}
