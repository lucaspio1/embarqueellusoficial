// ============================================================================
// GOOGLE APPS SCRIPT - ELLUS EMBARQUE (VERSÃO FINAL COM UPDATED_AT)
// ============================================================================
// CORREÇÕES APLICADAS:
// ✅ Coluna UPDATED_AT adicionada em PESSOAS e LOGS
// ✅ addPessoa agora salva updated_at
// ✅ addMovementLog agora salva updated_at
// ✅ getAllPeople filtra por since (Delta Sync)
// ✅ getAllLogs filtra por since (Delta Sync)
// ============================================================================

const SPREADSHEET_ID = '1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U';
const MOVIMENTACAO_COLUMN_INDEX = 10; // Coluna J

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

    if (lastColumn < MOVIMENTACAO_COLUMN_INDEX) {
      const colunasParaAdicionar = MOVIMENTACAO_COLUMN_INDEX - lastColumn;

      if (lastColumn === 0) {
        console.log('⚠️ Planilha vazia, pulando inserção de colunas');
      } else {
        console.log(`📝 Inserindo ${colunasParaAdicionar} coluna(s) após coluna ${lastColumn}`);
        pessoasSheet.insertColumnsAfter(lastColumn, colunasParaAdicionar);
      }
    }

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
      pessoasSheet.getRange(i + 2, MOVIMENTACAO_COLUMN_INDEX).setValue(movimentacao);
      // ✅ NOVO: Atualizar UPDATED_AT também
      pessoasSheet.getRange(i + 2, 13).setValue(new Date().toISOString());
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

    if (action === 'batchSync') {
      return batchSync(data);
    }

    switch (action) {
      case 'login':
        return login(data);
      case 'getAllUsers':
        return getAllUsers(data);
      case 'getAllPeople':
        return getAllPeople(data);
      case 'getAllStudents':
        return getAllStudents(data);
      case 'getAlunos':
        return getAlunos(data);
      case 'getPessoas':
        return getPessoas();
      case 'getLogs':
        return getLogs();
      case 'getUsuarios':
        return getUsuarios();
      case 'getQuartos':
        return getQuartos();
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
        return getAllLogs(data);
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
        return getAllUsers(params);
      case 'getAllPeople':
        return getAllPeople(params);
      case 'getAllStudents':
        return getAllStudents(params);
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
            colegio: params.colegio || '',
            turma: params.turma || '',
            email: params.email || '',
            telefone: params.telefone || '',
            embedding: embedding,
            personId: params.personId || params.cpf,
            updated_at: params.updated_at
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
            colegio: params.colegio || '',
            turma: params.turma || '',
            email: params.email || '',
            telefone: params.telefone || '',
            embedding: embedding,
            updated_at: params.updated_at
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
          colegio: params.colegio || '',
          turma: params.turma || '',
          confidence: parseFloat(params.confidence || '0'),
          tipo: params.tipo || 'reconhecimento',
          updated_at: params.updated_at
        });
      case 'getAllLogs':
        return getAllLogs(params);
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
// BATCHING HTTP
// ============================================================================
function batchSync(data) {
  try {
    console.log('🚀 [batchSync] Iniciando batch sync...');

    const requests = data.requests || [];

    if (!Array.isArray(requests) || requests.length === 0) {
      return createResponse(false, 'Nenhuma requisição no batch');
    }

    console.log('📥 [batchSync] Processando', requests.length, 'requisição(ões)');

    const responses = [];

    for (let i = 0; i < requests.length; i++) {
      const request = requests[i];
      const requestAction = request.action;

      console.log(`📝 [batchSync] [${i + 1}/${requests.length}] Processando:`, requestAction);

      try {
        let result;

        switch (requestAction) {
          case 'getAllUsers':
            result = getAllUsers(request);
            break;
          case 'getAllPeople':
            result = getAllPeople(request);
            break;
          case 'getAllStudents':
            result = getAllStudents(request);
            break;
          case 'getAllLogs':
            result = getAllLogs(request);
            break;
          case 'getQuartos':
            result = getQuartos(request);
            break;
          case 'getEventos':
            result = getEventos(request);
            break;
          case 'getAlunos':
            result = getAlunos(request);
            break;
          default:
            result = createResponse(false, 'Ação não reconhecida: ' + requestAction);
        }

        const parsedResult = JSON.parse(result.getContent());
        responses.push({
          action: requestAction,
          success: parsedResult.success,
          data: parsedResult
        });

        console.log(`✅ [batchSync] [${i + 1}/${requests.length}] Sucesso:`, requestAction);

      } catch (error) {
        console.error(`❌ [batchSync] [${i + 1}/${requests.length}] Erro em ${requestAction}:`, error);
        responses.push({
          action: requestAction,
          success: false,
          error: error.message
        });
      }
    }

    console.log('✅ [batchSync] Batch concluído:', responses.length, 'respostas');

    return createResponse(true, 'Batch sync concluído', {
      total_requests: requests.length,
      responses: responses
    });

  } catch (error) {
    console.error('❌ [batchSync] Erro:', error);
    return createResponse(false, 'Erro no batch sync: ' + error.message);
  }
}

