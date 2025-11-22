# 🧪 Guia de Teste - Batch Sync no Postman

## 📋 Configuração do Postman

### 1. Criar Nova Request

- **Método:** `POST`
- **URL:**
  ```
  https://script.google.com/macros/s/AKfycbzHYYjdXnQSdntHYU_cYvevW18zB1t_v2CcVXDxm0-LV2fxJxtnXEiMP0XNwz-G1ZfYhQ/exec
  ```

### 2. Configurar Headers

```
Content-Type: application/json
```

### 3. Body (Raw → JSON)

Cole o conteúdo do arquivo `test_batch_sync.json`

---

## ✅ Resultado Esperado

Se o script estiver **corretamente implantado**, você receberá:

```json
{
  "success": true,
  "message": "Batch sync concluído",
  "data": {
    "total_requests": 10,
    "responses": [
      {
        "action": "getAllUsers",
        "success": true,
        "data": {
          "success": true,
          "data": [...array de usuários...]
        }
      },
      {
        "action": "syncLogs",
        "success": true,
        "data": {
          "success": true,
          "message": "1 logs sincronizados com sucesso"
        }
      },
      {
        "action": "getAllQuartos",
        "success": true,
        "data": {
          "success": true,
          "data": [...array de quartos...]
        }
      },
      {
        "action": "getEventos",
        "success": true,
        "data": {
          "success": true,
          "data": [...todos os eventos...]
        }
      },
      {
        "action": "getEventos",
        "success": true,
        "data": {
          "success": true,
          "data": [...apenas eventos após 15:00...]
        }
      },
      {
        "action": "getAllPeople",
        "success": true,
        "data": {
          "success": true,
          "data": [...pessoas com embeddings...]
        }
      },
      {
        "action": "getAllAlunos",
        "success": true,
        "data": {
          "success": true,
          "data": [...array de alunos...]
        }
      },
      {
        "action": "getPessoasByColegio",
        "success": true,
        "data": {
          "success": true,
          "data": [...pessoas do COC...]
        }
      },
      {
        "action": "getPessoasByTurma",
        "success": true,
        "data": {
          "success": true,
          "data": [...pessoas do 8 ANO 2...]
        }
      },
      {
        "action": "getQuartoByCPF",
        "success": true,
        "data": {
          "success": true,
          "data": {...dados do quarto...}
        }
      }
    ]
  }
}
```

---

## ❌ Possíveis Erros

### Erro 1: Script não implantado
```json
{
  "success": false,
  "message": "Ação inválida: batchSync"
}
```
**Solução:** Implantar nova versão do script

### Erro 2: Redirect (HTTP 302)
Resposta em HTML em vez de JSON

**Solução:**
- Verificar se a URL está correta
- Verificar se o script foi publicado como "Web app"
- Verificar permissões: "Anyone" ou "Anyone with the link"

### Erro 3: Erro de permissão
```json
{
  "success": false,
  "message": "Authorization required"
}
```
**Solução:** Reautorizar o script no Google Apps Script

---

## 📊 Checklist de Validação

Após executar o teste, verifique:

- [ ] Status code: `200 OK`
- [ ] `success: true` no root
- [ ] `total_requests: 10`
- [ ] Array `responses` com 10 elementos
- [ ] Cada response tem `action`, `success: true` e `data`
- [ ] Teste 2 (syncLogs) gravou o log na planilha
- [ ] Teste 5 retorna menos eventos que Teste 4 (delta sync funcionando)
- [ ] Tempos de resposta < 10 segundos

---

## 🎯 O que cada teste valida

1. **getAllUsers** → Sistema de usuários
2. **syncLogs** → Gravação de movimentações
3. **getAllQuartos** → Sistema de quartos
4. **getEventos (sem lastSync)** → Busca completa de eventos
5. **getEventos (com lastSync)** → Delta sync de eventos
6. **getAllPeople** → Pessoas com embeddings faciais
7. **getAllAlunos** → Sistema de alunos
8. **getPessoasByColegio** → Filtro por colégio
9. **getPessoasByTurma** → Filtro por turma
10. **getQuartoByCPF** → Busca individual de quarto

---

## 🚀 Próximos Passos

Se todos os testes passarem:
1. ✅ O script está 100% funcional
2. ✅ O app vai usar batch sync automaticamente
3. ✅ Redução de 6 requests → 1 request
4. ✅ Sincronização 6x mais rápida

Cole a resposta completa do Postman aqui para eu validar! 🎯
