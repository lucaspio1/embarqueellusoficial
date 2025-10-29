# Solução do Erro 404 na Sincronização de Usuários

## Problema

Ao clicar em "Sincronizar Usuários", você recebe:

```
I/flutter: 📥 [UserSync] Status: 404
I/flutter: ❌ [UserSync] Erro HTTP: 404
I/flutter: ❌ [Auth] Erro na sincronização: Erro ao conectar: 404
```

## Causa

O erro 404 ocorre porque:
- O Google Apps Script não foi re-publicado após adicionar a função `getAllUsers()`
- A URL de implantação pode estar desatualizada
- A implantação não está permitindo acesso público

## Solução: Re-publicar o Google Apps Script

### Passo 1: Acessar o Editor

1. Abra sua planilha:
   ```
   https://docs.google.com/spreadsheets/d/1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U/edit
   ```

2. Menu: **Extensões** → **Apps Script**

### Passo 2: Copiar o Código Atualizado

Copie TODO o conteúdo do arquivo `lib/script.gs` do projeto Flutter e cole no editor do Apps Script.

**IMPORTANTE**: O script deve conter:
- ✅ Linha 35-36: `case 'getAllUsers': return getAllUsers();`
- ✅ Linhas 126-168: Função `getAllUsers()` completa

### Passo 3: Salvar e Testar

1. Clique no ícone de **disquete** ou pressione `Ctrl + S` para salvar
2. Execute a função de teste:
   - No menu de funções (dropdown), selecione `getAllUsers`
   - Clique em **Executar** (▶️)
   - Autorize o script se solicitado
   - Verifique se não há erros no log de execução

### Passo 4: Re-publicar (ESCOLHA UMA OPÇÃO)

#### OPÇÃO A: Atualizar Implantação Existente (Recomendado - URL não muda)

1. Clique em **Implantar** → **Gerenciar implantações**
2. Você verá a implantação ativa atual
3. Clique no ícone de **lápis** ✏️ (Editar)
4. Em **Versão**, clique e selecione **Nova versão**
5. Clique em **Implantar**
6. Clique em **Concluído**

**Vantagem**: A URL continua a mesma, não precisa atualizar o app.

#### OPÇÃO B: Nova Implantação (URL nova)

1. Clique em **Implantar** → **Nova implantação**
2. Clique no ícone de **engrenagem** ⚙️
3. Selecione **Aplicativo da Web**
4. Configure:
   - **Descrição**: `Ellus Embarque API - v2.1 (getAllUsers)`
   - **Executar como**: `Eu (seu email)`
   - **Quem tem acesso**: `Qualquer pessoa`
5. Clique em **Implantar**
6. **COPIE A NOVA URL** (ex: `https://script.google.com/macros/s/NOVA_URL_AQUI/exec`)

**Desvantagem**: Você terá que atualizar a URL no código do app.

### Passo 5: Atualizar URL no App (Apenas se usou OPÇÃO B)

Se você fez uma **Nova Implantação**, edite o arquivo:

`lib/services/user_sync_service.dart`

Linha 10:
```dart
final String _apiUrl = 'https://script.google.com/macros/s/SUA_NOVA_URL_AQUI/exec';
```

Depois, recompile e instale o app novamente.

### Passo 6: Verificar Permissões

Certifique-se de que a implantação está configurada corretamente:

1. Vá em **Implantar** → **Gerenciar implantações**
2. Verifique:
   - **Executar como**: Deve estar como "Eu (seu email)"
   - **Quem tem acesso**: Deve estar como "Qualquer pessoa"

Se estiver diferente:
1. Clique no lápis ✏️ para editar
2. Altere as configurações
3. Clique em **Implantar**

### Passo 7: Testar

1. Abra o app
2. Na tela de login, clique em **"Sincronizar Usuários"**
3. Aguarde a sincronização
4. Você deve ver: ✅ **"Usuários sincronizados com sucesso!"**

## Teste Manual da API

Para testar se o script está funcionando, você pode fazer uma requisição HTTP:

### Usando curl (Linux/Mac):

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"action":"getAllUsers"}' \
  https://script.google.com/macros/s/AKfycbzLXa6c0HHv8Ff4uxvMNhvw8OB5gLzIhEv2uE4VPDGTCgZu6RsFIRPOv7I62VwZzBNk/exec
```

### Usando Postman:

- **Método**: POST
- **URL**: Sua URL do Apps Script
- **Headers**:
  - `Content-Type: application/json`
- **Body** (raw JSON):
  ```json
  {"action": "getAllUsers"}
  ```

### Resposta esperada:

```json
{
  "success": true,
  "message": "X usuários encontrados",
  "timestamp": "2025-10-29T...",
  "users": [
    {
      "id": 1,
      "nome": "João Silva",
      "cpf": "12345678901",
      "senha": "senha123",
      "perfil": "ADMIN"
    },
    ...
  ]
}
```

## Verificar Logs do Apps Script

Se ainda tiver problemas:

1. No editor do Apps Script, clique em **Execuções** (ícone de relógio)
2. Veja os logs das execuções recentes
3. Procure por erros em vermelho
4. Verifique se a ação `getAllUsers` está sendo recebida

## Checklist de Verificação

Antes de reportar erro, confirme:

- [ ] O código do script.gs foi copiado completamente
- [ ] A função `getAllUsers()` existe no script (linhas 126-168)
- [ ] O script foi salvo (Ctrl + S)
- [ ] A implantação foi atualizada (Nova versão)
- [ ] Permissões: "Executar como: Eu" e "Quem tem acesso: Qualquer pessoa"
- [ ] A URL no app está correta (user_sync_service.dart linha 10)
- [ ] Existe uma aba chamada "LOGIN" na planilha
- [ ] A aba LOGIN tem dados (pelo menos uma linha além do cabeçalho)

## Estrutura da Aba LOGIN

Certifique-se de que a planilha tem a aba LOGIN com essa estrutura:

| ID | NOME | CPF | SENHA | PERFIL |
|----|------|-----|-------|--------|
| 1  | Admin Sistema | 12345678901 | admin123 | ADMIN |
| 2  | Usuario Teste | 98765432100 | senha456 | USUARIO |

**IMPORTANTE**:
- Primeira linha deve ser o cabeçalho
- CPF deve conter apenas números
- PERFIL deve ser ADMIN ou USUARIO (maiúsculas)

## Problemas Comuns

### "Unauthorized" ou erro de permissão

**Solução**:
1. Abra a URL do script no navegador
2. Faça login com sua conta Google
3. Autorize o script quando solicitado
4. Tente sincronizar novamente

### "Script function not found"

**Solução**:
1. Verifique se o nome da função está correto: `getAllUsers` (case-sensitive)
2. Confirme que a função existe no código
3. Salve e re-publique o script

### "Spreadsheet not found"

**Solução**:
1. Verifique o SPREADSHEET_ID na linha 12 do script.gs
2. Deve ser: `1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U`
3. Confirme que você tem acesso a esta planilha

## Ainda não funciona?

Se após seguir todos os passos ainda tiver erro 404:

1. **Crie uma NOVA implantação** (não atualize a existente)
2. **Copie a nova URL**
3. **Atualize no código**:
   - `lib/services/user_sync_service.dart` (linha 10)
4. **Recompile o app**
5. **Reinstale no dispositivo**
6. **Teste novamente**

## Suporte

Se precisar de ajuda:
1. Tire um print do erro completo no console
2. Verifique os logs de execução no Apps Script
3. Confirme que seguiu todos os passos do checklist
4. Compartilhe os logs para análise
