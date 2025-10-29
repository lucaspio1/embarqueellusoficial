# Guia de Login Offline

## Visão Geral

Foi implementado um sistema de **login offline** para resolver o problema de redirecionamento HTTP 302 do Google Apps Script. Agora o aplicativo baixa os usuários da planilha e armazena localmente no SQLite com criptografia SHA-256.

## Como Funciona

### 1. Sincronização de Usuários

**Primeira vez:**
- Abra o aplicativo
- Você verá um aviso: "Nenhum usuário encontrado"
- Clique no botão **"Sincronizar Usuários"**
- O app baixa todos os usuários da aba LOGIN da planilha
- As senhas são hasheadas com SHA-256 antes de serem armazenadas

**Atualizações posteriores:**
- Clique em **"Atualizar Usuários"** sempre que houver novos usuários ou alterações de senha na planilha

### 2. Login

Após sincronizar:
- Digite seu CPF
- Digite sua senha
- Clique em **"ENTRAR"**
- O login valida contra o banco de dados local (SQLite)
- **Funciona mesmo sem internet!**

### 3. Perfis de Usuário

Existem 2 tipos de perfil:
- **USUARIO**: Acesso padrão ao sistema
- **ADMIN**: Acesso ao painel administrativo + todas as funcionalidades

Se você for ADMIN, verá o botão **"PAINEL"** no menu principal.

## Arquitetura Técnica

### Componentes Criados/Modificados

#### 1. **database_helper.dart**
- Adicionada tabela `usuarios`:
  - `id`: ID auto-incremental
  - `user_id`: ID do usuário na planilha
  - `nome`: Nome completo
  - `cpf`: CPF (único)
  - `senha_hash`: Senha criptografada com SHA-256
  - `perfil`: USUARIO ou ADMIN
  - `ativo`: Status do usuário
  - `created_at`, `updated_at`: Timestamps

Métodos adicionados:
- `upsertUsuario()`: Inserir ou atualizar usuário
- `getUsuarioByCpf()`: Buscar usuário por CPF
- `getAllUsuarios()`: Listar todos os usuários ativos
- `getTotalUsuarios()`: Contar usuários
- `deleteAllUsuarios()`: Limpar tabela

#### 2. **user_sync_service.dart** (NOVO)
Serviço responsável pela sincronização de usuários.

Funções principais:
- `syncUsuariosFromSheets()`: Baixa usuários da planilha via Google Apps Script
- `_hashSenha()`: Criptografa senhas com SHA-256
- `verificarSenha()`: Valida senha informada contra o hash armazenado
- `temUsuariosLocais()`: Verifica se existem usuários no banco

#### 3. **auth_service.dart**
Refatorado para login offline:

**ANTES:**
```dart
// Fazia requisição HTTP POST para Google Apps Script
final response = await http.post(uri, body: {...});
```

**DEPOIS:**
```dart
// Busca usuário no banco local
final usuario = await _db.getUsuarioByCpf(cpf);

// Valida senha localmente
final senhaValida = _userSync.verificarSenha(senha, usuario['senha_hash']);
```

Novos métodos:
- `syncUsuarios()`: Sincroniza usuários da planilha
- `temUsuariosLocais()`: Verifica se há usuários no banco

#### 4. **login_screen.dart**
Melhorias na interface:

- **Auto-verificação**: Ao abrir a tela, verifica se existem usuários locais
- **Aviso automático**: Mostra alerta se não houver usuários
- **Botão de sincronização**: Com 3 estados visuais:
  - "Sincronizar Usuários" (vermelho) - quando não há usuários
  - "Atualizar Usuários" (cinza) - quando já há usuários
  - "Sincronizando..." (loading) - durante o processo
- **Mensagem dinâmica**: Muda conforme o status dos usuários locais

#### 5. **script.gs**
Adicionado endpoint para sincronização:

```javascript
case 'getAllUsers':
  return getAllUsers();
```

Função `getAllUsers()`:
- Lê a aba LOGIN da planilha
- Retorna todos os usuários com: id, nome, cpf, senha, perfil
- Formato JSON para fácil integração

## Segurança

### Criptografia de Senhas

As senhas são protegidas com **SHA-256** (algoritmo hash criptográfico):

1. **No servidor (Google Sheets)**: Senhas em texto puro (visíveis apenas aos administradores da planilha)
2. **Durante sincronização**: Senhas são baixadas via HTTPS
3. **No app**: Senhas são imediatamente hasheadas e armazenadas como:
   ```
   Senha original: "1234"
   SHA-256 hash: "03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4"
   ```
