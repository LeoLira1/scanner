import 'package:flutter/material.dart';

import 'home_page.dart';
import 'tema.dart';
import 'turso_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Conecta em segundo plano na abertura; as consultas chamam
  // garantirConexao() e esperam este init se ele ainda estiver no ar. O
  // próprio init dispara a atualização do espelho quando os dados estão
  // velhos — quem abre o app já pega o estoque do dia sem apertar nada.
  TursoService().init();
  runApp(const ScannerCamdaApp());
}

class ScannerCamdaApp extends StatelessWidget {
  const ScannerCamdaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scanner CAMDA',
      debugShowCheckedModeBanner: false,
      theme: TemaCamda.tema(),
      home: const HomePage(),
    );
  }
}
