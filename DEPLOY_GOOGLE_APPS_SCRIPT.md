# Como Fazer Deploy do Google Apps Script Atualizado

## Problema Identificado

O cadastro facial não está sendo salvo na aba PESSOAS porque o Google Apps Script rodando no servidor está **desatualizado** e não possui a função `addPessoa`.

**Logs do problema:**
```
📤 [OfflineSync] POST -> action=addPessoa
📥 [OfflineSync] Resp 302 (redirect)
⚠️ [OfflineSync] POST não permitido, tentando GET...
📡 [OfflineSync] Status: 200
✅ [OfflineSync] Sincronização concluída (mas nada foi salvo!)
```

## Solução

Você precisa fazer o **deploy da versão atualizada** do script que está em `lib/script.gs` ou `google_apps_script_CORRIGIDO.js`.

## Passo a Passo para Deploy

### 1. Acessar o Google Apps Script

1. Abra o Google Sheets da planilha (ID: `1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U`)
2. No menu, clique em **Extensões** > **Apps Script**

### 2. Substituir o Código

1. No editor do Apps Script, **selecione TODO o código existente** e **delete**
2. Copie o conteúdo do arquivo `lib/script.gs` (ou `google_apps_script_CORRIGIDO.js`)
3. Cole no editor do Apps Script
4. Salve (Ctrl+S ou ícone de disquete)

### 3. Fazer Deploy

1. Clique no botão **Implantar** (Deploy) no canto superior direito
2. Selecione **Nova implantação** (New deployment)
3. Clique no ícone de engrenagem ⚙️ ao lado de "Selecione o tipo"
4. Escolha **Aplicativo da Web** (Web app)
5. Configure:
   - **Execute as**: Me (seu email)
   - **Who has access**: Anyone (Qualquer pessoa)
6. Clique em **Deploy** (Implantar)
7. **Autorize o script** quando solicitado
8. **IMPORTANTE**: Copie a **URL da Web App** que aparecerá

### 4. Atualizar a URL no Flutter (se necessário)

Se a URL mudou, você precisará atualizar o arquivo `lib/services/offline_sync_service.dart`:

```dart
// Linha 12
final String _sheetsWebhook = 'COLE_A_NOVA_URL_AQUI';
```

### 5. Testar

Após o deploy:

1. Abra o app
2. Tente fazer um novo cadastro facial
3. Verifique na aba **PESSOAS** do Google Sheets se o registro foi criado

## Verificando se Funcionou

**Logs de sucesso:**
```
📤 [OfflineSync] POST -> action=addPessoa
📥 [OfflineSync] Resp 302 (redirect)
📡 [OfflineSync] Status: 200
📥 [addPessoa] Cadastrando pessoa: NOME_DA_PESSOA CPF: XXX
✅ [addPessoa] Nova pessoa cadastrada: NOME_DA_PESSOA
```

**No Google Sheets:**
- Aba PESSOAS deve ter uma nova linha com:
  - CPF
  - Nome
  - Email
  - Telefone
  - EMBEDDING (array JSON com 512 números)
  - Data de cadastro

## Diferença Entre os Scripts

### Script ANTIGO (sem addPessoa):
```javascript
switch(action) {
  case 'getAllStudents':
    return getAllStudents();
  case 'getAllPeople':
    return getAllPeople();
  // ... NÃO TEM addPessoa!
}
```

### Script NOVO (com addPessoa):
```javascript
switch(action) {
  case 'getAllStudents':
    return getAllStudents();
  case 'getAllPeople':
    return getAllPeople();
  case 'addPessoa':
    return addPessoa(data);  // ← FUNÇÃO CRÍTICA!
  case 'addMovementLog':
    return addMovementLog(data);
  // ... outras funções
}
```

## Estrutura da Aba PESSOAS

Cabeçalho esperado:
```
ID | CPF | NOME | EMAIL | TELEFONE | EMBEDDING | DATA_CADASTRO
```

A função `addPessoa`:
- Cria a aba PESSOAS se não existir
- Verifica se o CPF já existe (atualiza se sim)
- Adiciona nova linha se for novo cadastro
- Salva o embedding como JSON string

## Dúvidas?

Se após o deploy o problema persistir, verifique:
1. A URL do webhook está correta no app?
2. O script foi autorizado corretamente?
3. A aba PESSOAS foi criada no Sheets?
4. Os logs do Apps Script (View > Executions) mostram erros?
