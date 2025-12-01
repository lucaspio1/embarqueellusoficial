# ⚠️ ATENÇÃO: google-services.json NECESSÁRIO

## 🚨 Erro Atual
```
PlatformException: Failed to load FirebaseOptions from resource.
Check that you have defined values.xml correctly.
```

## 📋 O que está faltando?

O arquivo `google-services.json` é **obrigatório** para o Firebase funcionar no Android.

Este arquivo contém as configurações de conexão do seu app com o Firebase (API keys, IDs do projeto, etc.)

---

## ✅ Como Resolver

### Passo 1: Acesse o Firebase Console

1. Abra: https://console.firebase.google.com/
2. Selecione seu projeto (ou crie um novo)

### Passo 2: Adicione o App Android (se ainda não tiver)

1. No Firebase Console, clique no ícone ⚙️ (Configurações do projeto)
2. Na aba "Geral", role até "Seus apps"
3. Clique no ícone do Android (ou "Adicionar app" → Android)
4. Preencha:
   - **Nome do pacote**: `br.com.embarqueellus`
   - **Apelido**: Embarque Ellus Android
   - **Certificado SHA-1**: (opcional por enquanto)
5. Clique em "Registrar app"

### Passo 3: Baixe o arquivo google-services.json

1. Após registrar o app, o Firebase oferecerá o download do `google-services.json`
2. **Ou**, se já tiver o app registrado:
   - Vá em ⚙️ → Configurações do projeto → Geral
   - Role até "Seus apps" → Android app
   - Clique em "google-services.json" para baixar

### Passo 4: Coloque o arquivo na pasta correta

**COLOQUE O ARQUIVO AQUI:**
```
android/app/google-services.json
```

**Estrutura correta:**
```
embarqueellusoficial/
├── android/
│   ├── app/
│   │   ├── google-services.json  ← AQUI!
│   │   └── build.gradle.kts
│   └── build.gradle.kts
├── lib/
└── ...
```

---

## 🔍 Verificação

Após colocar o arquivo, verifique se está no local correto:

```bash
ls -la android/app/google-services.json
```

Deve mostrar o arquivo (não pode ser uma pasta vazia!)

---

## 🚀 Reconstrua o App

Depois de adicionar o arquivo:

```bash
flutter clean
flutter pub get
flutter run
```

---

## 📚 Documentação Completa

Para instruções detalhadas sobre configuração do Firebase, veja:
- `FIREBASE_SETUP.md` (na raiz do projeto)
- `FIRESTORE_STRUCTURE.md` (estrutura do banco)

---

## ⚠️ IMPORTANTE

- **NUNCA commite o `google-services.json` no Git!**
- Este arquivo contém chaves de API do seu projeto Firebase
- Já está configurado no `.gitignore`
- Cada desenvolvedor deve baixar seu próprio arquivo do Firebase Console
