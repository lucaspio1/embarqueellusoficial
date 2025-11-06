// ============================================================================
// CORREÇÃO: getAllStudents - Mapeamento correto das colunas
// Colunas: ID, NOME, TURMA, CPF, TELEFONE
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
    console.log('📋 Estrutura esperada: ID (0), NOME (1), TURMA (2), CPF (3), TELEFONE (4)');

    const alunos = [];

    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      if (!row[1]) continue; // Pula se não tem NOME

      const aluno = {
        id: row[0] || '',           // Coluna 1: ID
        nome: row[1] || '',         // Coluna 2: NOME ✅
        turma: row[2] || '',        // Coluna 3: TURMA ✅
        cpf: String(row[3] || '').trim(),  // Coluna 4: CPF ✅ (CORRIGIDO!)
        telefone: row[4] || '',     // Coluna 5: TELEFONE ✅
        email: '',                  // Não tem na planilha
        facial_status: 'NAO',       // Default
        tem_qr: 'NAO'              // Default
      };

      alunos.push(aluno);

      // Log do primeiro aluno para debug
      if (i === 1) {
        console.log('✅ Exemplo de aluno:', aluno);
      }
    }

    console.log('✅ [getAllStudents] ' + alunos.length + ' alunos encontrados');
    return createResponse(true, alunos.length + ' alunos encontrados', { data: alunos });
  } catch (error) {
    console.error('❌ Erro ao buscar alunos:', error);
    return createResponse(false, 'Erro: ' + error.message);
  }
}
