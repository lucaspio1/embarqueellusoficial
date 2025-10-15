import 'package:flutter/material.dart';
import 'package:embarqueellus/screens/main_menu_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SUBSTITUA ESTA STRING PELA URL DA SUA IMPLANTAÇÃO DO APPS SCRIPT
const String apiUrl = "https://script.google.com/macros/s/AKfycbzYfQrCYprqo8yBdHEi2UrOVp56w0aHbG_zXNHbuh7RAf-ut6n933at1Du9OzNkoAFh/exec";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ellus - Controle de Embarque',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4C643C),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const MainMenuScreen(),
    );
  }
}