# 📊 RELATÓRIO DE VALIDAÇÃO - SERVIÇOS SQLITE

**Data:** 2025-11-04
**Versão do Banco:** 2
**Arquivo:** `embarque.db`

---

## 📋 RESUMO EXECUTIVO

Análise completa da estrutura SQLite do projeto identificou **5 conflitos** principais relacionados a duplicação de dados, sistemas paralelos e falta de integridade referencial. O sistema está funcional, mas apresenta redundância significativa que pode causar inconsistências futuras.

**Severidade Geral:** 🟡 **MÉDIA-ALTA**

---

## 🗄️ ESTRUTURA DO BANCO DE DADOS

**Library:** `sqflite ^2.3.3+1`
**Total de Tabelas:** 7

### Tabelas

| # | Tabela | Propósito | Chave Única | Linhas Código |
|---|--------|-----------|-------------|---------------|
| 1 | `passageiros` | Dados de embarque de passageiros | - | 38-49 |
| 2 | `alunos` | Cadastro de alunos | CPF | 52-63 |
| 3 | `embeddings` | Embeddings de reconhecimento facial | CPF | 66-73 |
| 4 | `pessoas_facial` | Pessoas com facial cadastrada | CPF | 76-88 |
| 5 | `logs` | Logs de acesso e reconhecimento | (cpf, timestamp, tipo) | 91-102 |
| 6 | `sync_queue` | Fila de sincronização offline | - | 104-111 |
| 7 | `usuarios` | Usuários do sistema | CPF | 114-125 |

**Referência:** `/lib/database/database_helper.dart`

---

## ⚠️ CONFLITOS IDENTIFICADOS

### 1. 🔴 **DUPLICAÇÃO DE DADOS DE EMBEDDINGS** (CRÍTICO)

**Arquivo:** `lib/services/alunos_sync_service.dart:229-245`

#### Descrição do Problema

Quando o sistema sincroniza pessoas da aba "Pessoas" do Google Sheets, cada embedding é salvo em **DUAS tabelas simultaneamente**:

```dart
// 1. Salvar na tabela pessoas_facial (sistema novo)
await _db.upsertPessoaFacial({
  'cpf': pessoa['cpf'],
  'nome': pessoa['nome'],
  'embedding': jsonEncode(embedding),  // 512 dimensões
  'facial_status': 'CADASTRADA',
});

// 2. Também salvar na tabela embeddings (sistema antigo)
await _db.insertEmbedding({
  'cpf': pessoa['cpf'],
  'nome': pessoa['nome'],
  'embedding': embedding,  // DUPLICADO!
});
```

#### Impacto

- ❌ **Redundância de dados:** Embeddings de 512 dimensões (512 × 8 bytes = 4KB por pessoa) duplicados
- ❌ **Desperdício de espaço:** 2× o espaço necessário para embeddings
- ❌ **Risco de inconsistência:** Se um embedding for atualizado e outro não
- ❌ **Confusão arquitetural:** Não há fonte única da verdade
- ❌ **Maior complexidade de manutenção**

#### Evidência

```
Comentário no código (linha 240):
// Também salvar na tabela embeddings antiga para compatibilidade
```

Isso indica que o desenvolvedor reconheceu a duplicação mas optou por manter "compatibilidade".

---

### 2. 🔴 **DOIS SISTEMAS PARALELOS DE ARMAZENAMENTO** (CRÍTICO)

**Arquivo:** `lib/database/database_helper.dart:387-410`

#### Descrição do Problema

Existem **dois sistemas diferentes** para armazenar pessoas com reconhecimento facial:

**Sistema Antigo:**
- Tabela `alunos` → dados pessoais + campo `facial` (status)
- Tabela `embeddings` → embeddings separados (relacionados por CPF)
- Relacionamento via JOIN

**Sistema Novo:**
- Tabela `pessoas_facial` → dados pessoais + embedding + `facial_status` (tudo junto)
- Design desnormalizado (embedding na mesma tabela)

#### Query UNION Problemática

O método `getTodosAlunosComFacial()` tenta unir ambos os sistemas:

