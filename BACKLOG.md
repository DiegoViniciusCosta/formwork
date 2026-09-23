# Backlog

Em ordem de prioridade. Cada item diz do que depende. **Decisão** = precisa
de uma resposta sua antes de alguém executar.

Legenda: ⬜ a fazer · 🟨 esperando decisão · ✅ feito

---

## Prioridade máxima: a fundação

Motivo: hoje o formwork está atrás do `reactive_forms` em validação
(validação assíncrona, validação entre campos, erros como dados) e em
usabilidade para quem escreve formulários em código (sem tipos, sem
layout). Os itens 1 a 4 saem juntos, numa única versão com quebra limpa
(a 0.1 não foi publicada).

### 1. 🟨 Aprovar os design docs da fundação
Leitura e decisões suas, nesta ordem:
1. `0001-foundation.md`: modelo novo (`FieldDef`, `FormDef`, erros como
   dados, condições, grafo de dependências, `FieldState`). Perguntas em
   aberto: `toJson`, e caminhos relativos em listas.
2. `0006-code-first-and-layout.md`: formulário como classe, com campos
   tipados; `FieldView` para pôr cada campo em qualquer lugar; layout
   vindo do servidor (`section`, `row`). Perguntas em aberto: lint para
   campos fora de `fields`, `visibleWhen` em seções, e nomes.
3. `0002-per-change-cost.md`: desempenho. As metas de tempo são uma
   decisão sua.
4. `0004-api-naming.md`: nomes. Perguntas em aberto: um ou dois widgets,
   o nome `FieldProps`, e `initialValues` ou `data`.

### 2. ⬜ Design doc: estado do formulário na UI, e foco
- Um helper para a UI reagir ao estado do formulário: botão de enviar
  desabilitado, "enviando…", contagem de erros. Hoje isso exige um
  `ValueListenableBuilder` montado na mão.
- Levar o foco ao primeiro campo com erro ao enviar. O builder precisa
  receber um `FocusNode` (entra no `FieldProps` do 0004).

Pequeno. Deve ser escrito e aprovado junto com o item 1, porque mexe no
`FieldProps`.

### 3. ⬜ Implementar a fundação
Na ordem da "Implementation order" do 0001, e dentro dela:
- **0001:** erros como dados mais um localizador, condições, validação
  entre campos, grafo de dependências, `touched` e `dirty` separados,
  ciclos rejeitados com erro claro;
- **0002 etapas 2 e 3:** trie persistente para o `FieldState`, e
  notificação por campo, que o `FieldView` do 0006 exige;
- **0006:** classes, codecs, `FieldView`, `FormScope` e layout;
- **item 2:** o helper de estado para a UI, e o foco;
- **teste de "trabalho por mudança"**, que o `PRINCIPLES.md` §2 lista como
  "Planned".

Antes de começar: decidir como a regra do elo do meio (0003) se estende a
condições com vários campos (`all` / `any`), a pergunta 1 do 0003.

Depende de: 1 e 2.

### 4. ⬜ Aplicar os nomes do 0004 na mesma versão
Inclui os builders do `formwork_material` e a troca de `FieldContext` por
`FieldProps` no `PRINCIPLES.md` e nos `AGENTS.md`.
Depende de: 3.

---

## Próximo

### 5. 🟨 Campos de texto seguem o snapshot (0005)
Undo, reset e valores vindos de fora atualizam o estado, mas o `TextField`
continua mostrando o texto antigo. Afeta quem usa Bloc, Riverpod ou
qualquer estado externo (princípio 1).
- **Decisão:** aprovar `docs/design/0005-text-follows-snapshot.md` e
  responder as 2 perguntas em aberto: composição de teclado (IME) e
  adaptadores com atraso.
- Pequeno e independente da fundação: pode ser adiantado e implementado
  entre as etapas do item 3, se você quiser a correção antes.

### 6. ⬜ Reposicionar o README
O diferencial real não são os rebuilds (o `reactive_forms` e o
`flutter_form_builder` já reconstroem por campo). É a combinação:
- formulários definidos pelo servidor;
- qualquer design system e qualquer gerenciamento de estado;
- completar cadastro com `missingKeys` / `missingFields`;
- o mesmo catálogo validado no app e no servidor (núcleo em Dart puro).

O que fazer:
- abrir com esse posicionamento; rebuilds viram garantia de qualidade;
- uma seção "Quando **não** usar o formwork";
- conferir cada afirmação sobre concorrentes na versão atual deles.

Pode começar a qualquer momento, mas as afirmações sobre validação,
classes e layout só depois do item 3 (análise de 2026-09-23 no pub.dev).

---

## Perguntas abertas sem data (não bloqueiam nada acima)

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
- Design docs 0002, 0003 (aceito), 0004, 0005 e 0006.
