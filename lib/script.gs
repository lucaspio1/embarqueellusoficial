// ====================================================================
// SCRIPT COMPLETO DE RECONHECIMENTO FACIAL + SINCRONIZAÇÃO DE ALUNOS
// ====================================================================

function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const action = data.action;

    console.log('📡 Ação recebida:', action);

    // Rotas
    switch(action) {
      case 'addPerson':
        return addPerson(data);
      case 'getPersonByCPF':
        return getPersonByCPF(data);
      case 'addMovementLog':
        return addMovementLog(data);
      case 'getAllStudents': // ✅ NOVA ROTA
        return getAllStudents();
      case 'getStats':
        return getStats();
      case 'getAllPeople':
        return getAllPeople();
      default:
        return createResponse(false, 'Ação inválida: ' + action);
    }

  } catch (error) {
    console.error('❌ Erro no doPost:', error);
    return createResponse(false, 'Erro no servidor: ' + error.message);
  }
}

function doGet(e) {
  return ContentService.createTextOutput(JSON.stringify({
    status: 'API Ativa',
    message: 'Use POST para acessar a API',
    timestamp: new Date().toISOString()
  })).setMimeType(ContentService.MimeType.JSON);
}

// ============================================
// CONFIGURAÇÃO DE ABAS
// ============================================
const ALUNOS_SHEET = 'Alunos';
const PESSOAS_SHEET = 'Pessoas';
const LOGS_SHEET = 'Movimentacoes';

// ============================================
// 1. BUSCAR TODOS OS ALUNOS (NOVA!) ✅
// ============================================
function getAllStudents() {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const alunosSheet = ss.getSheetByName(ALUNOS_SHEET);

    if (!alunosSheet) {
      return createResponse(false, 'Aba "Alunos" não encontrada. Certifique-se de que a aba existe.');
    }

    const alunosData = alunosSheet.getDataRange().getValues();

    if (alunosData.length <= 1) {
      return createResponse(true, 'Nenhum aluno cadastrado', []);
    }

    const alunosHeaders = alunosData[0];
    const alunosRows = alunosData.slice(1);

    // Converte cabeçalhos para minúsculas para busca flexível
    const lowerHeaders = alunosHeaders.map(h => String(h).toLowerCase().trim());

    // Índices das colunas
    const idx = {
      id: lowerHeaders.indexOf('id'),
      cpf: lowerHeaders.indexOf('cpf'),
      nome: lowerHeaders.indexOf('nome'),
      email: lowerHeaders.indexOf('email'),
      telefone: lowerHeaders.indexOf('telefone'),
      turma: lowerHeaders.indexOf('turma'),
      facial: lowerHeaders.indexOf('facial')
    };

    // Validar se encontrou as colunas essenciais
    if (idx.cpf === -1 || idx.nome === -1) {
      return createResponse(false, 'Colunas obrigatórias não encontradas. Certifique-se de que existe "CPF" e "Nome" na primeira linha.');
    }

    const result = [];

    alunosRows.forEach(row => {
      const cpf = row[idx.cpf];
      const nome = row[idx.nome];

      // Pular linhas vazias
      if (!cpf || !nome) {
        return;
      }

      result.push({
        id: row[idx.id] || '',
        cpf: cpf.toString().trim(),
        nome: nome.toString().trim(),
        email: idx.email !== -1 ? (row[idx.email] || '') : '',
        telefone: idx.telefone !== -1 ? (row[idx.telefone] || '') : '',
        turma: idx.turma !== -1 ? (row[idx.turma] || '') : '',
        facial_status: idx.facial !== -1 ? (row[idx.facial] || null) : null
      });
    });

    console.log(`✅ ${result.length} alunos encontrados na aba Alunos`);

    return createResponse(true, `${result.length} alunos carregados`, result);

  } catch (error) {
    console.error('❌ Erro ao buscar alunos:', error);
    return createResponse(false, 'Erro ao buscar alunos: ' + error.message, []);
  }
}

