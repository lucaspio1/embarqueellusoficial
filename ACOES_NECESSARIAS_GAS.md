# 🔧 AÇÕES NECESSÁRIAS NO GOOGLE APPS SCRIPT

Este documento lista todas as actions que o Google Apps Script precisa implementar para o app funcionar corretamente.

---

## 📋 ACTIONS IMPLEMENTADAS (Existentes)

### 1. GET - Buscar Lista de Embarque
```
URL: ?colegio=X&id_passeio=Y&onibus=Z
Método: GET
```

**Código:**
```javascript
function doGet(e) {
  const colegio = e.parameter.colegio;
  const id_passeio = e.parameter.id_passeio;
  const onibus = e.parameter.onibus;

  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Embarque');
  const data = sheet.getDataRange().getValues();

  // Filtrar por colégio, passeio e ônibus
  const passageiros = [];
  // ... lógica de filtro

  return ContentService.createTextOutput(
    JSON.stringify({ passageiros: passageiros })
  ).setMimeType(ContentService.MimeType.JSON);
}
```

---

### 2. POST - getAllStudents (Buscar Alunos)
```
Action: getAllStudents
Método: POST
Body: { "action": "getAllStudents" }
```

**Aba destino:** Alunos

**Retorno esperado:**
```json
{
  "success": true,
  "data": [
    {
      "cpf": "12345678900",
      "nome": "João Silva",
      "email": "joao@email.com",
      "telefone": "11999999999",
      "turma": "3A",
      "facial_status": "NAO",
      "tem_qr": "SIM"
    }
  ]
}
```

---

### 3. POST - getAllPeople (Buscar Pessoas com Facial)
```
Action: getAllPeople
Método: POST
Body: { "action": "getAllPeople" }
```

**Aba destino:** Pessoas

**Retorno esperado:**
```json
{
  "success": true,
  "data": [
    {
      "cpf": "12345678900",
      "nome": "João Silva",
      "email": "joao@email.com",
      "telefone": "11999999999",
      "turma": "3A",
      "embedding": "[0.123, -0.456, 0.789, ...]"
    }
  ]
}
```

**IMPORTANTE:** O embedding deve ser uma string JSON contendo um array de números (512 dimensões).

---

### 4. POST - getAllUsers (Buscar Usuários)
```
Action: getAllUsers
Método: POST
Body: { "action": "getAllUsers" }
```

**Aba destino:** Usuários

**Retorno esperado:**
```json
{
  "success": true,
  "data": [
    {
      "user_id": "001",
      "cpf": "12345678900",
      "nome": "Maria Admin",
      "senha_hash": "abc123...",
      "perfil": "ADMIN",
      "ativo": true
    }
  ]
}
```

---

### 5. POST - login (Autenticar Usuário)
```
Action: login
Método: POST
Body: {
  "action": "login",
  "cpf": "12345678900",
  "senha": "senha123"
}
```

**Aba destino:** Usuários

**Código:**
```javascript
if (params.action === 'login') {
  const cpf = params.cpf;
  const senha = params.senha;

  // Hash da senha (usar mesma lógica do app - SHA256)
  const senhaHash = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    senha
  ).map(byte => ('0' + (byte & 0xFF).toString(16)).slice(-2)).join('');

  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Usuários');
  const data = sheet.getDataRange().getValues();

  for (let i = 1; i < data.length; i++) {
    if (data[i][1] === cpf && data[i][3] === senhaHash && data[i][5] === 1) {
      return ContentService.createTextOutput(
        JSON.stringify({
          success: true,
          user: {
            user_id: data[i][0],
            cpf: data[i][1],
            nome: data[i][2],
            perfil: data[i][4]
          }
        })
      ).setMimeType(ContentService.MimeType.JSON);
    }
  }

  return ContentService.createTextOutput(
    JSON.stringify({ success: false, message: 'Credenciais inválidas' })
  ).setMimeType(ContentService.MimeType.JSON);
}
```

---

### 6. POST - addMovementLog (Salvar Logs)
```
Action: addMovementLog
Método: POST
Body: {
  "action": "addMovementLog",
  "people": [
    {
      "cpf": "12345678900",
      "personName": "João Silva",
      "timestamp": "2025-10-30T20:00:00.000Z",
      "confidence": 0.85,
      "tipo": "EMBARQUE"
    }
  ]
}
```

