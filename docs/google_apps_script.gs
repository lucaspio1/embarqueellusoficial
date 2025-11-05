// ============================================================================
// GOOGLE APPS SCRIPT - ELLUS EMBARQUE (VERSÃO ATUALIZADA)
// ============================================================================
// Este script gerencia a integração entre o app Flutter e o Google Sheets
// Planilha com as seguintes abas:
// - PESSOAS: Lista de pessoas com embeddings faciais
// - LOGIN: Usuários do sistema com credenciais
// - LOGS: Logs de reconhecimento facial
// - Outras abas de passeios/embarques
// ============================================================================

const SPREADSHEET_ID = '1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U';
const MOVIMENTACAO_COLUMN_INDEX = 8; // Coluna H

function doPost(e) {
  try {
    console.log('📥 Requisição recebida');
    console.log('postData:', e.postData);

    if (!e.postData || !e.postData.contents) {
      console.error('❌ Sem postData.contents');
      return createResponse(false, 'Requisição inválida: sem dados POST');
    }

    const data = JSON.parse(e.postData.contents);
    const action = data.action;

    console.log('📥 Ação recebida:', action);
    console.log('📥 Dados:', JSON.stringify(data));

    switch (action) {
      case 'login':
        return login(data);
      case 'getAllUsers':
        return getAllUsers();
      case 'getAllPeople':
        return getAllPeople();
      case 'getAllStudents':
        return getAllStudents();
      case 'getAlunos':
        return getAlunos(data);
      case 'addPessoa':
        return addPessoa(data);
      case 'cadastrarFacial':
        return cadastrarFacial(data);
      case 'addMovementLog':
        return addMovementLog(data);
      case 'registrarLog':
        return registrarLog(data);
      case 'syncEmbedding':
        return syncEmbedding(data);
      case 'getAllLogs':
        return getAllLogs();
      default:
        console.error('❌ Ação não reconhecida:', action);
        return createResponse(false, 'Ação não reconhecida: ' + action);
    }
  } catch (error) {
    console.error('❌ Erro no doPost:', error);
    console.error('Stack:', error.stack);
    return createResponse(false, 'Erro no servidor: ' + error.message + ' | ' + error.stack);
  }
}

function doGet(e) {
  try {
    const params = e && e.parameter ? e.parameter : {};
    const action = params.action;

    console.log('📥 [doGet] Ação:', action, 'Params:', JSON.stringify(params));

    switch (action) {
      case 'getAllUsers':
        return getAllUsers();
      case 'getAllPeople':
        return getAllPeople();
      case 'getAllStudents':
        return getAllStudents();
      case 'getAlunos':
        return getAlunos({
          nomeAba: params.nomeAba,
          numeroOnibus: params.numeroOnibus
        });
      case 'addPessoa':
        try {
          const embeddingParam = params.embedding;
          const embedding = embeddingParam ? JSON.parse(embeddingParam) : null;

          return addPessoa({
            cpf: params.cpf,
            nome: params.nome,
            email: params.email || '',
            telefone: params.telefone || '',
            embedding: embedding,
            personId: params.personId || params.cpf
          });
        } catch (e) {
          return createResponse(false, 'Erro ao processar addPessoa via GET: ' + e.message);
        }
      case 'cadastrarFacial':
        try {
          const embeddingParam = params.embedding;
          const embedding = embeddingParam ? JSON.parse(embeddingParam) : null;

          return cadastrarFacial({
            cpf: params.cpf,
            nome: params.nome,
            email: params.email || '',
            telefone: params.telefone || '',
            embedding: embedding
          });
        } catch (e) {
          return createResponse(false, 'Erro ao processar cadastro facial via GET: ' + e.message);
        }
      case 'addMovementLog':
        try {
          const peopleParam = params.people;
          const people = peopleParam ? JSON.parse(peopleParam) : [];

          return addMovementLog({ people: people });
        } catch (e) {
          return createResponse(false, 'Erro ao processar addMovementLog via GET: ' + e.message);
        }
      case 'registrarLog':
        return registrarLog({
          cpf: params.cpf,
          nome: params.nome,
          confidence: parseFloat(params.confidence || '0'),
          tipo: params.tipo || 'reconhecimento'
        });
      case 'getAllLogs':
        return getAllLogs();
      default:
        return createResponse(false, 'Ação não reconhecida em GET: ' + action);
    }
  } catch (err) {
    console.error('❌ [doGet] Erro:', err);
    return createResponse(false, 'Erro no doGet: ' + err.message);
  }
}

