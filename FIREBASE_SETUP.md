# Configuração do Firebase - Sistema Embarque Ellus

Este guia detalha como configurar o Firebase para substituir o Google Sheets no sistema.

## 📋 Pré-requisitos

- Conta Google/Firebase
- Acesso ao Firebase Console: https://console.firebase.google.com/
- Flutter SDK instalado
- Acesso ao projeto no GitHub

---

## 🚀 Passo 1: Criar Projeto no Firebase

1. Acesse o [Firebase Console](https://console.firebase.google.com/)
2. Clique em "Adicionar projeto" (ou "Add project")
3. Digite o nome do projeto: `embarqueellus` (ou o nome que preferir)
4. Desabilite o Google Analytics (opcional)
5. Clique em "Criar projeto"
6. Aguarde a criação do projeto

---

## 📱 Passo 2: Adicionar Apps ao Projeto

### 2.1. Adicionar App Android

1. No Firebase Console, clique no ícone do Android
2. Preencha os campos:
   - **Nome do pacote Android**: `com.ellus.embarqueellus` (verifique em `android/app/build.gradle.kts`)
   - **Apelido do app**: `Embarque Ellus Android`
   - **Certificado de assinatura SHA-1**: (opcional por enquanto)
3. Clique em "Registrar app"
4. **Download do arquivo de configuração**:
   - Baixe o arquivo `google-services.json`
   - Coloque em: `/android/app/google-services.json`
5. Clique em "Próximo" até concluir

### 2.2. Adicionar App iOS

1. No Firebase Console, clique no ícone do iOS
2. Preencha os campos:
   - **ID do pacote iOS**: `com.ellus.embarqueellus` (verifique em `ios/Runner.xcodeproj`)
   - **Apelido do app**: `Embarque Ellus iOS`
   - **ID da App Store**: (deixe em branco)
3. Clique em "Registrar app"
4. **Download do arquivo de configuração**:
   - Baixe o arquivo `GoogleService-Info.plist`
   - Abra o Xcode
   - Arraste o arquivo para `ios/Runner/` no navegador do projeto
   - **IMPORTANTE**: Marque "Copy items if needed"
5. Clique em "Próximo" até concluir

---

## 🔥 Passo 3: Configurar Firestore Database

1. No Firebase Console, vá em **Firestore Database** (menu lateral)
2. Clique em "Criar banco de dados"
3. Escolha o modo:
   - **Teste** (para desenvolvimento): Regras permissivas por 30 dias
   - **Produção**: Regras restritivas (recomendado para produção)
4. Escolha a localização:
   - Recomendado: `southamerica-east1` (São Paulo, Brasil)
5. Clique em "Ativar"

### 3.1. Configurar Regras de Segurança

1. Vá em **Firestore Database** > **Regras**
2. Cole as seguintes regras (modo desenvolvimento):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Permitir leitura e escrita para todos (MODO DESENVOLVIMENTO)
    // ⚠️ IMPORTANTE: Mudar para regras restritas em produção!
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

3. Clique em "Publicar"

**⚠️ ATENÇÃO**: Em produção, use regras mais restritivas (veja `FIRESTORE_STRUCTURE.md`)

---

## 🗂️ Passo 4: Criar Coleções no Firestore

### Opção A: Criação Manual (via Console)

1. No Firestore Database, clique em "Iniciar coleção"
2. Crie as seguintes coleções (uma por vez):

**Coleções necessárias**:
- `usuarios`
- `alunos`
- `pessoas`
- `logs`
- `quartos`
- `embarques`
- `eventos`

Para cada coleção:
- Digite o nome da coleção
- Clique em "Próxima"
- Adicione um documento de exemplo (pode deletar depois)
- Clique em "Salvar"

### Opção B: Importação Automática (Recomendado)

Execute o script de migração dos dados do Google Sheets (veja Passo 6).

---

## 📊 Passo 5: Criar Índices Compostos

1. No Firestore, vá em **Índices** > **Compostos**
2. Crie os seguintes índices:

### alunos
- `inicio_viagem` (Ascending) + `fim_viagem` (Ascending)

### pessoas
- `inicio_viagem` (Ascending) + `fim_viagem` (Ascending)
- `colegio` (Ascending) + `movimentacao` (Ascending)

### logs
- `inicio_viagem` (Ascending) + `fim_viagem` (Ascending)
- `cpf` (Ascending) + `timestamp` (Descending)

### quartos
- `inicio_viagem` (Ascending) + `fim_viagem` (Ascending)

### embarques
- `colegio` (Ascending) + `idPasseio` (Ascending) + `onibus` (Ascending)

**Dica**: Você pode esperar que o Firebase sugira automaticamente os índices quando executar queries que precisam deles.

---

## 🔄 Passo 6: Migrar Dados do Google Sheets

### 6.1. Exportar Dados do Google Sheets

1. Abra a planilha do Google Sheets atual
2. Para cada aba (LOGIN, ALUNOS, PESSOAS, LOGS, HOMELIST, EMBARQUES):
   - Arquivo > Download > CSV
   - Salve com o nome: `{aba}.csv` (ex: `ALUNOS.csv`)

### 6.2. Importar para Firestore

**Opção 1: Via Firebase Console (UI)**

1. No Firestore, vá em **Dados** > **Importar/Exportar**
2. Clique em "Importar dados"
3. Selecione o arquivo CSV
4. Mapeie os campos corretamente
5. Clique em "Importar"

**Opção 2: Via Script (Recomendado)**

Crie um script Node.js para importar os dados:

```javascript
// import-to-firestore.js
const admin = require('firebase-admin');
const csv = require('csv-parser');
const fs = require('fs');

// Inicializar Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

// Importar usuários (LOGIN.csv)
async function importUsuarios() {
  const usuarios = [];
  fs.createReadStream('LOGIN.csv')
    .pipe(csv())
    .on('data', (row) => {
      usuarios.push({
        user_id: row.id || admin.firestore().collection('usuarios').doc().id,
        nome: row.nome,
        cpf: row.cpf,
        senha_hash: row.senha, // Já deve estar em hash SHA-256
        perfil: row.perfil || 'USUARIO',
        ativo: row.ativo === 'TRUE' || row.ativo === '1',
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
    })
    .on('end', async () => {
      const batch = db.batch();
      usuarios.forEach((user) => {
        const ref = db.collection('usuarios').doc(user.user_id);
        batch.set(ref, user);
      });
      await batch.commit();
      console.log(`✅ ${usuarios.length} usuários importados`);
    });
}

// Importar alunos (ALUNOS.csv)
async function importAlunos() {
  const alunos = [];
  fs.createReadStream('ALUNOS.csv')
    .pipe(csv())
    .on('data', (row) => {
      alunos.push({
        cpf: row.cpf,
        nome: row.nome,
        colegio: row.colegio,
        turma: row.turma,
        email: row.email || '',
        telefone: row.telefone || '',
        facial_status: row.facial_status || 'NAO',
        tem_qr: row.tem_qr === 'TRUE' || row.tem_qr === '1',
        inicio_viagem: row.inicio_viagem || '',
        fim_viagem: row.fim_viagem || '',
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
    })
    .on('end', async () => {
      const batch = db.batch();
      alunos.forEach((aluno) => {
        const ref = db.collection('alunos').doc(aluno.cpf);
        batch.set(ref, aluno);
      });
      await batch.commit();
      console.log(`✅ ${alunos.length} alunos importados`);
    });
}

// Executar importações
(async () => {
  await importUsuarios();
  await importAlunos();
  // Adicione outras importações conforme necessário
  process.exit(0);
})();
```

**Como executar**:
```bash
npm install firebase-admin csv-parser
node import-to-firestore.js
```

---

## ⚙️ Passo 7: Atualizar Arquivo .env

Remova as variáveis antigas do Google Sheets e mantenha apenas as necessárias:

```env
# Sentry (manter)
SENTRY_DSN=https://16c773f79c6fc2a3a4951733ce3570ed@o4504103203045376.ingest.us.sentry.io/4510326779740160

# Firebase (não precisa de variáveis de ambiente)
# As configurações vêm dos arquivos google-services.json e GoogleService-Info.plist

# REMOVER estas linhas (não usadas mais):
# GOOGLE_APPS_SCRIPT_URL=...
# EMBARQUE_SCRIPT_URL=...
# SPREADSHEET_ID=...
```

---

## 🔧 Passo 8: Instalar Dependências do Flutter

Execute os seguintes comandos:

```bash
# Limpar cache
flutter clean

# Instalar dependências
flutter pub get

# Para Android, adicionar plugin do Firebase
cd android
./gradlew clean
cd ..

# Para iOS, instalar pods
cd ios
pod install
cd ..
```

---

## 🏗️ Passo 9: Configurar Gradle (Android)

### 9.1. Atualizar `android/build.gradle.kts`

Adicione o plugin do Google Services:

```kotlin
buildscript {
    dependencies {
        // Firebase
        classpath("com.google.gms:google-services:4.4.2")
    }
}
```

### 9.2. Atualizar `android/app/build.gradle.kts`

No final do arquivo, adicione:

```kotlin
apply(plugin = "com.google.gms.google-services")
```

---

## 📱 Passo 10: Testar a Aplicação

### 10.1. Teste em Desenvolvimento

```bash
# Android
flutter run

# iOS
flutter run -d ios
```

### 10.2. Verificar Logs

Procure por estas mensagens no console:

```
🔥 Inicializando Firebase...
✅ Firebase inicializado com sucesso
🔥 Inicializando FirebaseService...
✅ FirebaseService inicializado com sucesso
✅ Listeners em tempo real iniciados
```

### 10.3. Testar Sincronização

1. Faça login no app
2. Verifique se os dados aparecem
3. Faça uma alteração (ex: registrar movimento)
4. Verifique no Firebase Console se o dado foi salvo

---

## 🐛 Troubleshooting

### Erro: "No Firebase App '[DEFAULT]' has been created"

**Solução**: Verifique se os arquivos de configuração estão nos lugares corretos:
- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

### Erro: "PERMISSION_DENIED" no Firestore

**Solução**: Verifique as regras de segurança no Firebase Console. Para desenvolvimento, use:
```javascript
allow read, write: if true;
```

### App não compila (Android)

**Solução**:
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

### App não compila (iOS)

**Solução**:
```bash
cd ios
pod deintegrate
pod install
cd ..
flutter clean
flutter pub get
flutter run -d ios
```

### Dados não aparecem no app

**Solução**:
1. Verifique se as coleções existem no Firestore
2. Verifique se há dados nas coleções
3. Verifique os logs do app
4. Verifique as regras de segurança

---

## 📚 Recursos Adicionais

- **Documentação Firebase**: https://firebase.google.com/docs
- **Firestore para Flutter**: https://firebase.flutter.dev/docs/firestore/overview
- **Firebase Console**: https://console.firebase.google.com/
- **Estrutura do Firestore**: Veja `FIRESTORE_STRUCTURE.md`

---

## ✅ Checklist de Configuração

- [ ] Projeto criado no Firebase Console
- [ ] App Android adicionado
- [ ] App iOS adicionado
- [ ] `google-services.json` no lugar correto
- [ ] `GoogleService-Info.plist` no lugar correto
- [ ] Firestore Database ativado
- [ ] Regras de segurança configuradas
- [ ] Coleções criadas
- [ ] Índices compostos criados
- [ ] Dados migrados do Google Sheets
- [ ] Arquivo `.env` atualizado
- [ ] Dependências instaladas (`flutter pub get`)
- [ ] Gradle configurado (Android)
- [ ] App testado e funcionando
- [ ] Sincronização em tempo real funcionando

---

## 🎉 Próximos Passos

Após a configuração completa:

1. **Desativar Google Sheets**: Pare de usar as planilhas antigas
2. **Monitorar uso**: Acompanhe o uso do Firebase no Console
3. **Configurar backup**: Configure backups automáticos
4. **Otimizar regras**: Em produção, use regras de segurança restritivas
5. **Implementar autenticação**: Use Firebase Authentication (opcional)

---

## 🔒 Segurança em Produção

**IMPORTANTE**: Antes de ir para produção, atualize as regras de segurança:

1. Vá em **Firestore Database** > **Regras**
2. Substitua as regras por:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /usuarios/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    match /alunos/{cpf} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }

    match /pessoas/{cpf} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }

    match /logs/{logId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if false;
    }

    match /quartos/{quartoId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }

    match /embarques/{embarqueId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }

    match /eventos/{eventoId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null;
    }
  }
}
```

3. Clique em "Publicar"

---

**Documentação mantida por**: Equipe Embarque Ellus
**Última atualização**: 30/11/2025
