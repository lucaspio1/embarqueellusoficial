# 🔧 Correção de Dados do Firebase - Usuário

## 🚨 Problema Identificado

Você cadastrou o usuário com campos em **MAIÚSCULO**, mas o código espera campos em **minúsculo**.

### ❌ O que você tem agora (ERRADO):
```javascript
{
  "CPF": "08943760981",        // ❌ Maiúsculo
  "ID": 1,                     // ❌ Campo errado (deveria ser user_id string)
  "NOME": "PIO",               // ❌ Maiúsculo
  "PERFIL": "ADMIN",           // ❌ Maiúsculo
  "SENHA": "12345"             // ❌ Senha em texto plano
}
```

### ✅ O que deveria ser (CORRETO):

**Document ID**: `user_admin_001` (ou deixe auto-gerar)

**Campos do documento**:
```javascript
{
  "nome": "PIO",               // ✅ Minúsculo
  "cpf": "08943760981",        // ✅ Minúsculo
  "senha_hash": "5994471abb01112afcc18159f6cc74b4f511b99806da59b3caf5a9c173cacfc5", // ✅ Hash SHA-256 de "12345"
  "perfil": "ADMIN",           // ✅ Minúsculo (valor ADMIN continua maiúsculo)
  "ativo": true,               // ✅ Boolean
  "created_at": "2025-12-01T18:00:00Z",  // ✅ Timestamp
  "updated_at": "2025-12-01T18:00:00Z"   // ✅ Timestamp
}
```

**📝 Nota**: O campo `user_id` NÃO é necessário dentro do documento, pois o código usa automaticamente o **Document ID** do Firestore como `user_id`.

---

## 📝 Como Corrigir no Firebase Console

### Passo 1: Acesse o Firestore

1. Abra: https://console.firebase.google.com/
2. Selecione seu projeto
3. Vá em **Firestore Database** (menu lateral)
4. Abra a coleção `usuarios`

### Passo 2: Delete o documento errado

1. Clique no documento com campos em MAIÚSCULO
2. Clique nos 3 pontinhos → **Excluir documento**
3. Confirme a exclusão

### Passo 3: Crie um novo documento correto

1. Clique em **Adicionar documento**
2. **ID do documento**: `user_admin_001` (ou deixe auto-gerar)
3. Adicione os seguintes campos:

| Campo | Tipo | Valor |
|-------|------|-------|
| `nome` | string | `PIO` |
| `cpf` | string | `08943760981` |
| `senha_hash` | string | `5994471abb01112afcc18159f6cc74b4f511b99806da59b3caf5a9c173cacfc5` |
| `perfil` | string | `ADMIN` |
| `ativo` | boolean | `true` ← **tipo boolean!** |
| `created_at` | timestamp | (use o botão "data e hora" e selecione agora) |
| `updated_at` | timestamp | (use o botão "data e hora" e selecione agora) |

**⚠️ IMPORTANTE**: NÃO adicione o campo `user_id` - ele não é necessário! O código usa automaticamente o Document ID.

4. Clique em **Salvar**

---

## 🔐 Hashes de Senhas Comuns

Para facilitar, aqui estão os hashes SHA-256 de senhas comuns:

| Senha | Hash SHA-256 |
|-------|--------------|
| `12345` | `5994471abb01112afcc18159f6cc74b4f511b99806da59b3caf5a9c173cacfc5` |
| `123456` | `8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92` |
| `admin` | `8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918` |
| `senha123` | `8f5793a44f78f22f465e7e0c3e64c5e6e4e0b7fba7e84a9b4e12c4b8f0c74a3d` |

**⚠️ IMPORTANTE**: Em produção, use senhas fortes! Estas são apenas para testes.

---

## 🧪 Como Gerar Hash de Outras Senhas

Se precisar gerar o hash de outra senha:

### Opção 1: Online (apenas para testes!)
1. Acesse: https://emn178.github.io/online-tools/sha256.html
2. Digite a senha
3. Copie o hash gerado

**⚠️ NUNCA use sites online para senhas de produção!**

### Opção 2: No Terminal (mais seguro)
```bash
echo -n "suasenha" | sha256sum
```

### Opção 3: No Flutter/Dart
```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

String gerarHash(String senha) {
  final bytes = utf8.encode(senha);
  final hash = sha256.convert(bytes);
  return hash.toString();
}

// Exemplo:
print(gerarHash('12345'));
// Resultado: 5994471abb01112afcc18159f6cc74b4f511b99806da59b3caf5a9c173cacfc5
```

---

## ✅ Verificação

Após corrigir o documento no Firebase:

1. O app deve detectar a mudança automaticamente (listeners em tempo real)
2. Nos logs, você verá:
   ```
   ✅ [FirebaseService] 1 usuários sincronizados
   ```
3. Tente fazer login com:
   - **CPF**: `08943760981`
   - **Senha**: `12345`

---

## 📋 Checklist de Correção

- [ ] Deletei o documento com campos em MAIÚSCULO
- [ ] Criei novo documento com campos em minúsculo
- [ ] Usei o hash SHA-256 correto da senha
- [ ] Adicionei todos os campos obrigatórios
- [ ] Campo `ativo` é do tipo `boolean` (não string)
- [ ] Campos `created_at` e `updated_at` são do tipo `timestamp`
- [ ] Testei o login no app

---

## 🆘 Ainda com problemas?

Se após a correção ainda não sincronizar:

1. **Force um restart do app** (feche completamente e reabra)
2. **Verifique os logs**: procure por mensagens do `[FirebaseService]`
3. **Limpe o cache**: `flutter clean && flutter run`

---

## 📚 Referências

- Estrutura completa: `FIRESTORE_STRUCTURE.md`
- Setup do Firebase: `FIREBASE_SETUP.md`
- Código de sincronização: `lib/services/firebase_service.dart:130-150`