// ============================================
// 2. BUSCAR PESSOA POR CPF (Aba Alunos)
// ============================================
function getPersonByCPF(data) {
  try {
    const cpf = data.cpf ? data.cpf.toString().replace(/\D/g, '') : null;

    if (!cpf) {
      return createResponse(false, 'CPF é obrigatório');
    }

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const alunosSheet = ss.getSheetByName(ALUNOS_SHEET);

    if (!alunosSheet) {
      return createResponse(false, 'Aba "Alunos" não encontrada. Crie a aba Alunos.');
    }

    const alunosData = alunosSheet.getDataRange().getValues();
    const alunosHeaders = alunosData[0];
    const alunosRows = alunosData.slice(1);

    const idx = {
      id: alunosHeaders.indexOf('ID'),
      cpf: alunosHeaders.indexOf('CPF'),
      nome: alunosHeaders.indexOf('Nome'),
      email: alunosHeaders.indexOf('Email'),
      telefone: alunosHeaders.indexOf('TELEFONE'),
      facial: alunosHeaders.indexOf('FACIAL')
    };

    const linhaEncontrada = alunosRows.find(row => {
      const rowCpf = row[idx.cpf] ? row[idx.cpf].toString().replace(/\D/g, '') : '';
      return rowCpf === cpf;
    });

    if (!linhaEncontrada) {
      return createResponse(false, 'CPF não encontrado na aba Alunos', null);
    }

    const result = {
      id: linhaEncontrada[idx.id],
      cpf: linhaEncontrada[idx.cpf],
      nome: linhaEncontrada[idx.nome],
      email: linhaEncontrada[idx.email] || '',
      telefone: linhaEncontrada[idx.telefone] || '',
      facial_status: linhaEncontrada[idx.facial] || '',
      embedding: null
    };

    return createResponse(true, 'Pessoa encontrada', result);

  } catch (error) {
    console.error('❌ Erro ao buscar CPF:', error);
    return createResponse(false, 'Erro ao buscar: ' + error.message, null);
  }
}

// ============================================
// 3. CADASTRAR FACE (Aba Pessoas + Atualiza Alunos)
// ============================================
function addPerson(data) {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    let pessoasSheet = ss.getSheetByName(PESSOAS_SHEET);
    let alunosSheet = ss.getSheetByName(ALUNOS_SHEET);

    // ✅ CORREÇÃO: SUPORTE PARA AMBOS OS FORMATOS
    let personData = data;
    if (data.people && Array.isArray(data.people) && data.people.length > 0) {
      personData = data.people[0]; // Pega o primeiro do array
      console.log('📦 Formato com array "people" detectado');
    } else {
      console.log('📦 Formato direto detectado');
    }

    if (!personData.cpf || !personData.nome || !personData.embedding) {
      return createResponse(false, 'CPF, nome e embedding são obrigatórios');
    }

    // Criar aba PESSOAS se não existir
    if (!pessoasSheet) {
      pessoasSheet = ss.insertSheet(PESSOAS_SHEET);
      pessoasSheet.appendRow(['ID', 'CPF', 'Nome', 'Email', 'Telefone', 'Facial (Embedding)', 'Data Cadastro']);
      console.log('✅ Aba "Pessoas" criada');
    }

    const now = new Date().toISOString();

    const newRow = [
      personData.personId || '',
      personData.cpf,
      personData.nome,
      personData.email || '',
      personData.telefone || '',
      JSON.stringify(personData.embedding),
      now
    ];

    pessoasSheet.appendRow(newRow);
    const newPersonRowIndex = pessoasSheet.getLastRow();
    console.log(`✅ Registro de facial adicionado em Pessoas para: ${personData.nome}`);

    // Atualizar o status "FACIAL" na aba ALUNOS
    if (alunosSheet) {
      const alunosData = alunosSheet.getDataRange().getValues();
      const alunosHeaders = alunosData[0];
      const idxCPF = alunosHeaders.indexOf('CPF');
      const idxFacial = alunosHeaders.indexOf('FACIAL');

      if (idxCPF !== -1 && idxFacial !== -1) {
        for (let i = 1; i < alunosData.length; i++) {
          const rowCpf = alunosData[i][idxCPF] ? alunosData[i][idxCPF].toString().replace(/\D/g, '') : '';
          const searchCpf = personData.cpf.toString().replace(/\D/g, '');

          if (rowCpf === searchCpf) {
            alunosSheet.getRange(i + 1, idxFacial + 1).setValue('CADASTRADA');
            console.log(`✅ Coluna FACIAL do aluno ${personData.nome} atualizada para 'CADASTRADA'.`);
            break;
          }
        }
      }
    }

    return createResponse(true, 'Cadastro facial e status de aluno atualizados com sucesso', {
        personId: newPersonRowIndex
    });

  } catch (error) {
    console.error('❌ Erro ao adicionar pessoa:', error);
    return createResponse(false, 'Erro ao cadastrar: ' + error.message);
  }
}

