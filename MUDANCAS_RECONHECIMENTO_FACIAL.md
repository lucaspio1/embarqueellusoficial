# 📋 Mudanças no Sistema de Reconhecimento Facial

## 🎯 Objetivo

Reestruturar o sistema de reconhecimento facial para separar corretamente:
- **Tabela de Embarque**: Lista de passageiros do passeio (temporária)
- **Tabela de Pessoas Facial**: Banco permanente de pessoas com facial cadastrada

## 🔄 Fluxo Atual (CORRETO)

### 1. Cadastro de Facial
1. **Origem**: Busca alunos da tabela `alunos` (que vem da lista de embarque via QR Code)
2. **Processamento**: Extrai embedding facial usando ArcFace
3. **Salvamento**:
   - Salva na tabela `embeddings` (para reconhecimento local)
   - **NOVO**: Salva na tabela `pessoas_facial` (banco permanente)
4. **Sincronização**: Envia para Google Sheets **aba "Pessoas"** (não para embarque)

### 2. Reconhecimento Facial
1. **Origem**: Busca pessoas da tabela `pessoas_facial` (sincronizada da aba "Pessoas")
2. **Comparação**: Compara face capturada com embeddings salvos
3. **Registro**: Salva log de acesso

## 📊 Estrutura de Tabelas

### ✅ Nova Tabela: `pessoas_facial`

```sql
CREATE TABLE pessoas_facial(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cpf TEXT UNIQUE,
  nome TEXT,
  email TEXT,
  telefone TEXT,
  turma TEXT,
  embedding TEXT,
  facial_status TEXT DEFAULT 'CADASTRADA',
  created_at TEXT,
  updated_at TEXT
)
```

**Propósito**: Banco permanente de pessoas com facial cadastrada, independente de passeios.

### 🔹 Tabela Existente: `alunos`

**Propósito**: Lista temporária de alunos/passageiros do passeio atual (sincronizada da lista de embarque).

### 🔹 Tabela Existente: `embeddings`

**Propósito**: Cache local de embeddings para reconhecimento facial rápido (mantida por compatibilidade).

## 🔧 Arquivos Modificados

### 1. `lib/database/database_helper.dart`
- ✅ Adicionada tabela `pessoas_facial`
- ✅ Adicionado método `upsertPessoaFacial()`
- ✅ Adicionado método `getAllPessoasFacial()`
- ✅ Adicionado método `getPessoaFacialByCpf()`
- ✅ Adicionado método `getTotalPessoasFacial()`
- ✅ Garantia que tabela é criada em `ensureFacialSchema()`

### 2. `lib/services/offline_sync_service.dart`
- ✅ Modificado `_sendPersonIndividually()` para usar action `addPessoa`
- ✅ Agora envia cadastros faciais para aba **"Pessoas"** do Google Sheets

### 3. `lib/services/alunos_sync_service.dart`
- ✅ Modificado `_processarRespostaPessoas()` para salvar em `pessoas_facial`
- ✅ Mantém compatibilidade salvando também em `embeddings`

### 4. `lib/screens/controle_alunos_screen.dart`
- ✅ Adicionado `import 'dart:convert'`
- ✅ Função `_cadastrarFacial()` agora salva em `pessoas_facial`
- ✅ Função `_cadastrarFacialAvancado()` agora salva em `pessoas_facial`

## 🚨 Como Resolver o Erro de Isolate

O erro `"Invalid argument(s): Illegal argument in isolate message: object is unsendable"` está acontecendo porque o dispositivo está rodando **código antigo em cache**.

### Solução:

```bash
# Execute o script de limpeza
chmod +x flutter_clean.sh
./flutter_clean.sh
```

Ou manualmente:

```bash
flutter clean
flutter pub get
flutter run
```

**Se o erro persistir:**
1. Desinstale o app do dispositivo manualmente
2. Execute `flutter run` novamente

## 📝 Requisitos no Google Apps Script

O backend (Google Apps Script) precisa implementar a action `addPessoa`:

```javascript
function doPost(e) {
  const params = JSON.parse(e.postData.contents);

  if (params.action === 'addPessoa') {
    // Adicionar pessoa na aba "Pessoas"
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Pessoas');
    sheet.appendRow([
      params.cpf,
      params.nome,
      params.email,
      params.telefone,
      params.embedding, // JSON string do array de doubles
      new Date(),
      'CADASTRADA'
    ]);

    return ContentService.createTextOutput(
      JSON.stringify({ success: true })
    ).setMimeType(ContentService.MimeType.JSON);
  }

  // ... outras actions
}
```

## ✅ Benefícios

1. **Separação de Dados**: Embarque e pessoas faciais são independentes
2. **Persistência**: Pessoas faciais não são perdidas ao limpar dados de passeio
3. **Escalabilidade**: Fácil adicionar pessoas sem depender de listas de embarque
4. **Rastreabilidade**: Aba "Pessoas" no Google Sheets contém histórico completo

## 🔍 Verificação

Para verificar se está funcionando:

1. Cadastre uma facial de um aluno
2. Verifique os logs:
   ```
   ✅ [CadastroFacial] Salvo na tabela pessoas_facial
   ✅ [CadastroFacial] Embedding enfileirado para sincronização com aba Pessoas
   ```
3. Verifique no Google Sheets se apareceu na aba "Pessoas"
4. Sincronize pessoas em outro dispositivo e verifique se reconhece

## 📞 Dúvidas?

Se tiver problemas, verifique:
- O Google Apps Script tem a action `addPessoa` implementada?
- O erro de isolate foi resolvido com `flutter clean`?
- A tabela `pessoas_facial` foi criada? (Verifique os logs ao iniciar o app)
