# CORREÇÃO GOOGLE APPS SCRIPT - SISTEMA DE EVENTOS

## 🐛 Problema Identificado:

Eventos eram marcados como "processados" globalmente, então quando um dispositivo processava, os outros não recebiam mais.

## ✅ Solução:

Cada dispositivo controla localmente quais eventos já processou.

---

## MUDANÇAS NECESSÁRIAS NO GOOGLE APPS SCRIPT:

### 1. Atualizar função `registrarEvento()` (linha ~1211):

**ANTES:**
```javascript
eventosSheet.appendRow([
  'ID',
  'TIMESTAMP',
  'TIPO_EVENTO',
  'INICIO_VIAGEM',
  'FIM_VIAGEM',
  'DADOS_ADICIONAIS',
  'PROCESSADO'  // ← REMOVER
]);
```

**DEPOIS:**
```javascript
eventosSheet.appendRow([
  'ID',
  'TIMESTAMP',
  'TIPO_EVENTO',
  'INICIO_VIAGEM',
  'FIM_VIAGEM',
  'DADOS_ADICIONAIS'  // ← SEM PROCESSADO
]);
```

E logo abaixo, REMOVER a coluna processado:

**ANTES:**
```javascript
eventosSheet.appendRow([
  eventoId,
  timestamp,
  tipoEvento,
  inicioViagem,
  fimViagem,
  dadosAdicionais,
  'NAO'  // ← REMOVER
]);
```

**DEPOIS:**
```javascript
eventosSheet.appendRow([
  eventoId,
  timestamp,
  tipoEvento,
  inicioViagem,
  fimViagem,
  dadosAdicionais  // ← SEM PROCESSADO
]);
```

---

### 2. Atualizar função `getEventos()` (linha ~1230):

**ANTES:**
```javascript
for (let i = 1; i < values.length; i++) {
  const row = values[i];

  const eventoId = row[0];
  const timestamp = row[1];
  const tipoEvento = row[2];
  const inicioViagem = row[3] || '';
  const fimViagem = row[4] || '';
  const dadosAdicionais = row[5] || '{}';
  const processado = String(row[6] || 'NAO').toUpperCase();  // ← REMOVER

  if (processado === 'NAO') {  // ← REMOVER ESSE IF
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
      processado: processado  // ← REMOVER
    });
  }  // ← REMOVER ESSE FECHAMENTO
}
```

**DEPOIS:**
```javascript
for (let i = 1; i < values.length; i++) {
  const row = values[i];

  const eventoId = row[0];
  const timestamp = row[1];
  const tipoEvento = row[2];
  const inicioViagem = row[3] || '';
  const fimViagem = row[4] || '';
  const dadosAdicionais = row[5] || '{}';

  // ✅ MUDANÇA: Não verificar mais se foi processado
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
    dados: dadosParsed  // ← SEM processado
  });
}
```

---

### 3. DELETAR função `marcarEventoProcessado()` (linha ~1287):

Esta função não é mais necessária. Pode deletá-la completamente ou deixar vazia:

```javascript
function marcarEventoProcessado(data) {
  // ✅ Função desativada - eventos são controlados localmente em cada dispositivo
  return createResponse(true, 'Eventos são controlados localmente');
}
```

---

## IMPORTANTE:

Após aplicar essas mudanças, você precisa:

1. **Limpar a coluna PROCESSADO existente** na aba EVENTOS (se já existir)
2. **Reimplantar** o script no Google Apps Script

Todos os dispositivos vão começar a processar eventos corretamente!
