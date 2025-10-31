# Configuração do Ambiente (.env)

## 🎯 Objetivo

Este documento explica como configurar o arquivo `.env` para centralizar todas as URLs e configurações do aplicativo em um único local.

## ✅ Benefícios

- **Configuração centralizada**: Todas as URLs em um único arquivo
- **Fácil manutenção**: Altere a URL em apenas 1 lugar
- **Segurança**: O arquivo `.env` não é commitado no Git
- **Flexibilidade**: Diferentes ambientes (dev, prod) com arquivos diferentes

## 📋 Passo a Passo

### 1. Configuração Inicial

O arquivo `.env.example` já está no projeto. Para começar:

```bash
# Copie o arquivo de exemplo
cp .env.example .env
```

### 2. Edite o arquivo .env

Abra o arquivo `.env` e preencha com suas configurações:

```env
# URL do Google Apps Script - DADOS GERAIS (obrigatório)
# Gerencia ALUNOS, PESSOAS, LOGS, LOGIN
GOOGLE_APPS_SCRIPT_URL=https://script.google.com/macros/s/SEU_ID_DADOS/exec

# URL do Google Apps Script - EMBARQUES (obrigatório)
# Gerencia listas de embarque por passeio
EMBARQUE_SCRIPT_URL=https://script.google.com/macros/s/SEU_ID_EMBARQUES/exec

# ID da Planilha do Google Sheets (obrigatório)
SPREADSHEET_ID=1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U

# Configurações opcionais (já têm valores padrão)
SYNC_INTERVAL_MINUTES=1
MAX_RETRY_ATTEMPTS=3
FACE_CONFIDENCE_THRESHOLD=0.7
EMBEDDING_SIZE=512
API_TIMEOUT_SECONDS=30
```

### 3. Obter as URLs do Google Apps Script

**Importante**: O sistema usa **2 scripts diferentes**:

#### Script 1 - DADOS GERAIS (ALUNOS, PESSOAS, LOGS, LOGIN)
1. Acesse a planilha com as abas ALUNOS, PESSOAS, LOGS, LOGIN
2. Vá em **Extensões** > **Apps Script**
3. Cole o código do arquivo `lib/script.gs`
4. Clique em **Implantar** > **Nova implantação**
5. Escolha **Aplicativo da Web**
6. Configure:
   - Execute as: **Me**
   - Who has access: **Anyone**
7. Clique em **Implantar**
8. **Copie a URL** gerada
9. Cole no arquivo `.env` em `GOOGLE_APPS_SCRIPT_URL`

#### Script 2 - EMBARQUES/PASSEIOS
1. Acesse o script que gerencia embarques
2. Faça o deploy seguindo os mesmos passos acima
3. **Copie a URL** gerada
4. Cole no arquivo `.env` em `EMBARQUE_SCRIPT_URL`

### 4. Instale as dependências

```bash
flutter pub get
```

### 5. Execute o app

```bash
flutter run
```

## 📊 Validação

Quando você iniciar o app, verá no console:

```
✅ Arquivo .env carregado com sucesso
⚙️  [1/5] Validando Configurações...
📋 [Config] Configurações carregadas:
   - Google Apps Script URL (Dados): ✓ Configurada
   - Embarque Script URL (Passeios): ✓ Configurada
   - Spreadsheet ID: ✓ Configurada
   - Intervalo de Sync: 1 minuto(s)
   - Max Retry: 3 tentativa(s)
   - Face Confidence: 0.7
   - Embedding Size: 512
   - API Timeout: 30 segundos
✅ Configurações válidas!
```

## ❌ Solução de Problemas

### Erro: "GOOGLE_APPS_SCRIPT_URL não configurada"

**Causa**: O arquivo `.env` não existe ou a variável não está definida.

**Solução**:
1. Certifique-se que o arquivo `.env` existe na raiz do projeto
2. Verifique se a variável `GOOGLE_APPS_SCRIPT_URL` está definida
3. Reinicie o app

### Erro: "Erro ao carregar .env"

**Causa**: O arquivo `.env` não foi incluído nos assets do Flutter.

**Solução**: Já está configurado no `pubspec.yaml`:

```yaml
flutter:
  assets:
    - .env
```

## 🔒 Segurança

**IMPORTANTE**: O arquivo `.env` contém informações sensíveis e **NÃO deve ser commitado** no Git.

O arquivo `.gitignore` já está configurado para ignorar:
```
.env
.env.local
.env.*.local
```

## 📂 Estrutura de Arquivos

```
embarqueellusoficial/
├── .env                    # Suas configurações (NÃO commitar)
├── .env.example            # Template (commitar)
├── lib/
│   ├── config/
│   │   └── app_config.dart # Classe que lê o .env
│   ├── services/
│   │   ├── offline_sync_service.dart    # Usa AppConfig (dados gerais)
│   │   ├── user_sync_service.dart       # Usa AppConfig (dados gerais)
│   │   ├── logs_sync_service.dart       # Usa AppConfig (dados gerais)
│   │   ├── alunos_sync_service.dart     # Usa AppConfig (dados gerais)
│   │   └── data_service.dart            # Usa AppConfig (embarques)
│   └── main.dart           # Carrega .env na inicialização
└── pubspec.yaml            # Configurado com flutter_dotenv
```

## 🚀 Próximos Passos

Após configurar o `.env`:

1. Execute `flutter pub get` para instalar as dependências
2. Execute `flutter run` para testar o app
3. Faça o deploy do Google Apps Script atualizado (veja `DEPLOY_GOOGLE_APPS_SCRIPT.md`)
4. Teste o cadastro facial para garantir que está salvando na aba PESSOAS

## 📝 Variáveis Disponíveis

| Variável | Obrigatória | Padrão | Descrição |
|----------|-------------|--------|-----------|
| `GOOGLE_APPS_SCRIPT_URL` | ✅ Sim | - | URL do script de dados gerais (ALUNOS, PESSOAS, LOGS, LOGIN) |
| `EMBARQUE_SCRIPT_URL` | ✅ Sim | - | URL do script de embarques/passeios |
| `SPREADSHEET_ID` | ✅ Sim | - | ID da planilha do Google Sheets |
| `SYNC_INTERVAL_MINUTES` | ❌ Não | 1 | Intervalo de sincronização em minutos |
| `MAX_RETRY_ATTEMPTS` | ❌ Não | 3 | Número de tentativas em caso de erro |
| `FACE_CONFIDENCE_THRESHOLD` | ❌ Não | 0.7 | Limiar de confiança para reconhecimento |
| `EMBEDDING_SIZE` | ❌ Não | 512 | Tamanho do vetor de embedding |
| `API_TIMEOUT_SECONDS` | ❌ Não | 30 | Timeout para requisições HTTP |

## 💡 Dicas

1. **Mantenha o .env.example atualizado**: Sempre que adicionar uma nova variável, atualize o `.env.example`
2. **Use ambientes diferentes**: Crie `.env.dev` e `.env.prod` para diferentes ambientes
3. **Documente as variáveis**: Adicione comentários explicativos no `.env.example`
4. **Valide as configurações**: O app valida automaticamente na inicialização
