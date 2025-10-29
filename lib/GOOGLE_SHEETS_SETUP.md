# 📋 Configuração do Google Sheets

Este documento explica como configurar o Google Apps Script para integração com o app.

## 1️⃣ Estrutura da Planilha

Sua planilha do Google Sheets deve ter as seguintes abas:

### **Aba: LOGIN**
Gerencia os usuários do sistema.

| Coluna | Nome     | Tipo   | Descrição                    |
|--------|----------|--------|------------------------------|
| A      | ID       | Número | ID único do usuário          |
| B      | NOME     | Texto  | Nome completo                |
| C      | CPF      | Texto  | CPF do usuário (sem pontos)  |
| D      | SENHA    | Texto  | Senha do usuário             |
| E      | PERFIL   | Texto  | USUARIO ou ADMIN             |

**Exemplo:**
```
ID | NOME              | CPF         | SENHA    | PERFIL
1  | João Silva        | 12345678900 | senha123 | ADMIN
2  | Maria Santos      | 98765432100 | senha456 | USUARIO
```

### **Aba: PESSOAS**
Armazena pessoas com embeddings faciais.

| Coluna | Nome      | Tipo   | Descrição                        |
|--------|-----------|--------|----------------------------------|
| A      | ID        | Número | ID único                         |
| B      | NOME      | Texto  | Nome completo                    |
| C      | CPF       | Texto  | CPF (sem pontos)                 |
| D      | EMAIL     | Texto  | E-mail                           |
| E      | TELEFONE  | Texto  | Telefone                         |
| F      | TURMA     | Texto  | Turma/Classe                     |
| G      | EMBEDDING | Texto  | JSON array com embedding facial  |
| H      | TEM_QR    | Texto  | SIM ou NAO                       |

**Exemplo:**
```
ID | NOME      | CPF         | EMAIL           | TELEFONE    | TURMA | EMBEDDING          | TEM_QR
1  | Ana Silva | 11122233344 | ana@email.com   | 11999999999 | 6A    | [0.123, 0.456,...] | SIM
```

### **Aba: LOGS**
Registra logs de reconhecimento facial (criada automaticamente).

| Coluna | Nome       | Tipo      | Descrição                     |
|--------|------------|-----------|-------------------------------|
| A      | TIMESTAMP  | Data/Hora | Momento do reconhecimento     |
| B      | CPF        | Texto     | CPF da pessoa reconhecida     |
| C      | NOME       | Texto     | Nome da pessoa                |
| D      | CONFIDENCE | Número    | Confiança (0.0 a 1.0)         |
| E      | TIPO       | Texto     | Tipo de evento                |

### **Outras Abas (Passeios/Embarques)**
Cada aba representa um passeio diferente.

| Coluna | Nome       | Tipo   | Descrição                  |
|--------|------------|--------|----------------------------|
| A      | NOME       | Texto  | Nome do aluno              |
| B      | CPF        | Texto  | CPF do aluno               |
| C      | ID_PASSEIO | Texto  | ID do passeio              |
| D      | TURMA      | Texto  | Turma                      |
| E      | EMBARQUE   | Texto  | SIM ou NAO                 |
| F      | RETORNO    | Texto  | SIM ou NAO                 |
| G      | ONIBUS     | Texto  | Número do ônibus           |
| H      | TEM_QR     | Texto  | SIM ou NAO                 |

## 2️⃣ Configurando o Google Apps Script

### Passo 1: Abra o Editor de Scripts
1. Abra sua planilha do Google Sheets
2. Clique em **Extensões** → **Apps Script**
3. Apague o código padrão

### Passo 2: Cole o Script
1. Copie todo o conteúdo do arquivo `script.gs`
2. Cole no editor do Apps Script
3. **IMPORTANTE:** Na linha 12, substitua `SEU_SPREADSHEET_ID_AQUI` pelo ID da sua planilha
   - O ID está na URL: `https://docs.google.com/spreadsheets/d/[ID_AQUI]/edit`

### Passo 3: Implante o Script
1. Clique em **Implantar** → **Nova implantação**
2. Clique no ícone de engrenagem ⚙️ → Selecione **Aplicativo da Web**
3. Configure:
   - **Descrição:** API Ellus Embarque
   - **Executar como:** Eu (seu e-mail)
   - **Quem tem acesso:** Qualquer pessoa
