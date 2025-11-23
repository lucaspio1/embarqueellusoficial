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

function createResponse(success, message, data = {}) {
  const response = {
    success: success,
    message: message,
    timestamp: new Date().toISOString(),
    ...data,
  };

  return ContentService.createTextOutput(JSON.stringify(response)).setMimeType(
    ContentService.MimeType.JSON,
  );
}

function garantirColunaMovimentacao(pessoasSheet) {
  try {
    const lastColumn = pessoasSheet.getLastColumn();

    // Se a planilha tem menos colunas que o necessário, adicionar colunas
    if (lastColumn < MOVIMENTACAO_COLUMN_INDEX) {
      const colunasParaAdicionar = MOVIMENTACAO_COLUMN_INDEX - lastColumn;

      // Se a planilha está vazia (lastColumn = 0), usar método diferente
      if (lastColumn === 0) {
        // Planilha vazia - não fazer nada, o header será criado depois
        console.log('⚠️ Planilha vazia, pulando inserção de colunas');
      } else {
        // Inserir colunas depois da última coluna existente
        console.log(`📝 Inserindo ${colunasParaAdicionar} coluna(s) após coluna ${lastColumn}`);
        pessoasSheet.insertColumnsAfter(lastColumn, colunasParaAdicionar);
      }
    }

    // Garantir que o cabeçalho está correto
    const headerCell = pessoasSheet.getRange(1, MOVIMENTACAO_COLUMN_INDEX);
    const currentValue = headerCell.getValue();

    if (currentValue !== 'MOVIMENTAÇÃO') {
      console.log(`📝 Atualizando cabeçalho da coluna ${MOVIMENTACAO_COLUMN_INDEX} de "${currentValue}" para "MOVIMENTAÇÃO"`);
      headerCell.setValue('MOVIMENTAÇÃO');
    }

    console.log('✅ Coluna MOVIMENTAÇÃO garantida');
  } catch (error) {
    console.error('❌ Erro ao garantir coluna movimentação:', error);
    throw new Error('Falha ao configurar coluna MOVIMENTAÇÃO: ' + error.message);
  }
}

