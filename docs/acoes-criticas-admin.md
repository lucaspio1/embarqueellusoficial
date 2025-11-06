# Ações Críticas do Painel Admin

## ⚠️ IMPORTANTE: Operações Destrutivas

Este documento descreve duas funcionalidades **EXTREMAMENTE CRÍTICAS** do painel administrativo que executam operações **IRREVERSÍVEIS** e **DESTRUTIVAS**.

---

## 🔴 1. ENCERRAR VIAGEM

### Descrição
Remove **TODOS** os dados do sistema, tanto da planilha Google Sheets quanto do banco de dados local.

### O que é apagado:
- ✗ **Aba PESSOAS** (Google Sheets)
- ✗ **Aba LOGS** (Google Sheets)
- ✗ **Aba ALUNOS** (Google Sheets)
- ✗ **Tabela pessoas_facial** (banco local)
- ✗ **Tabela logs** (banco local)
- ✗ **Tabela alunos** (banco local)
- ✗ **Tabela offline_sync_queue** (banco local)

### Quando usar:
- Ao **finalizar** uma viagem/excursão
- Para **resetar completamente** o sistema
- Quando precisar **começar do zero**

### Segurança:
1. ✅ **Verificação de Perfil**: Apenas usuários ADMIN podem executar
2. ✅ **Confirmação Dupla**: Dois dialogs de confirmação
3. ✅ **Confirmação Textual**: Usuário precisa digitar "ENCERRAR"

### Como usar:
1. No painel admin, role até "Ações Críticas"
2. Clique no botão vermelho **"ENCERRAR VIAGEM"**
3. Leia o aviso e clique em **"Continuar"**
4. Digite **"ENCERRAR"** no campo de texto
5. Aguarde a conclusão da operação

### Fluxo:
```
Usuário clica → Verifica ADMIN → Dialog 1 (Aviso) → Dialog 2 (Digite ENCERRAR)
→ Limpa Google Sheets → Limpa Banco Local → Feedback de sucesso
```

---

## 🔵 2. ENVIAR TODOS PARA QUARTO

### Descrição
Atualiza a **movimentação** de todas as pessoas cadastradas para **"QUARTO"**.

### O que é alterado:
- ✓ **Coluna MOVIMENTACAO** na aba PESSOAS (Google Sheets)
- ✓ **Campo movimentacao** na tabela pessoas_facial (banco local)

### Quando usar:
- **Início do dia**: Todos voltam para o quarto
- **Fim do dia**: Reset das localizações
- **Toques de recolher**: Marcar que todos devem estar no quarto

### Segurança:
1. ✅ **Confirmação Única**: Um dialog de confirmação

### Como usar:
1. No painel admin, role até "Ações Críticas"
2. Clique no botão azul **"ENVIAR TODOS PARA QUARTO"**
3. Leia o aviso e clique em **"Confirmar"**
4. Aguarde a conclusão da operação

### Fluxo:
```
Usuário clica → Dialog de Confirmação → Atualiza Google Sheets
→ Atualiza Banco Local → Recarrega Painel → Feedback de sucesso
```

---

## 📋 Configuração Necessária

### Google Apps Script

**IMPORTANTE**: Antes de usar essas funcionalidades, você precisa implantar o código do Google Apps Script.

#### Passo a Passo:

1. **Abra seu Google Sheets** do projeto ELLUS
2. Vá em **Extensões → Apps Script**
3. **Copie o código** de `docs/google-apps-script-acoes-criticas.js`
4. **Cole** no editor do Apps Script
5. Clique em **"Implantar" → "Nova implantação"**
6. Configure:
   - Tipo: **"Aplicativo da Web"**
   - Executar como: **"Eu"**
   - Quem tem acesso: **"Qualquer pessoa"**
7. Clique em **"Implantar"**
8. **Copie a URL** gerada
9. Cole a URL no arquivo Flutter:
   - Arquivo: `lib/services/acoes_criticas_service.dart`
   - Linha: `static const String _googleAppsScriptUrl = 'SUA_URL_AQUI';`

#### Verificar Estrutura da Planilha

O código assume a seguinte estrutura na aba **PESSOAS**:

| Coluna | Campo |
|--------|-------|
| 1 | CPF |
| 2 | NOME |
| 3 | EMAIL |
| 4 | TELEFONE |
| 5 | TURMA |
| 6 | EMBEDDING |
| 7 | MOVIMENTACAO |

**Se sua planilha tiver estrutura diferente**, ajuste a variável `colunaMovimentacao` no Google Apps Script.

---

## 🛡️ Medidas de Segurança Implementadas

### Para ENCERRAR VIAGEM:
- ✅ Verificação de perfil ADMIN
- ✅ Dialog de aviso com descrição detalhada
- ✅ Dialog de confirmação textual (digite "ENCERRAR")
- ✅ Feedback visual durante processamento
- ✅ Mensagens de sucesso/erro claras
- ✅ Logs no console para auditoria

### Para ENVIAR TODOS PARA QUARTO:
- ✅ Dialog de confirmação com descrição
- ✅ Feedback visual durante processamento
- ✅ Mensagens de sucesso/erro claras
- ✅ Logs no console para auditoria

---

## 📊 Arquivos Relacionados

| Arquivo | Descrição |
|---------|-----------|
| `docs/google-apps-script-acoes-criticas.js` | Código do Google Apps Script |
| `lib/services/acoes_criticas_service.dart` | Serviço Flutter para ações críticas |
| `lib/screens/painel_admin_screen.dart` | Interface do painel admin |

---

## 🐛 Troubleshooting

### Erro: "Erro HTTP 403"
- **Causa**: Permissões do Google Apps Script
- **Solução**: Reimplantar o Apps Script com "Quem tem acesso: Qualquer pessoa"

### Erro: "Erro ao processar requisição"
- **Causa**: URL do Apps Script incorreta
- **Solução**: Verificar URL em `acoes_criticas_service.dart`

### Erro: "Ação desconhecida"
- **Causa**: Código do Apps Script desatualizado
- **Solução**: Copiar novamente o código de `google-apps-script-acoes-criticas.js`

### Botão não aparece no painel
- **Causa**: Usuário não é ADMIN
- **Solução**: Botões são visíveis para todos, mas ENCERRAR VIAGEM só funciona para ADMIN

---

## ⚠️ AVISOS FINAIS

1. **NUNCA** execute "ENCERRAR VIAGEM" sem fazer backup dos dados
2. **SEMPRE** confirme que está na planilha/ambiente correto
3. **TESTE** primeiro em um ambiente de desenvolvimento
4. **DOCUMENTE** quando usar essas funcionalidades (data, hora, motivo)
5. **AVISE** a equipe antes de executar operações críticas

---

## 📝 Changelog

| Data | Versão | Alteração |
|------|--------|-----------|
| 2024 | 1.0.0 | Criação das funcionalidades ENCERRAR VIAGEM e ENVIAR TODOS PARA QUARTO |