// ============================================================================
// GET QUARTOS
// ============================================================================
function getQuartos() {
  try {
    console.log('📥 [getQuartos] Buscando quartos da aba HOMELIST...');

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const sheet = ss.getSheetByName('HOMELIST');

    if (!sheet) {
      console.error('❌ [getQuartos] Aba HOMELIST não encontrada');
      return createResponse(false, 'Aba HOMELIST não encontrada');
    }

    const data = sheet.getDataRange().getValues();

    if (data.length <= 1) {
      console.log('⚠️ [getQuartos] Nenhum quarto encontrado (planilha vazia)');
      return createResponse(true, 'Nenhum quarto encontrado', { data: [] });
    }

    const headers = data[0];
    const rows = data.slice(1);

    console.log('📊 [getQuartos] Headers:', headers);
    console.log('📊 [getQuartos] Total de linhas:', rows.length);

    const quartos = [];

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const obj = {};

      for (let j = 0; j < headers.length; j++) {
        const header = headers[j];
        obj[header] = row[j] || '';
      }

      if (obj['Quarto'] && obj['CPF']) {
        quartos.push(obj);
      } else {
        console.log('⚠️ [getQuartos] Linha ' + (i + 2) + ' ignorada: falta Quarto ou CPF');
      }
    }

    console.log('✅ [getQuartos] ' + quartos.length + ' quartos encontrados');

    if (quartos.length > 0) {
      console.log('📝 [getQuartos] Exemplo:', JSON.stringify(quartos[0]));
    }

    return createResponse(true, quartos.length + ' quartos sincronizados', { data: quartos });

  } catch (error) {
    console.error('❌ [getQuartos] Erro:', error);
    console.error('Stack:', error.stack);
    return createResponse(false, 'Erro ao buscar quartos: ' + error.message);
  }
}

