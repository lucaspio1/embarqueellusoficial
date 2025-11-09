# Instruções para Build e Deploy iOS - Detecção Facial + Sentry

## IMPORTANTE: Correções Aplicadas

Foram aplicadas as seguintes correções CRÍTICAS para resolver o problema de detecção facial e logs no iOS:

### ✅ Correções Implementadas:

1. **Sentry Nativo no iOS** (`ios/Runner/AppDelegate.swift`)
   - Inicialização nativa do Sentry SDK no AppDelegate
   - Captura de crashes e erros nativos do iOS
   - Logs de confirmação de inicialização

2. **Sentry Flutter com Debug Forçado** (`lib/main.dart`)
   - `options.debug = true` SEMPRE ativo (para diagnóstico)
   - Captura de erros Flutter não tratados (`FlutterError.onError`)
   - Captura de erros assíncronos não tratados (`PlatformDispatcher.onError`)
   - Screenshots e hierarquia de view anexados aos eventos

3. **Logs Detalhados em Todo o Fluxo**
   - `lib/services/face_image_processor.dart`: Logs de cada etapa do processamento
   - `lib/widgets/camera_preview_widget.dart`: Logs de captura de câmera
   - `lib/screens/reconhecimento_facial_completo.dart`: Logs do fluxo completo
   - `lib/services/face_detection_service.dart`: Logs de detecção MLKit

---

## 📱 Passos para Build e Deploy no TestFlight

### 1. Limpar Build Anterior

```bash
cd /path/to/embarqueellusoficial

# Limpar cache Flutter
flutter clean

# Limpar pods do iOS
cd ios
rm -rf Pods Podfile.lock
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

### 2. Instalar Dependências

```bash
# Voltar para raiz do projeto
cd ..

# Instalar dependências Flutter
flutter pub get

# Instalar pods iOS (CRÍTICO: instala Sentry SDK nativo)
cd ios
pod install --repo-update

# Verificar se Sentry foi instalado
grep -r "Sentry" Podfile.lock
# Deve mostrar: Sentry (~> 8.x.x) e sentry_flutter
```

### 3. Build para TestFlight

**OPÇÃO A: Via Flutter (Recomendado)**

```bash
# Voltar para raiz
cd ..

# Build em modo Release (NECESSÁRIO para TestFlight)
flutter build ios --release

