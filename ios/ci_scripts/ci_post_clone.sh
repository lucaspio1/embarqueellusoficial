#!/bin/sh
set -e

cd $CI_PRIMARY_REPOSITORY_PATH

echo "🔧 Installing Flutter..."

git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

flutter config --no-enable-swift-package-manager

flutter precache --ios

echo "📦 Installing Flutter dependencies..."
flutter pub get

echo "🔨 Generating Flutter files..."
# Número de build único a cada execução do Xcode Cloud: o App Store Connect
# recusa ("Preparing build for App Store Connect failed") um build com o mesmo
# CFBundleVersion de um já enviado. Usa o maior entre o pubspec e o CI_BUILD_NUMBER.
BUILD_NAME=$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//; s/+.*//' | tr -d '\r')
PUBSPEC_BUILD=$(grep '^version:' pubspec.yaml | sed 's/.*+//' | tr -d '\r')
BUILD_NUMBER=${CI_BUILD_NUMBER:-$PUBSPEC_BUILD}
if [ "$PUBSPEC_BUILD" -gt "$BUILD_NUMBER" ] 2>/dev/null; then
  BUILD_NUMBER=$PUBSPEC_BUILD
fi
echo "📌 Versão iOS: $BUILD_NAME ($BUILD_NUMBER)"
flutter build ios --config-only --no-codesign --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER"

echo "🍺 Installing CocoaPods..."
export HOMEBREW_NO_AUTO_UPDATE=1
brew install cocoapods

echo "📦 Installing CocoaPods dependencies..."
cd ios

rm -f Podfile.lock
rm -rf Pods

pod deintegrate || true
pod repo update
pod install --repo-update

cd ..

echo "✅ CI setup complete!"