// ============================================================================
// LOGIN
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
// GET ALL USERS (SEM DELTA SYNC - usuários não mudam frequentemente)
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
// GET ALL PEOPLE (✅ COM DELTA SYNC)
// ============================================================================
function getAllPeople(params) {
  try {
    const since = params ? params.since : null;
    console.log('📥 [getAllPeople] Buscando pessoas... Since:', since);

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

    // ✅ ESTRUTURA: ID, CPF, COLÉGIO, TURMA, NOME, EMAIL, TELEFONE, EMBEDDING, DATA_CADASTRO, MOVIMENTAÇÃO, INÍCIO VIAGEM, FIM VIAGEM, UPDATED_AT
    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      if (!row[1]) continue;

      const updatedAt = row[12] ? row[12].toString() : '';

      // ✅ DELTA SYNC: Filtrar por timestamp se 'since' foi fornecido
      if (since && updatedAt) {
        try {
          const updatedDate = new Date(updatedAt);
          const sinceDate = new Date(since);
          if (updatedDate <= sinceDate) {
            continue; // Pular registros antigos
          }
        } catch (e) {
          console.log('⚠️ Erro ao comparar datas para CPF', row[1]);
        }
      }

      const pessoa = {
        cpf: String(row[1]).trim(),
        colegio: row[2] || '',
        turma: row[3] || '',
        nome: row[4] || '',
        email: row[5] || '',
        telefone: row[6] || '',
        embedding: row[7] || null,
        movimentacao: (row[9] || '').toString(),
        inicio_viagem: row[10] || '',
        fim_viagem: row[11] || '',
        updated_at: updatedAt  // ✅ NOVO
      };

      if (pessoa.embedding && pessoa.embedding.length > 0) {
        const embeddingStr = String(pessoa.embedding);
        if (embeddingStr.startsWith('[') && embeddingStr.includes(',')) {
          pessoas.push(pessoa);
          if (pessoas.length === 1) {
            console.log('✅ Exemplo de pessoa válida:', {
              cpf: pessoa.cpf,
              colegio: pessoa.colegio,
              turma: pessoa.turma,
              nome: pessoa.nome,
              movimentacao: pessoa.movimentacao,
              updated_at: pessoa.updated_at,
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

    const msg = since
      ? pessoas.length + ' pessoas modificadas desde ' + since
      : pessoas.length + ' pessoas encontradas';

    console.log('✅ [getAllPeople]', msg);
    return createResponse(true, msg, { data: pessoas });
  } catch (error) {
    console.error('❌ Erro ao buscar pessoas:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}

// ============================================================================
// GET ALL STUDENTS (SEM DELTA SYNC - planilha simples)
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
      if (!row[1]) continue;

      // ✅ Garantir que datas sejam convertidas para string ISO
      let inicioViagem = row[9] || '';
      let fimViagem = row[10] || '';

      if (inicioViagem instanceof Date) {
        inicioViagem = inicioViagem.toISOString();
      } else if (inicioViagem) {
        inicioViagem = inicioViagem.toString().trim();
      }

      if (fimViagem instanceof Date) {
        fimViagem = fimViagem.toISOString();
      } else if (fimViagem) {
        fimViagem = fimViagem.toString().trim();
      }

      const aluno = {
        cpf: String(row[4] || '').trim(),
        nome: row[1] || '',
        colegio: row[2] || '',
        turma: row[3] || '',
        email: '',
        telefone: row[5] || '',
        facial_status: 'NAO',
        tem_qr: 'NAO',
        inicio_viagem: inicioViagem,
        fim_viagem: fimViagem
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
// ADD PESSOA (✅ COM UPDATED_AT)
// ============================================================================
function addPessoa(data) {
  try {
    const cpf = data.cpf;
    const nome = data.nome;
    const colegio = data.colegio || '';
    const turma = data.turma || '';
    const email = data.email || '';
    const telefone = data.telefone || '';
    const embedding = data.embedding;
    const personId = data.personId || cpf;
    const movimentacaoValor = (data.movimentacao || '').toString().trim().toUpperCase();
    const inicioViagem = data.inicio_viagem || data.inicioViagem || '';
    const fimViagem = data.fim_viagem || data.fimViagem || '';
    const updatedAt = data.updated_at || new Date().toISOString(); // ✅ NOVO

    console.log('📥 [addPessoa] Cadastrando pessoa:', nome, 'CPF:', cpf, 'Updated:', updatedAt);

    if (!cpf || !nome || !embedding) {
      return createResponse(false, 'CPF, nome e embedding são obrigatórios');
    }

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    let pessoasSheet = ss.getSheetByName('PESSOAS');

    if (!pessoasSheet) {
      console.log('📝 Criando aba PESSOAS...');
      pessoasSheet = ss.insertSheet('PESSOAS');
      // ✅ Header atualizado com UPDATED_AT na coluna M
      pessoasSheet.appendRow(['ID', 'CPF', 'COLÉGIO', 'TURMA', 'NOME', 'EMAIL', 'TELEFONE', 'EMBEDDING', 'DATA_CADASTRO', 'MOVIMENTAÇÃO', 'INÍCIO VIAGEM', 'FIM VIAGEM', 'UPDATED_AT']);
    }

    garantirColunaMovimentacao(pessoasSheet);

    const embeddingJson = JSON.stringify(embedding);
    const dataCadastro = new Date().toISOString();

    const data_range = pessoasSheet.getDataRange();
    const values = data_range.getValues();

    // Procurar pessoa existente por CPF
    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      const cpfSheet = String(row[1]).trim();

      if (cpfSheet === cpf) {
        console.log('🔄 Atualizando pessoa existente:', nome);
        pessoasSheet.getRange(i + 1, 3).setValue(colegio);
        pessoasSheet.getRange(i + 1, 4).setValue(turma);
        pessoasSheet.getRange(i + 1, 5).setValue(nome);
        pessoasSheet.getRange(i + 1, 6).setValue(email);
        pessoasSheet.getRange(i + 1, 7).setValue(telefone);
        pessoasSheet.getRange(i + 1, 8).setValue(embeddingJson);
        pessoasSheet.getRange(i + 1, 9).setValue(dataCadastro);
        if (movimentacaoValor) {
          pessoasSheet.getRange(i + 1, MOVIMENTACAO_COLUMN_INDEX).setValue(movimentacaoValor);
        }
        if (inicioViagem) {
          pessoasSheet.getRange(i + 1, 11).setValue(inicioViagem);
        }
        if (fimViagem) {
          pessoasSheet.getRange(i + 1, 12).setValue(fimViagem);
        }
        pessoasSheet.getRange(i + 1, 13).setValue(updatedAt); // ✅ NOVO: Coluna M
        console.log('✅ [addPessoa] Pessoa atualizada com sucesso');
        return createResponse(true, 'Pessoa atualizada com sucesso');
      }
    }

    // Pessoa nova - adicionar linha
    const newId = values.length;
    const newRow = [
      newId,              // Coluna A (ID)
      cpf,                // Coluna B (CPF)
      colegio,            // Coluna C (COLÉGIO)
      turma,              // Coluna D (TURMA)
      nome,               // Coluna E (NOME)
      email,              // Coluna F (EMAIL)
      telefone,           // Coluna G (TELEFONE)
      embeddingJson,      // Coluna H (EMBEDDING)
      dataCadastro,       // Coluna I (DATA_CADASTRO)
      movimentacaoValor,  // Coluna J (MOVIMENTAÇÃO)
      inicioViagem,       // Coluna K (INÍCIO VIAGEM)
      fimViagem,          // Coluna L (FIM VIAGEM)
      updatedAt           // Coluna M (UPDATED_AT) ✅ NOVO
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
// ADD MOVEMENT LOG (✅ COM UPDATED_AT)
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
      // ✅ Header atualizado com UPDATED_AT na coluna L
      logsSheet.appendRow(['TIMESTAMP', 'CPF', 'COLÉGIO', 'TURMA', 'NOME', 'CONFIDENCE', 'TIPO', 'PERSON_ID', 'OPERADOR', 'INÍCIO_VIAGEM', 'FIM_VIAGEM', 'UPDATED_AT']);
    }

    let count = 0;

    for (const person of people) {
      const timestamp = person.timestamp || new Date().toISOString();
      const cpf = person.cpf || '';
      const colegio = person.colegio || '';
      const turma = person.turma || '';
      const personName = person.personName || person.nome || '';
      const confidence = person.confidence || 0;
      const tipo = (person.tipo || 'RECONHECIMENTO').toString().toUpperCase();
      const movimentacaoRecebida = (person.movimentacao || person.movimento || '').toString().trim();
      const personId = person.personId || cpf;
      const operadorNome = person.operadorNome || 'Sistema';
      const inicioViagem = person.inicio_viagem || person.inicioViagem || '';
      const fimViagem = person.fim_viagem || person.fimViagem || '';
      const updatedAt = person.updated_at || new Date().toISOString(); // ✅ NOVO

      logsSheet.appendRow([
        timestamp,      // Coluna A (TIMESTAMP)
        cpf,            // Coluna B (CPF)
        colegio,        // Coluna C (COLÉGIO)
        turma,          // Coluna D (TURMA)
        personName,     // Coluna E (NOME)
        confidence,     // Coluna F (CONFIDENCE)
        tipo,           // Coluna G (TIPO)
        personId,       // Coluna H (PERSON_ID)
        operadorNome,   // Coluna I (OPERADOR)
        inicioViagem,   // Coluna J (INÍCIO_VIAGEM)
        fimViagem,      // Coluna K (FIM_VIAGEM)
        updatedAt       // Coluna L (UPDATED_AT) ✅ NOVO
      ]);

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
// GET ALUNOS
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

      const onibus = String(row[7]).trim();

      if (numeroOnibus && onibus !== numeroOnibus) {
        continue;
      }

      const aluno = {
        nome: row[1],
        cpf: String(row[4]).trim(),
        colegio: row[2] || '',
        turma: row[3] || '',
        id_passeio: row[6] || '',
        embarque: String(row[11] || 'NAO').toUpperCase(),
        retorno: String(row[12] || 'NAO').toUpperCase(),
        onibus: onibus,
        tem_qr: String(row[8] || 'NAO').toUpperCase(),
        inicio_viagem: row[9] || '',
        fim_viagem: row[10] || ''
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
      colegio: data.colegio || '',
      turma: data.turma || '',
      confidence: data.confidence || 0,
      tipo: data.tipo || 'reconhecimento',
      movimentacao: data.movimentacao || data.tipo || '',
      timestamp: new Date().toISOString(),
      updated_at: data.updated_at
    }]
  });
}

function syncEmbedding(data) {
  console.log('ℹ️ [syncEmbedding] Redirecionando para addPessoa...');
  return addPessoa(data);
}

// ============================================================================
// GET ALL LOGS (✅ COM DELTA SYNC)
// ============================================================================
function getAllLogs(params) {
  try {
    const since = params ? params.since : null;
    console.log('📥 [getAllLogs] Buscando logs... Since:', since);

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const logsSheet = ss.getSheetByName('LOGS');

    if (!logsSheet) {
      console.error('❌ Aba LOGS não encontrada');
      return createResponse(false, 'Aba LOGS não encontrada na planilha');
    }

    const data_range = logsSheet.getDataRange();
    const values = data_range.getValues();

    const logs = [];

    // ✅ ESTRUTURA: TIMESTAMP, CPF, COLÉGIO, TURMA, NOME, CONFIDENCE, TIPO, PERSON_ID, OPERADOR, INÍCIO_VIAGEM, FIM_VIAGEM, UPDATED_AT
    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      if (!row[0]) continue;

      const updatedAt = row[11] ? row[11].toString() : '';

      // ✅ DELTA SYNC: Filtrar por timestamp se 'since' foi fornecido
      if (since && updatedAt) {
        try {
          const updatedDate = new Date(updatedAt);
          const sinceDate = new Date(since);
          if (updatedDate <= sinceDate) {
            continue; // Pular registros antigos
          }
        } catch (e) {
          console.log('⚠️ Erro ao comparar datas para log', i);
        }
      }

      const log = {
        timestamp: row[0],
        cpf: row[1] || '',
        colegio: row[2] || '',
        turma: row[3] || '',
        nome: row[4] || '',
        confidence: row[5] || 0,
        tipo: row[6] || '',
        person_id: row[7] || '',
        operador: row[8] || '',
        updated_at: updatedAt  // ✅ NOVO
      };

      logs.push(log);
    }

    const msg = since
      ? logs.length + ' logs modificados desde ' + since
      : logs.length + ' logs encontrados';

    console.log('✅ [getAllLogs]', msg);
    return createResponse(true, msg, { data: logs });
  } catch (error) {
    console.error('❌ Erro ao buscar logs:', error);
    return createResponse(false, 'Erro ao buscar logs: ' + error.message);
  }
}

// ============================================================================
// AÇÕES CRÍTICAS (mantidas como estão)
// ============================================================================

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

    const viagensMap = new Map();

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      let inicioViagem = row[9] || '';
      let fimViagem = row[10] || '';

      // ✅ Garantir que datas sejam convertidas para string ISO
      if (inicioViagem instanceof Date) {
        inicioViagem = inicioViagem.toISOString();
      } else if (inicioViagem) {
        inicioViagem = inicioViagem.toString().trim();
      }

      if (fimViagem instanceof Date) {
        fimViagem = fimViagem.toISOString();
      } else if (fimViagem) {
        fimViagem = fimViagem.toString().trim();
      }

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

function encerrarViagem(data) {
  try {
    console.log('🔥 [CRÍTICO] Iniciando encerramento de viagem...');

    const inicioViagem = data ? (data.inicio_viagem || data.inicioViagem) : null;
    const fimViagem = data ? (data.fim_viagem || data.fimViagem) : null;

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);

    if (!inicioViagem || !fimViagem) {
      console.log('⚠️ Nenhuma data especificada - limpando TODAS as viagens');

      const abaPessoas = ss.getSheetByName('PESSOAS');
      if (abaPessoas) {
        const lastRow = abaPessoas.getLastRow();
        if (lastRow > 1) {
          abaPessoas.getRange(2, 1, lastRow - 1, abaPessoas.getLastColumn()).clearContent();
          console.log('✅ Aba PESSOAS limpa');
        }
      }

      const abaLogs = ss.getSheetByName('LOGS');
      if (abaLogs) {
        const lastRow = abaLogs.getLastRow();
        if (lastRow > 1) {
          abaLogs.getRange(2, 1, lastRow - 1, abaLogs.getLastColumn()).clearContent();
          console.log('✅ Aba LOGS limpa');
        }
      }

      const abaAlunos = ss.getSheetByName('ALUNOS');
      if (abaAlunos) {
        const lastRow = abaAlunos.getLastRow();
        if (lastRow > 1) {
          abaAlunos.getRange(2, 1, lastRow - 1, abaAlunos.getLastColumn()).clearContent();
          console.log('✅ Aba ALUNOS limpa');
        }
      }

      console.log('✅ [CRÍTICO] Todas as viagens encerradas com sucesso!');

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

    console.log('🎯 Encerrando viagem específica:', inicioViagem, 'a', fimViagem);

    let totalRemovidos = 0;

    const abaPessoas = ss.getSheetByName('PESSOAS');
    if (abaPessoas) {
      totalRemovidos += limparAbaFiltrada(abaPessoas, inicioViagem, fimViagem, 11, 12);
    }

    const abaLogs = ss.getSheetByName('LOGS');
    if (abaLogs) {
      totalRemovidos += limparAbaFiltrada(abaLogs, inicioViagem, fimViagem, 10, 11);
    }

    const abaAlunos = ss.getSheetByName('ALUNOS');
    if (abaAlunos) {
      totalRemovidos += limparAbaFiltrada(abaAlunos, inicioViagem, fimViagem, 10, 11);
    }

    console.log('✅ [CRÍTICO] Viagem encerrada com sucesso! Total de registros removidos:', totalRemovidos);

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

  for (let i = 0; i < values.length; i++) {
    const row = values[i];
    let inicio = row[colunaInicio - 1];
    let fim = row[colunaFim - 1];

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

    const match = inicio === inicioViagem && fim === fimViagem;

    if (i < 3) {
      console.log('📋 Linha', i + 2, '- Inicio:', inicio, 'Fim:', fim, 'Match:', match);
    }

    if (match) {
      linhasParaRemover.push(i + 2);
    }
  }

  for (let i = linhasParaRemover.length - 1; i >= 0; i--) {
    sheet.deleteRow(linhasParaRemover[i]);
  }

  console.log('✅ Aba', sheet.getName(), ':', linhasParaRemover.length, 'registro(s) removido(s)');
  return linhasParaRemover.length;
}

function enviarTodosParaQuarto() {
  try {
    console.log('🔄 [CRÍTICO] Enviando todos para QUARTO...');

    console.log('📝 Passo 1: Abrindo planilha...');
    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const abaPessoas = ss.getSheetByName('PESSOAS');

    if (!abaPessoas) {
      console.error('❌ Aba PESSOAS não encontrada');
      return createResponse(false, 'Aba PESSOAS não encontrada');
    }
    console.log('✅ Aba PESSOAS encontrada');

    console.log('📝 Passo 2: Garantindo coluna MOVIMENTAÇÃO...');
    try {
      garantirColunaMovimentacao(abaPessoas);
    } catch (errColuna) {
      console.error('❌ Erro ao garantir coluna:', errColuna);
      return createResponse(false, 'Erro ao configurar coluna MOVIMENTAÇÃO: ' + errColuna.message);
    }

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

    if (lastColumn < MOVIMENTACAO_COLUMN_INDEX) {
      console.error(`❌ Planilha não tem coluna ${MOVIMENTACAO_COLUMN_INDEX}. Última coluna: ${lastColumn}`);
      return createResponse(false, `Erro: Planilha não possui a coluna ${MOVIMENTACAO_COLUMN_INDEX} necessária`);
    }

    console.log('📝 Passo 4: Preparando valores...');
    const numPessoas = lastRow - 1;
    const valores = [];

    for (let i = 0; i < numPessoas; i++) {
      valores.push(['QUARTO']);
    }

    console.log(`📊 Total de ${numPessoas} pessoa(s) serão atualizadas`);

    console.log('📝 Passo 5: Atualizando células...');
    try {
      const range = abaPessoas.getRange(2, MOVIMENTACAO_COLUMN_INDEX, numPessoas, 1);
      range.setValues(valores);
      console.log('✅ Células atualizadas com sucesso');
    } catch (errUpdate) {
      console.error('❌ Erro ao atualizar células:', errUpdate);
      return createResponse(false, 'Erro ao atualizar células: ' + errUpdate.message);
    }

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

function registrarEvento(tipoEvento, dados) {
  try {
    console.log('📢 [registrarEvento] Tipo:', tipoEvento, 'Dados:', JSON.stringify(dados));

    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    let eventosSheet = ss.getSheetByName('EVENTOS');

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

    const eventoId = 'EVT_' + new Date().getTime();
    const timestamp = new Date().toISOString();

    // ✅ Garantir que inicio_viagem e fim_viagem sejam sempre strings
    let inicioViagem = dados.inicio_viagem || dados.inicioViagem || '';
    let fimViagem = dados.fim_viagem || dados.fimViagem || '';

    // Se forem Date objects, converter para ISO string
    if (inicioViagem instanceof Date) {
      inicioViagem = inicioViagem.toISOString();
    } else if (inicioViagem && typeof inicioViagem !== 'string') {
      inicioViagem = inicioViagem.toString().trim();
    }

    if (fimViagem instanceof Date) {
      fimViagem = fimViagem.toISOString();
    } else if (fimViagem && typeof fimViagem !== 'string') {
      fimViagem = fimViagem.toString().trim();
    }

    const dadosAdicionais = JSON.stringify(dados);
    const processado = 'NAO';

    // ✅ DEBUG: Verificar valores antes de inserir
    console.log('🔍 [registrarEvento] Valores a serem inseridos:');
    console.log('  - inicioViagem:', inicioViagem, '(tipo:', typeof inicioViagem, ')');
    console.log('  - fimViagem:', fimViagem, '(tipo:', typeof fimViagem, ')');
    console.log('  - dados.inicio_viagem:', dados.inicio_viagem);
    console.log('  - dados.fim_viagem:', dados.fim_viagem);

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

      // ✅ Garantir que inicio_viagem e fim_viagem sejam sempre strings ISO
      let inicioViagem = row[3] || '';
      let fimViagem = row[4] || '';

      if (inicioViagem instanceof Date) {
        inicioViagem = inicioViagem.toISOString();
      } else if (inicioViagem) {
        inicioViagem = inicioViagem.toString().trim();
      }

      if (fimViagem instanceof Date) {
        fimViagem = fimViagem.toISOString();
      } else if (fimViagem) {
        fimViagem = fimViagem.toString().trim();
      }

      const dadosAdicionais = row[5] || '{}';
      const processado = String(row[6] || 'NAO').toUpperCase();

      if (processado === 'NAO') {
        if (timestampFiltro) {
          const eventoTimestamp = new Date(timestamp).getTime();
          const filtroTimestamp = new Date(timestampFiltro).getTime();

          if (eventoTimestamp <= filtroTimestamp) {
            continue;
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

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      const rowEventoId = row[0];

      if (rowEventoId === eventoId) {
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

function getPessoas() {
  return getAllPeople();
}

function getLogs() {
  return getAllLogs();
}

function getUsuarios() {
  return getAllUsers();
}
