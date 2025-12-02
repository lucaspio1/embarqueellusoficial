# 🔥 Instruções para Configurar Firebase no iOS/Android

## 🚨 Problema Identificado

O erro que você está vendo no iPhone:

```
[core/not-initialized] Firebase has not been correctly initialized.
```

Acontece porque o app não tem as configurações do Firebase necessárias para iOS e Android.

---

## ✅ Solução Aplicada

Foram feitas as seguintes alterações no código:

1. ✅ Criado arquivo `lib/firebase_options.dart` (com template)
2. ✅ Atualizado `lib/main.dart` para usar as opções do Firebase
3. ⚠️ **VOCÊ PRECISA**: Preencher as configurações do seu projeto Firebase

---

## 📋 Passo a Passo - Configurar Firebase

### Opção 1: Usar FlutterFire CLI (Recomendado - Mais Fácil)

Se você tiver o Flutter instalado localmente, pode gerar o arquivo automaticamente:

```bash
# 1. Instalar FlutterFire CLI
dart pub global activate flutterfire_cli

# 2. Fazer login no Firebase (abrirá o navegador)
firebase login

# 3. Executar configuração automática
flutterfire configure
```

O comando `flutterfire configure` irá:
- Listar seus projetos Firebase
- Permitir selecionar ou criar um projeto
- Gerar automaticamente `lib/firebase_options.dart` com TODAS as configurações
- Configurar iOS e Android automaticamente

**Depois de executar, substitua o arquivo `lib/firebase_options.dart` pelo gerado.**

---

### Opção 2: Configuração Manual (Se não puder usar FlutterFire CLI)

#### Passo 1: Acessar Firebase Console

1. Acesse: https://console.firebase.google.com/
2. Faça login com sua conta Google
3. Selecione seu projeto (ou crie um novo se ainda não tiver)

#### Passo 2: Obter Configurações para Android

1. No Firebase Console, clique no ícone ⚙️ (Configurações do projeto)
2. Vá para a aba **"Geral"**
3. Role até a seção **"Seus apps"**
4. Se ainda não tiver um app Android:
   - Clique em **"Adicionar app"** → Escolha **Android**
   - **Nome do pacote**: `br.com.embarqueellus`
   - **Apelido do app**: Embarque Ellus
   - Clique em **"Registrar app"**
5. Se já tiver o app Android, clique nele para ver os detalhes

Copie as seguintes informações:
- **API Key** (apiKey)
- **App ID** (appId) - formato: `1:123456789:android:abcdef...`
- **Messaging Sender ID** (messagingSenderId)
- **Project ID** (projectId)
- **Storage Bucket** (storageBucket)

#### Passo 3: Obter Configurações para iOS

1. No Firebase Console, ainda em **Configurações do projeto** > **Geral**
2. Role até a seção **"Seus apps"**
3. Se ainda não tiver um app iOS:
   - Clique em **"Adicionar app"** → Escolha **iOS+**
   - **Bundle ID**: `br.com.embarqueellus`
   - **Apelido do app**: Embarque Ellus iOS
   - Clique em **"Registrar app"**
4. Se já tiver o app iOS, clique nele para ver os detalhes

Copie as seguintes informações:
- **API Key** (apiKey)
- **App ID** (appId) - formato: `1:123456789:ios:abcdef...`
- **Messaging Sender ID** (messagingSenderId)
- **Project ID** (projectId)
- **Storage Bucket** (storageBucket)
- **iOS Bundle ID** (iosBundleId) - deve ser `br.com.embarqueellus`

#### Passo 4: Editar o arquivo `lib/firebase_options.dart`

Abra o arquivo `lib/firebase_options.dart` e substitua os valores placeholder:

**Para Android (linha ~53):**
```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIzaSyC...',  // ← Cole aqui o API Key do Android
  appId: '1:123456789:android:abcdef...',  // ← Cole aqui o App ID do Android
  messagingSenderId: '123456789',  // ← Cole aqui o Messaging Sender ID
  projectId: 'embarque-ellus',  // ← Cole aqui o Project ID
  storageBucket: 'embarque-ellus.appspot.com',  // ← Cole aqui o Storage Bucket
);
```

**Para iOS (linha ~72):**
```dart
static const FirebaseOptions ios = FirebaseOptions(
  apiKey: 'AIzaSyD...',  // ← Cole aqui o API Key do iOS
  appId: '1:123456789:ios:abcdef...',  // ← Cole aqui o App ID do iOS
  messagingSenderId: '123456789',  // ← Cole aqui o Messaging Sender ID
  projectId: 'embarque-ellus',  // ← Cole aqui o Project ID
  storageBucket: 'embarque-ellus.appspot.com',  // ← Cole aqui o Storage Bucket
  iosBundleId: 'br.com.embarqueellus',  // ← Confirme que está correto
);
```

#### Passo 5: Salvar e Testar

Depois de preencher todas as configurações:

```bash
# 1. Limpar build anterior
flutter clean

# 2. Obter dependências
flutter pub get

# 3. Rodar no iPhone
flutter run
```

---

## 🔍 Verificação

Depois de configurar, o app deve:
- ✅ Iniciar sem erros no iPhone
- ✅ Mostrar no console: `✅ Firebase inicializado com sucesso`
- ✅ Conectar ao Firestore sem problemas

---

## ⚠️ Importante

### Não Commite Configurações Sensíveis

O arquivo `lib/firebase_options.dart` contém chaves de API do seu projeto.

**Para produção, considere:**
- Adicionar `lib/firebase_options.dart` ao `.gitignore`
- Usar variáveis de ambiente
- Usar configurações diferentes para debug/release

Mas para desenvolvimento local, está ok usar o arquivo diretamente.

---

## 📚 Documentação

- [Firebase Console](https://console.firebase.google.com/)
- [FlutterFire Documentation](https://firebase.flutter.dev/)
- [FlutterFire CLI](https://firebase.flutter.dev/docs/cli)

---

## 🆘 Problemas Comuns

### Erro: "API key not found"
- Verifique se copiou o API Key correto do Firebase Console
- Certifique-se de que não há espaços extras

### Erro: "App ID not found"
- Verifique se o App ID tem o formato correto: `1:123456789:ios:abcdef...`
- Confirme que está usando o App ID certo (iOS para iOS, Android para Android)

### Erro: "Project not found"
- Verifique se o Project ID está correto
- Confirme que o projeto existe no Firebase Console

### Erro persiste no iPhone
- Verifique se o Bundle ID no Xcode é `br.com.embarqueellus`
- Confirme que o App iOS está registrado no Firebase Console com o mesmo Bundle ID
- Tente `flutter clean && flutter pub get` e rode novamente

---

## 🎯 Resumo

**O que foi feito:**
- ✅ Criado arquivo de configuração do Firebase
- ✅ Atualizado código para usar as configurações

**O que você precisa fazer:**
1. Seguir Opção 1 (FlutterFire CLI) OU Opção 2 (Manual)
2. Preencher as configurações no arquivo `firebase_options.dart`
3. Testar no iPhone

Depois de configurar, o erro deve desaparecer! 🎉
