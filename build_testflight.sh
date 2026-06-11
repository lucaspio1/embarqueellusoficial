#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH 

echo "🔧 Instalando e Configurando Flutter..."

# Configuração crítica: desativa o SPM antes de qualquer build
flutter config --no-enable-swift-package-manager

# Install Flutter using git.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Install Flutter artifacts
flutter precache --ios

# Install Flutter dependencies.
echo "📦 Installing Flutter dependencies..."
flutter pub get

# Generate necessary files
echo "🔨 Generating Flutter files..."
flutter build ios --config-only --no-codesign

# Install CocoaPods
echo "🍺 Installing CocoaPods..."
# Removido o HOMEBREW_NO_AUTO_UPDATE=1 para garantir que o pod seja instalado corretamente
brew install cocoapods

# Install CocoaPods dependencies.
echo "📦 Installing CocoaPods dependencies..."
cd ios

# GARANTE QUE O PODFILE NÃO TENHA REFERÊNCIAS AO SPM
# Se o seu Podfile usa a regra de "use_frameworks!", mantenha, 
# mas garanta que o comando de desativação do SPM (acima) já resolveu.
rm -rf Pods
rm -f Podfile.lock
pod install --repo-update

echo "✅ CI setup complete!"

exit 0