# Verificar se build foi bem-sucedido
ls -lh build/ios/iphoneos/Runner.app
```

**OPÇÃO B: Via Xcode (se preferir interface gráfica)**

```bash
# Abrir workspace no Xcode
cd ios
open Runner.xcworkspace
```

No Xcode:
1. Selecione **Product → Scheme → Runner**
2. Selecione **Any iOS Device** como target
3. Selecione **Product → Archive**
4. Aguarde build terminar (pode demorar 5-10 minutos)

### 4. Upload para TestFlight

No Xcode, após Archive concluir:

1. **Organizer** abrirá automaticamente
2. Selecione o archive recém-criado
3. Clique em **Distribute App**
4. Selecione **App Store Connect**
5. Selecione **Upload**
6. Configure:
   - ✅ Include bitcode: NO
   - ✅ Upload symbols: YES (CRÍTICO para Sentry)
   - ✅ Manage Version: Automatically
7. Clique em **Upload**
8. Aguarde upload (pode demorar 10-20 minutos)

### 5. Processar no App Store Connect

1. Acesse: https://appstoreconnect.apple.com
2. Vá em **My Apps → EmbarqueEllus → TestFlight**
3. Aguarde o build aparecer na seção **Builds** (pode demorar 5-10 minutos)
4. Quando aparecer, clique no build
5. Preencha informações de exportação (se pedido)
6. Aguarde "Processing" terminar (pode demorar até 30 minutos)

### 6. Distribuir para Testadores

Quando status mudar para "Ready to Test":

1. Em **TestFlight → Builds**, clique no build
2. Clique em **Groups** ou **Individual Testers**
3. Adicione testadores ou selecione grupo existente
4. Testadores receberão email para instalar via TestFlight

---

## 🔍 Como Verificar se Sentry Está Funcionando

### Método 1: Logs do Console (Xcode)

Quando rodar o app via Xcode ou TestFlight, procure nos logs:

```
✅ [iOS Native] Sentry inicializado nativamente no AppDelegate
✅ [iOS Native] DSN configurado: https://16c773f79c6fc2a3a4951733ce3570ed@...
🔵 [Sentry Flutter] Configurando Sentry...
✅ [Sentry Flutter] Evento de teste enviado!
```

Se ver essas mensagens = **Sentry está funcionando!**

### Método 2: Dashboard do Sentry

1. Acesse: https://sentry.io
2. Login com suas credenciais
3. Vá em **Issues** ou **Discover**
4. Procure por eventos recentes:
   - `"iOS AppDelegate: Sentry NATIVO inicializado com sucesso!"`
   - `"App Flutter iniciado com sucesso! Platform: iOS"`

Se esses eventos aparecerem = **Sentry está enviando dados!**

### Método 3: Forçar Erro de Teste

Se quiser testar captura de erro, adicione botão de teste temporário:

No arquivo que quiser testar, adicione:

```dart
ElevatedButton(
  onPressed: () async {
    // Forçar erro para testar Sentry
    throw Exception('TESTE SENTRY iOS - Erro forçado para teste');
  },
  child: Text('🧪 TESTAR SENTRY'),
)
```

Clique no botão e verifique se erro aparece no Sentry em 30 segundos.

---

## 🧪 Testando Detecção Facial

### Checklist de Teste:

1. **Abrir app no iPhone via TestFlight**
2. **Fazer login**
3. **Ir em "Reconhecimento Facial"**
4. **Verificar se existem alunos com facial cadastrada** (deve aparecer número > 0)
5. **Clicar em "RECONHECER POR FOTO"**
6. **Câmera deve abrir** (se não abrir, problema de permissão)
7. **Posicionar rosto na moldura e tirar foto**

### Logs Esperados no Sentry:

Se tudo funcionar, você verá no Sentry:

```
🎯 [Reconhecimento] Etapa 1/3: Abrindo câmera...
✅ [Reconhecimento] Imagem capturada: /path/to/image.jpg
🎯 [Reconhecimento] Etapa 2/3: Processando imagem...
🖼️ [FaceImageProcessor] Iniciando detecção de faces...
👁️ [FaceDetection] 1 rosto(s) detectado(s)
✅ [Reconhecimento] Imagem processada: 112x112
🎯 [Reconhecimento] Etapa 3/3: Comparando com banco...
✅ RECONHECIDO: Nome do Aluno
```

### Se NENHUM rosto for detectado:

Você verá no Sentry:

```
❌ [FaceImageProcessor] NENHUM ROSTO DETECTADO!
[⚠️ FaceDetection] Nenhuma face encontrada!
```

**Causa provável:**
- Iluminação ruim
- Rosto muito pequeno na foto
- Câmera tremida/desfocada
- MLKit não conseguiu detectar face

**Solução:**
- Melhorar iluminação
- Aproximar rosto da câmera
- Segurar iPhone firme
- Tentar novamente

---

## 🚨 Troubleshooting

### Problema: "No Sentry logs appearing"

**Solução:**

1. Verifique se `pod install` foi executado
2. Verifique se build foi em **Release** (não Debug)
3. Aguarde 2-3 minutos após abrir app (Sentry pode ter delay)
4. Verifique internet no iPhone (Sentry precisa internet para enviar)

### Problema: "Face detection not working"

**Solução:**

1. Verifique se `arcface.tflite` está em `assets/models/`
2. Verifique se existem alunos cadastrados com facial
3. Verifique permissões de câmera no iOS (Settings → App → Camera)
4. Verifique logs no Sentry para ver onde está falhando

### Problema: "App crashes on launch"

**Solução:**

1. Verifique logs do crash no Sentry
2. Se Sentry não capturar, verifique Xcode Organizer → Crashes
3. Pode ser modelo TFLite faltando ou arquivo .env inválido

---

## 📊 Monitoramento Contínuo

Após deploy no TestFlight:

1. **Monitore Sentry Dashboard** em tempo real
2. **Procure por erros** relacionados a:
   - `face_image_processor`
   - `face_detection_service`
   - `face_recognition_service`
   - `camera_preview_widget`

3. **Analise métricas:**
   - Quantas tentativas de reconhecimento
   - Quantas falhas de detecção
   - Quantos reconhecimentos bem-sucedidos

---

## 🎯 Próximos Passos (Após Confirmar Funcionamento)

1. **Desabilitar debug do Sentry** (para produção):
   - Edite `lib/main.dart`: `options.debug = kDebugMode;`
   - Edite `ios/Runner/AppDelegate.swift`: `options.debug = false`

2. **Ajustar threshold de reconhecimento** se necessário:
   - Edite `lib/services/face_recognition_service.dart`
   - Altere `DISTANCE_THRESHOLD = 1.1` conforme calibração

3. **Remover logs excessivos** (opcional):
   - Remover `debugPrint` que não sejam críticos
   - Manter apenas logs de erro

---

## ✅ Checklist Final

Antes de fazer deploy:

- [ ] `flutter clean` executado
- [ ] `flutter pub get` executado
- [ ] `cd ios && pod install` executado
- [ ] Sentry SDK instalado (verificar Podfile.lock)
- [ ] Build em modo **Release**
- [ ] Archive bem-sucedido
- [ ] Upload para App Store Connect bem-sucedido
- [ ] TestFlight mostrando build "Ready to Test"
- [ ] Testadores adicionados
- [ ] App testado em iPhone real via TestFlight
- [ ] Sentry recebendo eventos (verificar dashboard)
- [ ] Detecção facial testada e funcionando

---

## 📞 Suporte

Se ainda assim tiver problemas:

1. Verifique o dashboard do Sentry: https://sentry.io
2. Procure por erros específicos com tag `platform:iOS`
3. Analise stacktraces completos
4. Compartilhe logs específicos para análise

**DSN do Sentry:**
```
https://16c773f79c6fc2a3a4951733ce3570ed@o4504103203045376.ingest.us.sentry.io/4510326779740160
```

**Dashboard:**
https://o4504103203045376.ingest.us.sentry.io/issues/

---

## 🔐 Segurança

**IMPORTANTE:** Após confirmar funcionamento, lembre-se de:

1. Nunca commitar arquivos `.env` com credenciais reais
2. Usar secrets management para produção
3. Rotacionar tokens/keys periodicamente
4. Revisar permissões do Info.plist

---

**Data:** $(date +%Y-%m-%d)
**Versão do App:** 1.0.6
**iOS Deployment Target:** 15.5+
