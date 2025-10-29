# 🚀 Guia Rápido: Re-publicar Google Apps Script

## ⚡ Solução Rápida em 5 Passos

### 1️⃣ Abrir Editor do Apps Script

```
Planilha → Extensões → Apps Script
```

### 2️⃣ Copiar Código Atualizado

- Abra o arquivo: `lib/script.gs` do projeto Flutter
- Copie TUDO (Ctrl + A, Ctrl + C)
- Cole no editor do Apps Script (Ctrl + V)
- Salve (Ctrl + S)

### 3️⃣ Re-publicar

**OPÇÃO FÁCIL** (URL não muda):

```
Implantar → Gerenciar implantações → ✏️ Editar
→ Versão: Nova versão → Implantar → Concluído
```

**OPÇÃO ALTERNATIVA** (Nova URL):

```
Implantar → Nova implantação → ⚙️ Tipo: Aplicativo da Web
→ Executar como: Eu
→ Acesso: Qualquer pessoa
→ Implantar
→ COPIAR NOVA URL
```

### 4️⃣ Atualizar URL no App (Se usou OPÇÃO ALTERNATIVA)

Edite: `lib/services/user_sync_service.dart`

Linha 10:
```dart
final String _apiUrl = 'COLE_SUA_NOVA_URL_AQUI';
```

### 5️⃣ Testar

Abra o app → Tela de Login → **"Sincronizar Usuários"**

✅ Deve aparecer: "Usuários sincronizados com sucesso!"

---

## 📋 Checklist Rápido

Antes de testar, confirme:

- [ ] ✅ Código copiado completamente do `script.gs`
- [ ] ✅ Script salvo (Ctrl + S)
- [ ] ✅ Implantação atualizada ou nova criada
- [ ] ✅ Permissões: "Qualquer pessoa"
- [ ] ✅ URL atualizada no app (se criou nova)
- [ ] ✅ Aba "LOGIN" existe na planilha
- [ ] ✅ Aba LOGIN tem dados (além do cabeçalho)

---

## 🔍 Teste Manual (Opcional)

Copie e cole no terminal (Linux/Mac):

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"action":"getAllUsers"}' \
  https://script.google.com/macros/s/AKfycbzLXa6c0HHv8Ff4uxvMNhvw8OB5gLzIhEv2uE4VPDGTCgZu6RsFIRPOv7I62VwZzBNk/exec
```

Resposta esperada:
```json
{
  "success": true,
  "message": "X usuários encontrados",
  "users": [...]
}
```

---

## 🎯 URL Atual do Projeto

**URL do Apps Script em uso:**
```
https://script.google.com/macros/s/AKfycbzLXa6c0HHv8Ff4uxvMNhvw8OB5gLzIhEv2uE4VPDGTCgZu6RsFIRPOv7I62VwZzBNk/exec
```

**Planilha:**
```
https://docs.google.com/spreadsheets/d/1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U/edit
```

---

## ❓ Problemas?

**Erro 404 persistindo?**
→ Use OPÇÃO ALTERNATIVA (criar nova implantação) e atualizar URL no código

**Erro de permissão?**
→ Abra a URL no navegador e autorize o script

**Aba LOGIN não encontrada?**
→ Crie a aba "LOGIN" na planilha (nome exato, maiúsculas)

**Nenhum usuário retornado?**
→ Adicione pelo menos 1 linha de dados na aba LOGIN (além do cabeçalho)

---

## 📱 Estrutura da Aba LOGIN

| ID | NOME | CPF | SENHA | PERFIL |
|----|------|-----|-------|--------|
| 1  | Admin | 12345678901 | admin | ADMIN |
| 2  | Usuario | 98765432100 | senha | USUARIO |

**Regras:**
- CPF: apenas números (11 dígitos)
- PERFIL: ADMIN ou USUARIO (maiúsculas)
- Sem linhas vazias entre os dados

---

## 💡 Dica

Recomendamos usar a **OPÇÃO FÁCIL** (atualizar implantação existente) para não precisar mudar código no app!

---

**Documentação completa:** Veja `CORRIGIR_ERRO_404_SYNC.md`