// ============================================
// 4. REGISTRAR LOG DE MOVIMENTAÇÃO
// ============================================
function addMovementLog(data) {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    let logsSheet = ss.getSheetByName(LOGS_SHEET);

    if (!data.people || !Array.isArray(data.people) || data.people.length === 0) {
      return createResponse(false, 'Array "people" é obrigatório e deve conter ao menos um log');
    }

    if (!logsSheet) {
      logsSheet = ss.insertSheet(LOGS_SHEET);
      logsSheet.appendRow([
        'ID',
        'CPF',
        'Nome',
        'Data/Hora',
        'Tipo',
        'Confiança',
        'Person ID'
      ]);
      console.log('✅ Aba "Movimentacoes" criada');
    }

    const ultimaLinha = logsSheet.getLastRow();
    let ultimoID = 0;

    if (ultimaLinha > 1) {
      const valorUltimoID = logsSheet.getRange(ultimaLinha, 1).getValue();
      const idLido = parseInt(valorUltimoID);
      if (!isNaN(idLido) && idLido > 0) {
        ultimoID = idLido;
      }
    }

    const logsProcessados = [];

    data.people.forEach(log => {
      if (!log.cpf || !log.personName || !log.timestamp || !log.tipo) {
        console.warn('⚠️ Log incompleto ignorado:', log);
        return;
      }

      ultimoID++;

      const novaLinha = [
        ultimoID,
        log.cpf,
        log.personName,
        log.timestamp,
        log.tipo,
        log.confidence || 0.95,
        log.personId || log.cpf
      ];

      logsSheet.appendRow(novaLinha);
      logsProcessados.push({
        id: ultimoID,
        cpf: log.cpf,
        nome: log.personName,
        tipo: log.tipo
      });

      console.log(`✅ Log registrado: ${log.personName} - ${log.tipo} (${log.timestamp})`);
    });

    return createResponse(true, `${logsProcessados.length} logs registrados com sucesso`, {
      logs_processados: logsProcessados,
      total: logsProcessados.length
    });

  } catch (error) {
    console.error('❌ Erro ao adicionar logs:', error);
    return createResponse(false, 'Erro ao registrar logs: ' + error.message);
  }
}

// ============================================
// 5. SINCRONIZAR TODOS OS EMBEDDINGS
// ============================================
function getAllPeople() {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const pessoasSheet = ss.getSheetByName(PESSOAS_SHEET);

    if (!pessoasSheet) {
      console.error('❌ Aba "Pessoas" não encontrada');
      return createResponse(false, 'Aba "Pessoas" não encontrada');
    }

    const pessoasData = pessoasSheet.getDataRange().getValues();
    const pessoasHeaders = pessoasData[0];
    const pessoasRows = pessoasData.slice(1);

    if (pessoasRows.length === 0) {
        return createResponse(true, 'Nenhum cadastro facial encontrado', []);
    }

    const lowerCaseHeaders = pessoasHeaders.map(h => String(h).toLowerCase().trim());

    const idx = {
      id: lowerCaseHeaders.indexOf('id'),
      cpf: lowerCaseHeaders.indexOf('cpf'),
      nome: lowerCaseHeaders.indexOf('nome'),
      email: lowerCaseHeaders.indexOf('email'),
      telefone: lowerCaseHeaders.indexOf('telefone'),
      embedding: lowerCaseHeaders.findIndex(h => h.includes('embedding') || h.includes('facial')),
      dataCadastro: lowerCaseHeaders.indexOf('data cadastro')
    };

    if (idx.embedding === -1) {
        console.error('❌ Erro: Coluna de Embedding (Facial) não encontrada.');
        return createResponse(false, 'Erro: Coluna "embedding" não encontrada no cabeçalho. Verifique a ortografia.');
    }

    const result = [];
    let pessoasComEmbeddingValido = 0;

    pessoasRows.forEach(row => {
      const cpfValue = row[idx.cpf];
      const embeddingCellValue = row[idx.embedding];

      if (!cpfValue || !embeddingCellValue) {
          return;
      }

      const embeddingStr = embeddingCellValue.toString().trim();
      let embedding = null;

      if (embeddingStr.length > 2) {
        try {
          embedding = JSON.parse(embeddingStr);

          if (Array.isArray(embedding) && embedding.length > 0) {
            pessoasComEmbeddingValido++;
          } else {
             embedding = null;
          }
        } catch (e) {
          console.error(`❌ Erro ao parsear JSON do embedding no CPF ${cpfValue}. Dado corrompido.`, e);
          embedding = null;
        }
      }

      if (embedding) {
          result.push({
            id: row[idx.id],
            cpf: cpfValue,
            nome: row[idx.nome],
            email: row[idx.email] || '',
            telefone: row[idx.telefone] || '',
            data_cadastro: row[idx.dataCadastro] ? row[idx.dataCadastro].toString() : '',
            embedding: embedding
          });
      }
    });

    console.log(`✅ ${result.length} registros prontos. ${pessoasComEmbeddingValido} com embedding válido.`);

    return createResponse(true, 'Dados de sincronização carregados', result);

  } catch (error) {
    console.error('❌ Erro em getAllPeople:', error);
    return createResponse(false, 'Erro ao buscar dados: ' + error.message, []);
  }
}