4. **No banco SQLite**: Apenas o hash é armazenado, nunca a senha original
5. **Durante login**: A senha digitada é hasheada e comparada com o hash armazenado

**Vantagens:**
- Hash é irreversível (não é possível recuperar a senha original)
- Mesmo que alguém acesse o banco SQLite, não verá as senhas reais
- Padrão da indústria para armazenamento de senhas

### Proteção de Dados

- Banco SQLite armazenado localmente no dispositivo
- Acesso restrito ao app
- Nenhuma senha trafega ou é armazenada em texto puro

## Fluxo de Trabalho

### Cenário 1: Primeiro Acesso
```
1. Usuário abre o app
2. Tela de login detecta: "Sem usuários locais"
3. Mostra aviso: "Clique em Sincronizar Usuários"
4. Usuário clica no botão de sincronização
5. App baixa usuários da planilha via Google Apps Script
6. Senhas são hasheadas e armazenadas no SQLite
7. Mensagem: "Usuários sincronizados com sucesso!"
8. Usuário pode fazer login normalmente
```

### Cenário 2: Login Offline
```
1. Usuário abre o app (SEM INTERNET)
2. Tela de login mostra: "Login offline ativo"
3. Usuário digita CPF e senha
4. App busca usuário no banco local
5. Valida senha contra hash armazenado
6. Login bem-sucedido! (mesmo offline)
```

### Cenário 3: Atualização de Usuários
```
1. Administrador adiciona novo usuário na planilha
2. Usuário do app clica em "Atualizar Usuários"
3. App baixa lista completa de usuários
4. Substitui dados antigos pelos novos
5. Novo usuário pode fazer login
```

## Gerenciamento de Usuários na Planilha

### Estrutura da Aba LOGIN

Colunas obrigatórias:
| ID | NOME | CPF | SENHA | PERFIL |
|----|------|-----|-------|--------|
| 1 | João Silva | 12345678901 | senha123 | ADMIN |
| 2 | Maria Santos | 98765432100 | abc456 | USUARIO |

### Adicionar Novo Usuário

1. Abra a planilha no Google Sheets
2. Vá para a aba **LOGIN**
3. Adicione uma nova linha com:
   - **ID**: Próximo número sequencial
   - **NOME**: Nome completo
   - **CPF**: Apenas números (11 dígitos)
   - **SENHA**: Senha em texto puro
   - **PERFIL**: ADMIN ou USUARIO
4. No app, clique em **"Atualizar Usuários"**
5. Novo usuário pode fazer login

### Alterar Senha

1. Na planilha, localize o usuário
2. Altere o valor na coluna **SENHA**
3. No app, clique em **"Atualizar Usuários"**
4. Nova senha entra em vigor

### Remover Usuário

**Opção 1**: Deletar linha da planilha
**Opção 2**: Mudar perfil ou adicionar coluna de status

## Solução de Problemas

### "Erro ao sincronizar usuários"
**Causa**: Sem conexão com internet ou erro no Google Apps Script
**Solução**:
- Verifique sua conexão com internet
- Confirme que o script está publicado corretamente
- Verifique os logs do Apps Script

### "CPF ou senha inválidos"
**Causa**: Credenciais incorretas ou usuário não sincronizado
**Solução**:
- Verifique se digitou o CPF corretamente (apenas números)
- Confirme a senha na planilha
- Clique em "Atualizar Usuários" para sincronizar novamente

### "Nenhum usuário encontrado"
**Causa**: Banco local vazio (primeira vez ou após limpeza)
**Solução**:
- Clique em "Sincronizar Usuários"
- Certifique-se de ter internet

## Dependências

Pacotes utilizados:
- `sqflite`: Banco de dados SQLite
- `crypto`: SHA-256 hashing
- `http`: Requisições para Google Apps Script
- `shared_preferences`: Cache de sessão do usuário

## Próximos Passos (Melhorias Futuras)

1. **Sincronização automática periódica**: Atualizar usuários em background
2. **Política de expiração**: Forçar re-sincronização após X dias
3. **Auditoria de login**: Registrar tentativas de login (sucesso/falha)
4. **Recuperação de senha**: Fluxo para reset de senha
5. **Multi-fator**: Adicionar segundo fator de autenticação

## Conclusão

O sistema de login offline oferece:
- ✅ Funcionamento sem internet
- ✅ Segurança com criptografia SHA-256
- ✅ Sincronização fácil e rápida
- ✅ Gerenciamento simples via planilha
- ✅ Suporte a perfis de acesso (USUARIO/ADMIN)

**Resultado**: Login 100% funcional mesmo sem conexão com a internet!
