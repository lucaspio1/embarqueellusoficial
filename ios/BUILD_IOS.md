# Guia de Build para iOS - Embarque Ellus

Este documento contém as instruções necessárias para fazer o build do aplicativo para iOS.

## Pré-requisitos

- macOS (necessário para desenvolvimento iOS)
- Xcode 14.0 ou superior
- CocoaPods instalado (`sudo gem install cocoapods`)
- Flutter SDK instalado e configurado
- Conta Apple Developer (para deploy em dispositivos físicos)

## Configurações do Projeto

### Versão Mínima do iOS
- **iOS 15.5** ou superior

### Permissões Configuradas

O arquivo `Info.plist` já está configurado com as seguintes permissões:

- **NSCameraUsageDescription**: Acesso à câmera para reconhecimento facial
- **NSPhotoLibraryUsageDescription**: Acesso à galeria de fotos
- **NSPhotoLibraryAddUsageDescription**: Permissão para salvar fotos
- **NSMicrophoneUsageDescription**: Acesso ao microfone (funcionalidade de câmera)

### Dependências Principais

As seguintes dependências estão configuradas para iOS:

1. **tflite_flutter**: Reconhecimento facial com TensorFlow Lite
2. **camera**: Acesso à câmera do dispositivo
3. **google_mlkit_face_detection**: Detecção de rostos
4. **google_mlkit_barcode_scanning**: Leitura de códigos de barras/QR
5. **sqflite**: Banco de dados local
6. **connectivity_plus**: Verificação de conectividade
7. **shared_preferences**: Armazenamento de preferências

## Passos para Build

### 1. Instalar Dependências do Flutter

```bash
cd /path/to/embarqueellusoficial
flutter pub get
```

### 2. Instalar Dependências do CocoaPods

```bash
cd ios
pod install --repo-update
```

**Nota**: Se encontrar erros, tente:
```bash
pod cache clean --all
rm -rf Pods Podfile.lock
pod install --repo-update
```

### 3. Abrir o Projeto no Xcode

```bash
open ios/Runner.xcworkspace
```

**IMPORTANTE**: Sempre abra o arquivo `.xcworkspace`, não o `.xcodeproj`!

### 4. Configurar Assinatura de Código

No Xcode:

1. Selecione o projeto "Runner" no navegador de projetos
2. Selecione o target "Runner"
3. Vá para a aba "Signing & Capabilities"
4. Selecione seu Team (conta Apple Developer)
5. Altere o Bundle Identifier se necessário (sugestão: `com.ellus.embarque`)

### 5. Selecionar o Dispositivo/Simulador

- Para simulador: Selecione um simulador iOS 15.5+ no menu superior
- Para dispositivo físico: Conecte seu iPhone/iPad e selecione-o no menu

### 6. Build e Run

**Opção 1: Pelo Xcode**
- Clique no botão "Play" (▶) ou pressione `Cmd + R`

**Opção 2: Pela linha de comando**
```bash
# Para simulador
flutter run -d ios

# Para dispositivo específico
flutter run -d <device_id>

# Para listar dispositivos disponíveis
flutter devices
```

### 7. Build para Release

```bash
# Build do IPA
flutter build ipa --release

# Ou build do bundle
flutter build ios --release
```

O arquivo IPA será gerado em: `build/ios/ipa/`

## Configurações Especiais do Podfile

O Podfile está configurado com as seguintes otimizações:

- **ENABLE_BITCODE**: Desabilitado (necessário para TensorFlow Lite)
- **BUILD_LIBRARY_FOR_DISTRIBUTION**: Habilitado (compatibilidade com MLKit)
- **IPHONEOS_DEPLOYMENT_TARGET**: 15.5
- **SWIFT_VERSION**: 5.0

## Arquivos de Modelo

Certifique-se de que o modelo de reconhecimento facial está presente:

```
assets/models/arcface.tflite
```

## Solução de Problemas Comuns

### Erro: "Command PhaseScriptExecution failed"

```bash
cd ios
pod deintegrate
pod install --repo-update
```

### Erro: "Unable to find a specification for..."

```bash
pod repo update
pod install
```

### Erro: "DT_TOOLCHAIN_DIR cannot be used to evaluate..."

Este erro já está resolvido no `post_install` do Podfile.

### Erro: "Missing purpose string in Info.plist"

Todas as permissões necessárias já estão configuradas no Info.plist.

### Erro com TensorFlow Lite

Se houver erros relacionados ao tflite_flutter:

1. Verifique se o modelo está em `assets/models/arcface.tflite`
2. Limpe o build: `flutter clean && flutter pub get`
3. Reinstale os pods: `cd ios && pod install --repo-update`

### Problemas com MLKit

Se o MLKit apresentar erros:

```bash
cd ios
rm -rf Pods Podfile.lock
pod cache clean --all
pod install --repo-update
```

## Build para App Store

### 1. Preparar o App para Produção

```bash
flutter build ipa --release
```

### 2. Configurar no App Store Connect

1. Acesse https://appstoreconnect.apple.com
2. Crie um novo app
3. Configure as informações do app
4. Adicione screenshots e descrições

### 3. Upload do Build

**Opção 1: Via Xcode**
1. Abra `ios/Runner.xcworkspace`
2. Product > Archive
3. Distribute App > App Store Connect

**Opção 2: Via Transporter App**
1. Abra o app Transporter
2. Arraste o arquivo `.ipa`
3. Faça o upload

## Checklist Pré-Build

- [ ] Todas as permissões estão configuradas no Info.plist
- [ ] Bundle Identifier está correto
- [ ] Versão do app está atualizada (pubspec.yaml)
- [ ] Modelo TFLite está presente em assets/
- [ ] Ícone do app está configurado
- [ ] Splash screen está configurado
- [ ] Pods instalados e atualizados
- [ ] Build de debug funciona corretamente
- [ ] Assinatura de código configurada (para dispositivo físico)

## Recursos Adicionais

- [Documentação oficial Flutter - iOS](https://docs.flutter.dev/deployment/ios)
- [Guia de deployment - App Store](https://docs.flutter.dev/deployment/ios#create-an-app-bundle)
- [CocoaPods Troubleshooting](https://guides.cocoapods.org/using/troubleshooting)

## Suporte

Em caso de dúvidas ou problemas:

1. Verifique os logs no Xcode (View > Debug Area > Activate Console)
2. Execute `flutter doctor -v` para verificar a instalação
3. Consulte a documentação das dependências específicas

---

**Última atualização**: 2025-10-31
**Versão do iOS suportada**: 15.5+
**Xcode recomendado**: 14.0+
