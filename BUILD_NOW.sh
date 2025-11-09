#!/bin/bash

# ============================================
# SCRIPT DE BUILD iOS - EXECUTAR NO MAC (VNC)
# ============================================
#
# IMPORTANTE: Este script deve ser executado no Mac da Amazon via VNC
# Não execute em ambiente Linux!
#
# Passos:
# 1. Conectar no Mac via VNC
# 2. Abrir Terminal
# 3. Navegar até o projeto: cd /caminho/para/embarqueellusoficial
# 4. Executar: bash BUILD_NOW.sh
#
# ============================================

set -e  # Parar se houver erro

echo "🚀 ========================================"
echo "🚀 BUILD iOS - EmbarqueEllus"
echo "🚀 ========================================"
echo ""

# Verificar se estamos no diretório correto
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ ERRO: Execute este script na raiz do projeto Flutter!"
    echo "   Exemplo: cd /caminho/para/embarqueellusoficial && bash BUILD_NOW.sh"
    exit 1
fi

echo "📁 Diretório atual: $(pwd)"
echo ""

# ============================================
# PASSO 1: Puxar alterações do Git
# ============================================
echo "📥 [1/6] Puxando alterações do Git..."
git fetch origin
git checkout claude/fix-facial-detection-ios-011CUxfp7S6e3gpsK46ZLW8F
git pull origin claude/fix-facial-detection-ios-011CUxfp7S6e3gpsK46ZLW8F
echo "✅ Código atualizado!"
echo ""

# ============================================
# PASSO 2: Limpar cache Flutter
# ============================================
echo "🧹 [2/6] Limpando cache Flutter..."
flutter clean
echo "✅ Cache Flutter limpo!"
echo ""

# ============================================
# PASSO 3: Instalar dependências Flutter
# ============================================
echo "📦 [3/6] Instalando dependências Flutter..."
flutter pub get
echo "✅ Dependências Flutter instaladas!"
echo ""

# ============================================
# PASSO 4: Limpar e reinstalar CocoaPods
# ============================================
echo "🍫 [4/6] Limpando e reinstalando CocoaPods..."
cd ios
rm -rf Pods Podfile.lock
rm -rf ~/Library/Developer/Xcode/DerivedData/*

echo "   Instalando pods (pode demorar 3-5 minutos)..."
pod install --repo-update

echo "✅ CocoaPods instalado!"
echo ""

# Verificar se Sentry foi instalado
echo "🔍 Verificando instalação do Sentry..."
if grep -q "Sentry" Podfile.lock; then
    SENTRY_VERSION=$(grep -A 1 "- Sentry" Podfile.lock | tail -1 | sed 's/.*(\(.*\))/\1/')
    echo "✅ Sentry instalado: $SENTRY_VERSION"
else
    echo "⚠️  AVISO: Sentry pode não ter sido instalado corretamente!"
fi

if grep -q "sentry_flutter" Podfile.lock; then
    SENTRY_FLUTTER_VERSION=$(grep -A 1 "- sentry_flutter" Podfile.lock | tail -1 | sed 's/.*(\(.*\))/\1/')
    echo "✅ sentry_flutter instalado: $SENTRY_FLUTTER_VERSION"
else
    echo "⚠️  AVISO: sentry_flutter pode não ter sido instalado corretamente!"
fi
echo ""

cd ..

# ============================================
# PASSO 5: Build iOS em modo Release
# ============================================
echo "🏗️  [5/6] Buildando iOS em modo Release..."
echo "   (Este passo pode demorar 10-15 minutos...)"
flutter build ios --release --no-codesign

echo "✅ Build iOS concluído!"
echo ""

# ============================================
# PASSO 6: Verificar resultado
# ============================================
echo "🔍 [6/6] Verificando resultado do build..."

if [ -d "build/ios/iphoneos/Runner.app" ]; then
    echo "✅ Runner.app criado com sucesso!"

    APP_SIZE=$(du -sh build/ios/iphoneos/Runner.app | cut -f1)
    echo "   Tamanho: $APP_SIZE"

    echo ""
    echo "🎯 ========================================"
    echo "🎯 BUILD CONCLUÍDO COM SUCESSO!"
    echo "🎯 ========================================"
    echo ""
    echo "📱 PRÓXIMOS PASSOS:"
    echo ""
    echo "1. Abrir projeto no Xcode:"
    echo "   cd ios && open Runner.xcworkspace"
    echo ""
    echo "2. No Xcode:"
    echo "   • Selecione 'Any iOS Device' como target"
    echo "   • Product → Archive"
    echo "   • Aguarde conclusão do Archive"
    echo ""
    echo "3. Upload para TestFlight:"
    echo "   • Organizer abrirá automaticamente"
    echo "   • Selecione o archive"
    echo "   • Distribute App → App Store Connect → Upload"
    echo "   • ✅ Upload symbols: YES (CRÍTICO para Sentry)"
    echo "   • ❌ Include bitcode: NO"
    echo ""
    echo "4. Aguardar processamento no App Store Connect:"
    echo "   https://appstoreconnect.apple.com"
    echo ""
    echo "5. Distribuir para testadores quando status = 'Ready to Test'"
    echo ""
    echo "🔍 MONITORAR SENTRY:"
    echo "   https://sentry.io"
    echo ""
    echo "   Procure por eventos:"
    echo "   • '🍎 iOS AppDelegate: Sentry NATIVO inicializado!'"
    echo "   • '✅ App Flutter iniciado com sucesso! Platform: iOS'"
    echo ""
    echo "📖 DOCUMENTAÇÃO COMPLETA:"
    echo "   Veja: IOS_BUILD_INSTRUCTIONS.md"
    echo ""
else
    echo "❌ ERRO: Runner.app não foi criado!"
    echo "   Verifique erros acima e tente novamente."
    echo ""
    echo "   Se houver erro de assinatura, use:"
    echo "   flutter build ios --release --no-codesign"
    echo ""
    exit 1
fi

echo "✅ Script concluído!"