**Aba destino:** Embarque (ou uma aba de Logs)

**Código:**
```javascript
if (params.action === 'addMovementLog') {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Logs');
  const people = params.people || [];

  for (const person of people) {
    sheet.appendRow([
      person.cpf,
      person.personName,
      person.timestamp,
      person.confidence,
      person.tipo,
      new Date()
    ]);
  }

  return ContentService.createTextOutput(
    JSON.stringify({
      success: true,
      data: { total: people.length }
    })
  ).setMimeType(ContentService.MimeType.JSON);
}
```

---

## 🚨 ACTIONS FALTANDO (CRÍTICO)

### 7. POST - addPessoa (Cadastrar Pessoa com Facial) ⚠️ **IMPLEMENTAR AGORA**

```
Action: addPessoa
Método: POST
Body: {
  "action": "addPessoa",
  "cpf": "12345678900",
  "nome": "João Silva",
  "email": "joao@email.com",
  "telefone": "11999999999",
  "embedding": "[0.123, -0.456, 0.789, ...]",
  "personId": "12345678900"
}
```

**Aba destino:** Pessoas

**Estrutura esperada da aba "Pessoas":**

| Coluna A | Coluna B | Coluna C | Coluna D | Coluna E | Coluna F | Coluna G |
|----------|----------|----------|----------|----------|----------|----------|
| CPF | Nome | Email | Telefone | Embedding | Data Cadastro | Status |

**Código para implementar:**

```javascript
function doPost(e) {
  const params = JSON.parse(e.postData.contents);

  // ... outras actions ...

  // 🆕 NOVA ACTION - addPessoa
  if (params.action === 'addPessoa') {
    try {
      const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Pessoas');

      if (!sheet) {
        return ContentService.createTextOutput(
          JSON.stringify({
            success: false,
            message: 'Aba "Pessoas" não encontrada'
          })
        ).setMimeType(ContentService.MimeType.JSON);
      }

      // Verificar se já existe
      const data = sheet.getDataRange().getValues();
      let linhaExistente = -1;

      for (let i = 1; i < data.length; i++) {
        if (data[i][0] === params.cpf) {
          linhaExistente = i + 1; // +1 porque sheet é 1-indexed
          break;
        }
      }

      const novaLinha = [
        params.cpf,
        params.nome,
        params.email || '',
        params.telefone || '',
        params.embedding, // String JSON do array
        new Date(),
        'CADASTRADA'
      ];

      if (linhaExistente > 0) {
        // Atualizar linha existente
        sheet.getRange(linhaExistente, 1, 1, novaLinha.length).setValues([novaLinha]);
      } else {
        // Adicionar nova linha
        sheet.appendRow(novaLinha);
      }

      return ContentService.createTextOutput(
        JSON.stringify({
          success: true,
          message: 'Pessoa cadastrada com sucesso'
        })
      ).setMimeType(ContentService.MimeType.JSON);

    } catch (error) {
      return ContentService.createTextOutput(
        JSON.stringify({
          success: false,
          message: 'Erro ao cadastrar pessoa: ' + error.toString()
        })
      ).setMimeType(ContentService.MimeType.JSON);
    }
  }

  // ... resto do código ...
}
```

---

## 📊 ESTRUTURA DAS ABAS

### Aba: Embarque
| Coluna | Nome | Tipo | Descrição |
|--------|------|------|-----------|
| A | CPF | Text | CPF do passageiro |
| B | Nome | Text | Nome completo |
| C | ID Passeio | Text | Identificador do passeio |
| D | Turma | Text | Turma do aluno |
| E | Embarque | Text | Status: SIM/NÃO |
| F | Retorno | Text | Status: SIM/NÃO |
| G | Ônibus | Text | Número do ônibus |
| H | Código Pulseira | Text | Código QR/barras |

---

### Aba: Alunos
| Coluna | Nome | Tipo | Descrição |
|--------|------|------|-----------|
| A | CPF | Text | CPF do aluno |
| B | Nome | Text | Nome completo |
| C | Email | Text | Email |
| D | Telefone | Text | Telefone |
| E | Turma | Text | Turma |
| F | Facial Status | Text | CADASTRADA/NAO |
| G | Tem QR | Text | SIM/NAO |
| H | Data Cadastro | Date | Data do cadastro |

---

