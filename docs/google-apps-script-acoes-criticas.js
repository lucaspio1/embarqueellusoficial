/**
 * Google Apps Script - Ações Críticas para ELLUS
 *
 * ATENÇÃO: Estas funções executam operações DESTRUTIVAS e IRREVERSÍVEIS!
 * Use com extremo cuidado.
 *
 * Deploy: Copiar e colar no Google Apps Script do projeto
 */

// =========================================================================
// 1. ENCERRAR VIAGEM - Limpa TODAS as abas (PESSOAS, LOGS, ALUNOS)
// =========================================================================

/**
 * Limpa todas as abas da planilha (PESSOAS, LOGS, ALUNOS)
 * ATENÇÃO: OPERAÇÃO IRREVERSÍVEL! Todos os dados serão perdidos!
 *
 * @returns {Object} Resultado da operação
 */
function encerrarViagem() {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();

    // 1. Limpar aba PESSOAS
    const abaPessoas = ss.getSheetByName('Pessoas');
    if (abaPessoas) {
      const lastRow = abaPessoas.getLastRow();
      if (lastRow > 1) {
        abaPessoas.getRange(2, 1, lastRow - 1, abaPessoas.getLastColumn()).clearContent();
      }
    }

    // 2. Limpar aba LOGS
    const abaLogs = ss.getSheetByName('Logs');
    if (abaLogs) {
      const lastRow = abaLogs.getLastRow();
      if (lastRow > 1) {
        abaLogs.getRange(2, 1, lastRow - 1, abaLogs.getLastColumn()).clearContent();
      }
    }

    // 3. Limpar aba ALUNOS
    const abaAlunos = ss.getSheetByName('Alunos');
    if (abaAlunos) {
      const lastRow = abaAlunos.getLastRow();
      if (lastRow > 1) {
        abaAlunos.getRange(2, 1, lastRow - 1, abaAlunos.getLastColumn()).clearContent();
      }
    }

    return ContentService
      .createTextOutput(JSON.stringify({
        success: true,
        message: 'Viagem encerrada com sucesso! Todas as abas foram limpas.',
        timestamp: new Date().toISOString(),
        abas_limpas: ['Pessoas', 'Logs', 'Alunos']
      }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    return ContentService
      .createTextOutput(JSON.stringify({
        success: false,
        message: 'Erro ao encerrar viagem: ' + error.toString()
      }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// =========================================================================
// 2. ENVIAR TODOS PARA QUARTO - Atualiza movimentação de todos
// =========================================================================

/**
 * Atualiza a movimentação de TODAS as pessoas para 'QUARTO'
 * Útil para início/fim de dia ou reset de localização
 *
 * @returns {Object} Resultado da operação
 */
function enviarTodosParaQuarto() {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const abaPessoas = ss.getSheetByName('Pessoas');

    if (!abaPessoas) {
      throw new Error('Aba Pessoas não encontrada');
    }

    const lastRow = abaPessoas.getLastRow();
    if (lastRow <= 1) {
      return ContentService
        .createTextOutput(JSON.stringify({
          success: true,
          message: 'Nenhuma pessoa para atualizar',
          pessoas_atualizadas: 0
        }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    // Verificar estrutura da planilha (assumindo que MOVIMENTACAO está na coluna 7)
    // Ajustar conforme a estrutura real da sua planilha
    // Colunas esperadas: CPF | NOME | EMAIL | TELEFONE | TURMA | EMBEDDING | MOVIMENTACAO
    const colunaMovimentacao = 7;

    // Atualizar todas as linhas (exceto cabeçalho) para 'QUARTO'
    const range = abaPessoas.getRange(2, colunaMovimentacao, lastRow - 1, 1);
    const valores = [];
    for (let i = 0; i < lastRow - 1; i++) {
      valores.push(['QUARTO']);
    }
    range.setValues(valores);

    const pessoasAtualizadas = lastRow - 1;

    return ContentService
      .createTextOutput(JSON.stringify({
        success: true,
        message: `${pessoasAtualizadas} pessoa(s) enviada(s) para QUARTO`,
        pessoas_atualizadas: pessoasAtualizadas,
        timestamp: new Date().toISOString()
      }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    return ContentService
      .createTextOutput(JSON.stringify({
        success: false,
        message: 'Erro ao enviar para quarto: ' + error.toString()
      }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// =========================================================================
// 3. doPost - Handler para requisições POST
// =========================================================================

/**
 * Handler para requisições POST do Flutter
 * Rotas:
 * - action=encerrarViagem
 * - action=enviarTodosParaQuarto
 */
function doPost(e) {
  try {
    const params = JSON.parse(e.postData.contents);
    const action = params.action;

    switch (action) {
      case 'encerrarViagem':
        return encerrarViagem();

      case 'enviarTodosParaQuarto':
        return enviarTodosParaQuarto();

      default:
        return ContentService
          .createTextOutput(JSON.stringify({
            success: false,
            message: 'Ação desconhecida: ' + action
          }))
          .setMimeType(ContentService.MimeType.JSON);
    }
  } catch (error) {
    return ContentService
      .createTextOutput(JSON.stringify({
        success: false,
        message: 'Erro ao processar requisição: ' + error.toString()
      }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// =========================================================================
// INSTRUÇÕES DE DEPLOY
// =========================================================================

/**
 * COMO IMPLANTAR:
 *
 * 1. Abra seu Google Sheets do projeto ELLUS
 * 2. Extensões → Apps Script
 * 3. Cole este código
 * 4. Clique em "Implantar" → "Nova implantação"
 * 5. Tipo: "Aplicativo da Web"
 * 6. Executar como: "Eu"
 * 7. Quem tem acesso: "Qualquer pessoa"
 * 8. Clique em "Implantar"
 * 9. Copie a URL do Web App
 * 10. Cole a URL no arquivo .env do Flutter (GOOGLE_APPS_SCRIPT_URL)
 *
 * IMPORTANTE:
 * - Verifique a coluna de MOVIMENTACAO na aba Pessoas (atualmente assumida como coluna 7)
 * - Teste primeiro com dados de exemplo
 * - Faça backup antes de usar em produção
 */
