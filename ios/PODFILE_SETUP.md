# Configuração do Podfile - Solução para Conflitos MLKit/TensorFlow

## ✅ Problemas Resolvidos

### 1. Conflito EXCLUDED_ARCHS
**Problema Original:**
```
[!] Can't merge user_target_xcconfig for pod targets: ["BarcodeScanning", "FaceDetection",
"MLKitCore", "MLImage", "MLKitBarcodeScanning", "MLKitCommon", "MLKitFaceDetection",
"MLKitVision", "TensorFlowLiteC", "Core", "CoreML", "Metal", "TensorFlowLiteSwift"].
Singular build setting EXCLUDED_ARCHS[sdk=iphonesimulator*] has different values.
```

**Causa:**
Diferentes pods do GoogleMLKit e TensorFlow Lite definem valores conflitantes para `EXCLUDED_ARCHS[sdk=iphonesimulator*]`. Alguns tentam excluir `arm64`, outros não, causando erro no merge do CocoaPods.

**Solução Implementada:**
- **pre_install hook**: Remove `EXCLUDED_ARCHS` de todos os pods ANTES do CocoaPods fazer o merge
- **post_install hook**: Remove `EXCLUDED_ARCHS` de todas as configurações de build após a instalação
- **Salva o projeto**: Força a regeneração dos arquivos `.xcconfig` sem os conflitos

### 2. Aviso de Configuração Base do CocoaPods
**Aviso Original:**
```
[!] CocoaPods did not set the base configuration of your project because your project
already has a custom config set. In order for CocoaPods integration to work at all,
please either set the base configurations of the target `Runner` to
`Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig` or include the
`Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig` in your build
configuration (`Flutter/Release.xcconfig`)
```

**Status:**
⚠️ Este é um aviso **INFORMATIVO e ESPERADO** em projetos Flutter.

**Por que é esperado:**
- O Flutter gerencia seus próprios arquivos `.xcconfig` em `ios/Flutter/`
- Estes arquivos JÁ INCLUEM os arquivos do CocoaPods usando `#include?`
- Verificado em:
  - `ios/Flutter/Debug.xcconfig`: `#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"`
  - `ios/Flutter/Release.xcconfig`: `#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"`
  - `ios/Flutter/Profile.xcconfig`: `#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"`

**Conclusão:**
Não requer correção. A integração está funcionando corretamente através dos includes.

## 📋 Estrutura do Podfile

```ruby
platform :ios, '15.5'  # Versão mínima para GoogleMLKit 7.0.0

# PRE-INSTALL: Remove EXCLUDED_ARCHS antes do merge
pre_install do |installer|
  installer.pod_targets.each do |pod|
    if pod.respond_to?(:user_build_configurations)
      pod.user_build_configurations.each do |config_name, config_hash|
        config_hash.delete('EXCLUDED_ARCHS[sdk=iphonesimulator*]')
        config_hash.delete('EXCLUDED_ARCHS[sdk=iphoneos*]')
      end
    end
  end
end

# POST-INSTALL: Configurações finais e limpeza
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    target.build_configurations.each do |config|
      # Remove EXCLUDED_ARCHS completamente
      config.build_settings.delete('EXCLUDED_ARCHS[sdk=iphonesimulator*]')
      config.build_settings.delete('EXCLUDED_ARCHS[sdk=iphoneos*]')
      config.build_settings.delete('EXCLUDED_ARCHS')

      # Outras correções para Xcode 15/16 + MLKit
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['ENABLE_MODULE_VERIFIER'] = 'NO'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'
    end
  end

  # Força regeneração sem conflitos
  installer.pods_project.save
end
```

## 🚀 Instalação e Build

```bash
cd ios

# Limpa instalação anterior
rm -rf Pods Podfile.lock

# Instala com as novas configurações
pod install

# Retorna à raiz e executa
cd ..
flutter clean
flutter pub get
flutter run
```

## ✅ Resultado Esperado

Após executar `pod install`, você deve ver:

```
Analyzing dependencies
Downloading dependencies
Installing [pods...]
Generating Pods project
Integrating client project

[!] CocoaPods did not set the base configuration... [AVISO INFORMATIVO - OK]

Pod installation complete! There are X dependencies from the Podfile and X total pods installed.
```

**Avisos de EXCLUDED_ARCHS não devem mais aparecer.**

## 🔧 Configurações Incluídas

### Correções de Build
- ✅ Versão mínima iOS 15.5 (requerida por GoogleMLKit 7.0.0)
- ✅ Sem assinatura de código para Pods
- ✅ Module Verifier desativado (bug Xcode 15/16)
- ✅ Headers do Flutter configurados corretamente
- ✅ Suporte nativo para Apple Silicon (arm64)

### Pods Suportados
- GoogleMLKit (FaceDetection, BarcodeScanning)
- TensorFlowLiteSwift e TensorFlowLiteC
- MLImage, MLKitCommon, MLKitVision
- Todos os outros pods Flutter (camera, image_picker, sqflite, etc.)

## 📝 Notas Importantes

1. **Não ignore o aviso do CocoaPods sobre configuração base** - mas entenda que é esperado e não causa problemas
2. **Apple Silicon**: arm64 agora é SUPORTADO no simulador (não mais excluído)
3. **Versão mínima**: Dispositivos com iOS < 15.5 não poderão executar o app
4. **Xcode 15/16**: Todas as configurações foram testadas para compatibilidade

## 🐛 Troubleshooting

Se ainda encontrar problemas:

```bash
# Limpeza completa
cd ios
rm -rf Pods Podfile.lock .symlinks
cd ..
flutter clean
flutter pub get
cd ios
pod install --repo-update
```

---
**Última atualização:** 2025-11-07
**Versão Flutter testada:** 3.22+
**Xcode testado:** 15.x, 16.x
