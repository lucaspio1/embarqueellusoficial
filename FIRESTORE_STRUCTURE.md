# Estrutura do Firestore - Sistema Embarque Ellus

Este documento descreve a estrutura completa do banco de dados Firestore utilizado pelo sistema.

## 📊 Visão Geral

O Firestore substitui o Google Sheets como banco de dados central, oferecendo:
- ✅ Sincronização em tempo real
- ✅ Escalabilidade automática
- ✅ Queries mais eficientes
- ✅ Segurança robusta com regras
- ✅ Offline-first nativo

## 🗂️ Coleções Principais

### 1. `usuarios` - Usuários do Sistema

Armazena informações de login e autenticação.

**Documento ID**: `{user_id}` (ex: `user_admin_001`, ou auto-gerado)

**Campos**:
```javascript
{
  // ⚠️ NÃO incluir user_id como campo - o Document ID já é o user_id!
  nome: string,              // Nome completo
  cpf: string,               // CPF (único)
  senha_hash: string,        // Hash SHA-256 da senha
  perfil: string,            // "ADMIN" | "USUARIO"
  ativo: boolean,            // true/false
  created_at: timestamp,     // Data de criação
  updated_at: timestamp      // Última atualização
}
```

**Índices necessários**:
- `cpf` (único)
- `ativo`

**Exemplo**:

**Document ID**: `user_12345`

**Campos**:
```javascript
{
  nome: "João Silva",
  cpf: "12345678900",
  senha_hash: "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8",
  perfil: "ADMIN",
  ativo: true,
  created_at: "2025-01-15T10:00:00Z",
  updated_at: "2025-01-15T10:00:00Z"
}
```

**📝 Nota**: O código lê o Document ID do Firestore e o salva como `user_id` no banco SQLite local (`lib/services/firebase_service.dart:140`).

---

### 2. `alunos` - Cadastro Geral de Alunos

Armazena o cadastro geral de alunos (equivalente à aba ALUNOS do Google Sheets).

**Documento ID**: `{cpf}` (CPF é a chave primária)

**Campos**:
```javascript
{
  cpf: string,               // CPF (chave primária)
  nome: string,              // Nome completo
  colegio: string,           // Nome do colégio
  turma: string,             // Turma
  email: string,             // Email
  telefone: string,          // Telefone
  facial_status: string,     // "NAO" | "CADASTRADA"
  tem_qr: boolean,           // Possui QR Code?
  inicio_viagem: string,     // Data início (formato: dd/MM/yyyy)
  fim_viagem: string,        // Data fim (formato: dd/MM/yyyy)
  created_at: timestamp,     // Data de criação
  updated_at: timestamp      // Última atualização
}
```

**Índices necessários**:
- `colegio`
- `turma`
- `inicio_viagem + fim_viagem` (composto)
- `facial_status`

**Exemplo**:
```javascript
{
  cpf: "98765432100",
  nome: "Maria Santos",
  colegio: "Colégio ABC",
  turma: "3A",
  email: "maria@exemplo.com",
  telefone: "(11) 98765-4321",
  facial_status: "CADASTRADA",
  tem_qr: true,
  inicio_viagem: "01/02/2025",
  fim_viagem: "10/02/2025",
  created_at: "2025-01-15T10:00:00Z",
  updated_at: "2025-01-15T10:00:00Z"
}
```

---

### 3. `pessoas` - Pessoas com Reconhecimento Facial

Armazena pessoas com cadastro facial e embeddings (equivalente à aba PESSOAS do Google Sheets).

**Documento ID**: `{cpf}` (CPF é a chave primária)

**Campos**:
```javascript
{
  cpf: string,               // CPF (chave primária)
  nome: string,              // Nome completo
  colegio: string,           // Nome do colégio
  turma: string,             // Turma
  email: string,             // Email
  telefone: string,          // Telefone
  embedding: array<double>,  // Array de 512 floats (embedding facial ArcFace)
  facial_status: string,     // "CADASTRADA" (sempre)
  movimentacao: string,      // "QUARTO" | "FESTA" | "PRAIA"
  inicio_viagem: string,     // Data início (formato: dd/MM/yyyy)
  fim_viagem: string,        // Data fim (formato: dd/MM/yyyy)
  created_at: timestamp,     // Data de criação
  updated_at: timestamp      // Última atualização
}
```

**Índices necessários**:
- `colegio`
- `turma`
- `movimentacao`
- `inicio_viagem + fim_viagem` (composto)

