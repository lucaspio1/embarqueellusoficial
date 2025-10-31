#!/bin/bash

# Script para limpar cache do Flutter e reconstruir o app
# Resolve o erro de isolate "unsendable object"

echo "🧹 Limpando cache do Flutter..."
flutter clean

echo ""
echo "📦 Obtendo dependências..."
flutter pub get

echo ""
echo "🔨 Reconstruindo o aplicativo..."
echo "   Escolha uma opção:"
echo "   1) Executar em modo debug (flutter run)"
echo "   2) Apenas compilar APK (flutter build apk)"
echo ""
read -p "Opção (1 ou 2): " opcao

if [ "$opcao" = "1" ]; then
    echo ""
    echo "🚀 Executando em modo debug..."
    flutter run
elif [ "$opcao" = "2" ]; then
    echo ""
    echo "🏗️  Compilando APK..."
    flutter build apk
    echo ""
    echo "✅ APK compilado em: build/app/outputs/flutter-apk/app-release.apk"
    echo ""
    read -p "Deseja instalar o APK no dispositivo conectado? (s/n): " instalar
    if [ "$instalar" = "s" ] || [ "$instalar" = "S" ]; then
        echo "📲 Instalando APK..."
        flutter install
    fi
else
    echo "❌ Opção inválida"
    exit 1
fi

echo ""
echo "✅ Processo concluído!"
echo ""
echo "ℹ️  Se o erro de isolate persistir:"
echo "   1. Desinstale o app do dispositivo manualmente"
echo "   2. Execute: flutter run"