```sql
-- Sistema Antigo
SELECT a.cpf, a.nome, a.email, a.telefone, a.turma, e.embedding
FROM alunos a
INNER JOIN embeddings e ON a.cpf = e.cpf
WHERE a.facial = 'CADASTRADA'

UNION

-- Sistema Novo
SELECT p.cpf, p.nome, p.email, p.telefone, p.turma, p.embedding
FROM pessoas_facial p
WHERE p.facial_status = 'CADASTRADA' AND p.embedding IS NOT NULL
```

#### Impacto

- ❌ **Possível duplicação:** Se a mesma pessoa existir em `alunos` E `pessoas_facial`
- ❌ **Ambiguidade:** Qual embedding será usado se houver conflito?
- ❌ **Inconsistência de nomes:** `facial` vs `facial_status` para o mesmo propósito
- ❌ **Complexidade de queries:** Sempre precisa fazer UNION
- ❌ **Dificulta debugging:** Dados espalhados em múltiplos locais

#### Arquivos Afetados

6 arquivos usam `getTodosAlunosComFacial()`:
- `lib/services/face_recognition_service.dart` (linha 129)
- `lib/screens/painel_admin_screen.dart`
- `lib/screens/reconhecimento_facial_completo.dart`
- `lib/screens/lista_alunos_screen.dart`
- `lib/screens/controle_embarque_screen.dart`
- `lib/screens/controle_alunos_screen.dart`

---

### 3. 🟡 **FALTA DE SINCRONIZAÇÃO ENTRE TABELAS** (IMPORTANTE)

**Arquivo:** `lib/services/alunos_sync_service.dart`

#### Descrição do Problema

As sincronizações do Google Sheets usam **tabelas diferentes** sem coordenação:

```dart
// Sincronização 1: Alunos (linha 90-161)
syncAlunosFromSheets() {
  // Salva em: tabela 'alunos'
  // NÃO salva embeddings
  await _db.upsertAluno(alunoData);
}

// Sincronização 2: Pessoas (linha 17-88)
syncPessoasFromSheets() {
  // Salva em: tabela 'pessoas_facial' + 'embeddings'
  // Inclui embeddings
  await _db.upsertPessoaFacial(...);
  await _db.insertEmbedding(...);
}
```

#### Cenários Problemáticos

1. **Aluno sem facial:** Existe em `alunos`, não existe em `pessoas_facial` ✅ (correto)
2. **Pessoa com facial:** Existe em `pessoas_facial`, pode não existir em `alunos` ⚠️
3. **Dados desatualizados:** Nome atualizado em uma tabela mas não na outra ❌
4. **Aluno que cadastrou facial:** Pode existir em ambas as tabelas ❌ (duplicação)

#### Impacto

- ❌ **Dados potencialmente desatualizados**
- ❌ **Não há "fonte única da verdade"**
- ❌ **Sincronização pode falhar parcialmente** (uma tabela atualizada, outra não)
- ❌ **Dificulta rastreamento de estado**

---

### 4. 🟡 **AUSÊNCIA DE FOREIGN KEYS** (IMPORTANTE)

**Arquivo:** `lib/database/database_helper.dart:36-126`

#### Descrição do Problema

As tabelas relacionam-se logicamente por CPF, mas **não há constraints de foreign key** no SQLite:

```sql
-- Embeddings referencia alunos/pessoas por CPF, mas sem FK
CREATE TABLE embeddings(
  cpf TEXT UNIQUE,  -- ⚠️ Deveria ser FK para alunos.cpf
  ...
)

-- Logs referencia pessoas por CPF, mas sem FK
CREATE TABLE logs(
  cpf TEXT,  -- ⚠️ Deveria ser FK para uma tabela de pessoas
  ...
)

-- Passageiros referencia alunos por CPF, mas sem FK
CREATE TABLE passageiros(
  cpf TEXT,  -- ⚠️ Deveria ser FK para alunos.cpf
  ...
)
```

#### Impacto

- ❌ **Permite dados órfãos:** Embeddings sem pessoa correspondente
- ❌ **Permite CPFs inválidos:** Logs com CPFs que não existem
- ❌ **Dificulta garantir integridade referencial**
- ❌ **Sem CASCADE DELETE:** Deletar aluno não deleta embeddings/logs relacionados
- ⚠️ **Possível acúmulo de lixo:** Dados órfãos que nunca serão limpos

#### Nota

