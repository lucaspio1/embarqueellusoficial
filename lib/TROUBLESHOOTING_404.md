# 🔧 Troubleshooting - Erro 404 no Login

## Problema Identificado
```
I/flutter: 🔐 [Auth] Tentando login: CPF=8943760981
I/flutter: ❌ [Auth] Erro HTTP: 404
```

O script executa sem erro no Google Apps Script, mas o app retorna 404.

## ✅ Checklist de Verificação

### 1. Verifique o Deploy do Script

**Passo 1:** Abra o Google Apps Script
- Vá em **Extensões** → **Apps Script**

**Passo 2:** Verifique o Deploy
- Clique em **Implantar** → **Gerenciar implantações**
- Verifique se existe uma implantação ativa
- **IMPORTANTE:** Tipo deve ser **"Aplicativo da Web"**

**Configurações Corretas:**
- ✅ **Executar como:** Eu (seu e-mail)
- ✅ **Quem tem acesso:** **Qualquer pessoa**
- ✅ **URL termina com:** `/exec` (não `/dev`)

### 2. Use a URL Correta

A URL deve seguir este formato:
```
https://script.google.com/macros/s/[SCRIPT_ID]/exec
```

**Erros Comuns:**
- ❌ `/dev` no final (URL de desenvolvimento, não funciona)
- ❌ URL antiga (após re-implantar, a URL muda!)
- ❌ Espaços ou caracteres especiais

### 3. Teste a URL Diretamente

Abra a URL no navegador. Deve mostrar:
```
API Ellus Embarque - Funcionando!
```

Se mostrar erro 404 ou página não encontrada:
- ✅ A URL está errada
- ✅ Refaça o deploy

### 4. Verifique as Permissões

**Ao fazer o primeiro deploy:**
1. Você deve ter autorizado o script
2. Pode ser solicitado "Permitir acesso não seguro" - aceite
3. O Google pode mostrar aviso de segurança - clique em "Avançado" → "Ir para... (não seguro)"

**Para reverificar:**
1. Vá em https://myaccount.google.com/permissions
2. Procure pelo nome do seu script
3. Revogue e autorize novamente se necessário

### 5. Teste com cURL

Execute no terminal ou Postman:
```bash
curl -X POST "SUA_URL_AQUI" \
  -H "Content-Type: application/json" \
  -d '{"action":"login","cpf":"8943760981","senha":"sua_senha"}'
```

**Resposta esperada:**
```json
{
  "success": true,
  "message": "Login bem-sucedido",
  "user": { ... }
}
```

**Se retornar 404:**
- A URL está incorreta
- O deploy não está ativo
- Não está implantado como "Aplicativo Web"

### 6. Verifique os Logs do Script

No Google Apps Script:
1. Clique em **Execuções** (ícone de relógio)
2. Veja se há execuções recentes
3. Verifique os logs de cada execução

**Se NÃO houver execuções:**
- O script não está recebendo as requisições
- Problema com a URL ou deploy

**Se houver execuções mas com erros:**
- Veja o log de erro específico
- Corrija o problema no script

### 7. Problemas Comuns e Soluções

#### 🔴 Erro: "Authorization required"
**Solução:** Refaça o deploy e autorize novamente

#### 🔴 Erro: "Script has been disabled"
**Solução:** Habilite o script nas configurações

#### 🔴 Erro: 404 no navegador
**Solução:**
1. Delete a implantação atual
2. Crie uma nova implantação
3. Use a nova URL

#### 🔴 Erro: Script executa mas app retorna 404
**Problema:** Pode ser cache ou URL antiga
**Solução:**
1. Limpe o cache do app
2. Copie novamente a URL do deploy
3. Atualize no `auth_service.dart`
4. Rebuilde o app

### 8. Passos para Re-implantar

Se nada funcionar, siga estes passos:

1. **Arquive a implantação atual:**
   - Implantar → Gerenciar implantações
   - Clique nos 3 pontos → Arquivar

2. **Crie nova implantação:**
   - Implantar → Nova implantação
   - Tipo: Aplicativo da Web
   - **Nova descrição:** (ex: "API v2")
   - Executar como: Eu
   - Acesso: Qualquer pessoa
   - Implantar

3. **Copie a nova URL**

4. **Atualize no app:**
   ```dart
   // lib/services/auth_service.dart
   final String _apiUrl = 'NOVA_URL_AQUI';
   ```

5. **Teste no navegador:**
   - Cole a URL
   - Deve mostrar: "API Ellus Embarque - Funcionando!"

6. **Teste o login:**
   - Use curl ou Postman
   - Verifique se retorna JSON

### 9. Verificação da URL no Código

Verifique se a URL está correta em:

1. **lib/services/auth_service.dart** (linha 10)
2. **lib/services/alunos_sync_service.dart**
3. **lib/services/offline_sync_service.dart** (se usar)

**Todas devem ter a MESMA URL!**

### 10. Logs Adicionais

Com as mudanças recentes, agora o app mostra mais logs:

```
🔐 [Auth] Tentando login: CPF=...
📥 [Auth] Status Code: ...
📥 [Auth] Response Body: ...
```

Execute o app novamente e veja o que aparece em Response Body.

**Se Response Body mostrar HTML:**
- É uma página de erro do Google
- URL está incorreta ou deploy inativo

**Se Response Body mostrar JSON:**
- O script está funcionando!
- Veja o conteúdo do JSON

## 📝 Checklist Final

Antes de testar novamente:

- [ ] URL termina com `/exec`?
- [ ] Testei a URL no navegador?
- [ ] O deploy está ativo?
- [ ] Tipo de deploy é "Aplicativo da Web"?
- [ ] Acesso está configurado como "Qualquer pessoa"?
- [ ] Atualizei a URL no auth_service.dart?
- [ ] Rebuildi o app após mudar a URL?
- [ ] Testei com curl ou Postman?
- [ ] Vi os logs de execução no Apps Script?
- [ ] A aba LOGIN existe na planilha?
- [ ] Há usuários cadastrados na aba LOGIN?

## 🆘 Ainda não funciona?

Se após todas essas verificações ainda tiver problema:

1. Compartilhe os logs completos do app
2. Compartilhe os logs do Google Apps Script
3. Confirme a URL exata que está usando
4. Verifique se consegue acessar a URL no navegador

## 💡 Dica Extra

Para garantir que o script está funcionando:

1. No Google Apps Script, adicione este teste:
   ```javascript
   function testeLogin() {
     const resultado = login({
       cpf: "8943760981",
       senha: "SUA_SENHA_AQUI"
     });
     console.log(resultado.getContent());
   }
   ```

2. Execute a função `testeLogin`
3. Veja o resultado no log
4. Se funcionar, o problema é na conexão app → script
5. Se não funcionar, o problema é no script ou planilha
