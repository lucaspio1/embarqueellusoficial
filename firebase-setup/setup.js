#!/usr/bin/env node

/**
 * CLI para Configuração Automática do Firebase Firestore
 * Sistema Embarque Ellus
 *
 * Este script automatiza:
 * 1. Inicialização do Firebase Admin SDK
 * 2. Criação de coleções no Firestore
 * 3. Configuração de índices compostos
 * 4. Importação de dados (opcional)
 */

import admin from 'firebase-admin';
import inquirer from 'inquirer';
import chalk from 'chalk';
import ora from 'ora';
import Table from 'cli-table3';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================================================
// CONFIGURAÇÃO
// ============================================================================

const COLLECTIONS = [
  {
    name: 'usuarios',
    description: 'Usuários do sistema',
    sampleDoc: {
      nome: 'Admin Sistema',
      cpf: '08943760981',
      senha: '12345',  // Texto plano (ou use senha_hash com SHA-256)
      perfil: 'ADMIN',
      ativo: true,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    }
  },
  {
    name: 'alunos',
    description: 'Cadastro geral de alunos (múltiplos exemplos com QR codes)',
    sampleDoc: {
      cpf: '44533457800',
      nome: 'ALICE LOPES MARTINS',
      colegio: 'SARAPIQUA',
      turma: '9° ANO',
      email: 'alice@exemplo.com',
      telefone: '48988168320',
      facial_status: 'NAO',
      tem_qr: 'SIM',  // ✅ Campo TEXT: 'SIM' ou 'NAO'
      inicio_viagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-01T00:00:00')), // Hoje
      fim_viagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-10T00:00:00')), // +9 dias
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    }
  },
  {
    name: 'pessoas',
    description: 'Pessoas com reconhecimento facial',
    sampleDoc: {
      cpf: '22222222222',
      nome: 'Pessoa de Exemplo',
      colegio: 'Colégio Exemplo',
      turma: '3A',
      email: 'pessoa@exemplo.com',
      telefone: '(11) 98765-4321',
      embedding: Array(512).fill(0), // Array de 512 floats
      facial_status: 'CADASTRADA',
      movimentacao: 'QUARTO',
      inicio_viagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-01T00:00:00')), // Hoje
      fim_viagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-10T00:00:00')), // +9 dias
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    }
  },
  {
    name: 'logs',
    description: 'Histórico de movimentações',
    sampleDoc: {
      cpf: '22222222222',
      person_name: 'Pessoa de Exemplo',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      confidence: 0.95,
      tipo: 'RECONHECIMENTO',
      operador_nome: '',
      colegio: 'Colégio Exemplo',
      turma: '3A',
      inicio_viagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-01T00:00:00')),
      fim_viagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-10T00:00:00')),
      created_at: admin.firestore.FieldValue.serverTimestamp()
    }
  },
  {
    name: 'quartos',
    description: 'Hospedagem/Quartos',
    sampleDoc: {
      numero_quarto: '101',
      escola: 'Colégio Exemplo',
      nome_hospede: 'Pessoa de Exemplo',
      cpf: '22222222222',
      inicio_viagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-01T00:00:00')),
      fim_viagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-10T00:00:00')),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    }
  },
  {
    name: 'embarques',
    description: 'Listas de embarque/passeios',
    sampleDoc: {
      nome: 'Pessoa de Exemplo',
      cpf: '22222222222',
      colegio: 'Colégio Exemplo',
      turma: '3A',
      idPasseio: 'PRAIA_2025_12_01',
      onibus: '1',
      embarque: '',
      retorno: '',
      inicioViagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-01T00:00:00')),
      fimViagem: admin.firestore.Timestamp.fromDate(new Date('2025-12-10T00:00:00')),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    }
  },
  {
    name: 'eventos',
    description: 'Notificações de ações críticas',
    sampleDoc: {
      tipo_evento: 'sistema_inicializado',
      dados: { message: 'Sistema configurado via CLI' },
      inicio_viagem: '',
      fim_viagem: '',
      processado: false,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      created_at: admin.firestore.FieldValue.serverTimestamp()
    }
  }
];

const INDEXES = [
  {
    collection: 'alunos',
    fields: ['inicio_viagem', 'fim_viagem'],
    description: 'Busca por viagem'
  },
  {
    collection: 'pessoas',
    fields: ['inicio_viagem', 'fim_viagem'],
    description: 'Busca por viagem'
  },
  {
    collection: 'pessoas',
    fields: ['colegio', 'movimentacao'],
    description: 'Busca por colégio e localização'
  },
  {
    collection: 'logs',
    fields: ['inicio_viagem', 'fim_viagem'],
    description: 'Busca logs por viagem'
  },
  {
    collection: 'logs',
    fields: ['cpf', 'timestamp'],
    description: 'Busca logs por pessoa'
  },
  {
    collection: 'quartos',
    fields: ['inicio_viagem', 'fim_viagem'],
    description: 'Busca quartos por viagem'
  },
  {
    collection: 'embarques',
    fields: ['colegio', 'idPasseio', 'onibus'],
    description: 'Busca embarques por colégio/passeio/ônibus'
  }
];

const SECURITY_RULES = `rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // MODO DESENVOLVIMENTO - Permitir tudo
    // ⚠️ IMPORTANTE: Mudar para regras restritas em produção!
    match /{document=**} {
      allow read, write: if true;
    }
  }
}`;

// ============================================================================
// FUNÇÕES AUXILIARES
// ============================================================================

function showBanner() {
  console.log(chalk.cyan.bold(`
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   🔥 FIREBASE SETUP CLI - EMBARQUE ELLUS 🔥              ║
║                                                           ║
║   Configuração Automática do Firestore                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
  `));
}

async function checkServiceAccount() {
  const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');

  if (!fs.existsSync(serviceAccountPath)) {
    console.log(chalk.red('\n❌ Arquivo serviceAccountKey.json não encontrado!\n'));
    console.log(chalk.yellow('📝 Como obter o arquivo:\n'));
    console.log('1. Acesse o Firebase Console: https://console.firebase.google.com/');
    console.log('2. Vá em Configurações do Projeto > Contas de Serviço');
    console.log('3. Clique em "Gerar nova chave privada"');
    console.log('4. Salve o arquivo como serviceAccountKey.json nesta pasta\n');
    process.exit(1);
  }

  return serviceAccountPath;
}

function initializeFirebase(serviceAccountPath) {
  const spinner = ora('Inicializando Firebase Admin SDK...').start();

  try {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });

    spinner.succeed(chalk.green('Firebase Admin SDK inicializado com sucesso!'));
    return admin.firestore();
  } catch (error) {
    spinner.fail(chalk.red('Erro ao inicializar Firebase'));
    console.error(error);
    process.exit(1);
  }
}

