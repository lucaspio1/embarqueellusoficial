# 🚀 GUIA RÁPIDO - BUILD iOS NO MAC (VNC)

## ⚡ INÍCIO RÁPIDO (3 minutos de setup)

### 1️⃣ Conectar no Mac via VNC
```
Conectar no Mac da Amazon usando VNC
```

### 2️⃣ Abrir Terminal no Mac
```
Spotlight (Cmd+Space) → "Terminal" → Enter
```

### 3️⃣ Navegar até o projeto
```bash
cd embarqueellusoficial
```
**(ajuste o caminho se necessário)**

### 4️⃣ Executar script automático
```bash
bash BUILD_NOW.sh
```

**O script vai:**
- ✅ Puxar código atualizado do Git
- ✅ Limpar cache Flutter
- ✅ Instalar dependências
- ✅ Reinstalar CocoaPods (com Sentry)
- ✅ Fazer build em Release
- ✅ Verificar se tudo funcionou

**Tempo estimado:** 15-20 minutos

---

## 📱 APÓS O SCRIPT TERMINAR

### 5️⃣ Abrir no Xcode
```bash
cd ios
open Runner.xcworkspace
```

**IMPORTANTE:** Abra `Runner.xcworkspace` (NÃO `Runner.xcodeproj`)

### 6️⃣ Archive no Xcode

1. **Selecione target:**
   - Barra superior: `Any iOS Device` (ou dispositivo conectado)

2. **Archive:**
   - Menu: `Product` → `Archive`
   - Aguardar 5-10 minutos

3. **Organizer abre automaticamente:**
   - Lista de archives aparece
   - Selecione o mais recente (topo da lista)

### 7️⃣ Upload para App Store Connect

1. **Distribute App:**
   - Botão azul: `Distribute App`

2. **Selecione método:**
   - ✅ `App Store Connect`
   - Clique `Next`

3. **Upload:**
   - ✅ `Upload`
   - Clique `Next`

4. **Configurações importantes:**
   ```
   ❌ Include bitcode for iOS content: NO
   ✅ Upload your app's symbols: YES (CRÍTICO!)
   ✅ Manage Version and Build Number: Automatically
   ```
   - Clique `Next`

5. **Revisar e Upload:**
   - Revisar informações
   - Clique `Upload`
   - Aguardar 10-20 minutos

### 8️⃣ Verificar no App Store Connect

1. **Acessar:** https://appstoreconnect.apple.com

2. **Navegar:**
   - `My Apps` → `EmbarqueEllus` → `TestFlight`

3. **Aguardar processamento:**
   - Build aparece em "Builds" (5-10 min)
   - Status muda de "Processing" para "Ready to Test" (até 30 min)

4. **Distribuir quando pronto:**
   - Clique no build
   - Adicione testadores ou grupo
   - Testadores recebem email

---

## 🔍 VERIFICAR SE SENTRY ESTÁ FUNCIONANDO

### No iPhone (após instalar via TestFlight):

1. **Abrir app**
2. **Aguardar 30-60 segundos**
3. **Verificar dashboard do Sentry:**

   🔗 https://sentry.io

**Eventos esperados:**
```
✅ "🍎 iOS AppDelegate: Sentry NATIVO inicializado com sucesso!"
✅ "✅ App Flutter iniciado com sucesso! Platform: iOS"
```

**Se aparecerem = SENTRY FUNCIONANDO! 🎉**

---

## 🧪 TESTAR DETECÇÃO FACIAL

1. **Login no app**
2. **Ir em "Reconhecimento Facial"**
3. **Verificar:** Número de "Alunos com Facial" > 0
4. **Clicar:** "RECONHECER POR FOTO"
5. **Tirar foto** de um rosto
6. **Aguardar 30-60 segundos**
7. **Verificar Sentry:**

**Logs esperados (SUCESSO):**
```
🎯 [Reconhecimento] Etapa 1/3: Abrindo câmera...
✅ [Reconhecimento] Imagem capturada
🎯 [Reconhecimento] Etapa 2/3: Processando imagem...
👁️ [FaceDetection] 1 rosto(s) detectado(s)
✅ RECONHECIDO: Nome do Aluno
```

**Logs esperados (FALHA - sem detecção):**
```
❌ [FaceImageProcessor] NENHUM ROSTO DETECTADO!
👁️ [FaceDetection] Nenhuma face encontrada!
```

**Agora vocês vão VER onde está falhando!** 🔍

---

## 🚨 TROUBLESHOOTING RÁPIDO

### Erro: "No provisioning profile"
```bash
# Use build sem codesign
flutter build ios --release --no-codesign
```

### Erro: "Pod install failed"
```bash
cd ios
rm -rf Pods Podfile.lock
pod cache clean --all
pod install --repo-update
```

### Erro: "Xcode not found"
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### Build demora muito
- ✅ Normal! Build iOS pode levar 10-20 minutos
- ✅ Archive pode levar 5-10 minutos adicionais
- ✅ Aguarde pacientemente

### Sentry não aparece
- ✅ Aguarde 2-3 minutos após abrir app
- ✅ Verifique internet no iPhone
- ✅ Verifique dashboard correto: https://sentry.io

---

## 📊 CHECKLIST COMPLETO

- [ ] ✅ Conectado no Mac via VNC
- [ ] ✅ Terminal aberto
- [ ] ✅ `bash BUILD_NOW.sh` executado
- [ ] ✅ Script terminou sem erros
- [ ] ✅ `open Runner.xcworkspace` executado
- [ ] ✅ Xcode abriu
- [ ] ✅ Target: "Any iOS Device"
- [ ] ✅ Product → Archive executado
- [ ] ✅ Archive bem-sucedido
- [ ] ✅ Organizer aberto
- [ ] ✅ Distribute App → Upload bem-sucedido
- [ ] ✅ App Store Connect mostra build
- [ ] ✅ Status mudou para "Ready to Test"
- [ ] ✅ Testadores adicionados
- [ ] ✅ App instalado via TestFlight
- [ ] ✅ Sentry recebendo eventos
- [ ] ✅ Detecção facial testada

---

## 📞 LINKS IMPORTANTES

**Sentry Dashboard:**
https://sentry.io

**App Store Connect:**
https://appstoreconnect.apple.com

**Documentação Completa:**
Ver arquivo: `IOS_BUILD_INSTRUCTIONS.md`

**Changelog:**
Ver arquivo: `CHANGELOG_iOS_Fix.md`

---

## ⚡ RESUMO - 3 COMANDOS

```bash
# 1. Navegar até projeto
cd embarqueellusoficial

# 2. Executar build automático
bash BUILD_NOW.sh

# 3. Abrir no Xcode
cd ios && open Runner.xcworkspace
```

**Depois:** Product → Archive → Upload para TestFlight

---

**Data:** 2025-11-09
**Branch:** `claude/fix-facial-detection-ios-011CUxfp7S6e3gpsK46ZLW8F`
**Versão:** 1.0.6

**PRONTO PARA DEPLOY! 🚀**
