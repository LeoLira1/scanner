import 'package:flutter/material.dart';

/// Identidade visual da maquete tag-estoque.html (raiz do repositório),
/// que segue o camda-estoque: fundo escuro, laranja "brasa" e verde como
/// acentos, JetBrains Mono para números e Sora para texto.
///
/// Tela pensada para uso de pé, com uma mão, sob luz de galpão:
/// contraste alto, números grandes, área de toque generosa.
abstract class TemaCamda {
  // Paleta da maquete (--ink, --surface, --line, --text, --muted...).
  static const Color fundo      = Color(0xFF0C0D0F);
  static const Color card       = Color(0xFF15171B);
  static const Color borda      = Color(0x12FFFFFF); // branco 7%
  static const Color texto      = Color(0xFFF2EFEC);
  static const Color textoFraco = Color(0xFF767C85);
  static const Color laranja    = Color(0xFFE87722); // --brasa
  static const Color verde      = Color(0xFF00D68F);
  static const Color vermelho   = Color(0xFFE57373);

  static const String fonteTexto   = 'Sora';
  static const String fonteNumeros = 'JetBrains Mono';

  /// Sora embarcada é variável (eixo wght): pesos acima do Regular
  /// precisam do FontVariation — fontWeight sozinho não move o eixo.
  static TextStyle textoStyle({
    double tamanho = 14,
    double peso = 400,
    Color cor = texto,
    double? altura,
    double? espacamento,
  }) =>
      TextStyle(
        fontFamily: fonteTexto,
        fontSize: tamanho,
        color: cor,
        height: altura,
        letterSpacing: espacamento,
        fontVariations: [FontVariation('wght', peso)],
        fontWeight: peso >= 600 ? FontWeight.w600 : FontWeight.w400,
      );

  static TextStyle numeroStyle({
    double tamanho = 16,
    bool negrito = false,
    Color cor = texto,
    double? altura,
    double? espacamento,
  }) =>
      TextStyle(
        fontFamily: fonteNumeros,
        fontSize: tamanho,
        color: cor,
        height: altura,
        letterSpacing: espacamento,
        fontWeight: negrito ? FontWeight.w700 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static ThemeData tema() => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: fundo,
        colorScheme: ColorScheme.fromSeed(
          seedColor: laranja,
          brightness: Brightness.dark,
          surface: fundo,
        ),
        fontFamily: fonteTexto,
        appBarTheme: const AppBarTheme(
          backgroundColor: fundo,
          elevation: 0,
          iconTheme: IconThemeData(color: textoFraco),
          titleTextStyle: TextStyle(
            fontFamily: fonteTexto,
            color: texto,
            fontSize: 15,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          contentTextStyle: TextStyle(
            fontFamily: fonteTexto,
            fontSize: 13,
            color: Colors.white,
          ),
        ),
      );
}