// ============================================================================
// CRIAÇÃO DE COLEÇÕES
// ============================================================================

/**
 * Cria múltiplos alunos de exemplo com diferentes configurações de QR code
 */
async function createMultipleStudentSamples(db, collection) {
  const hoje = new Date('2025-12-01T00:00:00');
  const fimViagem = new Date('2025-12-10T00:00:00');

  const studentSamples = [
    {
      cpf: '44533457800',
      nome: 'ALICE LOPES MARTINS',
      colegio: 'SARAPIQUA',
      turma: '9° ANO',
      email: 'alice@exemplo.com',
      telefone: '48988168320',
      facial_status: 'NAO',
      tem_qr: 'SIM',  // ✅ COM QR code
      inicio_viagem: admin.firestore.Timestamp.fromDate(hoje),
      fim_viagem: admin.firestore.Timestamp.fromDate(fimViagem),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    },
    {
      cpf: '12345678901',
      nome: 'BRUNO SANTOS SILVA',
      colegio: 'SARAPIQUA',
      turma: '8° ANO',
      email: 'bruno@exemplo.com',
      telefone: '48999887766',
      facial_status: 'NAO',
      tem_qr: 'SIM',  // ✅ COM QR code
      inicio_viagem: admin.firestore.Timestamp.fromDate(hoje),
      fim_viagem: admin.firestore.Timestamp.fromDate(fimViagem),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    },
    {
      cpf: '98765432100',
      nome: 'CARLA OLIVEIRA COSTA',
      colegio: 'SARAPIQUA',
      turma: '7° ANO',
      email: 'carla@exemplo.com',
      telefone: '48988776655',
      facial_status: 'NAO',
      tem_qr: 'SIM',  // ✅ COM QR code
      inicio_viagem: admin.firestore.Timestamp.fromDate(hoje),
      fim_viagem: admin.firestore.Timestamp.fromDate(fimViagem),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    },
    {
      cpf: '55566677788',
      nome: 'DANIEL PEREIRA SOUZA',
      colegio: 'SARAPIQUA',
      turma: '9° ANO',
      email: 'daniel@exemplo.com',
      telefone: '48977665544',
      facial_status: 'CADASTRADA',  // Este tem facial E QR code
      tem_qr: 'SIM',  // ✅ COM QR code
      inicio_viagem: admin.firestore.Timestamp.fromDate(hoje),
      fim_viagem: admin.firestore.Timestamp.fromDate(fimViagem),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    },
    {
      cpf: '11122233344',
      nome: 'EDUARDA LIMA FERREIRA',
      colegio: 'SARAPIQUA',
      turma: '6° ANO',
      email: 'eduarda@exemplo.com',
      telefone: '48966554433',
      facial_status: 'NAO',
      tem_qr: 'NAO',  // ❌ SEM QR code (para contraste)
      inicio_viagem: admin.firestore.Timestamp.fromDate(hoje),
      fim_viagem: admin.firestore.Timestamp.fromDate(fimViagem),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    }
  ];

  // Criar todos os documentos
  const batch = db.batch();
  studentSamples.forEach(student => {
    const docRef = db.collection('alunos').doc();
    batch.set(docRef, student);
  });

  await batch.commit();

  return studentSamples.length;
}

