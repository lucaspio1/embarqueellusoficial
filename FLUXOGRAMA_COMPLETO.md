# 🗺️ FLUXOGRAMA COMPLETO DO SISTEMA ELLUS

## 📑 Índice
1. [Arquitetura Geral](#1-arquitetura-geral)
2. [Banco de Dados SQLite](#2-banco-de-dados-sqlite)
3. [Conexões com Google Sheets](#3-conexões-com-google-sheets)
4. [Mapa de Navegação](#4-mapa-de-navegação)
5. [Fluxo de Autenticação](#5-fluxo-de-autenticação)
6. [Fluxo de Embarque](#6-fluxo-de-embarque)
7. [Fluxo de Reconhecimento Facial](#7-fluxo-de-reconhecimento-facial)
8. [Fluxo de Cadastro Facial](#8-fluxo-de-cadastro-facial)
9. [Fluxo de Sincronização](#9-fluxo-de-sincronização)
10. [Serviços e suas Funções](#10-serviços-e-suas-funções)

---

## 1. ARQUITETURA GERAL

```mermaid
graph TB
    subgraph "CAMADA DE APRESENTAÇÃO"
        UI[Telas Flutter]
    end

    subgraph "CAMADA DE SERVIÇOS"
        DataService[DataService<br/>Gerencia lista embarque]
        AuthService[AuthService<br/>Autenticação]
        FaceService[FaceRecognitionService<br/>IA Facial]
        OfflineSync[OfflineSyncService<br/>Fila de sincronização]
        AlunosSync[AlunosSyncService<br/>Sync alunos/pessoas]
        UserSync[UserSyncService<br/>Sync usuários]
    end

    subgraph "CAMADA DE DADOS LOCAL"
        SQLite[(SQLite<br/>7 Tabelas)]
        SharedPrefs[SharedPreferences]
        TFLite[Modelo ArcFace<br/>arcface.tflite]
    end

    subgraph "CAMADA EXTERNA"
        GAS[Google Apps Script]
        Sheets[(Google Sheets<br/>3 Abas)]
    end

    UI --> DataService
    UI --> AuthService
    UI --> FaceService
    UI --> OfflineSync
    UI --> AlunosSync

    DataService --> SQLite
    DataService --> SharedPrefs
    DataService --> GAS

    AuthService --> SQLite
    AuthService --> GAS

    FaceService --> SQLite
    FaceService --> TFLite

    OfflineSync --> SQLite
    OfflineSync --> GAS

    AlunosSync --> SQLite
    AlunosSync --> GAS

    UserSync --> SQLite
    UserSync --> GAS

    GAS --> Sheets

    style UI fill:#e1f5ff
    style SQLite fill:#fff4e1
    style GAS fill:#e8f5e9
    style Sheets fill:#e8f5e9
```

---

## 2. BANCO DE DADOS SQLite

### 2.1 Diagrama de Tabelas

```mermaid
erDiagram
    PASSAGEIROS {
        int id PK
        text nome
        text cpf
        text id_passeio
        text turma
        text embarque
        text retorno
        text onibus
        text codigo_pulseira
    }

    ALUNOS {
        int id PK
        text cpf UK
        text nome
        text email
        text telefone
        text turma
        text facial
        text tem_qr
        text created_at
    }

    PESSOAS_FACIAL {
        int id PK
        text cpf UK
        text nome
        text email
        text telefone
        text turma
        text embedding
        text facial_status
        text created_at
        text updated_at
    }

    EMBEDDINGS {
        int id PK
        text cpf UK
        text nome
        text embedding
        text created_at
    }

    LOGS {
        int id PK
        text cpf
        text person_name
        text timestamp
        real confidence
        text tipo
        text created_at
    }

    SYNC_QUEUE {
        int id PK
        text tipo
        text payload
        text created_at
    }

    USUARIOS {
        int id PK
        text user_id
        text nome
        text cpf UK
        text senha_hash
        text perfil
        int ativo
        text created_at
        text updated_at
    }

    PASSAGEIROS ||--o{ ALUNOS : "sincroniza para"
    ALUNOS ||--o{ PESSOAS_FACIAL : "cadastro facial"
    PESSOAS_FACIAL ||--|| EMBEDDINGS : "armazena"
    EMBEDDINGS ||--o{ LOGS : "usa para reconhecer"
```

### 2.2 Descrição das Tabelas

| Tabela | Propósito | Origem | Ciclo de Vida |
|--------|-----------|--------|---------------|
| **passageiros** | Lista temporária de embarque do passeio atual | Google Sheets (aba Embarque) | Limpa ao trocar passeio |
| **alunos** | Alunos que possuem QR/pulseira cadastrada | Copiado de passageiros + Sync da aba Alunos | Persiste entre passeios |
| **pessoas_facial** | **NOVO** Banco permanente de pessoas com facial | Aba Pessoas do Google Sheets | Permanente |
| **embeddings** | Cache de embeddings para reconhecimento rápido | Gerado localmente + Sync da aba Pessoas | Persiste |
| **logs** | Histórico de reconhecimentos faciais | Gerado localmente | Persiste |
| **sync_queue** | Fila de sincronização offline | Gerado localmente | Limpa após sync |
| **usuarios** | Usuários do sistema (login) | Aba Usuários do Google Sheets | Permanente |

---

## 3. CONEXÕES COM GOOGLE SHEETS

```mermaid
graph LR
    subgraph "Google Sheets"
        AbaEmbarque[(Aba: Embarque<br/>Lista do passeio)]
        AbaAlunos[(Aba: Alunos<br/>Cadastro geral)]
        AbaPessoas[(Aba: Pessoas<br/>Facial cadastrada)]
        AbaUsuarios[(Aba: Usuários<br/>Login)]
    end

    subgraph "Google Apps Script - ACTIONS"
        GetEmbarque[GET: Buscar lista embarque]
        UpdateEmbarque[POST: Atualizar status embarque/retorno]
        GetAlunos[POST: getAllStudents]
        GetPessoas[POST: getAllPeople]
        AddPessoa[POST: addPessoa]
        GetUsuarios[POST: getAllUsers]
        Login[POST: login]
        AddLog[POST: addMovementLog]
    end

    subgraph "App Flutter - Serviços"
        DataService[DataService]
        AlunosSync[AlunosSyncService]
        OfflineSync[OfflineSyncService]
        UserSync[UserSyncService]
        AuthSvc[AuthService]
    end

    AbaEmbarque --> GetEmbarque
    GetEmbarque --> DataService
    DataService --> UpdateEmbarque
    UpdateEmbarque --> AbaEmbarque

    AbaAlunos --> GetAlunos
    GetAlunos --> AlunosSync

    AbaPessoas --> GetPessoas
    GetPessoas --> AlunosSync
    OfflineSync --> AddPessoa
    AddPessoa --> AbaPessoas

    OfflineSync --> AddLog
    AddLog --> AbaEmbarque

    AbaUsuarios --> GetUsuarios
    GetUsuarios --> UserSync
    AuthSvc --> Login
    Login --> AbaUsuarios

    style AbaEmbarque fill:#fff3cd
    style AbaAlunos fill:#d1ecf1
    style AbaPessoas fill:#d4edda
    style AbaUsuarios fill:#f8d7da
```

### 3.1 Detalhamento das Actions

| Action | Método | Parâmetros | Retorno | Aba Destino |
|--------|--------|------------|---------|-------------|
| **GET (url params)** | GET | `?colegio=X&id_passeio=Y&onibus=Z` | Lista de passageiros | Embarque |
| **updateEmbarque** | POST | `cpf, tipo, timestamp` | Status | Embarque |
| **getAllStudents** | POST | `action: 'getAllStudents'` | Lista de alunos | Alunos |
| **getAllPeople** | POST | `action: 'getAllPeople'` | Lista de pessoas + embeddings | Pessoas |
| **addPessoa** | POST | `cpf, nome, email, telefone, embedding` | Success | Pessoas |
| **getAllUsers** | POST | `action: 'getAllUsers'` | Lista de usuários | Usuários |
| **login** | POST | `cpf, senha` | User data + token | Usuários |
| **addMovementLog** | POST | `people: [{cpf, timestamp, tipo}]` | Success | Embarque (Logs) |

---

## 4. MAPA DE NAVEGAÇÃO

```mermaid
graph TD
    Start([App Inicia]) --> AuthCheck{Está<br/>logado?}

    AuthCheck -->|Não| LoginScreen[LoginScreen]
    AuthCheck -->|Sim| MainMenu[MainMenuScreen]

    LoginScreen -->|Login OK| MainMenu

    MainMenu -->|1| EmbarqueScreen[EmbarqueScreen<br/>Ler QR/Pulseira]
    MainMenu -->|2| ControleEmbarque[ControleEmbarqueScreen<br/>Lista de embarque]
    MainMenu -->|3| Retorno[RetornoScreen<br/>Confirmar retornos]
    MainMenu -->|4| CadastroFacial[ControleAlunosScreen<br/>Cadastrar faciais]
    MainMenu -->|5| Reconhecimento[ReconhecimentoFacialCompleto<br/>Reconhecer por face]
    MainMenu -->|6| PainelAdmin[PainelAdminScreen<br/>Logs e gestão]

    EmbarqueScreen --> BarcodeScreen[BarcodeScreen<br/>Câmera QR]
    BarcodeScreen -->|QR lido| EmbarqueScreen

    CadastroFacial --> CameraFacial1[CameraPreviewScreen<br/>Captura facial]
    CameraFacial1 -->|Foto tirada| CadastroFacial

    Reconhecimento --> ReconhecerAluno[ReconhecerAlunoScreen<br/>Captura + Reconhece]

    style LoginScreen fill:#f8d7da
    style MainMenu fill:#d4edda
    style EmbarqueScreen fill:#d1ecf1
    style CadastroFacial fill:#fff3cd
    style Reconhecimento fill:#e2d3f4
```

---

## 5. FLUXO DE AUTENTICAÇÃO

```mermaid
sequenceDiagram
    participant User as Usuário
    participant UI as LoginScreen
    participant Auth as AuthService
    participant DB as SQLite (usuarios)
    participant GAS as Google Apps Script
    participant Sheet as Sheets (Usuários)

    User->>UI: Insere CPF e Senha
    UI->>Auth: login(cpf, senha)

    Auth->>Auth: Hasheia senha (SHA256)

    alt Tem Internet
        Auth->>GAS: POST login {cpf, senha_hash}
        GAS->>Sheet: Busca usuário
        Sheet-->>GAS: Dados do usuário
        GAS-->>Auth: {success: true, user: {...}}
        Auth->>DB: upsertUsuario (cache local)
    else Sem Internet
        Auth->>DB: getUsuarioByCpf(cpf)
        DB-->>Auth: Usuário cacheado
        Auth->>Auth: Compara senha_hash
    end

    alt Login OK
        Auth->>Auth: Salva sessão (SharedPreferences)
        Auth-->>UI: Login successful
        UI->>User: Redireciona para MainMenu
    else Login Falhou
        Auth-->>UI: Erro de credenciais
        UI->>User: Exibe erro
    end
```

---

## 6. FLUXO DE EMBARQUE

```mermaid
sequenceDiagram
    participant User as Monitor
    participant UI as EmbarqueScreen
    participant Barcode as BarcodeScreen
    participant Data as DataService
    participant DB as SQLite
    participant GAS as Google Apps Script
    participant Sheet as Sheets (Embarque)

    User->>UI: Seleciona Colégio e Ônibus
    UI->>Data: fetchData(nomeAba, onibus)

    Data->>GAS: GET ?colegio=X&id_passeio=Y&onibus=Z
    GAS->>Sheet: Busca passageiros
    Sheet-->>GAS: Lista de passageiros
    GAS-->>Data: JSON passageiros

    Data->>DB: Salva em passageiros
    Data->>DB: Sincroniza para alunos (tem_qr=SIM)
    Data-->>UI: Lista carregada

    User->>UI: Clica "Ler Código"
    UI->>Barcode: Abre câmera
    User->>Barcode: Posiciona QR/Código de barras
    Barcode->>Barcode: Detecta código
    Barcode-->>UI: Código detectado

    UI->>Data: Busca passageiro por código

    alt Passageiro Encontrado
        Data->>DB: Atualiza embarque='SIM'
        Data->>GAS: POST updateEmbarque {cpf, tipo: EMBARQUE}
        GAS->>Sheet: Atualiza planilha
        Data-->>UI: Embarque confirmado
        UI->>User: ✅ Exibe confirmação
    else Passageiro Não Encontrado
        Data-->>UI: Erro: não encontrado
        UI->>User: ❌ Exibe erro
    end
```

---

## 7. FLUXO DE RECONHECIMENTO FACIAL

```mermaid
sequenceDiagram
    participant User as Monitor
    participant UI as ReconhecimentoFacialCompleto
    participant Camera as Camera
    participant Face as FaceRecognitionService
    participant DB as SQLite
    participant Sync as OfflineSyncService
    participant GAS as Google Apps Script

    User->>UI: Abre reconhecimento
    UI->>DB: Sincroniza pessoas (getAllPessoasFacial)

    Note over UI,DB: Carrega banco de pessoas_facial<br/>com embeddings

    DB-->>UI: Lista de pessoas com embeddings

    User->>UI: Posiciona rosto na câmera
    Camera->>Camera: Captura frame
    Camera->>UI: Frame disponível

    UI->>Face: Processa frame
    Face->>Face: Detecta rosto
    Face->>Face: Extrai embedding (ArcFace)

    Face->>DB: getAllEmbeddings()
    DB-->>Face: Lista de embeddings conhecidos

    Face->>Face: Compara similaridade (cosine)

    alt Reconhecido (similarity > 0.35)
        Face-->>UI: Pessoa identificada
        UI->>User: 🎉 Exibe nome + confiança

        UI->>DB: insertLog (cpf, nome, confidence, tipo)
        UI->>Sync: queueLogAcesso (enfileira sync)

        Sync->>GAS: POST addMovementLog (quando houver internet)
        GAS->>GAS: Salva log na planilha
    else Não Reconhecido
        Face-->>UI: Desconhecido
        UI->>User: ❓ Pessoa não cadastrada
    end
```

---

## 8. FLUXO DE CADASTRO FACIAL

```mermaid
sequenceDiagram
    participant User as Monitor
    participant UI as ControleAlunosScreen
    participant Camera as CameraPreviewScreen
    participant Face as FaceRecognitionService
    participant DB as SQLite
    participant Sync as OfflineSyncService
    participant GAS as Google Apps Script
    participant Sheet as Sheets (Pessoas)

    User->>UI: Abre cadastro facial
    UI->>DB: getPassageiros() + getAlunos(tem_qr=SIM)
    DB-->>UI: Lista de alunos embarcados

    User->>UI: Seleciona aluno
    UI->>UI: Escolhe: Simples ou Avançado

    alt Cadastro Simples (1 foto)
        UI->>Camera: Abre câmera frontal
        User->>Camera: Posiciona rosto
        Camera->>Camera: Captura foto
        Camera-->>UI: imagePath

        UI->>UI: Processa imagem (160x160, RGB)
        UI->>Face: saveEmbeddingFromImage(cpf, nome, image)
        Face->>Face: Extrai embedding (ArcFace - 512 dims)
        Face->>DB: insertEmbedding(cpf, nome, embedding)
    else Cadastro Avançado (3 fotos)
        loop 3 vezes
            UI->>Camera: Abre câmera
            User->>Camera: Posiciona rosto (ângulos diferentes)
            Camera-->>UI: imagePath
            UI->>UI: Adiciona à lista de faces
        end

        UI->>Face: saveEmbeddingEnhanced(cpf, nome, [img1, img2, img3])
        Face->>Face: Extrai 3 embeddings
        Face->>Face: Calcula média dos embeddings
        Face->>DB: insertEmbedding(cpf, nome, embeddingMédio)
    end

    UI->>DB: upsertPessoaFacial({cpf, nome, email, embedding})
    Note over UI,DB: 🆕 Salva na tabela pessoas_facial

    UI->>DB: updateAlunoFacial(cpf, 'CADASTRADA')

    UI->>Sync: queueCadastroFacial({cpf, nome, embedding})
    Note over UI,Sync: Enfileira para sincronização

    Sync->>GAS: POST addPessoa (quando houver internet)
    Note over Sync,GAS: Action: addPessoa<br/>Envia para aba PESSOAS

    GAS->>Sheet: Adiciona linha na aba Pessoas
    Sheet-->>GAS: Success
    GAS-->>Sync: {success: true}

    Sync->>DB: deleteOutboxIds (remove da fila)

    UI->>User: ✅ Facial cadastrada com sucesso
```

---

## 9. FLUXO DE SINCRONIZAÇÃO

### 9.1 Sincronização Automática (Timer)

```mermaid
sequenceDiagram
    participant Timer as Timer (1 min)
    participant Sync as OfflineSyncService
    participant DB as SQLite (sync_queue)
    participant Net as Connectivity
    participant GAS as Google Apps Script

    Timer->>Sync: Dispara a cada 1 minuto
    Sync->>Net: Verifica conectividade

    alt Sem Internet
        Sync->>Sync: Cancela sincronização
    else Com Internet
        Sync->>DB: getOutboxBatch(limit: 50)
        DB-->>Sync: Lista de itens pendentes

        Sync->>Sync: Separa por tipo: face_register / movement_log

        par Cadastros Faciais (individual)
            loop Para cada face_register
                Sync->>GAS: POST addPessoa {cpf, nome, embedding}
                GAS-->>Sync: {success: true/false}

                alt Sucesso
                    Sync->>DB: deleteOutboxIds([id])
                else Falha
                    Sync->>Sync: Mantém na fila (retry)
                end
            end
        and Logs de Movimento (lote)
            Sync->>GAS: POST addMovementLog {people: [...]}

            alt Lote completo OK
                GAS-->>Sync: {success: true, total: X}
                Sync->>DB: deleteOutboxIds([id1, id2, ...])
            else Lote parcial/falha
                Sync->>Sync: Tenta enviar individualmente
                loop Para cada log
                    Sync->>GAS: POST addMovementLog {people: [item]}
                    alt Sucesso
                        Sync->>DB: deleteOutboxIds([id])
                    else Falha
                        Sync->>Sync: Mantém na fila
                    end
                end
            end
        end
    end
```

### 9.2 Sincronização de Pessoas (Download)

```mermaid
sequenceDiagram
    participant UI as ReconhecimentoFacialCompleto
    participant Sync as AlunosSyncService
    participant GAS as Google Apps Script
    participant Sheet as Sheets (Pessoas)
    participant DB as SQLite

    UI->>Sync: syncPessoasFromSheets()
    Sync->>GAS: POST {action: 'getAllPeople'}

    alt Status 302 (Redirect)
        GAS-->>Sync: Location header (redirect URL)
        Sync->>Sync: Segue redirect com GET
        Sync->>GAS: GET redirectURL
    end

    GAS->>Sheet: Lê aba "Pessoas"
    Sheet-->>GAS: Lista de pessoas com embeddings
    GAS-->>Sync: {success: true, data: [...]}

    loop Para cada pessoa
        Sync->>Sync: Valida embedding (formato, tamanho)

        alt Embedding válido
            Sync->>DB: upsertPessoaFacial({cpf, nome, embedding...})
            Note over Sync,DB: 🆕 Salva na tabela pessoas_facial

            Sync->>DB: insertEmbedding({cpf, nome, embedding})
            Note over Sync,DB: Também salva em embeddings (cache)
        else Embedding inválido
            Sync->>Sync: Log erro e pula
        end
    end

    Sync-->>UI: {success: true, count: X pessoas}
    UI->>UI: Atualiza lista de reconhecimento
```

---

## 10. SERVIÇOS E SUAS FUNÇÕES

### 10.1 DataService

```mermaid
graph TB
    DataService[DataService]

    DataService --> fetchData["fetchData(nomeAba, onibus)<br/>📥 Busca lista de embarque do servidor"]
    DataService --> saveLocalData["saveLocalData()<br/>💾 Salva em SharedPrefs + SQLite"]
    DataService --> loadLocalData["loadLocalData()<br/>📂 Carrega dados locais"]
    DataService --> updateEmbarque["updateEmbarque(cpf, tipo)<br/>✅ Atualiza status embarque/retorno"]
    DataService --> syncPendentes["syncPendentes()<br/>🔄 Sincroniza pendentes offline"]

    style DataService fill:#e1f5ff
```

**Responsabilidades:**
- Gerenciar lista de passageiros do embarque atual
- Comunicação com Google Sheets (aba Embarque)
- Atualização de status de embarque/retorno
- Cache local (SharedPreferences + SQLite tabela passageiros)
- Sincronização de pendentes quando volta online

---

### 10.2 AuthService

```mermaid
graph TB
    AuthService[AuthService]

    AuthService --> login["login(cpf, senha)<br/>🔐 Autentica usuário"]
    AuthService --> logout["logout()<br/>🚪 Encerra sessão"]
    AuthService --> isLoggedIn["isLoggedIn()<br/>✅ Verifica se está logado"]
    AuthService --> getCurrentUser["getCurrentUser()<br/>👤 Retorna usuário atual"]
    AuthService --> hashPassword["hashPassword(senha)<br/>🔒 Hash SHA256"]

    style AuthService fill:#f8d7da
```

**Responsabilidades:**
- Autenticação online (Google Sheets) e offline (SQLite)
- Gerenciamento de sessão (SharedPreferences)
- Hash de senhas (SHA256)
- Cache de usuários localmente (tabela usuarios)

---

### 10.3 FaceRecognitionService

```mermaid
graph TB
    Face[FaceRecognitionService]

    Face --> init["init()<br/>🧠 Carrega modelo ArcFace"]
    Face --> extractEmbedding["extractEmbedding(imageBytes)<br/>📸 Extrai embedding (512 dims)"]
    Face --> saveEmbeddingFromImage["saveEmbeddingFromImage(cpf, nome, image)<br/>💾 Salva embedding simples"]
    Face --> saveEmbeddingEnhanced["saveEmbeddingEnhanced(cpf, nome, images)<br/>🎯 Salva embedding avançado (média de 3)"]
    Face --> recognizeFace["recognizeFace(imageBytes)<br/>🔍 Reconhece rosto"]
    Face --> compareFaces["compareFaces(emb1, emb2)<br/>📊 Calcula similaridade (cosine)"]

    style Face fill:#e2d3f4
```

**Responsabilidades:**
- Carregar e gerenciar modelo TensorFlow Lite (ArcFace)
- Extração de embeddings faciais (512 dimensões)
- Reconhecimento facial por similaridade (cosine similarity)
- Cadastro simples (1 foto) e avançado (3 fotos com média)
- Threshold de reconhecimento: 0.35 (35%)

---

### 10.4 OfflineSyncService

```mermaid
graph TB
    Offline[OfflineSyncService]

    Offline --> init["init()<br/>⏰ Inicia timer de sync (1 min)"]
    Offline --> queueLogAcesso["queueLogAcesso(...)<br/>📝 Enfileira log de acesso"]
    Offline --> queueCadastroFacial["queueCadastroFacial(...)<br/>📸 Enfileira cadastro facial"]
    Offline --> trySyncNow["trySyncNow()<br/>🔄 Executa sincronização imediata"]
    Offline --> sendBatch["_sendMovementsBatch()<br/>📤 Envia lote de logs"]
    Offline --> sendIndividual["_sendPersonIndividually()<br/>📤 Envia pessoa individual"]

    style Offline fill:#fff3cd
```

**Responsabilidades:**
- Fila de sincronização offline (tabela sync_queue)
- Timer automático de sincronização (1 minuto)
- Envio de logs de movimento (lote + fallback individual)
- Envio de cadastros faciais (sempre individual)
- Tolerância a 301/302 do Google Apps Script
- Retry automático com backoff

**IMPORTANTE:**
- Cadastros faciais vão para aba "Pessoas" (action: `addPessoa`)
- Logs de movimento vão para aba "Embarque" (action: `addMovementLog`)

---

### 10.5 AlunosSyncService

```mermaid
graph TB
    Alunos[AlunosSyncService]

    Alunos --> syncPessoas["syncPessoasFromSheets()<br/>👥 Sincroniza aba Pessoas"]
    Alunos --> syncAlunos["syncAlunosFromSheets()<br/>📚 Sincroniza aba Alunos"]
    Alunos --> processarPessoas["_processarRespostaPessoas()<br/>🔄 Processa e salva pessoas"]
    Alunos --> processarAlunos["_processarResposta()<br/>🔄 Processa e salva alunos"]
    Alunos --> temAlunosLocais["temAlunosLocais()<br/>✅ Verifica se há alunos"]

    style Alunos fill:#d1ecf1
```

**Responsabilidades:**
- Sincronizar aba "Pessoas" → tabela `pessoas_facial` (com embeddings)
- Sincronizar aba "Alunos" → tabela `alunos` (sem embeddings)
- Validação de embeddings (formato, tamanho, tipo)
- Tratamento de redirects 302 do Google Apps Script
- Parse de embeddings (string JSON → List<double>)

**Diferença entre Pessoas e Alunos:**
- **Pessoas**: Tem facial cadastrada, salva em `pessoas_facial` com embedding
- **Alunos**: Cadastro geral, pode ou não ter facial, salva em `alunos`

---

### 10.6 UserSyncService

```mermaid
graph TB
    Users[UserSyncService]

    Users --> syncUsers["syncUsersFromSheets()<br/>👥 Sincroniza usuários"]
    Users --> processarResposta["_processarResposta()<br/>🔄 Processa e salva usuários"]
    Users --> temUsuariosLocais["temUsuariosLocais()<br/>✅ Verifica se há usuários"]

    style Users fill:#d4edda
```

**Responsabilidades:**
- Sincronizar aba "Usuários" → tabela `usuarios`
- Cache de usuários para login offline
- Validação e sanitização de dados de usuários

---

## 11. GAPS E PROBLEMAS IDENTIFICADOS

### 🚨 CRÍTICO

1. **Erro de Isolate Persistente**
   - **Problema**: Código em cache está tentando usar isolates
   - **Solução**: Execute `./flutter_clean.sh`
   - **Status**: Script criado, aguardando execução

2. **Action `addPessoa` não implementada no GAS**
   - **Problema**: App tenta enviar cadastros para aba Pessoas, mas action não existe
   - **Solução**: Implementar no Google Apps Script
   - **Código necessário**:
   ```javascript
   if (params.action === 'addPessoa') {
     const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Pessoas');
     sheet.appendRow([
       params.cpf,
       params.nome,
       params.email,
       params.telefone,
       params.embedding,
       new Date(),
       'CADASTRADA'
     ]);
     return ContentService.createTextOutput(
       JSON.stringify({ success: true })
     ).setMimeType(ContentService.MimeType.JSON);
   }
   ```

### ⚠️ ATENÇÃO

3. **Tabela `pessoas_facial` não será criada em apps existentes**
   - **Problema**: Apps já instalados não têm a nova tabela
   - **Solução**: Adicionar migration ou forçar reinstalação
   - **Status**: Tabela criada apenas em novas instalações

4. **Dados duplicados entre `alunos` e `pessoas_facial`**
   - **Problema**: Mesma pessoa pode estar nas 2 tabelas
   - **Impacto**: Uso de espaço, possível inconsistência
   - **Solução**: Documentar claramente o propósito de cada tabela

5. **Sincronização de Pessoas retorna 0 pessoas**
   - **Problema**: Logs mostram "✅ [0] pessoas sincronizadas"
   - **Possíveis causas**:
     - Aba "Pessoas" vazia no Google Sheets
     - Embeddings em formato inválido
     - Action `getAllPeople` retornando dados errados
   - **Debug**: Verificar resposta do GAS

### 💡 MELHORIAS

6. **Reconhecimento usa `embeddings` ao invés de `pessoas_facial`**
   - **Atual**: `getAllEmbeddings()`
   - **Ideal**: `getAllPessoasFacial()`
   - **Impacto**: Funciona, mas não usa a nova estrutura

7. **Sem limpeza automática de `sync_queue`**
   - **Problema**: Itens que falharam permanentemente ficam na fila
   - **Solução**: Adicionar limite de tentativas ou TTL

8. **Logs não têm informação de onibus/passeio**
   - **Problema**: Difícil rastrear logs por passeio
   - **Solução**: Adicionar campos id_passeio e onibus na tabela logs

9. **Validação de CPF ausente**
   - **Problema**: Pode salvar CPFs inválidos
   - **Solução**: Adicionar validação de formato

10. **Sem backup local**
    - **Problema**: Limpar dados perde tudo
    - **Solução**: Adicionar export/import de banco de dados

---

## 12. CHECKLIST DE AÇÕES NECESSÁRIAS

### 🔴 URGENTE (Fazer Agora)

- [ ] Executar `./flutter_clean.sh` para resolver erro de isolate
- [ ] Implementar action `addPessoa` no Google Apps Script
- [ ] Verificar por que `syncPessoasFromSheets()` retorna 0 pessoas
- [ ] Testar fluxo completo de cadastro facial após correções

### 🟡 IMPORTANTE (Esta Semana)

- [ ] Atualizar `FaceRecognitionService.recognizeFace()` para usar `getAllPessoasFacial()`
- [ ] Adicionar migration para criar tabela `pessoas_facial` em apps existentes
- [ ] Documentar estrutura da aba "Pessoas" no Google Sheets
- [ ] Adicionar validação de embeddings no cadastro facial

### 🟢 MELHORIAS (Quando Possível)

- [ ] Adicionar limite de tentativas na `sync_queue`
- [ ] Adicionar campos id_passeio/onibus na tabela logs
- [ ] Implementar validação de CPF
- [ ] Adicionar funcionalidade de backup/restore
- [ ] Criar testes automatizados para fluxos críticos

---

## 13. RESUMO DO FLUXO DE DADOS

```mermaid
graph LR
    subgraph "ENTRADA"
        QR[Leitura QR]
        Camera[Captura Facial]
        Login[Login]
    end

    subgraph "PROCESSAMENTO"
        ArcFace[Modelo ArcFace]
        Hash[Hash SHA256]
        Compare[Comparação Cosine]
    end

    subgraph "ARMAZENAMENTO"
        Queue[sync_queue]
        Local[(SQLite 7 tabelas)]
    end

    subgraph "SINCRONIZAÇÃO"
        Timer[Timer 1min]
        Check{Tem<br/>Internet?}
    end

    subgraph "BACKEND"
        GAS[Google Apps Script]
        Sheets[(Google Sheets)]
    end

    QR --> Local
    Camera --> ArcFace
    ArcFace --> Local
    Login --> Hash
    Hash --> GAS

    Local --> Compare
    Compare --> Local

    Local --> Queue
    Timer --> Check
    Check -->|Sim| GAS
    Check -->|Não| Queue

    GAS <--> Sheets

    style Queue fill:#fff3cd
    style Local fill:#fff4e1
    style GAS fill:#e8f5e9
```

---

**Última atualização**: 2025-10-30
**Versão**: 1.0
**Autor**: Sistema Ellus - Documentação Técnica