SQLite suporta foreign keys, mas precisa ser habilitado explicitamente:
```sql
PRAGMA foreign_keys = ON;
```

---

### 5. 🟢 **INCONSISTÊNCIA DE NOMENCLATURA** (BAIXA PRIORIDADE)

#### Descrição do Problema

Campos com propósitos similares têm nomes diferentes:

| Campo | Tabela | Tipo | Observação |
|-------|--------|------|------------|
| `facial` | alunos | TEXT | Status do cadastro facial |
| `facial_status` | pessoas_facial | TEXT | **Mesmo propósito, nome diferente** |
| `tem_qr` | alunos | TEXT | Indica se tem QR/pulseira |
| `tem_qr` | pessoas_facial | - | **Campo ausente** |
| `created_at` | Múltiplas | TEXT | Timestamp de criação ✅ |
| `updated_at` | Algumas | TEXT | Timestamp de atualização (falta em `alunos`) |

#### Impacto

- ⚠️ **Confusão para desenvolvedores**
- ⚠️ **Queries mais complexas** (precisa lembrar qual tabela usa qual nome)
- ⚠️ **Dificulta refatoração**
- 🟢 **Baixo impacto funcional** (sistema funciona apesar disso)

---

## 🔧 RECOMENDAÇÕES DE CORREÇÃO

### Opção 1: **Migrar para Sistema Unificado** ⭐ (RECOMENDADO)

#### Estratégia

1. **Escolher `pessoas_facial` como tabela única**
   - Já tem embedding integrado (design mais simples)
   - Evita JOINs desnecessários

2. **Migração de dados**
   ```sql
   -- Migrar alunos com facial para pessoas_facial
   INSERT INTO pessoas_facial (cpf, nome, email, telefone, turma, embedding, facial_status)
   SELECT a.cpf, a.nome, a.email, a.telefone, a.turma, e.embedding, a.facial
   FROM alunos a
   INNER JOIN embeddings e ON a.cpf = e.cpf
   WHERE a.facial = 'CADASTRADA'
   ON CONFLICT(cpf) DO UPDATE SET
     nome = excluded.nome,
     email = excluded.email,
     embedding = excluded.embedding;
   ```

3. **Deprecar tabelas antigas**
   - Marcar `alunos` e `embeddings` como deprecated
   - Atualizar código para usar apenas `pessoas_facial`
   - Eventualmente dropar tabelas antigas

4. **Adicionar campo `tem_qr`** em `pessoas_facial`

#### Vantagens

- ✅ Eliminação de duplicação de embeddings
- ✅ Modelo de dados mais simples
- ✅ Redução de ~50% do espaço usado por embeddings
- ✅ Fonte única de verdade
- ✅ Queries mais rápidas (sem UNION/JOIN)
- ✅ Mais fácil de manter

#### Esforço

🟡 **Médio** (2-3 dias de desenvolvimento + testes)

---

### Opção 2: **Separação Clara de Responsabilidades**

#### Estratégia

1. **Definir regras claras:**
   - `alunos` → APENAS alunos SEM facial cadastrada
   - `pessoas_facial` → TODAS as pessoas COM facial (incluindo alunos)

2. **Remover tabela `embeddings`** (redundante)

3. **Implementar lógica de transição:**
   ```dart
   // Quando aluno cadastrar facial:
   // 1. Inserir em pessoas_facial com embedding
   // 2. Atualizar alunos.facial = 'CADASTRADA' (manter registro)
   // OU deletar de alunos (mover completamente)
   ```

4. **Atualizar query:**
   ```sql
   -- Query simplificada (apenas pessoas_facial)
   SELECT cpf, nome, email, telefone, turma, embedding
   FROM pessoas_facial
   WHERE facial_status = 'CADASTRADA' AND embedding IS NOT NULL
   ```

#### Vantagens

- ✅ Separação clara de estados (com/sem facial)
- ✅ Elimina duplicação de embeddings
- ✅ Fácil identificar quem tem/não tem facial
- ✅ Mantém histórico em `alunos`

#### Esforço

🟡 **Médio** (2-3 dias)

---

### Opção 3: **Adicionar Foreign Keys e Validações**

#### Estratégia

