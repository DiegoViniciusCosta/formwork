# Backlog

Ordem de execução. Cada item diz do que depende. **Decisão** = precisa de
uma resposta sua antes de alguém executar.

Legenda: ⬜ a fazer · 🟨 esperando decisão · ✅ feito

---

## Agora: destrava tudo e não precisa de design

### 1. ✅ Projeto em git
Repositório local criado com commit inicial, e o remoto `origin` aponta
para `git@github.com:DiegoViniciusCosta/formwork.git`. Falta só o push,
que é seu: `git push -u origin main`.

### 2. ✅ A 0.1 não foi publicada
Confirmado no pub.dev em 2026-09-23: `formwork` e `formwork_material` não
existem (404), então os nomes estão livres. Os itens 7 e 8 são uma quebra
limpa, sem aliases nem guia de migração.

### 3. ✅ Testes do exemplo no `verify.sh`
O `verify.sh` roda os testes do exemplo nos dois modos (`--fast` e
completo), e portanto também no CI. Testado: um teste quebrado no exemplo
faz o script sair com código 1.

---

## Próximo: bugs que afetam quem usa a biblioteca

### 4. ✅ 0003 implementado (dados faltantes)
- `missingKeys` é nova;
- `missingFields` mantém o elo do meio da cadeia, preenchido;
- README com o Quick start do formulário completo e duas receitas;
- linha de receita no `PRINCIPLES.md`;
- no exemplo, o preset "Renewal" e o seletor "Only missing" / "Highlight
  missing".

### 5. 🟨 Campos de texto ignoram valores vindos de fora
Undo, reset e preencher por código atualizam o estado, mas o `TextField`
continua mostrando o texto antigo. Afeta quem usa Bloc, Riverpod ou
qualquer estado externo (princípio 1). O cenário "External state & undo"
mostra o problema, e há um teste pulado.
- **Decisão:** é um comportamento documentado do `TextControllerBinding`.
  Mudar pede um design doc (ainda não escrito). Quer que eu escreva?

---

## Depois: a fundação (grande, em sequência)

### 6. 🟨 Aprovar os design docs da fundação
Leitura e decisões suas, nesta ordem:
1. `0001-foundation.md`: modelo novo (`FieldDef`, `FormDef`, erros como
   dados, condições, grafo de dependências, `FieldState`).
2. `0002-per-change-cost.md`: desempenho. As metas de tempo são uma
   decisão sua.
3. `0004-api-naming.md`: nomes. Tem 3 perguntas em aberto: um ou dois
   widgets, o nome `FieldProps`, e `initialValues` ou `data`.

### 7. ⬜ Implementar o 0001, junto com a etapa 2 do 0002
Seguir a "Implementation order" do 0001. A trie persistente (0002, etapa
2) é o armazenamento do `FieldState` do 0001 §6, então entra junto.
Resolve também:
- validadores devolvendo texto em vez de dados (princípio 3);
- `touched` e `dirty` separados;
- ciclos rejeitados com erro claro.

Depende de: 6.

### 8. ⬜ Aplicar os nomes do 0004 na mesma versão do 0001
Quebra limpa, na mesma versão do 0001. Inclui os builders do
`formwork_material`.
Depende de: 7.

### 9. ⬜ Etapa 3 do 0002: a view visita só o que mudou
O ganho grande em formulários enormes: 21 ms → poucos ms por tecla com
10.000 campos.
Depende de: 7 (`changedPaths`).

---

## Perguntas abertas sem data (não bloqueiam nada acima)

- **Dados antigos no servidor:** um campo que fica oculto não vai no
  payload, e o servidor mantém o valor antigo. Mandar `null` ou deixar com
  o servidor? (0003, pergunta 2)
- **Condições com vários campos** (`all` / `any`) e a regra do elo do
  meio. Precisa estar resolvido antes do item 8. (0003, pergunta 1)
- **Teste de "trabalho por mudança"**, que o `PRINCIPLES.md` §2 lista como
  "Planned". Encaixa no item 7.

---

## Feito nesta rodada ✅

- Galeria de exemplos com 8 cenários e testes de widget.
- Correção: `visibleWhen` segue cadeias (ocultar um campo oculta os que
  dependem dele).
- 0002 etapa 1: `change()` cerca de 4x mais rápido por tecla.
- Correção: `FormSnapshot.touched` agora é somente-leitura.
- Design docs 0002, 0003 e 0004 (rascunhos).
- Confirmado: 0.1 não publicada, e os nomes estão livres no pub.dev.