async function createCollections(db, options = {}) {
  console.log(chalk.cyan('\n📂 Criando coleções no Firestore...\n'));

  const results = [];

  for (const collection of COLLECTIONS) {
    const spinner = ora(`Criando coleção "${collection.name}"...`).start();

    try {
      // Verificar se a coleção já existe
      const snapshot = await db.collection(collection.name).limit(1).get();

      if (!snapshot.empty && !options.force) {
        spinner.warn(chalk.yellow(`Coleção "${collection.name}" já existe (pulando)`));
        results.push({ collection: collection.name, status: 'exists', doc: null });
        continue;
      }

      // Criar documento de exemplo se solicitado
      if (options.createSamples) {
        // Para alunos, criar múltiplos exemplos com QR codes
        if (collection.name === 'alunos') {
          await createMultipleStudentSamples(db, collection);
          spinner.succeed(chalk.green(`Coleção "${collection.name}" criada com múltiplos documentos de exemplo (incluindo QR codes)`));
          results.push({ collection: collection.name, status: 'created', doc: 'multiple' });
        } else {
          const docRef = await db.collection(collection.name).add(collection.sampleDoc);
          spinner.succeed(chalk.green(`Coleção "${collection.name}" criada com documento de exemplo`));
          results.push({ collection: collection.name, status: 'created', doc: docRef.id });
        }
      } else {
        // Apenas garantir que a coleção existe (Firebase cria automaticamente ao adicionar documento)
        spinner.succeed(chalk.green(`Coleção "${collection.name}" configurada`));
        results.push({ collection: collection.name, status: 'configured', doc: null });
      }
    } catch (error) {
      spinner.fail(chalk.red(`Erro ao criar coleção "${collection.name}"`));
      console.error(error);
      results.push({ collection: collection.name, status: 'error', doc: null });
    }
  }

  // Exibir tabela de resultados
  const table = new Table({
    head: [chalk.cyan('Coleção'), chalk.cyan('Status'), chalk.cyan('Descrição')],
    colWidths: [20, 15, 40]
  });

  COLLECTIONS.forEach((col, index) => {
    const result = results[index];
    const status = result.status === 'created' ? chalk.green('✓ Criada') :
                   result.status === 'exists' ? chalk.yellow('○ Existe') :
                   result.status === 'configured' ? chalk.blue('✓ Config') :
                   chalk.red('✗ Erro');

    table.push([col.name, status, col.description]);
  });

  console.log('\n' + table.toString());

  return results;
}

// ============================================================================
// CONFIGURAÇÃO DE ÍNDICES
// ============================================================================

async function showIndexInstructions() {
  console.log(chalk.cyan('\n📊 Configuração de Índices Compostos\n'));
  console.log(chalk.yellow('⚠️  Os índices compostos devem ser criados manualmente no Firebase Console.\n'));

  const table = new Table({
    head: [chalk.cyan('Coleção'), chalk.cyan('Campos'), chalk.cyan('Descrição')],
    colWidths: [20, 35, 35]
  });

  INDEXES.forEach(index => {
    table.push([
      index.collection,
      index.fields.join(' + '),
      index.description
    ]);
  });

  console.log(table.toString());

  console.log(chalk.yellow('\n📝 Como criar os índices:\n'));
  console.log('1. Acesse o Firebase Console: https://console.firebase.google.com/');
  console.log('2. Vá em Firestore Database > Índices > Compostos');
  console.log('3. Clique em "Criar índice"');
  console.log('4. Configure cada índice conforme a tabela acima');
  console.log('5. Todos os campos devem ser "Ascending"\n');

  console.log(chalk.gray('💡 Dica: O Firebase pode sugerir índices automaticamente quando você executar queries que precisam deles.\n'));
}

// ============================================================================
// REGRAS DE SEGURANÇA
// ============================================================================

