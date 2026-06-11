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
flutter build ios --config-only --no-codesign

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