// ============================================================================
// FUNÇÃO DE LOGIN
// ============================================================================
function login(data) {
  try {
    const cpf = data.cpf;
    const senha = data.senha;

    console.log('🔐 Tentativa de login:', cpf);

    if (!cpf || !senha) {
      return createResponse(false, 'CPF e senha são obrigatórios');
    }

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const loginSheet = ss.getSheetByName('LOGIN');

    if (!loginSheet) {
      return createResponse(false, 'Aba LOGIN não encontrada na planilha');
    }

    const data_range = loginSheet.getDataRange();
    const values = data_range.getValues();

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      const id = row[0];
      const nome = row[1];
      const cpfSheet = String(row[2]).trim();
      const senhaSheet = String(row[3]).trim();
      const perfil = String(row[4]).trim().toUpperCase();

      if (cpfSheet === cpf && senhaSheet === senha) {
        console.log('✅ Login bem-sucedido:', nome);
        return createResponse(true, 'Login bem-sucedido', {
          user: {
            id: id,
            nome: nome,
            cpf: cpfSheet,
            perfil: perfil || 'USUARIO'
          }
        });
      }
    }

    console.log('❌ Credenciais inválidas');
    return createResponse(false, 'CPF ou senha inválidos');
  } catch (error) {
    console.error('❌ Erro no login:', error);
    return createResponse(false, 'Erro ao fazer login: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: GET ALL USERS
// ============================================================================
function getAllUsers() {
  try {
    console.log('📥 [getAllUsers] Buscando todos os usuários da aba LOGIN...');

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const loginSheet = ss.getSheetByName('LOGIN');

    if (!loginSheet) {
      console.error('❌ Aba LOGIN não encontrada');
      return createResponse(false, 'Aba LOGIN não encontrada na planilha');
    }

    const data_range = loginSheet.getDataRange();
    const values = data_range.getValues();

    const users = [];

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      if (!row[2] || !row[3]) continue;

      const user = {
        id: row[0],
        nome: row[1],
        cpf: String(row[2]).trim(),
        senha: String(row[3]).trim(),
        perfil: String(row[4] || 'USUARIO').trim().toUpperCase()
      };

      users.push(user);
    }

    console.log('✅ [getAllUsers] ' + users.length + ' usuários encontrados');
    return createResponse(true, users.length + ' usuários encontrados', { users: users });
  } catch (error) {
    console.error('❌ Erro ao buscar usuários:', error);
    return createResponse(false, 'Erro ao buscar usuários: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: GET ALL PEOPLE
// ============================================================================
function getAllPeople() {
  try {
    console.log('📥 [getAllPeople] Buscando pessoas da aba PESSOAS...');

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const pessoasSheet = ss.getSheetByName('PESSOAS');

    if (!pessoasSheet) {
      console.error('❌ Aba PESSOAS não encontrada');
      return createResponse(false, 'Aba PESSOAS não encontrada');
    }

    garantirColunaMovimentacao(pessoasSheet);

    const data_range = pessoasSheet.getDataRange();
    const values = data_range.getValues();

    console.log('📋 Cabeçalho da planilha PESSOAS:', values[0]);
    console.log('📋 Total de linhas:', values.length);

    const pessoas = [];

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      if (!row[1]) continue;

      const pessoa = {
        cpf: String(row[1]).trim(),
        nome: row[2] || '',
        email: row[3] || '',
        telefone: row[4] || '',
        embedding: row[5] || null,
        turma: '',
        movimentacao: (row[MOVIMENTACAO_COLUMN_INDEX - 1] || '').toString()
      };

      if (pessoa.embedding && pessoa.embedding.length > 0) {
        const embeddingStr = String(pessoa.embedding);
        if (embeddingStr.startsWith('[') && embeddingStr.includes(',')) {
          pessoas.push(pessoa);
          if (pessoas.length === 1) {
            console.log('✅ Exemplo de pessoa válida:', {
              cpf: pessoa.cpf,
              nome: pessoa.nome,
              movimentacao: pessoa.movimentacao,
              embeddingPreview: embeddingStr.substring(0, 50) + '...'
            });
          }
        } else {
          console.log(`⚠️ Ignorando ${pessoa.nome} - embedding inválido: ${embeddingStr.substring(0, 50)}`);
        }
      } else {
        console.log(`⚠️ Ignorando ${pessoa.nome} - sem embedding`);
      }
    }

    console.log('✅ [getAllPeople] ' + pessoas.length + ' pessoas encontradas');
    return createResponse(true, pessoas.length + ' pessoas encontradas', { data: pessoas });
  } catch (error) {
    console.error('❌ Erro ao buscar pessoas:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: GET ALL STUDENTS - permanece igual
// ============================================================================
function getAllStudents() {
  try {
    console.log('📥 [getAllStudents] Buscando alunos...');

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);

    let alunosSheet = ss.getSheetByName('ALUNOS') ||
                      ss.getSheetByName('Alunos') ||
                      ss.getSheetByName('LISTA_ALUNOS');

    if (!alunosSheet) {
      console.log('⚠️ Aba ALUNOS não encontrada, retornando lista vazia');
      return createResponse(true, 'Aba ALUNOS não encontrada', { data: [] });
    }

    const data_range = alunosSheet.getDataRange();
    const values = data_range.getValues();

    console.log('📋 Cabeçalho da planilha ALUNOS:', values[0]);

    const alunos = [];

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      if (!row[0]) continue;

      const aluno = {
        cpf: String(row[0]).trim(),
        nome: row[1] || '',
        email: row[2] || '',
        telefone: row[3] || '',
        turma: row[4] || '',
        facial_status: String(row[5] || 'NAO').toUpperCase(),
        tem_qr: String(row[6] || 'NAO').toUpperCase()
      };

      alunos.push(aluno);
    }

    console.log('✅ [getAllStudents] ' + alunos.length + ' alunos encontrados');
    return createResponse(true, alunos.length + ' alunos encontrados', { data: alunos });
  } catch (error) {
    console.error('❌ Erro ao buscar alunos:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: ADD PESSOA
// ============================================================================
function addPessoa(data) {
  try {
    const cpf = data.cpf;
    const nome = data.nome;
    const email = data.email || '';
    const telefone = data.telefone || '';
    const embedding = data.embedding;
    const personId = data.personId || cpf;

    console.log('📥 [addPessoa] Cadastrando pessoa:', nome, 'CPF:', cpf);

    if (!cpf || !nome || !embedding) {
      return createResponse(false, 'CPF, nome e embedding são obrigatórios');
    }

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    let pessoasSheet = ss.getSheetByName('PESSOAS');

    if (!pessoasSheet) {
      console.log('📝 Criando aba PESSOAS...');
      pessoasSheet = ss.insertSheet('PESSOAS');
      pessoasSheet.appendRow(['ID', 'CPF', 'NOME', 'EMAIL', 'TELEFONE', 'EMBEDDING', 'DATA_CADASTRO', 'MOVIMENTAÇÃO']);
    }

    garantirColunaMovimentacao(pessoasSheet);

    const embeddingJson = JSON.stringify(embedding);
    const dataCadastro = new Date().toISOString();

    const data_range = pessoasSheet.getDataRange();
    const values = data_range.getValues();

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      const cpfSheet = String(row[1]).trim();

      if (cpfSheet === cpf) {
        console.log('🔄 Atualizando pessoa existente:', nome);
        pessoasSheet.getRange(i + 1, 3).setValue(nome);
        pessoasSheet.getRange(i + 1, 4).setValue(email);
        pessoasSheet.getRange(i + 1, 5).setValue(telefone);
        pessoasSheet.getRange(i + 1, 6).setValue(embeddingJson);
        pessoasSheet.getRange(i + 1, 7).setValue(dataCadastro);
        console.log('✅ [addPessoa] Pessoa atualizada com sucesso');
        return createResponse(true, 'Pessoa atualizada com sucesso');
      }
    }

    const newId = values.length;
    const newRow = [
      newId,
      cpf,
      nome,
      email,
      telefone,
      embeddingJson,
      dataCadastro,
      ''
    ];

    pessoasSheet.appendRow(newRow);

    console.log('✅ [addPessoa] Nova pessoa cadastrada:', nome);
    return createResponse(true, 'Pessoa cadastrada com sucesso');
  } catch (error) {
    console.error('❌ [addPessoa] Erro:', error);
    return createResponse(false, 'Erro ao cadastrar pessoa: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: ADD MOVEMENT LOG
// ============================================================================
function addMovementLog(data) {
  try {
    const people = data.people || [];

    console.log('📥 [addMovementLog] Recebendo', people.length, 'log(s)');

    if (people.length === 0) {
      return createResponse(false, 'Nenhum log para processar');
    }

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    let logsSheet = ss.getSheetByName('LOGS');

    if (!logsSheet) {
      console.log('📝 Criando aba LOGS...');
      logsSheet = ss.insertSheet('LOGS');
      logsSheet.appendRow(['TIMESTAMP', 'CPF', 'NOME', 'CONFIDENCE', 'TIPO', 'PERSON_ID', 'OPERADOR']);
    }

    let count = 0;

    for (const person of people) {
      const timestamp = person.timestamp || new Date().toISOString();
      const cpf = person.cpf || '';
      const personName = person.personName || person.nome || '';
      const confidence = person.confidence || 0;
      const tipo = (person.tipo || 'RECONHECIMENTO').toString().toUpperCase();
      const personId = person.personId || cpf;
      const operadorNome = person.operadorNome || 'Sistema';

      logsSheet.appendRow([
        timestamp,
        cpf,
        personName,
        confidence,
        tipo,
        personId,
        operadorNome
      ]);

      if (cpf && tipo !== 'RECONHECIMENTO' && tipo !== 'FACIAL') {
        atualizarMovimentacaoPessoa(cpf, tipo);
      }

      count++;
    }

    console.log('✅ [addMovementLog]', count, 'log(s) registrado(s)');
    return createResponse(true, count + ' log(s) registrado(s)', {
      data: { total: count }
    });
  } catch (error) {
    console.error('❌ [addMovementLog] Erro:', error);
    return createResponse(false, 'Erro ao registrar logs: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: GET ALUNOS
// ============================================================================
function getAlunos(data) {
  try {
    const nomeAba = data.nomeAba;
    const numeroOnibus = data.numeroOnibus;

    console.log('📥 [getAlunos] Buscando alunos:', nomeAba, 'Ônibus:', numeroOnibus);

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const sheet = ss.getSheetByName(nomeAba);

    if (!sheet) {
      return createResponse(false, 'Aba não encontrada: ' + nomeAba);
    }

    const data_range = sheet.getDataRange();
    const values = data_range.getValues();

    const alunos = [];

    for (let i = 1; i < values.length; i++) {
      const row = values[i];

      const onibus = String(row[6]).trim();

      if (numeroOnibus && onibus !== numeroOnibus) {
        continue;
      }

      const aluno = {
        nome: row[0],
        cpf: String(row[1]).trim(),
        id_passeio: row[2] || '',
        turma: row[3] || '',
        embarque: String(row[4] || 'NAO').toUpperCase(),
        retorno: String(row[5] || 'NAO').toUpperCase(),
        onibus: onibus,
        tem_qr: String(row[7] || 'NAO').toUpperCase()
      };

      alunos.push(aluno);
    }

    console.log('✅ [getAlunos] Alunos encontrados:', alunos.length);
    return createResponse(true, alunos.length + ' alunos encontrados', { data: alunos });
  } catch (error) {
    console.error('❌ Erro ao buscar alunos:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÕES DE COMPATIBILIDADE
// ============================================================================
function cadastrarFacial(data) {
  console.log('ℹ️ [cadastrarFacial] Redirecionando para addPessoa...');
  return addPessoa(data);
}

function registrarLog(data) {
  console.log('ℹ️ [registrarLog] Redirecionando para addMovementLog...');
  return addMovementLog({
    people: [{
      cpf: data.cpf,
      personName: data.nome,
      confidence: data.confidence || 0,
      tipo: data.tipo || 'reconhecimento',
      timestamp: new Date().toISOString()
    }]
  });
}

function syncEmbedding(data) {
  console.log('ℹ️ [syncEmbedding] Redirecionando para addPessoa...');
  return addPessoa(data);
}

// ============================================================================
// FUNÇÃO: GET ALL LOGS
// ============================================================================
function getAllLogs() {
  try {
    console.log('📥 [getAllLogs] Buscando todos os logs da aba LOGS...');

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const logsSheet = ss.getSheetByName('LOGS');

    if (!logsSheet) {
      console.error('❌ Aba LOGS não encontrada');
      return createResponse(false, 'Aba LOGS não encontrada na planilha');
    }

    const data_range = logsSheet.getDataRange();
    const values = data_range.getValues();

    const logs = [];

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      if (!row[0]) continue;

      const log = {
        timestamp: row[0],
        cpf: row[1] || '',
        nome: row[2] || '',
        confidence: row[3] || 0,
        tipo: row[4] || '',
        person_id: row[5] || '',
        operador: row[6] || ''
      };

      logs.push(log);
    }

    console.log('✅ [getAllLogs] ' + logs.length + ' logs encontrados');
    return createResponse(true, logs.length + ' logs encontrados', { data: logs });
  } catch (error) {
    console.error('❌ Erro ao buscar logs:', error);
    return createResponse(false, 'Erro ao buscar logs: ' + error.message);
  }
}

// ============================================================================
// FUNÇÕES AUXILIARES
// ============================================================================
function atualizarMovimentacaoPessoa(cpf, movimentacao) {
  if (!cpf) return;
  const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
  const pessoasSheet = ss.getSheetByName('PESSOAS');

  if (!pessoasSheet) {
    console.error('❌ Aba PESSOAS não encontrada ao atualizar movimentação');
    return;
  }

  garantirColunaMovimentacao(pessoasSheet);

  const lastRow = pessoasSheet.getLastRow();
  if (lastRow < 2) return;

  const cpfRange = pessoasSheet.getRange(2, 2, lastRow - 1, 1);
  const cpfValues = cpfRange.getValues();

  for (let i = 0; i < cpfValues.length; i++) {
    const cpfSheet = String(cpfValues[i][0] || '').trim();
    if (cpfSheet === cpf) {
      pessoasSheet.getRange(i + 2, MOVIMENTACAO_COLUMN_INDEX).setValue(movimentacao);
      console.log(`🔄 Atualizada movimentação de ${cpf} para ${movimentacao}`);
      return;
    }
  }

  console.log(`⚠️ CPF ${cpf} não encontrado para atualizar movimentação`);
}

function garantirColunaMovimentacao(pessoasSheet) {
  const lastColumn = pessoasSheet.getLastColumn();
  if (lastColumn < MOVIMENTACAO_COLUMN_INDEX) {
    pessoasSheet.insertColumnsAfter(lastColumn, MOVIMENTACAO_COLUMN_INDEX - lastColumn);
  }

  const headerCell = pessoasSheet.getRange(1, MOVIMENTACAO_COLUMN_INDEX);
  if (headerCell.getValue() !== 'MOVIMENTAÇÃO') {
    headerCell.setValue('MOVIMENTAÇÃO');
  }
}

function createResponse(success, message, data = {}) {
  const response = {
    success: success,
    message: message,
    timestamp: new Date().toISOString(),
    ...data
  };

  return ContentService
    .createTextOutput(JSON.stringify(response))
    .setMimeType(ContentService.MimeType.JSON);
}