### Aba: Pessoas (🆕 NOVA - Criar se não existir)
| Coluna | Nome | Tipo | Descrição |
|--------|------|------|-----------|
| A | CPF | Text | CPF da pessoa |
| B | Nome | Text | Nome completo |
| C | Email | Text | Email |
| D | Telefone | Text | Telefone |
| E | Embedding | Text | JSON array de 512 números |
| F | Data Cadastro | Date | Data do cadastro facial |
| G | Status | Text | CADASTRADA |

**Exemplo de embedding:**
```
"[0.123,-0.456,0.789,0.234,-0.567,0.891,...]"
```
(512 números separados por vírgula, entre colchetes)

---

### Aba: Usuários
| Coluna | Nome | Tipo | Descrição |
|--------|------|------|-----------|
| A | User ID | Text | ID único |
| B | CPF | Text | CPF do usuário |
| C | Nome | Text | Nome completo |
| D | Senha Hash | Text | SHA256 da senha |
| E | Perfil | Text | ADMIN/USUARIO |
| F | Ativo | Number | 1=ativo, 0=inativo |
| G | Data Cadastro | Date | Data do cadastro |

---

### Aba: Logs (Opcional, mas recomendado)
| Coluna | Nome | Tipo | Descrição |
|--------|------|------|-----------|
| A | CPF | Text | CPF reconhecido |
| B | Nome | Text | Nome da pessoa |
| C | Timestamp | Date | Data/hora do reconhecimento |
| D | Confidence | Number | Confiança (0-1) |
| E | Tipo | Text | EMBARQUE/RETORNO |
| F | Data Sync | Date | Quando foi sincronizado |

---

## ✅ CHECKLIST DE IMPLEMENTAÇÃO

### Passo 1: Verificar Abas Existentes
- [ ] Aba "Embarque" existe e tem estrutura correta
- [ ] Aba "Alunos" existe e tem estrutura correta
- [ ] Aba "Usuários" existe e tem estrutura correta
- [ ] Criar aba "Pessoas" (se não existir)
- [ ] Criar aba "Logs" (opcional, mas recomendado)

### Passo 2: Implementar Actions Faltando
- [ ] Implementar `addPessoa` (CRÍTICO)
- [ ] Testar `addPessoa` com Postman ou app

### Passo 3: Validar Actions Existentes
- [ ] Testar `getAllStudents` retorna dados corretos
- [ ] Testar `getAllPeople` retorna embeddings corretos
- [ ] Testar `getAllUsers` retorna usuários
- [ ] Testar `login` autentica corretamente
- [ ] Testar `addMovementLog` salva logs

### Passo 4: Validar Formato de Dados
- [ ] Embeddings estão em formato JSON string
- [ ] Embeddings têm 512 dimensões
- [ ] Senhas estão em SHA256
- [ ] Datas estão em formato correto

---

## 🧪 TESTES

### Testar addPessoa com Postman

**URL:** Sua URL do Google Apps Script
**Método:** POST
**Headers:**
```
Content-Type: application/json
```

**Body:**
```json
{
  "action": "addPessoa",
  "cpf": "12345678900",
  "nome": "João Teste",
  "email": "joao@teste.com",
  "telefone": "11999999999",
  "embedding": "[0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0]",
  "personId": "12345678900"
}
```

**Resposta esperada:**
```json
{
  "success": true,
  "message": "Pessoa cadastrada com sucesso"
}
```

---

## 📝 NOTAS IMPORTANTES

1. **Embedding Format**: O embedding DEVE ser uma string JSON contendo um array de 512 números decimais. Exemplo:
   ```
   "[0.123,-0.456,0.789,...]"
   ```

2. **SHA256 Hash**: Senhas devem ser hasheadas com SHA256 tanto no app quanto no GAS. Use a mesma função em ambos.

3. **Redirect 302**: O GAS pode retornar 302. O app já trata isso automaticamente.

4. **CORS**: Certifique-se de que o script está configurado para aceitar requisições do app:
   ```javascript
   function doPost(e) {
     // ... código ...

     return ContentService.createTextOutput(JSON.stringify(response))
       .setMimeType(ContentService.MimeType.JSON);
   }
   ```

5. **Deploy**: Após implementar, faça deploy como "Web app":
   - Execute as: Me
   - Who has access: Anyone

---

**Última atualização**: 2025-10-30
**Prioridade**: 🚨 CRÍTICA - Implementar `addPessoa` imediatamente
