#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH # change working directory to the root of your cloned repo.

echo "🔧 Installing Flutter..."

# Install Flutter using git.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

flutter config --no-enable-swift-package-manager

# Install Flutter artifacts for iOS (--ios), or macOS (--macos) platforms.
flutter precache --ios

# Install Flutter dependencies.
echo "📦 Installing Flutter dependencies..."
flutter pub get

# Generate necessary files


# Install CocoaPods using Homebrew.
echo "🍺 Installing CocoaPods..."
HOMEBREW_NO_AUTO_UPDATE=1 # disable homebrew's automatic updates.
brew install cocoapods

# Install CocoaPods dependencies.
echo "📦 Installing CocoaPods dependencies..."
cd ios
pod install

echo "🔨 Generating Flutter files..."
flutter build ios --config-only --no-codesign

echo "✅ CI setup complete!"

exit 0
