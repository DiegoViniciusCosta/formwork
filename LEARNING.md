# Learning journal

### 2026-09-23 — O "elo do meio" em cadeias de visibleWhen
- **Contexto**: depois da correção das cadeias de visibilidade no engine, a
  revisão de princípios achou um caso em que o bug volta: `missingFields`
  tira do formulário um campo intermediário já conhecido.
- **Conceitos**:
  - Um campo numa cadeia tem dois papéis: guardar um dado e ser um elo de
    dependência. `missingFields` corta pelo primeiro e perde o segundo
    ("colar somente valores" numa planilha).
  - Um campo pode ter valor conhecido e relevância desconhecida.
  - Regra: julgar um controlador fora do formulário só pelo valor é seguro
    se, e somente se, nenhum campo acima dele na cadeia está no formulário.
    O bug exige um campo fora entre dois campos na tela.
  - Opções: incluir só os elos do meio (A refinada), separar "o que
    renderizar" de "que regras existem" (B, grafo do 0001 §5), ou
    documentar (C).
- **No código**: `packages/formwork/lib/src/core/missing_fields.dart`
  (`relevant`), `packages/formwork/lib/src/core/form_engine.dart`
  (`_buildChains`, `_isVisible`), teste pulado "a chain stays connected
  when missingFields drops its middle link" em
  `packages/formwork/test/core_test.dart`.
- **Correção posterior**: o exemplo usava `hasVehicle` como checkbox
  obrigatório. Um checkbox obrigatório desmarcado conta como vazio
  (`isEmptyValue(false)`), então "não" nunca seria enviável. O exemplo
  correto usa um dropdown Sim/Não (ver 0003).
- **Lacunas**: sem checkpoint: pediu as respostas explicadas em vez de
  responder. Revisar depois.
- **Para revisar**:
  - Com `{hasVehicle: true, vehicleType: 'car'}` salvo, o bug acontece? Por
    quê?
  - Na opção B, se o usuário marca `hasVehicle = false`, o payload deveria
    avisar o servidor que o `vehicleType` salvo ficou irrelevante?
