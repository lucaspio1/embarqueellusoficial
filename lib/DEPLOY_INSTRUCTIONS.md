# 🚀 Instruções de Deploy - Passo a Passo

## Planilha Identificada
**ID:** `1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U`
**Link:** https://docs.google.com/spreadsheets/d/1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U/edit

---

## 📋 Passo 1: Preparar a Planilha

### 1.1 Criar Aba LOGIN (se não existir)

1. Abra a planilha
2. Clique no **+** para adicionar nova aba
3. Renomeie para **LOGIN** (tudo em maiúsculas)
4. Adicione o cabeçalho na primeira linha:

| A | B | C | D | E |
|---|---|---|---|---|
| ID | NOME | CPF | SENHA | PERFIL |

5. Adicione alguns usuários de teste:

**Exemplo:**
```
ID | NOME              | CPF         | SENHA    | PERFIL
1  | Admin Sistema     | 12345678900 | admin123 | ADMIN
2  | Usuario Teste     | 98765432100 | user123  | USUARIO
```

⚠️ **Importante:**
- CPF sem pontos ou traços (apenas números)
- PERFIL deve ser **ADMIN** ou **USUARIO** (maiúsculas)
- Senhas em texto plano (para simplificar os testes)

### 1.2 Verificar Aba PESSOAS (se ainda não existir)

Cabeçalho:
```
ID | NOME | CPF | EMAIL | TELEFONE | TURMA | EMBEDDING | TEM_QR
```

---

## 🔧 Passo 2: Configurar o Google Apps Script

### 2.1 Abrir Editor de Scripts

1. Na planilha, clique em **Extensões** → **Apps Script**
2. Você verá um editor de código com uma função `myFunction()` vazia
3. **Delete todo o código** que estiver lá

### 2.2 Copiar o Script

1. Abra o arquivo `lib/script.gs` deste projeto
2. **Copie TODO o conteúdo**
3. Cole no editor do Google Apps Script
4. O SPREADSHEET_ID já está configurado automaticamente! ✅

### 2.3 Salvar o Projeto

1. Clique no ícone de **disquete** 💾 ou Ctrl+S
2. Dê um nome ao projeto: **"API Ellus Embarque"**
3. Clique em **OK**

---

## 🌐 Passo 3: Implantar o Script

### 3.1 Criar Nova Implantação

1. No canto superior direito, clique em **Implantar** → **Nova implantação**
2. Clique no ícone de **engrenagem** ⚙️ ao lado de "Selecione o tipo"
3. Selecione **Aplicativo da Web**

### 3.2 Configurar a Implantação

Configure da seguinte forma:

**Descrição:**
```
API Ellus Embarque v1
```

**Executar como:**
```
Eu (seu-email@gmail.com)
```

**Quem tem acesso:**
```
Qualquer pessoa
```

⚠️ **IMPORTANTE:** Deve ser "Qualquer pessoa" para o app funcionar!

### 3.3 Autorizar Permissões

1. Clique em **Implantar**
2. Uma janela de autorização vai aparecer
3. Clique em **Autorizar acesso**
4. Escolha sua conta Google
5. Clique em **Avançado** (se aparecer aviso)
6. Clique em **Ir para API Ellus Embarque (não seguro)**
7. Clique em **Permitir**

### 3.4 Copiar a URL de Implantação

Após autorizar, você verá uma tela com:

```
✅ Nova implantação criada

URL do aplicativo da Web:
https://script.google.com/macros/s/AKfycby.../exec
```

**COPIE ESTA URL COMPLETA!** 📋

⚠️ Certifique-se de que termina com `/exec` (não `/dev`)

---

## 📱 Passo 4: Atualizar o App Flutter

### 4.1 Atualizar auth_service.dart

Abra o arquivo `lib/services/auth_service.dart` e na linha 10, cole a URL:

```dart
final String _apiUrl = 'COLE_A_URL_AQUI';
```

**Exemplo:**
```dart
final String _apiUrl = 'https://script.google.com/macros/s/AKfycby.../exec';
```

### 4.2 Atualizar alunos_sync_service.dart (se necessário)

Se você usa sincronização de alunos, atualize também em:
`lib/services/alunos_sync_service.dart`

---

## ✅ Passo 5: Testar a Integração

### 5.1 Testar no Navegador

1. Abra a URL no navegador
2. Deve mostrar:
   ```
   API Ellus Embarque - Funcionando!
   ```
3. Se mostrar isso, o script está OK! ✅

### 5.2 Testar Login com cURL (Opcional)

Execute no terminal:
```bash
curl -X POST "SUA_URL_AQUI" \
  -H "Content-Type: application/json" \
  -d '{"action":"login","cpf":"12345678900","senha":"admin123"}'
```

Resposta esperada:
```json
{
  "success": true,
  "message": "Login bem-sucedido",
  "timestamp": "2025-10-29T...",
  "user": {
    "id": 1,
    "nome": "Admin Sistema",
    "cpf": "12345678900",
    "perfil": "ADMIN"
  }
}
```

### 5.3 Testar no App

1. Rebuilde o app Flutter
2. Abra o app
3. Tente fazer login com:
   - **CPF:** 12345678900
   - **Senha:** admin123
4. Deve entrar e mostrar o menu com botão "PAINEL" (se for ADMIN)

---

## 🐛 Se Algo Der Errado

### Erro: "Script disabled for your account"
**Solução:** Reautorize o script nas configurações de segurança do Google

### Erro: 404 Not Found
**Problema:** URL incorreta ou deploy não está ativo
**Solução:**
1. Verifique se a URL termina com `/exec`
2. Vá em **Implantar** → **Gerenciar implantações**
3. Certifique-se de que há uma implantação ativa
4. Se necessário, crie uma nova implantação

### Erro: "Aba LOGIN não encontrada"
**Solução:** Verifique se a aba se chama exatamente **LOGIN** (maiúsculas)

### Erro: "CPF ou senha inválidos"
**Solução:**
1. Verifique se o CPF está sem pontos/traços
2. Verifique se a senha está correta
3. Veja os logs no Apps Script (Execuções)

---

## 📊 Ver Logs de Execução

Para ver se o script está recebendo requisições:

1. No Google Apps Script, clique no ícone de **relógio** ⏱️ (Execuções)
2. Você verá todas as execuções recentes
3. Clique em uma execução para ver os logs
4. Procure por:
   ```
   📥 Requisição recebida
   📥 Ação recebida: login
   🔐 Tentativa de login: [CPF]
   ```

---

## 🔄 Próximas Atualizações do Script

Se você precisar atualizar o script no futuro:

1. Edite o código no Google Apps Script
2. Salve (Ctrl+S)
3. Vá em **Implantar** → **Gerenciar implantações**
4. Clique nos **3 pontos** ao lado da implantação ativa
5. Clique em **Editar**
6. Mude a **Versão** para "Nova versão"
7. Clique em **Implantar**

⚠️ **A URL permanece a mesma**, não precisa atualizar no app!

---

## ✨ Tudo Pronto!

Agora seu app está conectado ao Google Sheets com:
- ✅ Login funcionando
- ✅ Controle de perfis (ADMIN/USUARIO)
- ✅ Painel administrativo
- ✅ Sincronização de dados

🎉 **Parabéns! O sistema está completo!**
