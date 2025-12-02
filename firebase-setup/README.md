# Firebase Setup CLI - Embarque Ellus

Scripts para configuração automática do Firebase Firestore.

## 📋 Pré-requisitos

1. Node.js 18+ instalado
2. Conta Firebase configurada
3. Arquivo `serviceAccountKey.json` (veja instruções abaixo)

## 🚀 Instalação

```bash
cd firebase-setup
npm install
```

## 🔑 Obter Service Account Key

1. Acesse o [Firebase Console](https://console.firebase.google.com/)
2. Selecione seu projeto
3. Vá em **Configurações do Projeto** (ícone de engrenagem) > **Contas de Serviço**
4. Clique em **Gerar nova chave privada**
5. Salve o arquivo como `serviceAccountKey.json` nesta pasta

⚠️ **IMPORTANTE**: Nunca commite este arquivo no Git!

## 📝 Scripts Disponíveis

### 1. Setup Completo (Recomendado)

Configura tudo automaticamente:

```bash
npm run setup
```

**Menu interativo com opções:**
- 🚀 Setup Completo (criar coleções + documentos de exemplo)
- 📂 Apenas criar coleções (sem documentos)
- 📊 Mostrar instruções de índices
- 🔐 Mostrar regras de segurança
- 🔍 Verificar setup

### 2. Importar Dados do Google Sheets

Importa dados de arquivos CSV:

```bash
npm run import
```

**Preparação dos dados:**
1. Exporte cada aba do Google Sheets como CSV
2. Crie a pasta `csv/` neste diretório
3. Salve os arquivos como:
   - `LOGIN.csv` → Usuários
   - `ALUNOS.csv` → Alunos
   - `PESSOAS.csv` → Pessoas com facial
   - `HOMELIST.csv` → Quartos
   - `EMBARQUES.csv` → Embarques

## 📂 Estrutura de Pastas

```
firebase-setup/
├── setup.js              # Script principal de configuração
├── import-data.js        # Script de importação de dados
├── package.json          # Dependências
├── README.md            # Este arquivo
├── serviceAccountKey.json  # ⚠️ NÃO COMMITAR! (obtenha do Firebase)
├── csv/                 # Pasta para arquivos CSV (criar manualmente)
│   ├── LOGIN.csv
│   ├── ALUNOS.csv
│   ├── PESSOAS.csv
│   └── HOMELIST.csv
└── firestore.rules      # Regras de segurança (gerado automaticamente)
```

## 🎯 Uso Passo a Passo

### Primeiro Uso

1. **Instalar dependências:**
   ```bash
   npm install
   ```

2. **Obter Service Account Key** (veja seção acima)

3. **Executar setup:**
   ```bash
   npm run setup
   ```

4. **Escolher "Setup Completo"** no menu

5. **Seguir instruções** para configurar índices e regras de segurança

### Importar Dados

1. **Exportar dados do Google Sheets:**
   - Abra cada aba da planilha
   - Arquivo > Download > CSV (.csv)
   - Salve com os nomes corretos

2. **Criar pasta csv:**
   ```bash
   mkdir csv
   ```

3. **Mover arquivos CSV para a pasta csv/**

4. **Executar importação:**
   ```bash
   npm run import
   ```

5. **Selecionar arquivos** para importar

## 🗂️ Coleções Criadas

O script cria as seguintes coleções com dados de exemplo:

1. **usuarios** - Usuários do sistema
   - Exemplo: Admin com CPF `08943760981`, senha `12345`

2. **alunos** - Cadastro geral de alunos
   - **5 exemplos criados automaticamente** para testes de QR code:
     - ALICE LOPES MARTINS (QR: SIM)
     - BRUNO SANTOS SILVA (QR: SIM)
     - CARLA OLIVEIRA COSTA (QR: SIM)
     - DANIEL PEREIRA SOUZA (QR: SIM + Facial cadastrada)
     - EDUARDA LIMA FERREIRA (QR: NAO - para contraste)
   - Datas: 01/12/2025 a 10/12/2025 (hoje + 9 dias)
   - Campo `tem_qr`: 'SIM' ou 'NAO' (TEXT)

3. **pessoas** - Pessoas com reconhecimento facial
   - Exemplo: Pessoa com embedding facial
   - Datas: 01/12/2025 a 10/12/2025 (hoje + 9 dias)

4. **logs** - Histórico de movimentações
5. **quartos** - Hospedagem/quartos
6. **embarques** - Listas de embarque/passeios
7. **eventos** - Notificações de ações críticas

**📅 Nota**: Os exemplos usam a data de **hoje (01/12/2025)** para funcionar com filtros de data do app.

## 📊 Índices Compostos

Os seguintes índices precisam ser criados manualmente no Firebase Console:

| Coleção | Campos | Descrição |
|---------|--------|-----------|
| alunos | inicio_viagem + fim_viagem | Busca por viagem |
| pessoas | inicio_viagem + fim_viagem | Busca por viagem |
| pessoas | colegio + movimentacao | Busca por colégio e localização |
| logs | inicio_viagem + fim_viagem | Busca logs por viagem |
| logs | cpf + timestamp | Busca logs por pessoa |
| quartos | inicio_viagem + fim_viagem | Busca quartos por viagem |
| embarques | colegio + idPasseio + onibus | Busca embarques |

**Como criar:**
1. Firebase Console > Firestore Database > Índices > Compostos
2. Criar cada índice conforme a tabela acima
3. Todos os campos em "Ascending"

## 🔐 Regras de Segurança

As regras são salvas automaticamente em `firestore.rules`.

**Para aplicar:**
1. Firebase Console > Firestore Database > Regras
2. Copiar conteúdo do arquivo `firestore.rules`
3. Colar no editor
4. Publicar

## 🐛 Troubleshooting

### Erro: "serviceAccountKey.json não encontrado"
- Certifique-se de ter baixado e salvado o arquivo na pasta correta

### Erro: "Permission denied"
- Verifique as permissões da Service Account no Firebase Console
- A conta deve ter permissões de "Editor" ou "Proprietário"

### Importação falha
- Verifique o formato dos arquivos CSV
- Certifique-se de que os nomes das colunas estão corretos
- Use UTF-8 como encoding

### Coleção já existe
- O script pula coleções existentes por padrão
- Use a opção "force" se quiser sobrescrever

## 📚 Recursos Adicionais

- [Documentação Firebase Admin SDK](https://firebase.google.com/docs/admin/setup)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Composite Indexes](https://firebase.google.com/docs/firestore/query-data/index-overview)

## 🤝 Suporte

Para dúvidas ou problemas:
1. Verifique a documentação em `../FIREBASE_SETUP.md`
2. Consulte os logs de erro
3. Verifique o Firebase Console

---

**Desenvolvido para**: Sistema Embarque Ellus
**Última atualização**: 30/11/2025