**Exemplo**:
```javascript
{
  cpf: "98765432100",
  nome: "Maria Santos",
  colegio: "Colégio ABC",
  turma: "3A",
  email: "maria@exemplo.com",
  telefone: "(11) 98765-4321",
  embedding: [0.123, -0.456, 0.789, ...], // 512 valores
  facial_status: "CADASTRADA",
  movimentacao: "QUARTO",
  inicio_viagem: "01/02/2025",
  fim_viagem: "10/02/2025",
  created_at: "2025-01-15T10:00:00Z",
  updated_at: "2025-01-15T10:00:00Z"
}
```

---

### 4. `logs` - Histórico de Movimentações

Armazena o histórico completo de movimentações (reconhecimento facial, QR Code, manual).

**Documento ID**: Auto-gerado

**Campos**:
```javascript
{
  cpf: string,               // CPF da pessoa
  person_name: string,       // Nome da pessoa
  timestamp: timestamp,      // Data/hora da movimentação
  confidence: number,        // Confiança do reconhecimento (0.0 a 1.0)
  tipo: string,              // "RECONHECIMENTO" | "QR" | "MANUAL"
  operador_nome: string,     // Nome do operador (vazio se automático)
  colegio: string,           // Nome do colégio
  turma: string,             // Turma
  inicio_viagem: string,     // Data início da viagem
  fim_viagem: string,        // Data fim da viagem
  created_at: timestamp      // Data de criação
}
```

**Índices necessários**:
- `cpf`
- `timestamp` (descendente)
- `tipo`
- `inicio_viagem + fim_viagem` (composto)
- `colegio`

**Exemplo**:
```javascript
{
  cpf: "98765432100",
  person_name: "Maria Santos",
  timestamp: "2025-01-15T14:30:00Z",
  confidence: 0.95,
  tipo: "RECONHECIMENTO",
  operador_nome: "",
  colegio: "Colégio ABC",
  turma: "3A",
  inicio_viagem: "01/02/2025",
  fim_viagem: "10/02/2025",
  created_at: "2025-01-15T14:30:00Z"
}
```

---

### 5. `quartos` - Hospedagem/Quartos

Armazena informações de alocação de quartos (equivalente à aba HOMELIST do Google Sheets).

**Documento ID**: Auto-gerado ou `{cpf}_{numero_quarto}`

**Campos**:
```javascript
{
  numero_quarto: string,     // Número do quarto
  escola: string,            // Nome da escola
  nome_hospede: string,      // Nome do hóspede
  cpf: string,               // CPF do hóspede
  inicio_viagem: string,     // Data início da viagem
  fim_viagem: string,        // Data fim da viagem
  created_at: timestamp,     // Data de criação
  updated_at: timestamp      // Última atualização
}
```

**Índices necessários**:
- `cpf`
- `numero_quarto`
- `escola`
- `inicio_viagem + fim_viagem` (composto)

**Exemplo**:
```javascript
{
  numero_quarto: "101",
  escola: "Colégio ABC",
  nome_hospede: "Maria Santos",
  cpf: "98765432100",
  inicio_viagem: "01/02/2025",
  fim_viagem: "10/02/2025",
  created_at: "2025-01-15T10:00:00Z",
  updated_at: "2025-01-15T10:00:00Z"
}
```

---

### 6. `embarques` - Listas de Embarque/Passeios

Armazena listas de passageiros por passeio e ônibus (equivalente à aba EMBARQUES do Google Sheets).

**Documento ID**: `{cpf}_{idPasseio}_{onibus}`

**Campos**:
```javascript
{
  nome: string,              // Nome do passageiro
  cpf: string,               // CPF
  colegio: string,           // Nome do colégio
  turma: string,             // Turma
  idPasseio: string,         // ID do passeio
  onibus: string,            // Número do ônibus
  embarque: string,          // Status de embarque ("SIM" | "NAO" | "")
  retorno: string,           // Status de retorno ("SIM" | "NAO" | "")
  inicioViagem: string,      // Data início da viagem
  fimViagem: string,         // Data fim da viagem
  created_at: timestamp,     // Data de criação
  updated_at: timestamp      // Última atualização
}
```

**Índices necessários**:
- `colegio + idPasseio + onibus` (composto)
- `cpf`
- `idPasseio`

