// ============================================================================
// GOOGLE APPS SCRIPT - ELLUS EMBARQUE
// ============================================================================
// Este script gerencia a integração entre o app Flutter e o Google Sheets
// Planilha com as seguintes abas:
// - PESSOAS: Lista de pessoas com embeddings faciais
// - LOGIN: Usuários do sistema com credenciais
// - LOGS: Logs de reconhecimento facial
// - Outras abas de passeios/embarques
// ============================================================================

const SPREADSHEET_ID = '1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U';

function doPost(e) {
  try {
    // Log da requisição recebida
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

      case 'getAlunos':
        return getAlunos(data);

      case 'cadastrarFacial':
        return cadastrarFacial(data);

      case 'registrarLog':
        return registrarLog(data);

      case 'syncEmbedding':
        return syncEmbedding(data);

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
  return ContentService.createTextOutput('API Ellus Embarque - Funcionando!');
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

    // Primeira linha é cabeçalho: ID, NOME, CPF, SENHA, PERFIL
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
// FUNÇÃO: GET ALL USERS (para sincronização offline)
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

    // Primeira linha é cabeçalho: ID, NOME, CPF, SENHA, PERFIL
    for (let i = 1; i < values.length; i++) {
      const row = values[i];

      // Pular linhas vazias
      if (!row[2] || !row[3]) continue;

      const user = {
        id: row[0],
        nome: row[1],
        cpf: String(row[2]).trim(),
        senha: String(row[3]).trim(), // Senha será hasheada no app
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
// FUNÇÃO: GET ALL PEOPLE (com embeddings)
// ============================================================================
function getAllPeople() {
  try {
    console.log('📥 Buscando todas as pessoas com embeddings...');

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const pessoasSheet = ss.getSheetByName('PESSOAS');

    if (!pessoasSheet) {
      return createResponse(false, 'Aba PESSOAS não encontrada');
    }

    const data_range = pessoasSheet.getDataRange();
    const values = data_range.getValues();

    // Log do cabeçalho para debug
    console.log('📋 Cabeçalho da planilha PESSOAS:', values[0]);
    console.log('📋 Total de colunas:', values[0].length);

    // Cabeçalho: ID, NOME, CPF, EMAIL, TELEFONE, TURMA, EMBEDDING, TEM_QR
    const pessoas = [];

    for (let i = 1; i < values.length; i++) {
      const row = values[i];

      // Log da primeira pessoa para debug
      if (i === 1) {
        console.log('🔍 Debug primeira pessoa:');
        for (let col = 0; col < row.length; col++) {
          const value = row[col];
          const preview = typeof value === 'string' && value.length > 50
            ? value.substring(0, 50) + '...'
            : value;
          console.log(`  Coluna ${col}: ${preview} (tipo: ${typeof value})`);
        }
      }

      const pessoa = {
        id: row[0],
        nome: row[1],
        cpf: String(row[2]).trim(),
        email: row[3] || '',
        telefone: row[4] || '',
        turma: row[5] || '',
        embedding: row[6] || null, // JSON string ou null
        tem_qr: String(row[7] || 'NAO').toUpperCase()
      };

      // Apenas adicionar pessoas com embedding válido
      if (pessoa.embedding && pessoa.embedding.length > 0) {
        // Verificar se não é uma data
        const embeddingStr = String(pessoa.embedding);
        if (!embeddingStr.includes('T') && embeddingStr.startsWith('[')) {
          pessoas.push(pessoa);
        } else {
          console.log(`⚠️ Ignorando pessoa ${pessoa.nome} - embedding parece ser data ou formato inválido: ${embeddingStr.substring(0, 50)}`);
        }
      }
    }

    console.log('✅ Pessoas encontradas:', pessoas.length);
    return createResponse(true, pessoas.length + ' pessoas encontradas', { data: pessoas });

  } catch (error) {
    console.error('❌ Erro ao buscar pessoas:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: GET ALUNOS (de uma aba específica)
// ============================================================================
function getAlunos(data) {
  try {
    const nomeAba = data.nomeAba;
    const numeroOnibus = data.numeroOnibus;

    console.log('📥 Buscando alunos:', nomeAba, 'Ônibus:', numeroOnibus);

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const sheet = ss.getSheetByName(nomeAba);

    if (!sheet) {
      return createResponse(false, 'Aba não encontrada: ' + nomeAba);
    }

    const data_range = sheet.getDataRange();
    const values = data_range.getValues();

    const alunos = [];

    // Cabeçalho: NOME, CPF, ID_PASSEIO, TURMA, EMBARQUE, RETORNO, ONIBUS, TEM_QR
    for (let i = 1; i < values.length; i++) {
      const row = values[i];

      const onibus = String(row[6]).trim();

      // Filtrar por ônibus se especificado
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

    console.log('✅ Alunos encontrados:', alunos.length);
    return createResponse(true, alunos.length + ' alunos encontrados', { data: alunos });

  } catch (error) {
    console.error('❌ Erro ao buscar alunos:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: CADASTRAR FACIAL
// ============================================================================
function cadastrarFacial(data) {
  try {
    const cpf = data.cpf;
    const nome = data.nome;
    const email = data.email || '';
    const telefone = data.telefone || '';
    const embedding = data.embedding; // Array de números

    console.log('📥 Cadastrando facial:', nome, 'CPF:', cpf);

    if (!cpf || !nome || !embedding) {
      return createResponse(false, 'CPF, nome e embedding são obrigatórios');
    }

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const pessoasSheet = ss.getSheetByName('PESSOAS');

    if (!pessoasSheet) {
      return createResponse(false, 'Aba PESSOAS não encontrada');
    }

    // Converter embedding para JSON string
    const embeddingJson = JSON.stringify(embedding);

    // Verificar se já existe
    const data_range = pessoasSheet.getDataRange();
    const values = data_range.getValues();

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      const cpfSheet = String(row[2]).trim();

      if (cpfSheet === cpf) {
        // Atualizar linha existente
        pessoasSheet.getRange(i + 1, 2).setValue(nome); // NOME
        pessoasSheet.getRange(i + 1, 4).setValue(email); // EMAIL
        pessoasSheet.getRange(i + 1, 5).setValue(telefone); // TELEFONE
        pessoasSheet.getRange(i + 1, 7).setValue(embeddingJson); // EMBEDDING

        console.log('✅ Facial atualizada:', nome);
        return createResponse(true, 'Facial atualizada com sucesso');
      }
    }

    // Adicionar nova linha
    const newRow = [
      values.length, // ID
      nome,
      cpf,
      email,
      telefone,
      '', // TURMA
      embeddingJson,
      'SIM' // TEM_QR
    ];

    pessoasSheet.appendRow(newRow);

    console.log('✅ Nova facial cadastrada:', nome);
    return createResponse(true, 'Facial cadastrada com sucesso');

  } catch (error) {
    console.error('❌ Erro ao cadastrar facial:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: REGISTRAR LOG
// ============================================================================
function registrarLog(data) {
  try {
    const cpf = data.cpf;
    const nome = data.nome;
    const confidence = data.confidence || 0;
    const tipo = data.tipo || 'reconhecimento';

    console.log('📥 Registrando log:', nome, 'Confiança:', confidence);

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    let logsSheet = ss.getSheetByName('LOGS');

    // Criar aba LOGS se não existir
    if (!logsSheet) {
      logsSheet = ss.insertSheet('LOGS');
      logsSheet.appendRow(['TIMESTAMP', 'CPF', 'NOME', 'CONFIDENCE', 'TIPO']);
    }

    const timestamp = new Date().toISOString();
    logsSheet.appendRow([timestamp, cpf, nome, confidence, tipo]);

    console.log('✅ Log registrado');
    return createResponse(true, 'Log registrado com sucesso');

  } catch (error) {
    console.error('❌ Erro ao registrar log:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: SYNC EMBEDDING (sincronizar embedding individual)
// ============================================================================
function syncEmbedding(data) {
  try {
    const cpf = data.cpf;
    const nome = data.nome;
    const embedding = data.embedding;

    console.log('📥 Sincronizando embedding:', nome);

    if (!cpf || !embedding) {
      return createResponse(false, 'CPF e embedding são obrigatórios');
    }

    return cadastrarFacial(data);

  } catch (error) {
    console.error('❌ Erro ao sincronizar embedding:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO AUXILIAR: CREATE RESPONSE
// ============================================================================
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
-------------------------------------------------------

GS QUE ESTÁ IMPLEMENTADO AGORA

// ============================================================================
// GOOGLE APPS SCRIPT - ELLUS EMBARQUE
// ============================================================================
// Este script gerencia a integração entre o app Flutter e o Google Sheets
// Planilha com as seguintes abas:
// - PESSOAS: Lista de pessoas com embeddings faciais
// - LOGIN: Usuários do sistema com credenciais
// - LOGS: Logs de reconhecimento facial
// - Outras abas de passeios/embarques
// ============================================================================

const SPREADSHEET_ID = '1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U';

function doPost(e) {
  try {
    // Log da requisição recebida
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

      case 'getAlunos':
        return getAlunos(data);

      case 'cadastrarFacial':
        return cadastrarFacial(data);

      case 'registrarLog':
        return registrarLog(data);

      case 'syncEmbedding':
        return syncEmbedding(data);

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

      case 'getAlunos':
        // nomeAba e numeroOnibus podem vir por query
        return getAlunos({
          nomeAba: params.nomeAba,
          numeroOnibus: params.numeroOnibus
        });

      default:
        return ContentService
          .createTextOutput(JSON.stringify({
            success: false,
            message: 'Ação não reconhecida em GET: ' + action,
            timestamp: new Date().toISOString()
          }))
          .setMimeType(ContentService.MimeType.JSON);
    }
  } catch (err) {
    console.error('❌ [doGet] Erro:', err);
    return ContentService
      .createTextOutput(JSON.stringify({
        success: false,
        message: 'Erro no doGet: ' + err.message,
        timestamp: new Date().toISOString()
      }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// ============================================================================
// FUNÇÃO: GET ALL USERS (para sincronização offline)
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

    // Primeira linha é cabeçalho: ID, NOME, CPF, SENHA, PERFIL
    for (let i = 1; i < values.length; i++) {
      const row = values[i];

      // Pular linhas vazias
      if (!row[2] || !row[3]) continue;

      const user = {
        id: row[0],
        nome: row[1],
        cpf: String(row[2]).trim(),
        senha: String(row[3]).trim(), // Senha será hasheada no app
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
// FUNÇÃO: GET ALL PEOPLE (com embeddings)
// ============================================================================
function getAllPeople() {
  try {
    console.log('📥 Buscando todas as pessoas com embeddings...');

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const pessoasSheet = ss.getSheetByName('PESSOAS');

    if (!pessoasSheet) {
      return createResponse(false, 'Aba PESSOAS não encontrada');
    }

    const data_range = pessoasSheet.getDataRange();
    const values = data_range.getValues();

    // Log do cabeçalho para debug
    console.log('📋 Cabeçalho da planilha PESSOAS:', values[0]);
    console.log('📋 Total de colunas:', values[0].length);

    // Cabeçalho: ID, NOME, CPF, EMAIL, TELEFONE, TURMA, EMBEDDING, TEM_QR
    const pessoas = [];

    for (let i = 1; i < values.length; i++) {
      const row = values[i];

      // Log da primeira pessoa para debug
      if (i === 1) {
        console.log('🔍 Debug primeira pessoa:');
        for (let col = 0; col < row.length; col++) {
          const value = row[col];
          const preview = typeof value === 'string' && value.length > 50
            ? value.substring(0, 50) + '...'
            : value;
          console.log(`  Coluna ${col}: ${preview} (tipo: ${typeof value})`);
        }
      }

      const pessoa = {
        id: row[0],
        nome: row[1],
        cpf: String(row[2]).trim(),
        email: row[3] || '',
        telefone: row[4] || '',
        turma: row[5] || '',
        embedding: row[6] || null, // JSON string ou null
        tem_qr: String(row[7] || 'NAO').toUpperCase()
      };

      // Apenas adicionar pessoas com embedding válido
      if (pessoa.embedding && pessoa.embedding.length > 0) {
        // Verificar se não é uma data
        const embeddingStr = String(pessoa.embedding);
        if (!embeddingStr.includes('T') && embeddingStr.startsWith('[')) {
          pessoas.push(pessoa);
        } else {
          console.log(`⚠️ Ignorando pessoa ${pessoa.nome} - embedding parece ser data ou formato inválido: ${embeddingStr.substring(0, 50)}`);
        }
      }
    }

    console.log('✅ Pessoas encontradas:', pessoas.length);
    return createResponse(true, pessoas.length + ' pessoas encontradas', { data: pessoas });

  } catch (error) {
    console.error('❌ Erro ao buscar pessoas:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: GET ALUNOS (de uma aba específica)
// ============================================================================
function getAlunos(data) {
  try {
    const nomeAba = data.nomeAba;
    const numeroOnibus = data.numeroOnibus;

    console.log('📥 Buscando alunos:', nomeAba, 'Ônibus:', numeroOnibus);

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const sheet = ss.getSheetByName(nomeAba);

    if (!sheet) {
      return createResponse(false, 'Aba não encontrada: ' + nomeAba);
    }

    const data_range = sheet.getDataRange();
    const values = data_range.getValues();

    const alunos = [];

    // Cabeçalho: NOME, CPF, ID_PASSEIO, TURMA, EMBARQUE, RETORNO, ONIBUS, TEM_QR
    for (let i = 1; i < values.length; i++) {
      const row = values[i];

      const onibus = String(row[6]).trim();

      // Filtrar por ônibus se especificado
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

    console.log('✅ Alunos encontrados:', alunos.length);
    return createResponse(true, alunos.length + ' alunos encontrados', { data: alunos });

  } catch (error) {
    console.error('❌ Erro ao buscar alunos:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: CADASTRAR FACIAL
// ============================================================================
function cadastrarFacial(data) {
  try {
    const cpf = data.cpf;
    const nome = data.nome;
    const email = data.email || '';
    const telefone = data.telefone || '';
    const embedding = data.embedding; // Array de números

    console.log('📥 Cadastrando facial:', nome, 'CPF:', cpf);

    if (!cpf || !nome || !embedding) {
      return createResponse(false, 'CPF, nome e embedding são obrigatórios');
    }

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const pessoasSheet = ss.getSheetByName('PESSOAS');

    if (!pessoasSheet) {
      return createResponse(false, 'Aba PESSOAS não encontrada');
    }

    // Converter embedding para JSON string
    const embeddingJson = JSON.stringify(embedding);

    // Verificar se já existe
    const data_range = pessoasSheet.getDataRange();
    const values = data_range.getValues();

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      const cpfSheet = String(row[2]).trim();

      if (cpfSheet === cpf) {
        // Atualizar linha existente
        pessoasSheet.getRange(i + 1, 2).setValue(nome); // NOME
        pessoasSheet.getRange(i + 1, 4).setValue(email); // EMAIL
        pessoasSheet.getRange(i + 1, 5).setValue(telefone); // TELEFONE
        pessoasSheet.getRange(i + 1, 7).setValue(embeddingJson); // EMBEDDING

        console.log('✅ Facial atualizada:', nome);
        return createResponse(true, 'Facial atualizada com sucesso');
      }
    }

    // Adicionar nova linha
    const newRow = [
      values.length, // ID
      nome,
      cpf,
      email,
      telefone,
      '', // TURMA
      embeddingJson,
      'SIM' // TEM_QR
    ];

    pessoasSheet.appendRow(newRow);

    console.log('✅ Nova facial cadastrada:', nome);
    return createResponse(true, 'Facial cadastrada com sucesso');

  } catch (error) {
    console.error('❌ Erro ao cadastrar facial:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: REGISTRAR LOG
// ============================================================================
function registrarLog(data) {
  try {
    const cpf = data.cpf;
    const nome = data.nome;
    const confidence = data.confidence || 0;
    const tipo = data.tipo || 'reconhecimento';

    console.log('📥 Registrando log:', nome, 'Confiança:', confidence);

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    let logsSheet = ss.getSheetByName('LOGS');

    // Criar aba LOGS se não existir
    if (!logsSheet) {
      logsSheet = ss.insertSheet('LOGS');
      logsSheet.appendRow(['TIMESTAMP', 'CPF', 'NOME', 'CONFIDENCE', 'TIPO']);
    }

    const timestamp = new Date().toISOString();
    logsSheet.appendRow([timestamp, cpf, nome, confidence, tipo]);

    console.log('✅ Log registrado');
    return createResponse(true, 'Log registrado com sucesso');

  } catch (error) {
    console.error('❌ Erro ao registrar log:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO: SYNC EMBEDDING (sincronizar embedding individual)
// ============================================================================
function syncEmbedding(data) {
  try {
    const cpf = data.cpf;
    const nome = data.nome;
    const embedding = data.embedding;

    console.log('📥 Sincronizando embedding:', nome);

    if (!cpf || !embedding) {
      return createResponse(false, 'CPF e embedding são obrigatórios');
    }

    return cadastrarFacial(data);

  } catch (error) {
    console.error('❌ Erro ao sincronizar embedding:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// FUNÇÃO AUXILIAR: CREATE RESPONSE
// ============================================================================
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
