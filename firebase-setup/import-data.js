#!/usr/bin/env node

/**
 * Script para Importar Dados do Google Sheets (CSV) para Firestore
 * Sistema Embarque Ellus
 */

import admin from 'firebase-admin';
import csv from 'csv-parser';
import fs from 'fs';
import path from 'path';
import chalk from 'chalk';
import ora from 'ora';
import inquirer from 'inquirer';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================================================
// INICIALIZAÇÃO
// ============================================================================

function initializeFirebase() {
  const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');

  if (!fs.existsSync(serviceAccountPath)) {
    console.log(chalk.red('\n❌ Arquivo serviceAccountKey.json não encontrado!\n'));
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });

  return admin.firestore();
}

// ============================================================================
// IMPORTADORES POR TIPO
// ============================================================================

async function importUsuarios(db, csvPath) {
  const spinner = ora('Importando usuários...').start();
  const usuarios = [];

  return new Promise((resolve, reject) => {
    fs.createReadStream(csvPath)
      .pipe(csv())
      .on('data', (row) => {
        usuarios.push({
          user_id: row.id || `user_${row.cpf}`,
          nome: row.nome || '',
          cpf: row.cpf || '',
          senha_hash: row.senha || row.senha_hash || '',
          perfil: row.perfil || 'USUARIO',
          ativo: row.ativo === 'TRUE' || row.ativo === '1' || row.ativo === 'true',
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
      })
      .on('end', async () => {
        try {
          const batch = db.batch();
          let count = 0;

          usuarios.forEach((user) => {
            const ref = db.collection('usuarios').doc(user.user_id);
            batch.set(ref, user);
            count++;

            // Firebase limita batches a 500 operações
            if (count % 500 === 0) {
              batch.commit();
            }
          });

          await batch.commit();
          spinner.succeed(chalk.green(`✓ ${usuarios.length} usuários importados`));
          resolve(usuarios.length);
        } catch (error) {
          spinner.fail(chalk.red('Erro ao importar usuários'));
          reject(error);
        }
      })
      .on('error', reject);
  });
}

async function importAlunos(db, csvPath) {
  const spinner = ora('Importando alunos...').start();
  const alunos = [];

  return new Promise((resolve, reject) => {
    fs.createReadStream(csvPath)
      .pipe(csv())
      .on('data', (row) => {
        alunos.push({
          cpf: row.cpf || row.CPF || '',
          nome: row.nome || row.Nome || '',
          colegio: row.colegio || row.Colegio || '',
          turma: row.turma || row.Turma || '',
          email: row.email || row.Email || '',
          telefone: row.telefone || row.Telefone || '',
          facial_status: row.facial_status || 'NAO',
          tem_qr: row.tem_qr === 'TRUE' || row.tem_qr === '1' || row.tem_qr === 'true',
          inicio_viagem: row.inicio_viagem || '',
          fim_viagem: row.fim_viagem || '',
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
      })
      .on('end', async () => {
        try {
          const batch = db.batch();
          let count = 0;

          alunos.forEach((aluno) => {
            if (aluno.cpf) {
              const ref = db.collection('alunos').doc(aluno.cpf);
              batch.set(ref, aluno);
              count++;

              if (count % 500 === 0) {
                batch.commit();
              }
            }
          });

          await batch.commit();
          spinner.succeed(chalk.green(`✓ ${alunos.length} alunos importados`));
          resolve(alunos.length);
        } catch (error) {
          spinner.fail(chalk.red('Erro ao importar alunos'));
          reject(error);
        }
      })
      .on('error', reject);
  });
}

async function importPessoas(db, csvPath) {
  const spinner = ora('Importando pessoas com embeddings...').start();
  const pessoas = [];

  return new Promise((resolve, reject) => {
    fs.createReadStream(csvPath)
      .pipe(csv())
      .on('data', (row) => {
        // Parsear embedding (pode estar como string JSON)
        let embedding = [];
        if (row.embedding) {
          try {
            embedding = JSON.parse(row.embedding);
          } catch {
            // Se não for JSON, tentar split por vírgula
            embedding = row.embedding.split(',').map(x => parseFloat(x.trim()));
          }
        }

        pessoas.push({
          cpf: row.cpf || row.CPF || '',
          nome: row.nome || row.Nome || '',
          colegio: row.colegio || row.Colegio || '',
          turma: row.turma || row.Turma || '',
          email: row.email || row.Email || '',
          telefone: row.telefone || row.Telefone || '',
          embedding: embedding.length === 512 ? embedding : Array(512).fill(0),
          facial_status: 'CADASTRADA',
          movimentacao: row.movimentacao || 'QUARTO',
          inicio_viagem: row.inicio_viagem || '',
          fim_viagem: row.fim_viagem || '',
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
      })
      .on('end', async () => {
        try {
          const batch = db.batch();
          let count = 0;

          pessoas.forEach((pessoa) => {
            if (pessoa.cpf) {
              const ref = db.collection('pessoas').doc(pessoa.cpf);
              batch.set(ref, pessoa);
              count++;

              if (count % 500 === 0) {
                batch.commit();
              }
            }
          });

          await batch.commit();
          spinner.succeed(chalk.green(`✓ ${pessoas.length} pessoas importadas`));
          resolve(pessoas.length);
        } catch (error) {
          spinner.fail(chalk.red('Erro ao importar pessoas'));
          reject(error);
        }
      })
      .on('error', reject);
  });
}

async function importQuartos(db, csvPath) {
  const spinner = ora('Importando quartos...').start();
  const quartos = [];

  return new Promise((resolve, reject) => {
    fs.createReadStream(csvPath)
      .pipe(csv())
      .on('data', (row) => {
        quartos.push({
          numero_quarto: row.Quarto || row.numero_quarto || '',
          escola: row.Escola || row.escola || '',
          nome_hospede: row['Nome do Hóspede'] || row.nome_hospede || '',
          cpf: row.CPF || row.cpf || '',
          inicio_viagem: row.inicio_viagem || '',
          fim_viagem: row.fim_viagem || '',
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
      })
      .on('end', async () => {
        try {
          const batch = db.batch();

          quartos.forEach((quarto, index) => {
            const ref = db.collection('quartos').doc();
            batch.set(ref, quarto);

            if (index % 500 === 0) {
              batch.commit();
            }
          });

          await batch.commit();
          spinner.succeed(chalk.green(`✓ ${quartos.length} quartos importados`));
          resolve(quartos.length);
        } catch (error) {
          spinner.fail(chalk.red('Erro ao importar quartos'));
          reject(error);
        }
      })
      .on('error', reject);
  });
}

// ============================================================================
// MENU PRINCIPAL
// ============================================================================

async function main() {
  console.log(chalk.cyan.bold('\n📥 IMPORTADOR DE DADOS - FIREBASE\n'));

  const db = initializeFirebase();

  // Listar arquivos CSV disponíveis
  const csvDir = path.join(__dirname, 'csv');
  if (!fs.existsSync(csvDir)) {
    fs.mkdirSync(csvDir);
  }

  const csvFiles = fs.readdirSync(csvDir).filter(f => f.endsWith('.csv'));

  if (csvFiles.length === 0) {
    console.log(chalk.yellow('⚠️  Nenhum arquivo CSV encontrado na pasta csv/\n'));
    console.log(chalk.gray('📝 Instruções:\n'));
    console.log('1. Crie a pasta "csv" neste diretório');
    console.log('2. Exporte os dados do Google Sheets como CSV');
    console.log('3. Salve os arquivos com os nomes:');
    console.log('   - LOGIN.csv (usuários)');
    console.log('   - ALUNOS.csv (alunos)');
    console.log('   - PESSOAS.csv (pessoas com facial)');
    console.log('   - HOMELIST.csv (quartos)\n');
    process.exit(0);
  }

  console.log(chalk.green('✓ Arquivos CSV encontrados:\n'));
  csvFiles.forEach(f => console.log(`  - ${f}`));
  console.log('');

  const { files } = await inquirer.prompt([
    {
      type: 'checkbox',
      name: 'files',
      message: 'Selecione os arquivos para importar:',
      choices: csvFiles.map(f => ({ name: f, value: f }))
    }
  ]);

  if (files.length === 0) {
    console.log(chalk.yellow('\n⚠️  Nenhum arquivo selecionado.\n'));
    process.exit(0);
  }

  console.log('');

  // Importar arquivos selecionados
  for (const file of files) {
    const filePath = path.join(csvDir, file);

    try {
      if (file.toLowerCase().includes('login') || file.toLowerCase().includes('usuario')) {
        await importUsuarios(db, filePath);
      } else if (file.toLowerCase().includes('aluno')) {
        await importAlunos(db, filePath);
      } else if (file.toLowerCase().includes('pessoa')) {
        await importPessoas(db, filePath);
      } else if (file.toLowerCase().includes('quarto') || file.toLowerCase().includes('homelist')) {
        await importQuartos(db, filePath);
      } else {
        console.log(chalk.yellow(`⚠️  Tipo de arquivo não reconhecido: ${file}`));
      }
    } catch (error) {
      console.error(chalk.red(`\n❌ Erro ao importar ${file}:`), error);
    }
  }

  console.log(chalk.cyan('\n✅ Importação concluída!\n'));
}

main().catch(error => {
  console.error(chalk.red('\n❌ Erro fatal:'), error);
  process.exit(1);
});