**Exemplo**:
```javascript
{
  nome: "Maria Santos",
  cpf: "98765432100",
  colegio: "Colégio ABC",
  turma: "3A",
  idPasseio: "PRAIA_2025_02_01",
  onibus: "1",
  embarque: "SIM",
  retorno: "NAO",
  inicioViagem: "01/02/2025",
  fimViagem: "10/02/2025",
  created_at: "2025-01-15T10:00:00Z",
  updated_at: "2025-01-15T14:30:00Z"
}
```

---

### 7. `eventos` - Notificações de Ações Críticas

Armazena eventos importantes do sistema (encerramento de viagens, etc.).

**Documento ID**: Auto-gerado

**Campos**:
```javascript
{
  tipo_evento: string,       // "viagem_encerrada" | outros
  dados: map,                // Dados adicionais do evento
  inicio_viagem: string,     // Data início da viagem (se aplicável)
  fim_viagem: string,        // Data fim da viagem (se aplicável)
  processado: boolean,       // Evento já foi processado?
  timestamp: timestamp,      // Data/hora do evento
  created_at: timestamp      // Data de criação
}
```

**Índices necessários**:
- `processado`
- `tipo_evento`
- `timestamp` (descendente)

**Exemplo**:
```javascript
{
  tipo_evento: "viagem_encerrada",
  dados: {
    motivo: "Fim do período de viagem"
  },
  inicio_viagem: "01/02/2025",
  fim_viagem: "10/02/2025",
  processado: false,
  timestamp: "2025-02-10T23:59:59Z",
  created_at: "2025-02-10T23:59:59Z"
}
```

---

## 🔐 Regras de Segurança do Firestore

**IMPORTANTE**: Configure as seguintes regras de segurança no Firebase Console:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Permitir leitura e escrita em todas as coleções (modo desenvolvimento)
    // ⚠️ ATENÇÃO: Em produção, restrinja essas regras!
    match /{document=**} {
      allow read, write: if true;
    }

    // Regras sugeridas para produção:
    /*
    match /usuarios/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    match /alunos/{cpf} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }

    match /pessoas/{cpf} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }

    match /logs/{logId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if false;
    }

    match /quartos/{quartoId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }

    match /embarques/{embarqueId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }

    match /eventos/{eventoId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null;
    }
    */
  }
}
```

---

## 📈 Otimizações e Boas Práticas

### Índices Compostos Necessários

Configure os seguintes índices compostos no Firebase Console:

1. **alunos**:
   - `inicio_viagem (Ascending)` + `fim_viagem (Ascending)`

2. **pessoas**:
   - `inicio_viagem (Ascending)` + `fim_viagem (Ascending)`
   - `colegio (Ascending)` + `movimentacao (Ascending)`

3. **logs**:
   - `inicio_viagem (Ascending)` + `fim_viagem (Ascending)`
   - `cpf (Ascending)` + `timestamp (Descending)`

4. **quartos**:
   - `inicio_viagem (Ascending)` + `fim_viagem (Ascending)`

5. **embarques**:
   - `colegio (Ascending)` + `idPasseio (Ascending)` + `onibus (Ascending)`

### Limites de Taxa

- **Leitura**: 50.000 documentos/dia (plano gratuito)
- **Escrita**: 20.000 documentos/dia (plano gratuito)
- **Storage**: 1 GB (plano gratuito)

### Cache Offline

O Firebase SDK automaticamente:
- ✅ Mantém cache local dos dados
- ✅ Sincroniza quando online
- ✅ Permite operações offline
- ✅ Resolve conflitos automaticamente

---

## 🔄 Migração do Google Sheets

### Dados que NÃO migram automaticamente

Os seguintes dados do Google Sheets precisam ser migrados manualmente:

1. **Usuários** (LOGIN) - Criar no Firestore manualmente
2. **Alunos** (ALUNOS) - Importar via script
3. **Pessoas** (PESSOAS) - Importar via script (com embeddings)
4. **Logs** (LOGS) - Histórico pode ser importado se necessário
5. **Quartos** (HOMELIST) - Importar via script
6. **Embarques** (EMBARQUES) - Importar via script

### Script de Migração

Veja o arquivo `FIREBASE_SETUP.md` para instruções de migração.

---

## 📝 Notas Importantes

1. **Embeddings Faciais**: Os arrays de 512 floats são armazenados como arrays nativos do Firestore
2. **Timestamps**: Use `FieldValue.serverTimestamp()` para garantir sincronização precisa
3. **CPF como Chave**: CPF é usado como ID de documento para alunos e pessoas (facilita lookups)
4. **Viagens**: Use sempre o formato `dd/MM/yyyy` para datas de viagem
5. **Backup**: Configure backups automáticos no Firebase Console
