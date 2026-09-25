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

### 2026-09-23 — value, parse e format (campos de texto)
- **Contexto**: design doc 0005, que faz o `TextControllerBinding` seguir
  valores vindos de fora (undo, reset, estado restaurado).
- **Conceitos**:
  - Um campo de texto vive em dois mundos: o texto (String, pode estar
    incompleto: `-`, `1.`) e o valor (tipado, ou `null`).
  - `parse` (texto → valor) é muitos-para-um: `1.5`, `1.50` e `1,5` viram
    `1.5`. `format` (valor → texto) escolhe um representante.
  - Por isso `parse(format(v)) == v` vale (invariante para quem escreve
    builders), mas `format(parse(t)) == t` não vale.
  - A regra do 0005 mantém o texto se ele significa o valor, ou se já é a
    forma canônica do valor; senão, o valor veio de fora.
  - Analogia: o `ControlValueAccessor` do Angular (`writeValue` = format,
    `registerOnChange` = parse).
- **No código**: `packages/formwork/lib/src/flutter/text_controller_binding.dart`,
  o builder `_text` em `packages/formwork_material/lib/formwork_material.dart`
  e `docs/design/0005-text-follows-snapshot.md`.
- **Lacunas**: sem checkpoint: mudou de assunto antes de responder.
  Revisar depois.
- **Para revisar**:
  - Campo de número com o texto `2.0`; um undo põe o valor `2` (int). O que
    aparece na tela, e por quê?
  - Um campo de data com `parse` para `dd/MM/yyyy` e `format` padrão
    (`toString`): o que dá errado, e quando o usuário percebe?

### 2026-09-24 — Estruturas de dados no formwork (mini-livro)
- **Contexto**: pedido para separar os problemas de estrutura de dados do
  projeto, virou o mini-livro "Estruturas que Lembram":
  https://claude.ai/artifact/Wm3AfcZJbHVsXoZ2h5X75P
- **Conceitos** (um capítulo cada):
  1. imutabilidade ingênua custa O(n): visão x cópia, reaproveitar o que
     não mudou;
  2. aliasing: compartilhar só é seguro sem porta de escrita;
  3. estruturas persistentes: trie de 32 vias e HAMT (bitmap + popcount);
     a escolha depende do que se sabe sobre as chaves, não da velocidade;
  4. grafos: regra local x fecho transitivo (cadeias de visibilidade);
  5. índice reverso, e o custo quadrático escondido em `List.contains`;
  6. conjunto de visitados por busca; detectar x decidir;
  7. "entre dois pontos" = interseção de duas alcançabilidades;
  8. identidade como detector de mudança; igualdade por valor numa
     hierarquia aberta é uma armadilha.
- **No código**: `packages/formwork/lib/src/core/form_engine.dart`
  (`change`, `_withErrors`, `_buildChains`, `_buildDependents`),
  `missing_fields.dart`, design docs 0002 e 0007.
- **Lacunas**: sem checkpoint: o livro tem os exercícios com respostas
  escondidas. Revisar depois.
- **Para revisar**:
  - Por que devolver o mesmo snapshot num re-registro igual economiza mais
    do que "não mudar os valores"? Em qual camada?
  - Grafo `a → c`, `b → c`, `c → d`, com `a` e `d` faltantes: quais campos
    conhecidos entram? O `b` entra?