function atualizarMovimentacaoPessoa(cpf, movimentacao) {
  if (!cpf || !movimentacao) {
    return;
  }

  const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
  const pessoasSheet = ss.getSheetByName('PESSOAS');

  if (!pessoasSheet) {
    console.error('❌ Aba PESSOAS não encontrada ao atualizar movimentação');
    return;
  }

  garantirColunaMovimentacao(pessoasSheet);

  const lastRow = pessoasSheet.getLastRow();
  if (lastRow < 2) {
    return;
  }

  const cpfRange = pessoasSheet.getRange(2, 2, lastRow - 1, 1);
  const cpfValues = cpfRange.getValues();

  for (let i = 0; i < cpfValues.length; i++) {
    const cpfSheet = String(cpfValues[i][0] || '').trim();
    if (cpfSheet === cpf) {
      pessoasSheet
        .getRange(i + 2, MOVIMENTACAO_COLUMN_INDEX)
        .setValue(movimentacao);
      console.log(`🔄 Atualizada movimentação de ${cpf} para ${movimentacao}`);
      return;
    }
  }

  console.log(`⚠️ CPF ${cpf} não encontrado para atualizar movimentação`);
}

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
      case 'encerrarViagem':
        return encerrarViagem(data);
      case 'listarViagens':
        return listarViagens();
      case 'enviarTodosParaQuarto':
        return enviarTodosParaQuarto();
      case 'getEventos':
        return getEventos(data);
      case 'marcarEventoProcessado':
        return marcarEventoProcessado(data);
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
      case 'listarViagens':
        return listarViagens();
      case 'encerrarViagem':
        try {
          return encerrarViagem({
            inicio_viagem: params.inicio_viagem || params.inicioViagem,
            fim_viagem: params.fim_viagem || params.fimViagem
          });
        } catch (e) {
          return createResponse(false, 'Erro ao encerrar viagem via GET: ' + e.message);
        }
      case 'getEventos':
        return getEventos({ timestamp: params.timestamp });
      case 'marcarEventoProcessado':
        return marcarEventoProcessado({ evento_id: params.evento_id });
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
        movimentacao: (row[MOVIMENTACAO_COLUMN_INDEX - 1] || '').toString(),
        inicio_viagem: row[8] || '',
        fim_viagem: row[9] || ''
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
// FUNÇÃO: GET ALL STUDENTS
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

    // ✅ CORREÇÃO: Sequência das colunas: ID, NOME, TURMA, CPF, TELEFONE, ID-PASSEIO, CONTROLE, INICIO VIAGEM, FIM VIAGEM
    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      if (!row[1]) continue; // Verifica se há nome (coluna B)

      const aluno = {
        cpf: String(row[3] || '').trim(),        // Coluna D (CPF)
        nome: row[1] || '',                      // Coluna B (NOME)
        email: '',                               // Email não existe na planilha
        telefone: row[4] || '',                  // Coluna E (TELEFONE)
        turma: row[2] || '',                     // Coluna C (TURMA)
        facial_status: 'NAO',                    // Não mapeado na planilha atual
        tem_qr: 'NAO',                           // Não mapeado na planilha atual
        inicio_viagem: row[7] || '',             // Coluna H (INICIO VIAGEM)
        fim_viagem: row[8] || ''                 // Coluna I (FIM VIAGEM)
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
    const movimentacaoValor = (data.movimentacao || '')
      .toString()
      .trim()
      .toUpperCase();
    const inicioViagem = data.inicio_viagem || data.inicioViagem || '';
    const fimViagem = data.fim_viagem || data.fimViagem || '';

    console.log('📥 [addPessoa] Cadastrando pessoa:', nome, 'CPF:', cpf);

    if (!cpf || !nome || !embedding) {
      return createResponse(false, 'CPF, nome e embedding são obrigatórios');
    }

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    let pessoasSheet = ss.getSheetByName('PESSOAS');

    if (!pessoasSheet) {
      console.log('📝 Criando aba PESSOAS...');
      pessoasSheet = ss.insertSheet('PESSOAS');
      pessoasSheet.appendRow(['ID', 'CPF', 'NOME', 'EMAIL', 'TELEFONE', 'EMBEDDING', 'DATA_CADASTRO', 'MOVIMENTAÇÃO', 'INCIO VIAGEM', 'FIM VIAGEM']);
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
        if (movimentacaoValor) {
          pessoasSheet
            .getRange(i + 1, MOVIMENTACAO_COLUMN_INDEX)
            .setValue(movimentacaoValor);
        }
        if (inicioViagem) {
          pessoasSheet.getRange(i + 1, 9).setValue(inicioViagem);
        }
        if (fimViagem) {
          pessoasSheet.getRange(i + 1, 10).setValue(fimViagem);
        }
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
      movimentacaoValor,
      inicioViagem,
      fimViagem
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
// FUNÇÃO: ADD MOVEMENT LOG (✅ COM DEDUPLICAÇÃO)
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
      logsSheet.appendRow(['TIMESTAMP', 'CPF', 'NOME', 'CONFIDENCE', 'TIPO', 'PERSON_ID', 'OPERADOR', 'INICIO_VIAGEM', 'FIM_VIAGEM']);
    }

    // ✅ DEDUPLICAÇÃO: Buscar logs existentes (apenas colunas necessárias)
    const lastRow = logsSheet.getLastRow();
    let logsExistentes = new Set();

    if (lastRow > 1) {
      console.log('🔍 [addMovementLog] Carregando logs existentes para deduplicação...');
      const timestampCol = logsSheet.getRange(2, 1, lastRow - 1, 1).getValues();
      const cpfCol = logsSheet.getRange(2, 2, lastRow - 1, 1).getValues();
      const tipoCol = logsSheet.getRange(2, 5, lastRow - 1, 1).getValues();

      for (let i = 0; i < timestampCol.length; i++) {
        if (!timestampCol[i][0]) break;

        const chave = `${cpfCol[i][0]}_${timestampCol[i][0]}_${tipoCol[i][0]}`;
        logsExistentes.add(chave);
      }

      console.log(`✅ ${logsExistentes.size} log(s) existente(s) carregado(s)`);
    }

    let count = 0;
    let duplicados = 0;

    for (const person of people) {
      const timestamp = person.timestamp || new Date().toISOString();
      const cpf = person.cpf || '';
      const personName = person.personName || person.nome || '';
      const confidence = person.confidence || 0;
      const tipo = (person.tipo || 'RECONHECIMENTO').toString().toUpperCase();
      const movimentacaoRecebida = (
        person.movimentacao ||
        person.movimento ||
        ''
      )
        .toString()
        .trim();
      const personId = person.personId || cpf;
      const operadorNome = person.operadorNome || 'Sistema';
      const inicioViagem = person.inicio_viagem || person.inicioViagem || '';
      const fimViagem = person.fim_viagem || person.fimViagem || '';

      // ✅ VERIFICAR SE JÁ EXISTE
      const chave = `${cpf}_${timestamp}_${tipo}`;
      if (logsExistentes.has(chave)) {
        duplicados++;
        if (duplicados <= 3) {
          console.log(`⚠️ Duplicado ignorado: ${personName} - ${timestamp}`);
        }
        continue; // Pular este log
      }

      // ✅ ADICIONAR LOG NOVO
      logsSheet.appendRow([
        timestamp,
        cpf,
        personName,
        confidence,
        tipo,
        personId,
        operadorNome,
        inicioViagem,
        fimViagem
      ]);

      // Adicionar ao Set para evitar duplicatas dentro do mesmo batch
      logsExistentes.add(chave);

      let movimentacao = movimentacaoRecebida;
      if (!movimentacao) {
        const tipoNormalizado = tipo.trim();
        if (tipoNormalizado !== 'RECONHECIMENTO' && tipoNormalizado !== 'FACIAL') {
          movimentacao = tipoNormalizado;
        }
      }

      if (cpf && movimentacao) {
        atualizarMovimentacaoPessoa(cpf, movimentacao.toUpperCase());
      }

      count++;
    }

    console.log('✅ [addMovementLog]', count, 'log(s) adicionado(s),', duplicados, 'duplicado(s) ignorado(s)');
    return createResponse(true, count + ' log(s) adicionado(s), ' + duplicados + ' duplicado(s) ignorado(s)', {
      data: {
        total: count,
        duplicados: duplicados,
        recebidos: people.length
      }
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
        tem_qr: String(row[7] || 'NAO').toUpperCase(),
        inicio_viagem: row[8] || '',
        fim_viagem: row[9] || ''
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
      movimentacao: data.movimentacao || data.tipo || '',
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
// AÇÕES CRÍTICAS
// ============================================================================

/**
 * NOVA FUNÇÃO: Listar viagens disponíveis
 * Busca todas as viagens únicas (baseado em inicio_viagem e fim_viagem) na aba ALUNOS
 */
function listarViagens() {
  try {
    console.log('📥 [listarViagens] Buscando viagens disponíveis...');

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const abaAlunos = ss.getSheetByName('ALUNOS');

    if (!abaAlunos) {
      return createResponse(false, 'Aba ALUNOS não encontrada');
    }

    const lastRow = abaAlunos.getLastRow();
    if (lastRow <= 1) {
      return createResponse(true, 'Nenhuma viagem encontrada', { viagens: [] });
    }

    const data_range = abaAlunos.getDataRange();
    const values = data_range.getValues();

    // Usar Map para armazenar viagens únicas
    const viagensMap = new Map();

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      // Coluna I = índice 8, Coluna J = índice 9
      const inicioViagem = row[8] || '';
      const fimViagem = row[9] || '';

      if (inicioViagem && fimViagem) {
        const chave = inicioViagem + '|' + fimViagem;
        if (!viagensMap.has(chave)) {
          viagensMap.set(chave, {
            inicio_viagem: inicioViagem,
            fim_viagem: fimViagem
          });
        }
      }
    }

    const viagens = Array.from(viagensMap.values());
    console.log('✅ [listarViagens] ' + viagens.length + ' viagem(ns) encontrada(s)');

    return createResponse(true, viagens.length + ' viagem(ns) encontrada(s)', { viagens: viagens });
  } catch (error) {
    console.error('❌ [listarViagens] Erro:', error);
    return createResponse(false, 'Erro ao listar viagens: ' + error.message);
  }
}

/**
 * AÇÃO CRÍTICA: Encerrar viagem (ATUALIZADA)
 * Limpa dados de uma viagem específica ou de todas as viagens
 * ATENÇÃO: OPERAÇÃO IRREVERSÍVEL! Dados da viagem selecionada serão perdidos!
 */
function encerrarViagem(data) {
  try {
    console.log('🔥 [CRÍTICO] Iniciando encerramento de viagem...');

    const inicioViagem = data ? (data.inicio_viagem || data.inicioViagem) : null;
    const fimViagem = data ? (data.fim_viagem || data.fimViagem) : null;

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);

    // Se não especificou datas, limpa TUDO (comportamento antigo)
    if (!inicioViagem || !fimViagem) {
      console.log('⚠️ Nenhuma data especificada - limpando TODAS as viagens');

      // 1. Limpar aba PESSOAS
      const abaPessoas = ss.getSheetByName('PESSOAS');
      if (abaPessoas) {
        const lastRow = abaPessoas.getLastRow();
        if (lastRow > 1) {
          abaPessoas.getRange(2, 1, lastRow - 1, abaPessoas.getLastColumn()).clearContent();
          console.log('✅ Aba PESSOAS limpa');
        }
      }

      // 2. Limpar aba LOGS
      const abaLogs = ss.getSheetByName('LOGS');
      if (abaLogs) {
        const lastRow = abaLogs.getLastRow();
        if (lastRow > 1) {
          abaLogs.getRange(2, 1, lastRow - 1, abaLogs.getLastColumn()).clearContent();
          console.log('✅ Aba LOGS limpa');
        }
      }

      // 3. Limpar aba ALUNOS
      const abaAlunos = ss.getSheetByName('ALUNOS');
      if (abaAlunos) {
        const lastRow = abaAlunos.getLastRow();
        if (lastRow > 1) {
          abaAlunos.getRange(2, 1, lastRow - 1, abaAlunos.getLastColumn()).clearContent();
          console.log('✅ Aba ALUNOS limpa');
        }
      }

      console.log('✅ [CRÍTICO] Todas as viagens encerradas com sucesso!');

      // Registrar evento para notificar clientes
      try {
        registrarEvento('VIAGEM_ENCERRADA', {
          tipo: 'TODAS',
          abas_limpas: ['PESSOAS', 'LOGS', 'ALUNOS']
        });
      } catch (errEvento) {
        console.error('⚠️ Erro ao registrar evento (não crítico):', errEvento);
      }

      return createResponse(true, 'Todas as viagens foram encerradas! Todas as abas foram limpas.', {
        abas_limpas: ['PESSOAS', 'LOGS', 'ALUNOS']
      });
    }

    // Se especificou datas, limpa APENAS essa viagem
    console.log('🎯 Encerrando viagem específica:', inicioViagem, 'a', fimViagem);

    let totalRemovidos = 0;

    // 1. Limpar aba PESSOAS (filtrado por data)
    const abaPessoas = ss.getSheetByName('PESSOAS');
    if (abaPessoas) {
      totalRemovidos += limparAbaFiltrada(abaPessoas, inicioViagem, fimViagem, 9, 10);
    }

    // 2. Limpar aba LOGS (filtrado por data)
    const abaLogs = ss.getSheetByName('LOGS');
    if (abaLogs) {
      // TIMESTAMP, CPF, NOME, CONFIDENCE, TIPO, PERSON_ID, OPERADOR, INICIO_VIAGEM, FIM_VIAGEM
      totalRemovidos += limparAbaFiltrada(abaLogs, inicioViagem, fimViagem, 8, 9);
    }

    // 3. Limpar aba ALUNOS (filtrado por data)
    const abaAlunos = ss.getSheetByName('ALUNOS');
    if (abaAlunos) {
      // Colunas I=9 e J=10 na aba ALUNOS
      totalRemovidos += limparAbaFiltrada(abaAlunos, inicioViagem, fimViagem, 9, 10);
    }

    console.log('✅ [CRÍTICO] Viagem encerrada com sucesso! Total de registros removidos:', totalRemovidos);

    // Registrar evento para notificar clientes
    try {
      registrarEvento('VIAGEM_ENCERRADA', {
        tipo: 'ESPECIFICA',
        inicio_viagem: inicioViagem,
        fim_viagem: fimViagem,
        total_removidos: totalRemovidos
      });
    } catch (errEvento) {
      console.error('⚠️ Erro ao registrar evento (não crítico):', errEvento);
    }

    return createResponse(true, 'Viagem encerrada com sucesso! ' + totalRemovidos + ' registro(s) removido(s).', {
      inicio_viagem: inicioViagem,
      fim_viagem: fimViagem,
      total_removidos: totalRemovidos
    });

  } catch (error) {
    console.error('❌ [CRÍTICO] Erro ao encerrar viagem:', error);
    return createResponse(false, 'Erro ao encerrar viagem: ' + error.message);
  }
}

/**
 * Função auxiliar para limpar registros filtrados por data de viagem
 */
function limparAbaFiltrada(sheet, inicioViagem, fimViagem, colunaInicio, colunaFim) {
  const lastRow = sheet.getLastRow();
  if (lastRow <= 1) {
    console.log('⚠️ Aba', sheet.getName(), 'vazia ou só com header');
    return 0;
  }

  const values = sheet.getRange(2, 1, lastRow - 1, sheet.getLastColumn()).getValues();
  const linhasParaRemover = [];

  console.log('🔍 [limparAbaFiltrada] Aba:', sheet.getName());
  console.log('🔍 Buscando viagem:', inicioViagem, 'a', fimViagem);
  console.log('🔍 Colunas:', colunaInicio, 'e', colunaFim);

  // Identificar linhas que correspondem à viagem
  for (let i = 0; i < values.length; i++) {
    const row = values[i];
    let inicio = row[colunaInicio - 1];
    let fim = row[colunaFim - 1];

    // Converter Date objects para ISO string se necessário
    if (inicio instanceof Date) {
      inicio = inicio.toISOString();
    } else if (inicio) {
      inicio = inicio.toString();
    } else {
      inicio = '';
    }

    if (fim instanceof Date) {
      fim = fim.toISOString();
    } else if (fim) {
      fim = fim.toString();
    } else {
      fim = '';
    }

    // Comparar datas
    const match = inicio === inicioViagem && fim === fimViagem;

    if (i < 3) { // Log primeiras 3 linhas para debug
      console.log('📋 Linha', i + 2, '- Inicio:', inicio, 'Fim:', fim, 'Match:', match);
    }

    if (match) {
      linhasParaRemover.push(i + 2); // +2 porque arrays começam em 0 e pulamos o header
    }
  }

  // Remover linhas de trás para frente para não afetar índices
  for (let i = linhasParaRemover.length - 1; i >= 0; i--) {
    sheet.deleteRow(linhasParaRemover[i]);
  }

  console.log('✅ Aba', sheet.getName(), ':', linhasParaRemover.length, 'registro(s) removido(s)');
  return linhasParaRemover.length;
}

/**
 * AÇÃO CRÍTICA: Enviar todos para QUARTO
 * Atualiza a movimentação de TODAS as pessoas para 'QUARTO'
 * Útil para início/fim de dia ou reset de localização
 */
function enviarTodosParaQuarto() {
  try {
    console.log('🔄 [CRÍTICO] Enviando todos para QUARTO...');

    // Passo 1: Abrir planilha
    console.log('📝 Passo 1: Abrindo planilha...');
    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const abaPessoas = ss.getSheetByName('PESSOAS');

    if (!abaPessoas) {
      console.error('❌ Aba PESSOAS não encontrada');
      return createResponse(false, 'Aba PESSOAS não encontrada');
    }
    console.log('✅ Aba PESSOAS encontrada');

    // Passo 2: Verificar e garantir coluna movimentação
    console.log('📝 Passo 2: Garantindo coluna MOVIMENTAÇÃO...');
    try {
      garantirColunaMovimentacao(abaPessoas);
    } catch (errColuna) {
      console.error('❌ Erro ao garantir coluna:', errColuna);
      return createResponse(false, 'Erro ao configurar coluna MOVIMENTAÇÃO: ' + errColuna.message);
    }

    // Passo 3: Verificar quantas linhas temos
    console.log('📝 Passo 3: Verificando quantidade de pessoas...');
    const lastRow = abaPessoas.getLastRow();
    const lastColumn = abaPessoas.getLastColumn();

    console.log(`📊 Última linha: ${lastRow}, Última coluna: ${lastColumn}`);

    if (lastRow <= 1) {
      console.log('⚠️ Nenhuma pessoa para atualizar');
      return createResponse(true, 'Nenhuma pessoa para atualizar', {
        pessoas_atualizadas: 0
      });
    }

    // Verificar se a coluna MOVIMENTACAO existe
    if (lastColumn < MOVIMENTACAO_COLUMN_INDEX) {
      console.error(`❌ Planilha não tem coluna ${MOVIMENTACAO_COLUMN_INDEX}. Última coluna: ${lastColumn}`);
      return createResponse(false, `Erro: Planilha não possui a coluna ${MOVIMENTACAO_COLUMN_INDEX} necessária`);
    }

    // Passo 4: Preparar valores para atualização
    console.log('📝 Passo 4: Preparando valores...');
    const numPessoas = lastRow - 1;
    const valores = [];

    for (let i = 0; i < numPessoas; i++) {
      valores.push(['QUARTO']);
    }

    console.log(`📊 Total de ${numPessoas} pessoa(s) serão atualizadas`);

    // Passo 5: Atualizar células em lote
    console.log('📝 Passo 5: Atualizando células...');
    try {
      const range = abaPessoas.getRange(2, MOVIMENTACAO_COLUMN_INDEX, numPessoas, 1);
      range.setValues(valores);
      console.log('✅ Células atualizadas com sucesso');
    } catch (errUpdate) {
      console.error('❌ Erro ao atualizar células:', errUpdate);
      return createResponse(false, 'Erro ao atualizar células: ' + errUpdate.message);
    }

    // Passo 6: Confirmar sucesso
    console.log(`✅ [CRÍTICO] ${numPessoas} pessoa(s) enviada(s) para QUARTO`);

    return createResponse(true, numPessoas + ' pessoa(s) enviada(s) para QUARTO', {
      pessoas_atualizadas: numPessoas
    });

  } catch (error) {
    console.error('❌ [CRÍTICO] Erro ao enviar para quarto:', error);
    console.error('❌ Stack trace:', error.stack);
    return createResponse(false, 'Erro ao enviar para quarto: ' + error.message + ' | Stack: ' + error.stack);
  }
}

// ============================================================================
// SISTEMA DE EVENTOS
// ============================================================================

/**
 * Registra um evento na aba EVENTOS
 * Eventos são usados para notificar clientes sobre ações críticas
 */
function registrarEvento(tipoEvento, dados) {
  try {
    console.log('📢 [registrarEvento] Tipo:', tipoEvento, 'Dados:', JSON.stringify(dados));

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    let eventosSheet = ss.getSheetByName('EVENTOS');

    // Criar aba EVENTOS se não existir
    if (!eventosSheet) {
      console.log('📝 Criando aba EVENTOS...');
      eventosSheet = ss.insertSheet('EVENTOS');
      eventosSheet.appendRow([
        'ID',
        'TIMESTAMP',
        'TIPO_EVENTO',
        'INICIO_VIAGEM',
        'FIM_VIAGEM',
        'DADOS_ADICIONAIS',
        'PROCESSADO'
      ]);
    }

    // Gerar ID único baseado em timestamp
    const eventoId = 'EVT_' + new Date().getTime();
    const timestamp = new Date().toISOString();
    const inicioViagem = dados.inicio_viagem || dados.inicioViagem || '';
    const fimViagem = dados.fim_viagem || dados.fimViagem || '';
    const dadosAdicionais = JSON.stringify(dados);
    const processado = 'NAO';

    eventosSheet.appendRow([
      eventoId,
      timestamp,
      tipoEvento,
      inicioViagem,
      fimViagem,
      dadosAdicionais,
      processado
    ]);

    console.log('✅ Evento registrado:', eventoId);
    return eventoId;
  } catch (error) {
    console.error('❌ Erro ao registrar evento:', error);
    throw error;
  }
}

/**
 * Busca eventos pendentes (não processados)
 * Clientes chamam essa função periodicamente para verificar novos eventos
 */
function getEventos(data) {
  try {
    const timestampFiltro = data ? data.timestamp : null;
    console.log('📥 [getEventos] Buscando eventos... Filtro:', timestampFiltro);

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const eventosSheet = ss.getSheetByName('EVENTOS');

    if (!eventosSheet) {
      console.log('⚠️ Aba EVENTOS não existe ainda');
      return createResponse(true, 'Nenhum evento encontrado', { eventos: [] });
    }

    const lastRow = eventosSheet.getLastRow();
    if (lastRow <= 1) {
      console.log('⚠️ Nenhum evento registrado');
      return createResponse(true, 'Nenhum evento encontrado', { eventos: [] });
    }

    const data_range = eventosSheet.getDataRange();
    const values = data_range.getValues();

    const eventos = [];

    for (let i = 1; i < values.length; i++) {
      const row = values[i];

      const eventoId = row[0];
      const timestamp = row[1];
      const tipoEvento = row[2];
      const inicioViagem = row[3] || '';
      const fimViagem = row[4] || '';
      const dadosAdicionais = row[5] || '{}';
      const processado = String(row[6] || 'NAO').toUpperCase();

      // Filtrar apenas eventos não processados
      if (processado === 'NAO') {
        // Se tem filtro de timestamp, só retornar eventos mais recentes
        if (timestampFiltro) {
          const eventoTimestamp = new Date(timestamp).getTime();
          const filtroTimestamp = new Date(timestampFiltro).getTime();

          if (eventoTimestamp <= filtroTimestamp) {
            continue; // Pular eventos antigos
          }
        }

        let dadosParsed = {};
        try {
          dadosParsed = JSON.parse(dadosAdicionais);
        } catch (e) {
          console.log('⚠️ Erro ao parsear dados do evento', eventoId);
        }

        eventos.push({
          id: eventoId,
          timestamp: timestamp,
          tipo_evento: tipoEvento,
          inicio_viagem: inicioViagem,
          fim_viagem: fimViagem,
          dados: dadosParsed,
          processado: processado
        });
      }
    }

    console.log('✅ [getEventos] ' + eventos.length + ' evento(s) pendente(s) encontrado(s)');
    return createResponse(true, eventos.length + ' evento(s) encontrado(s)', { eventos: eventos });
  } catch (error) {
    console.error('❌ Erro ao buscar eventos:', error);
    return createResponse(false, 'Erro ao buscar eventos: ' + error.message);
  }
}

/**
 * Marca um evento como processado
 * Clientes devem chamar essa função após processar o evento localmente
 */
function marcarEventoProcessado(data) {
  try {
    const eventoId = data.evento_id || data.eventoId || data.id;
    console.log('📥 [marcarEventoProcessado] Evento:', eventoId);

    if (!eventoId) {
      return createResponse(false, 'ID do evento é obrigatório');
    }

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const eventosSheet = ss.getSheetByName('EVENTOS');

    if (!eventosSheet) {
      return createResponse(false, 'Aba EVENTOS não encontrada');
    }

    const lastRow = eventosSheet.getLastRow();
    if (lastRow <= 1) {
      return createResponse(false, 'Nenhum evento encontrado');
    }

    const data_range = eventosSheet.getDataRange();
    const values = data_range.getValues();

    // Procurar o evento pelo ID
    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      const rowEventoId = row[0];

      if (rowEventoId === eventoId) {
        // Marcar como processado (coluna 7 = índice 6)
        eventosSheet.getRange(i + 1, 7).setValue('SIM');
        console.log('✅ Evento', eventoId, 'marcado como processado');
        return createResponse(true, 'Evento marcado como processado');
      }
    }

    console.log('⚠️ Evento não encontrado:', eventoId);
    return createResponse(false, 'Evento não encontrado: ' + eventoId);
  } catch (error) {
    console.error('❌ Erro ao marcar evento:', error);
    return createResponse(false, 'Erro ao marcar evento: ' + error.message);
  }
}