# Activity + languages panel — design

Data: 2026-11-26
Repo: `msandredev/foamy-github`, base `1a5280d`

## Intent

O usuário quer ver, dentro do popup, o progresso de commits/atividade do GitHub
e uma barra de linguagens com cores e porcentagens iguais às do GitHub, para
saber qual linguagem predomina nos repositórios. Hoje o heatmap de contribuições
já é buscado e parseado, mas o componente `ContributionGraph` está oculto porque
o popup é limitado a 560px. Não existe dado de linguagem no plugin.

## Goals

- Abrir uma página **Activity & languages** a partir do badge `commits/yr`.
- Mostrar o heatmap existente de contribuições dos últimos 12 meses.
- Mostrar uma barra agregada de linguagens, com cor e porcentagem.
- Manter a lista de repositórios na altura atual.
- Falhas de linguagem devem ser explícitas, nunca virar `0%` ou barra vazia.

## Non-goals

- Não mudar contagens, PRs/issues, filtros ou o cabeçalho existentes.
- Não detalhar linguagem por repositório individual.
- Não transformar `commits/yr` em total semanal; ele continua sendo trailing-year.
- Não editar `kit/`.
- Não adicionar settings novas.

## Constraints

- Popup fixo em 560px; uma página separada evita comprimir a lista.
- `gh` e GraphQL são external data: argv fixo, sem shell, sem segredos em argv.
- JSON de linguagens precisa ser limitado antes do parse.
- QML usa apenas tokens Foamy existentes; texto externo com `Text.PlainText`.
- O request de linguagens não pode atrasar nem derrubar os badges atuais.

## Approaches

1. **Cartão fixo no topo da lista** — sempre visível, mas consome ~100px da
   lista de repos. Descartado: aperta a lista já densa.
2. **Página própria aberta pelo badge `commits/yr`** — segue o padrão das
   páginas de PRs/issues, dá espaço ao heatmap e à barra. **Escolhida.**
3. **Painel retrátil no topo** — economiza espaço, mas cria mais um estado e
   exige clique extra sem ganho sobre a página própria.

Decisão do usuário: opção 2.

## Design

### Navegação

`GithubView.qml` ganha `section === "activity"`. O badge `commits/yr` passa a ter
`selectsSection: "activity"`. A página usa o mesmo padrão de voltar das páginas
de PRs/issues: botão Backspace/Left/h e botão na header.

### Dados de atividade

Reaproveitar `service.githubActivity.calendar`, que já vem da query GraphQL
validada em `GithubStats.js`. O `ContributionGraph` existente passa a ser
instanciado na nova página, com o rótulo "%1 contributions in the last year".
Se `githubStatsValid` for falso, a página mostra o estado indisponível já
usado nos badges (`?`), sem tentar adivinhar zero.

### Dados de linguagem

Novo módulo puro `GithubLanguages.js`:

- `query()`: GraphQL fixo para
  `viewer.repositories(first: 100, ownerAffiliations: OWNER,
  orderBy: {field: UPDATED_AT, direction: DESC})` com
  `nodes { languages(first: 10, orderBy: {field: SIZE, direction: DESC})
  { edges { size node { name color } } } } }`.
- `parse(text, tr)`: valida payload, descarta `errors`, limita a saída, aceita
  apenas `name` curto, `color` no formato `#rrggbb` e `size` inteiro não
  negativo; agrega bytes por `(name, color)`, ordena por bytes, calcula
  porcentagem arredondada e mantém no máximo 8 linguagens, agrupando o resto
  como "Other". Falha fechada com erro traduzido.
- Sem `shell`, sem `jq`, sem segredo.

`Service.qml` ganha um processo finito dedicado, com os mesmos mecanismos já
usados para GitHub: `operationId`, deadline de 20s, fallback de failed-start,
`cancelGithubWork()` ao desativar/descarregar e flags
`githubLanguagesValid` / `githubLanguagesError` / `githubLanguagesRefreshing`.
A página dispara `reloadLanguages()` ao abrir e oferece Retry no erro.

### UI

A página `GithubActivityView.qml` contém:

```text
[←] Activity & languages
24 contributions in the last year
▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪   heatmap rolável
Less ▢▢▢▢▢ More
Languages
Rust ████████████ 47%   QML ██████ 26%   Python ████ 19%
```

Componentes: um `LanguageBar` com segmentos coloridos e uma legenda com
 nome, cor e porcentagem. Cores vêm do GitHub, mas só após validação de hex.
Texto é `PlainText`. O heatmap continua com os tokens Foamy atuais.

### Testes

- `tests/languages.test.js`: query equilibrada e campos presentes; agregação
  correta; porcentagens somam ~100 com arredondamento; payload inválido,
  oversized, cor inválida e tamanho negativo falham fechado.
- Harness QML: abrir página pelo badge, voltar, estado vazio/erro/loading.
- Suíte existente, `qmllint`, `qmlformat`, `plugin-validate`, stress curto.

## Scope decisions

- Linguagem é agregada por **bytes**, como a barra do GitHub, nos até 100
  repositórios possuídos pelo usuário. Decisão nossa; se o usuário quiser só os
  repos visíveis/filtrados, isso muda a query e deve ser dito antes da
  implementação.
- A consulta de linguagens é separada da consulta de stats para isolar falhas
  e custo. Decisão nossa.