async function showSecurityRules() {
  console.log(chalk.cyan('\n🔐 Regras de Segurança do Firestore\n'));

  console.log(chalk.yellow('⚠️  Configure as seguintes regras de segurança no Firebase Console:\n'));

  console.log(chalk.gray('────────────────────────────────────────────────────────────'));
  console.log(SECURITY_RULES);
  console.log(chalk.gray('────────────────────────────────────────────────────────────\n'));

  console.log(chalk.yellow('📝 Como configurar:\n'));
  console.log('1. Acesse o Firebase Console');
  console.log('2. Vá em Firestore Database > Regras');
  console.log('3. Cole as regras acima');
  console.log('4. Clique em "Publicar"\n');

  console.log(chalk.red('⚠️  IMPORTANTE: Em produção, use regras mais restritivas!\n'));

  // Salvar regras em arquivo
  const rulesPath = path.join(__dirname, 'firestore.rules');
  fs.writeFileSync(rulesPath, SECURITY_RULES);
  console.log(chalk.green(`✓ Regras salvas em: ${rulesPath}\n`));
}

// ============================================================================
// VERIFICAÇÃO DO SETUP
// ============================================================================

async function verifySetup(db) {
  console.log(chalk.cyan('\n🔍 Verificando configuração...\n'));

  const results = [];

  for (const collection of COLLECTIONS) {
    const spinner = ora(`Verificando "${collection.name}"...`).start();

    try {
      const snapshot = await db.collection(collection.name).limit(1).get();
      const count = (await db.collection(collection.name).count().get()).data().count;

      if (snapshot.empty) {
        spinner.warn(chalk.yellow(`"${collection.name}" existe mas está vazia`));
        results.push({ collection: collection.name, exists: true, count: 0 });
      } else {
        spinner.succeed(chalk.green(`"${collection.name}" OK (${count} documentos)`));
        results.push({ collection: collection.name, exists: true, count });
      }
    } catch (error) {
      spinner.fail(chalk.red(`Erro ao verificar "${collection.name}"`));
      results.push({ collection: collection.name, exists: false, count: 0 });
    }
  }

  return results;
}

// ============================================================================
// MENU PRINCIPAL
// ============================================================================

async function showMainMenu(db) {
  const answers = await inquirer.prompt([
    {
      type: 'list',
      name: 'action',
      message: 'O que você deseja fazer?',
      choices: [
        { name: '🚀 Setup Completo (Criar coleções + Documentos de exemplo)', value: 'full' },
        { name: '📂 Apenas Criar Coleções (sem documentos)', value: 'collections' },
        { name: '📊 Mostrar Instruções de Índices', value: 'indexes' },
        { name: '🔐 Mostrar Regras de Segurança', value: 'rules' },
        { name: '🔍 Verificar Setup', value: 'verify' },
        { name: '🚪 Sair', value: 'exit' }
      ]
    }
  ]);

  switch (answers.action) {
    case 'full':
      await createCollections(db, { createSamples: true });
      await showIndexInstructions();
      await showSecurityRules();
      await askContinue(db);
      break;

    case 'collections':
      await createCollections(db, { createSamples: false });
      await askContinue(db);
      break;

    case 'indexes':
      await showIndexInstructions();
      await askContinue(db);
      break;

    case 'rules':
      await showSecurityRules();
      await askContinue(db);
      break;

    case 'verify':
      await verifySetup(db);
      await askContinue(db);
      break;

    case 'exit':
      console.log(chalk.cyan('\n👋 Até logo!\n'));
      process.exit(0);
      break;
  }
}

async function askContinue(db) {
  const { continue: shouldContinue } = await inquirer.prompt([
    {
      type: 'confirm',
      name: 'continue',
      message: 'Deseja fazer algo mais?',
      default: true
    }
  ]);

  if (shouldContinue) {
    await showMainMenu(db);
  } else {
    console.log(chalk.cyan('\n✅ Configuração concluída!\n'));
    console.log(chalk.yellow('📝 Próximos passos:\n'));
    console.log('1. Configure os índices compostos no Firebase Console');
    console.log('2. Configure as regras de segurança');
    console.log('3. Importe os dados (se necessário)');
    console.log('4. Teste a aplicação Flutter\n');
    console.log(chalk.cyan('👋 Até logo!\n'));
    process.exit(0);
  }
}

// ============================================================================
// MAIN
// ============================================================================

async function main() {
  showBanner();

  // Verificar se o serviceAccountKey.json existe
  const serviceAccountPath = await checkServiceAccount();

  // Inicializar Firebase
  const db = initializeFirebase(serviceAccountPath);

  // Mostrar menu principal
  await showMainMenu(db);
}

// Executar
main().catch(error => {
  console.error(chalk.red('\n❌ Erro fatal:'), error);
  process.exit(1);
});
