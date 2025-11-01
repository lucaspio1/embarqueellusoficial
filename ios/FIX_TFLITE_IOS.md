# Fix TensorFlow Lite no iOS

## Problema
Erro ao cadastrar facial: `INVALID ARGUMENTS: FAILED TO LOOKUP SYMBOL 'TFLITEINTERPRETEROPTIONScREATE: DLSYM(RTLD_DEFAULT, TFLITEINTERPRETEROPTIONSCREATE) SYMBOL NOT FOUND`

## Causa
O pacote `tflite_flutter` não inclui automaticamente as bibliotecas nativas do TensorFlow Lite no iOS. É necessário adicionar manualmente o pod `TensorFlowLiteC`.

## Solução Aplicada

✅ Adicionei a dependência `TensorFlowLiteC` no arquivo `ios/Podfile`:

```ruby
pod 'TensorFlowLiteC', '~> 2.14.0'
```

## Próximos Passos (EXECUTE NO SEU MAC)

### 1. Limpar o projeto
```bash
flutter clean
```

### 2. Atualizar dependências Flutter
```bash
flutter pub get
```

### 3. Instalar pods do iOS
```bash
cd ios
pod deintegrate  # Remove pods antigos
pod install      # Instala novos pods incluindo TensorFlowLiteC
cd ..
```

### 4. Limpar build do Xcode (Opcional mas recomendado)
Abra o Xcode e:
- Product > Clean Build Folder (Cmd + Shift + K)
- Ou via terminal:
```bash
cd ios
rm -rf build
rm -rf Pods
rm Podfile.lock
pod install
cd ..
```

### 5. Rebuild do app
```bash
flutter run
# ou
flutter build ios
```

## Verificação

Após seguir os passos acima, tente cadastrar um rosto novamente. O erro deve ser resolvido e o TensorFlow Lite deve carregar corretamente.

## Troubleshooting

Se ainda tiver problemas:

### Erro: "pod: command not found"
```bash
sudo gem install cocoapods
```

### Erro ao instalar pods
```bash
cd ios
pod repo update
pod install --repo-update
cd ..
```

### Verificar se o TensorFlowLiteC foi instalado
```bash
cd ios
pod list | grep TensorFlow
```

Deve aparecer: `TensorFlowLiteC (2.14.0)`

### Limpar completamente e reinstalar
```bash
flutter clean
cd ios
rm -rf Pods
rm -rf build
rm Podfile.lock
pod cache clean --all
pod install
cd ..
flutter pub get
flutter run
```

## Notas Técnicas

- **Versão do TensorFlow Lite**: 2.14.0 (compatível com tflite_flutter 0.11.0)
- **Plataforma iOS mínima**: 15.5 (já configurado no Podfile)
- **Arquiteturas suportadas**: arm64 (dispositivos reais) e x86_64/arm64 (simulador)

## Arquivos Modificados

- ✅ `ios/Podfile` - Adicionado pod 'TensorFlowLiteC'
- ✅ `android/app/build.gradle.kts` - Adicionadas bibliotecas TensorFlow Lite (para Android também)