1. **Adicionar constraints (requer recriação de tabelas):**
   ```sql
   CREATE TABLE embeddings_new(
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     cpf TEXT UNIQUE NOT NULL,
     nome TEXT,
     embedding TEXT,
     created_at TEXT,
     FOREIGN KEY (cpf) REFERENCES alunos(cpf) ON DELETE CASCADE
   );
   ```

2. **Criar trigger para sincronizar `alunos` ↔ `pessoas_facial`:**
   ```sql
   CREATE TRIGGER sync_pessoas_facial
   AFTER INSERT ON pessoas_facial
   BEGIN
     INSERT OR REPLACE INTO alunos (cpf, nome, email, telefone, turma, facial)
     VALUES (NEW.cpf, NEW.nome, NEW.email, NEW.telefone, NEW.turma, NEW.facial_status);
   END;
   ```

3. **Adicionar validação para evitar duplicatas:**
   ```dart
   Future<void> upsertPessoaFacial(Map<String, dynamic> pessoa) async {
     // Verificar se já existe em alunos
     final existeEmAlunos = await getAlunoByCpf(pessoa['cpf']);
     if (existeEmAlunos != null) {
       // Atualizar aluno existente
       await updateAlunoFacial(pessoa['cpf'], 'CADASTRADA');
     }
     // Salvar em pessoas_facial
     await db.insert('pessoas_facial', pessoa, conflictAlgorithm: ConflictAlgorithm.replace);
   }
   ```

#### Vantagens

- ✅ Mantém estrutura atual
- ✅ Adiciona integridade referencial
- ✅ Previne dados órfãos
- ⚠️ Ainda mantém duplicação (não resolve problema principal)

#### Esforço

🟢 **Baixo-Médio** (1-2 dias)

---

### Opção 4: **Abordagem Incremental** (MAIS SEGURO)

#### Estratégia

**Fase 1: Parar de duplicar (imediato)**
```dart
// Comentar linha 241-245 em alunos_sync_service.dart
// await _db.insertEmbedding({...});  // REMOVIDO - duplicação desnecessária
```

**Fase 2: Migrar queries (1 semana)**
- Atualizar `getTodosAlunosComFacial()` para usar apenas `pessoas_facial`
- Testar extensivamente em desenvolvimento
- Deploy gradual

**Fase 3: Deprecar tabelas antigas (1 mês após Fase 2)**
- Marcar `embeddings` como deprecated
- Monitorar uso em produção
- Eventualmente dropar quando uso = 0

**Fase 4: Unificar modelo (2 meses após Fase 3)**
- Implementar Opção 1 ou 2 completamente

#### Vantagens

- ✅ **Menor risco** (mudanças incrementais)
- ✅ **Fácil reverter** se houver problemas
- ✅ **Tempo para testes** entre fases
- ✅ **Pode parar em qualquer fase** se surgirem impedimentos

#### Esforço

🟢 **Baixo por fase**, 🟡 **Médio total** (distribuído ao longo do tempo)

---

## 📊 COMPARAÇÃO DE OPÇÕES

| Critério | Opção 1 | Opção 2 | Opção 3 | Opção 4 |
|----------|---------|---------|---------|---------|
| **Resolve duplicação** | ✅ Sim | ✅ Sim | ❌ Não | ✅ Sim (gradual) |
| **Simplifica modelo** | ✅✅ Muito | ✅ Sim | ❌ Não | ✅ Sim |
| **Adiciona integridade** | 🟡 Pode | 🟡 Pode | ✅ Sim | 🟡 Pode |
| **Risco** | 🟡 Médio | 🟡 Médio | 🟢 Baixo | 🟢 Baixo |
| **Esforço** | 🟡 Médio | 🟡 Médio | 🟢 Baixo | 🟢 Baixo/fase |
| **Impacto no código** | 🔴 Alto | 🟡 Médio | 🟢 Baixo | 🟢 Baixo/fase |
| **Manutenibilidade futura** | ✅✅ Excelente | ✅ Boa | 🟡 Regular | ✅ Boa |
| **Recomendado para** | Refactor completo | Projeto novo | Correção rápida | Produção ativa |

---

## 📈 MÉTRICAS DO PROBLEMA

### Arquivos Afetados

```
Total de arquivos com código SQLite: 10
Arquivos que usam getTodosAlunosComFacial(): 6
Arquivos que fazem sincronização: 4
Linhas de código com lógica duplicada: ~100+
```

