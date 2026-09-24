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

### 1. ⬜ Design doc: estado do formulário na UI, e foco
- Um helper para a UI reagir ao estado do formulário: botão de enviar
  desabilitado, "enviando…", contagem de erros. Hoje isso exige um
  `ValueListenableBuilder` montado na mão.
- Levar o foco ao primeiro campo com erro ao enviar. O builder precisa
  receber um `FocusNode` (entra no `FieldProps` do 0004).

Pequeno. Deve ser aprovado antes da implementação, porque mexe no
`FieldProps`.

### 2. 🟨 Decidir o elo do meio com condições de vários campos
O 0003 define a regra para cadeias simples. Com `all` / `any` do 0001, um
campo pode depender de vários, e a cadeia vira um grafo.
- **Recomendação:** incluir um campo conhecido se algum caminho no grafo
  passa por ele entre dois campos faltantes. Generaliza a regra atual sem
  caso especial, ao custo de às vezes perguntar de novo um campo que não
  mudaria o resultado.
- **Alternativa:** incluir só se a condição ainda puder mudar de
  resultado. Pergunta o mínimo, mas é bem mais complexo.

### 3. ⬜ Implementar a fundação (0001, 0002, 0004, 0006, aceitos)
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

Depende de: 1 e 2.

### 4. ⬜ Aplicar os nomes do 0004 na mesma versão
Inclui os builders do `formwork_material` e a troca de `FieldContext` por
`FieldProps` no `PRINCIPLES.md` e nos `AGENTS.md`.
Depende de: 3.

---

## Próximo

### 5. ⬜ Reposicionar o README
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
classes e layout só depois do item 3 (análise de 2026-09-23 no pub.dev).

---

## Objetivos futuros

### Editor visual de formulários
Se o formulário vindo do servidor é o diferencial do formwork, um editor
visual é o que transforma esse nicho em produto: quem define o formulário
deixa de precisar escrever JSON.
- Depende de `FormDef.toJson()`, que ficou fora da fundação (decisão
  registrada no 0001 como plano, não como recusa).
- O custo a pesar na hora: todo tipo de campo customizado passa a precisar
  saber se converter para JSON.
- Precisa de um design doc próprio antes de começar.

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
- 0005 implementado: campos de texto seguem o snapshot (undo, reset e
  estado restaurado aparecem no campo). O último teste pulado do projeto
  voltou a rodar.
- Design docs 0001 a 0006 aceitos (2026-09-23).
