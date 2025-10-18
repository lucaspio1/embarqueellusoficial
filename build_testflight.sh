#!/bin/bash
set -e

# ==============================
#  Flutter iOS Build + Upload
# ==============================

# CONFIGURAES DO APP
APPLE_ID="lucaspio1@icloud.com"
APP_PASSWORD="xqps-oooq-rmom-uioq"   # senha especfica de app
TEAM_ID="UHKV55F459"
PROJECT_DIR="$HOME/Documents/embarqueellusoficial"
IPA_NAME="Runner.ipa"

echo "======================================"
echo "  Iniciando build iOS para TestFlight"
echo "======================================"
cd "$PROJECT_DIR"

# LIMPA O PROJETO
echo " Limpando build anterior..."
flutter clean
flutter pub get

# GERA O BUILD IOS
echo "  Gerando build iOS (modo release)..."
flutter build ios --release

# CRIA EXPORTOPTIONS PLIST (caso no exista)
EXPORT_PLIST="ios/exportOptions.plist"
if [ ! -f "$EXPORT_PLIST" ]; then
    echo " Criando exportOptions.plist..."
    cat <<EOF > "$EXPORT_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>uploadBitcode</key>
  <false/>
  <key>compileBitcode</key>
  <true/>
  <key>destination</key>
  <string>export</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>thinning</key>
  <string>&lt;none&gt;</string>
</dict>
</plist>
EOF
fi

# EXPORTA O IPA
echo " Exportando .ipa..."
xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist "$EXPORT_PLIST"

# VERIFICA SE O IPA EXISTE
if [ ! -f "build/ios/ipa/$IPA_NAME" ]; then
  echo " Erro: Arquivo $IPA_NAME no encontrado!"
  exit 1
fi

# UPLOAD PARA TESTFLIGHT
echo "  Enviando $IPA_NAME para o TestFlight..."
xcrun altool --upload-app \
  -f "build/ios/ipa/$IPA_NAME" \
  -t ios \
  -u "$APPLE_ID" \
  -p "$APP_PASSWORD"

# RESULTADO FINAL
if [ $? -eq 0 ]; then
  echo " Upload concludo com sucesso! Verifique o TestFlight no App Store Connect."
else
  echo " Falha no upload. Verifique suas credenciais ou a conexo."
fi