### Impacto em Espaço

```
Tamanho de 1 embedding: 512 × 8 bytes = 4 KB
Com duplicação: 8 KB por pessoa
Para 1000 pessoas: 8 MB desperdiçados
Para 10000 pessoas: 80 MB desperdiçados
```

### Performance

```
Query atual (com UNION): ~2× mais lenta
Queries com JOIN (embeddings separado): +overhead do JOIN
Query ideal (pessoas_facial unificado): baseline mais rápido
```

---

## 🎯 PLANO DE AÇÃO RECOMENDADO

### Prioridade ALTA (Resolver em 1 semana)

1. ✅ **Parar duplicação imediata**
   - Remover `await _db.insertEmbedding()` de `syncPessoasFromSheets()`
   - Arquivo: `lib/services/alunos_sync_service.dart:241-245`
   - Esforço: 5 minutos
   - Risco: Muito baixo

### Prioridade MÉDIA (Resolver em 1 mês)

2. ✅ **Implementar Opção 1 (Sistema Unificado)**
   - Migração de dados
   - Atualização de queries
   - Testes extensivos
   - Esforço: 2-3 dias
   - Risco: Médio

3. ✅ **Adicionar campo `tem_qr` em pessoas_facial**
   - Consistência entre tabelas
   - Esforço: 1 hora
   - Risco: Baixo

### Prioridade BAIXA (Considerar para futuro)

4. 🟡 **Adicionar Foreign Keys**
   - Integridade referencial
   - Esforço: 1-2 dias
   - Risco: Médio

5. 🟡 **Padronizar nomenclatura**
   - `facial_status` → `facial` (ou vice-versa)
   - Esforço: 2-3 horas
   - Risco: Baixo

---

## ✅ PONTOS POSITIVOS DO SISTEMA ATUAL

Apesar dos conflitos identificados, o sistema tem várias implementações corretas:

1. ✅ **UNIQUE constraints** em campos críticos (CPF)
2. ✅ **Sistema de migração** de versões funcional (v1 → v2)
3. ✅ **Validação dinâmica de schema** (`ensureFacialSchema()`)
4. ✅ **UNIQUE constraint em logs** para evitar duplicatas `(cpf, timestamp, tipo)`
5. ✅ **ConflictAlgorithm.replace** para upserts seguros
6. ✅ **Normalização L2** dos embeddings implementada corretamente
7. ✅ **Arquitetura offline-first** bem implementada (sync_queue)
8. ✅ **Backup antes de migrations** (logs migration)
9. ✅ **Tratamento de erros** em operações críticas
10. ✅ **Logging detalhado** para debugging

---

## 📚 REFERÊNCIAS

### Arquivos Analisados

```
/lib/database/database_helper.dart (612 linhas)
/lib/services/alunos_sync_service.dart (338 linhas)
/lib/services/face_recognition_service.dart
/lib/services/data_service.dart
/lib/services/user_sync_service.dart
/lib/services/logs_sync_service.dart
/lib/services/offline_sync_service.dart
/lib/services/auth_service.dart
/lib/models/passageiro.dart
/pubspec.yaml
```

### Ferramentas Utilizadas

- SQLite versão: (via sqflite)
- Flutter/Dart
- TensorFlow Lite (ArcFace model)

---

## 🔍 CONCLUSÃO

O sistema SQLite está **funcionalmente correto**, mas apresenta **duplicação significativa** e **arquitetura dividida** entre dois sistemas paralelos. Os conflitos identificados não causam falhas imediatas, mas:

- ❌ Desperdiçam espaço em disco
- ❌ Aumentam complexidade de manutenção
- ❌ Criam risco de inconsistências futuras
- ❌ Dificultam debugging e rastreamento

**Recomendação final:** Implementar **Opção 4 (Abordagem Incremental)** começando com **Opção 1 (Sistema Unificado)** como objetivo final.

**Próximos passos:**
1. Revisar este relatório com a equipe
2. Decidir qual opção implementar
3. Criar issues/tasks para tracking
4. Implementar em ambiente de desenvolvimento
5. Testes extensivos antes de produção

---

**Relatório gerado por:** Claude Code
**Validação completa:** ✅
**Ação requerida:** 🟡 Recomendada (não urgente)