4. Clique em **Implantar**
5. Autorize as permissões solicitadas
6. **Copie a URL da implantação** (você vai precisar dela!)

### Passo 4: Atualize o App Flutter
No arquivo `lib/services/auth_service.dart`, atualize a URL:
```dart
final String _apiUrl = 'SUA_URL_DE_IMPLANTACAO_AQUI';
```

No arquivo `lib/services/alunos_sync_service.dart`, atualize a URL:
```dart
final String _apiUrl = 'SUA_URL_DE_IMPLANTACAO_AQUI';
```

## 3️⃣ Testando a Integração

### Teste 1: Verificar se o script está funcionando
1. Abra a URL da implantação no navegador
2. Deve mostrar: `API Ellus Embarque - Funcionando!`

### Teste 2: Testar Login
Use uma ferramenta como Postman ou curl:
```bash
curl -X POST "SUA_URL_AQUI" \
  -H "Content-Type: application/json" \
  -d '{"action":"login","cpf":"12345678900","senha":"senha123"}'
```

Resposta esperada:
```json
{
  "success": true,
  "message": "Login bem-sucedido",
  "user": {
    "id": 1,
    "nome": "João Silva",
    "cpf": "12345678900",
    "perfil": "ADMIN"
  }
}
```

## 4️⃣ Funções Disponíveis

### `login`
**Input:**
```json
{
  "action": "login",
  "cpf": "12345678900",
  "senha": "senha123"
}
```

**Output:**
```json
{
  "success": true,
  "message": "Login bem-sucedido",
  "user": {
    "id": 1,
    "nome": "João Silva",
    "cpf": "12345678900",
    "perfil": "ADMIN"
  }
}
```

### `getAllPeople`
Busca todas as pessoas com embeddings da aba PESSOAS.

**Input:**
```json
{
  "action": "getAllPeople"
}
```

### `getAlunos`
Busca alunos de uma aba específica.

**Input:**
```json
{
  "action": "getAlunos",
  "nomeAba": "PASSEIO_COC",
  "numeroOnibus": "1"
}
```

### `cadastrarFacial`
Cadastra ou atualiza embedding facial na aba PESSOAS.

**Input:**
```json
{
  "action": "cadastrarFacial",
  "cpf": "12345678900",
  "nome": "João Silva",
  "email": "joao@email.com",
  "telefone": "11999999999",
  "embedding": [0.123, 0.456, ...]
}
```

### `registrarLog`
Registra um log de reconhecimento na aba LOGS.

**Input:**
```json
{
  "action": "registrarLog",
  "cpf": "12345678900",
  "nome": "João Silva",
  "confidence": 0.85,
  "tipo": "reconhecimento"
}
```

## 5️⃣ Solução de Problemas

### Erro: "Aba LOGIN não encontrada"
- Certifique-se que a aba se chama exatamente **LOGIN** (maiúsculas)
- Verifique se está na planilha correta (SPREADSHEET_ID)

### Erro: "CPF ou senha inválidos"
- Verifique se o CPF está sem pontos e traços
- Verifique se a senha está correta
- Confira se o PERFIL está em maiúsculas (ADMIN ou USUARIO)

### Erro de autorização
- Reimplante o script com as permissões corretas
- Certifique-se de ter concedido todas as autorizações

### Script não responde
- Verifique os logs: No editor do Apps Script → **Execuções**
- Veja se há erros de execução

## 6️⃣ Segurança

⚠️ **IMPORTANTE:**
- As senhas estão armazenadas em texto plano
- Para produção, considere usar hash de senhas
- Limite o acesso à planilha apenas para pessoas autorizadas
- Use HTTPS sempre (o Google já faz isso automaticamente)

## 7️⃣ Próximos Passos

Após configurar o script:
1. ✅ Crie alguns usuários de teste na aba LOGIN
2. ✅ Teste o login no app
3. ✅ Verifique se o botão PAINEL aparece para usuários ADMIN
4. ✅ Cadastre algumas faciais na aba PESSOAS
5. ✅ Teste o reconhecimento facial

---

💡 **Dica:** Mantenha uma cópia de backup da planilha antes de fazer mudanças importantes!
