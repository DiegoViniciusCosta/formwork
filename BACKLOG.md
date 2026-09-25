# Backlog

Em ordem de prioridade. Cada item diz do que depende. **Decisão** = precisa
de uma resposta sua antes de alguém executar.

Legenda: ⬜ a fazer · 🟨 esperando decisão · ✅ feito

---

## Prioridade máxima: a fundação

Motivo: hoje o formwork está atrás do `reactive_forms` em validação
(validação assíncrona, validação entre campos, erros como dados) e em
usabilidade para quem escreve formulários em código. O 0007 garante que a
fundação já suporte, no futuro, formulários feitos de widgets
("everything is a widget"). Os itens 4 e 5 saem numa única versão com
quebra limpa (a 0.1 não foi publicada).

### 4. ⬜ Implementar a fundação (0001, 0002, 0004, 0006, 0007 e 0008)
Na ordem da "Implementation order" do 0001, e dentro dela:
- **0007:**
  - registro de campos em tempo de execução;
  - definições e grafo dentro do snapshot;
  - HAMT por caminho;
  - biblioteca de catálogo separada do engine;
- **0001:** erros como dados mais um localizador, condições, validação
  entre campos, grafo de dependências, `touched` e `dirty` separados,
  ciclos rejeitados com erro claro;
- **0002 etapas 2 e 3:** armazenamento persistente para o `FieldState`, e
  notificação por campo;
- **0006:** classes, codecs, `FieldView` (com `builder:` por campo),
  `FormScope` e layout;
- **0008:** `FormStatus`, as transições de envio, `submitTo`,
  `FormStatusBuilder`, `focusNode` no `FieldProps` e `FormFocus`;
- **teste de "trabalho por mudança"**, que o `PRINCIPLES.md` §2 lista como
  "Planned".

Inclui a regra do elo do meio para condições de vários campos, decidida
no 0003.

Pode começar já.

### 5. ⬜ Aplicar os nomes do 0004 na mesma versão
Inclui os builders do `formwork_material` e a troca de `FieldContext` por
`FieldProps` no `PRINCIPLES.md` e nos `AGENTS.md`.
Depende de: 4.

---

## Próximo

### 6. ⬜ Reposicionar o README
O diferencial real não são os rebuilds (o `reactive_forms` e o
`flutter_form_builder` já reconstroem por campo). É a combinação:
- formulários definidos pelo servidor;
- qualquer design system e qualquer gerenciamento de estado;
- completar cadastro com `missingKeys` / `missingFields`;
- o mesmo catálogo validado no app e no servidor (núcleo em Dart puro).

O que fazer:
- abrir com esse posicionamento; rebuilds viram garantia de qualidade;
- dizer o limite da validação no backend: o mesmo catálogo só é validado
  sem esforço num backend em Dart; num Spring Boot, o engine precisa ser
  portado ou chamado como serviço;
- uma seção "Quando **não** usar o formwork";
- conferir cada afirmação sobre concorrentes na versão atual deles.

Pode começar a qualquer momento, mas as afirmações sobre validação,
classes e layout só depois do item 4 (análise de 2026-09-23 no pub.dev).

---

## Objetivos futuros

### Formulários feitos de widgets ("everything is a widget")
A segunda porta de entrada: campos declarados direto na árvore de
widgets, como nos concorrentes, sem classe nem JSON.
- **O primitivo** é um `Field<T>(name:, validators:, builder:)` no
  `formwork`, que não depende de nenhum design system.
- **Os widgets prontos** (`FwTextField(...)`) ficam nos kits, como o
  `formwork_material`.

O 0007 garante que o engine já suporta essa porta. Precisa de um design doc
próprio, que decida:
- quando um widget registra o campo durante o build;
- quem é dono de cada registro quando o mesmo campo está montado duas
  vezes;
- como registrar com Bloc ou Riverpod (`SnapshotFieldView`);
- como os widgets convivem com o `onlyMissing`.

É também essa porta que torna a lista `fields` opcional em formulários
escritos em código.

### Editor visual de formulários
Se o formulário vindo do servidor é o diferencial do formwork, um editor
visual é o que transforma esse nicho em produto: quem define o formulário
deixa de precisar escrever JSON.
- Depende de `FormDef.toJson()`, que ficou fora da fundação (decisão
  registrada no 0001 como plano, não como recusa).
- O custo a pesar na hora: todo tipo de campo customizado passa a precisar
  saber se converter para JSON.
- Precisa de um design doc próprio antes de começar.

### `touched` ao perder o foco
Um modo de validação em que os erros aparecem quando o campo perde o foco,
e não na primeira mudança. O `FocusNode` por campo do 0008 já permite
isso sem quebrar nada. Decidido no 0008: fica para depois da fundação.

---

## Perguntas abertas sem data (não bloqueiam nada acima)

- **`pana` no `verify.sh` completo (CI):** o `pana` ignora o
  `pubspec_overrides.yaml`, então falha em todo pacote que depende de um
  irmão não publicado. Já falhava no `formwork_material` (depende do
  `formwork`); desde a separação, falha também no `formwork` (depende do
  `formwork_core`). O `formwork_core` passa (150/160). Opções: pular o
  `pana` nesses pacotes até a primeira publicação, ou aceitar o CI
  vermelho até lá. O `--fast` não roda o `pana`.

- **Dados antigos no servidor:** um campo que fica oculto não vai no
  payload, e o servidor mantém o valor antigo. Mandar `null` ou deixar com
  o servidor? (0003, pergunta 2)

---

## Feito ✅

- Projeto em git. O remoto `origin` aponta para
  `git@github.com:DiegoViniciusCosta/formwork.git`; o push é seu.
- Confirmado no pub.dev em 2026-09-23: 0.1 não publicada, e os nomes
  `formwork` e `formwork_material` estão livres.
- Testes do exemplo no `verify.sh`, e portanto no CI.
- 0003 implementado: `missingKeys`, elo do meio preenchido, README com duas
  receitas, preset "Renewal".
- Galeria de exemplos com 8 cenários e testes de widget.
- Correção: `visibleWhen` segue cadeias.
- 0002 etapa 1: `change()` cerca de 4x mais rápido por tecla.
- Correção: `FormSnapshot.touched` agora é somente-leitura.
- 0005 implementado: campos de texto seguem o snapshot (undo, reset e
  estado restaurado aparecem no campo). O último teste pulado do projeto
  voltou a rodar.
- Design docs 0001 a 0006 aceitos (2026-09-23), com os trade-offs de
  cada um. Melhorias ficam para depois da fundação.
- Decidido: o elo do meio com condições de vários campos (0003).
- 0008 aceito (2026-09-25): estado do formulário na UI e foco. Decidido
  junto: o nome `submitTo`; `touched` ao perder o foco fica para depois da
  fundação; erros do servidor em caminhos não registrados não entram no
  `FormStatus`.
- Pacotes separados (2026-09-25): `formwork_core` em Dart puro, testado
  com `dart test`; o `formwork` o reexporta. Regras do 0007 aplicadas no
  `PRINCIPLES.md`, nos `AGENTS.md`, no hook, no `check_principles.sh` e no
  `principles-reviewer`. O `missing_fields` já está em `src/catalog`; o
  `FormConfig.fromMap` sai do engine no item 4.
- 0007 aceito (2026-09-25): três pacotes, registro em tempo de execução,
  HAMT por caminho, `builder:` por campo. Erros do servidor em caminhos
  nunca registrados aparecem, mas não bloqueiam o envio.