// ============================================
// 6. ESTATÍSTICAS
// ============================================
function getStats() {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const alunosSheet = ss.getSheetByName(ALUNOS_SHEET);
    const pessoasSheet = ss.getSheetByName(PESSOAS_SHEET);
    const logsSheet = ss.getSheetByName(LOGS_SHEET);

    const stats = {
      total_alunos: 0,
      alunos_com_facial: 0,
      total_cadastros_faciais: 0,
      total_logs: 0,
      logs_hoje: 0
    };

    if (alunosSheet) {
      const totalAlunos = Math.max(0, alunosSheet.getLastRow() - 1);
      stats.total_alunos = totalAlunos;

      // Contar alunos com facial cadastrada
      if (totalAlunos > 0) {
        const data = alunosSheet.getDataRange().getValues();
        const headers = data[0];
        const idxFacial = headers.indexOf('FACIAL');

        if (idxFacial !== -1) {
          for (let i = 1; i < data.length; i++) {
            if (data[i][idxFacial] === 'CADASTRADA') {
              stats.alunos_com_facial++;
            }
          }
        }
      }
    }

    if (pessoasSheet) {
      stats.total_cadastros_faciais = Math.max(0, pessoasSheet.getLastRow() - 1);
    }

    if (logsSheet) {
      const totalLogs = Math.max(0, logsSheet.getLastRow() - 1);
      stats.total_logs = totalLogs;

      if (totalLogs > 0) {
        const logsData = logsSheet.getDataRange().getValues();
        const headers = logsData[0];
        const idxTimestamp = headers.indexOf('Data/Hora');

        if (idxTimestamp !== -1) {
          const hoje = new Date();
          hoje.setHours(0, 0, 0, 0);

          for (let i = 1; i < logsData.length; i++) {
            const timestamp = new Date(logsData[i][idxTimestamp]);
            timestamp.setHours(0, 0, 0, 0);

            if (timestamp.getTime() === hoje.getTime()) {
              stats.logs_hoje++;
            }
          }
        }
      }
    }

    return createResponse(true, 'Estatísticas obtidas', stats);
  } catch (error) {
    return createResponse(false, 'Erro ao obter estatísticas: ' + error.message);
  }
}

// ============================================
// UTILITÁRIOS
// ============================================
function createResponse(success, message, data = null) {
  const response = {
    success: success,
    message: message,
    timestamp: new Date().toISOString()
  };

  if (data !== null) {
    response.data = data;
  }

  return ContentService
    .createTextOutput(JSON.stringify(response))
    .setMimeType(ContentService.MimeType.JSON);
}


// ============================================
// 7. TRATAR REQUISIÇÕES GET COM DADOS CODIFICADOS
// ============================================
function handleGetWithData(e) {
  try {
    const encodedData = e.parameter.data;

    if (!encodedData) {
      return createResponse(false, 'Dados não fornecidos via GET');
    }

    // Decodificar dados base64
    const decodedData = Utilities.newBlob(Utilities.base64Decode(encodedData)).getDataAsString();
    const data = JSON.parse(decodedData);

    console.log('📡 Dados recebidos via GET:', data.action);

    // Reutilizar a lógica existente do doPost
    switch(data.action) {
      case 'addPerson':
        return addPerson(data);
      case 'addMovementLog':
        return addMovementLog(data);
      case 'testConnection':
        return createResponse(true, 'Conexão GET funcionando', {
          timestamp: new Date().toISOString(),
          method: 'GET'
        });
      default:
        return createResponse(false, 'Ação inválida via GET: ' + data.action);
    }

  } catch (error) {
    console.error('❌ Erro no handleGetWithData:', error);
    return createResponse(false, 'Erro ao processar dados GET: ' + error.message);
  }
}

// Atualize a função doGet para lidar com dados:
function doGet(e) {
  // Se tiver parâmetro data, processar como uma requisição de dados
  if (e.parameter.data) {
    return handleGetWithData(e);
  }

  // Caso contrário, retornar status normal da API
  return ContentService.createTextOutput(JSON.stringify({
    status: 'API Ativa',
    message: 'Use POST para acessar a API ou forneça parâmetro "data" via GET',
    timestamp: new Date().toISOString()
  })).setMimeType(ContentService.MimeType.JSON);
}