# Scanner CAMDA

Consulta de estoque por QR code e código de barras. Leo aponta a câmera do
celular para o QR colado na folha A4 do galpão e o app mostra a quantidade
em estoque daquele produto. **Somente leitura** — nenhuma movimentação,
nenhum lançamento, nenhuma escrita no banco.

Banco: o mesmo Turso/libSQL do
[camda-estoque](https://github.com/LeoLira1/camda-estoque), acessado
direto do app via `libsql_dart` — sem backend no meio.

## Configuração (primeiro uso)

1. Abra o app e toque em ⚙️ (**Configuração do Banco**).
2. Digite a **Database URL** (`libsql://...turso.io`) e o **Token**.
3. **Salvar configuração** e depois **Testar conexão**.

As credenciais ficam salvas apenas no dispositivo — nunca entram neste
repositório.

> **Recomendado: token read-only.** Crie no Turso um token somente de
> leitura para este app (`turso db tokens create camda-estoque --read-only`).
> Não é pelo repositório (o token não vai para lá) — é por celular perdido:
> com token read-only, quem achar o aparelho não consegue alterar o estoque.

## Leitura

Duas formas, sempre disponíveis:

- **Câmera** (`mobile_scanner` / ML Kit): lê QR e código de barras 1D ao
  vivo, com lanterna para os cantos escuros do galpão. Aceita tanto um
  código puro (`US254185`) quanto uma URL que contenha `p=`.
- **Digitação manual**: aceita o **código** (`254185`, `US254185`) **ou o
  nome do produto** (`boral 20l`) — o fallback quando o QR está sujo ou
  rasgado, e a forma de testar o app inteiro sem depender da câmera.

A permissão de câmera é pedida pelo Android na primeira leitura; se for
negada, a tela explica e oferece a digitação manual.

## Busca pelo nome do produto

Mesma ideia do campo de busca do [camdaapp](https://github.com/LeoLira1/camdaapp)
(a tela **Estoque Mestre**), adaptada ao scanner: o campo da tela inicial é
um só e entende as duas coisas.

- Texto de **uma palavra com dígito e sem espaço** (`254185`, `US254185`) é
  tratado como código e vai pelo caminho de sempre: mapa de produtos, soma
  dos códigos vinculados, lista de vencimentos.
- Qualquer outra coisa é **nome**. Se o código digitado não existir, o app
  ainda tenta o nome antes de dizer "não encontrado" — a heurística nunca é
  a última palavra.

Como o nome é procurado:

- **as palavras valem em qualquer ordem**, com E entre elas: `boral 20`
  acha `HERBICIDA BORAL 500 SC 20L`, e `boral fox` não acha nada;
- **acento não atrapalha** — `orquidea` acha `INSETICIDA ORQUÍDEA 5L`. No
  SQL o `LIKE` do SQLite não ignora acento, então a consulta tenta primeiro
  o filtro barato com a palavra mais longa e só varre `estoque_mestre`
  quando ele não traz nada (mesma tática da lista de vencimentos);
- **mínimo de 3 letras** — com menos que isso meio galpão casa e a lista
  não ajuda ninguém;
- **um produto aparece uma vez só**: os códigos com o mesmo nome (`254185`
  e `US254185`) entram agrupados, com o saldo somado.

Um único resultado abre direto a tela do produto. Vários abrem a lista, com
nome, códigos, categoria e saldo; ao tocar, **a consulta completa é refeita
pelo código** — o número da lista é uma prévia, quem manda é a tela do
produto (que resolve `mapa_produtos` e a lista de vencimentos). Passando de
60 itens, a tela avisa para acrescentar uma palavra em vez de rolar o
catálogo inteiro.

## Regra crítica: múltiplos códigos

Um produto da CAMDA pode ter mais de um código ativo — um numérico e outro
com prefixo (`222534` e `US222534`, `237191` e `100237191`), cada um com
saldo próprio em `estoque_mestre`. Na prateleira existe uma pilha só, e o
saldo real é a soma:

```
ADJUVANTE PHOSFIX NORTOX 5L → 222534 (11) + US222534 (73) = 84
HERBICIDA ULTIMATO SC 20L   → 237191 (40) + 100237191 (125) = 165
```

A resolução tem dois degraus, nesta ordem — a mesma regra do
`agrupamento.dart` do app irmão `Contagemsimplificada`:

1. **`mapa_produtos`/`mapa_produtos_codigos`** — o vínculo cadastrado no
   dashboard. Autoritativo: o app soma o `qtd_sistema` de todos os códigos
   do produto, mesma lógica do `db_mapa.py` do camda-estoque.
2. **Nome do produto** — quando o código lido não está no mapa. Os irmãos
   são as linhas de `estoque_mestre` com a mesma chave de nome (maiúscula,
   sem acento, espaços colapsados), exatamente o que a busca por nome já
   faz. Isso cobre qualquer prefixo, presente ou futuro, sem adivinhar
   aritmética de string: a convenção `US` sozinha deixava o `100237191` do
   Ultimato de fora e mostrava 40 no lugar de 165 — saldo errado é pior que
   "não encontrado", porque quem está no galpão acredita no número.

O mapa manda mais que o nome: um código já cadastrado em outro produto não
entra num grupo montado por nome, e nome em branco não agrupa nada.

Grupo montado por nome é heurística, não cadastro — então a ressalva de
total incompleto continua na tela, dizendo o que de fato aconteceu:
*"códigos somados pelo nome · sem vínculo no mapa, o total pode estar
incompleto"*. Um código fora do mapa e sem irmão nenhum mantém a ressalva
antiga, *"código não vinculado no mapa"*.

## Lote a carregar primeiro (FEFO)

Logo abaixo da quantidade, a tela do produto mostra **qual lote deve sair
primeiro**: o de **validade mais próxima** (FEFO — *first expired, first
out*), lido da lista de vencimentos (`validade_lotes`, a mesma planilha que
alimenta os alertas de validade do camda-estoque).

```
        CARREGAR PRIMEIRO
             2411A
  vence 12/09/2026 · faltam 39 dias
     35 no lote · mais 2 lotes na lista
```

O número do lote muda de cor conforme a urgência: **laranja** faltando 30
dias ou menos, **vermelho** se já venceu.

**Como o lote é encontrado:** `validade_lotes` não tem coluna de código — o
vínculo com `estoque_mestre` é pelo **nome do produto**, e os nomes vindos
do BI trazem um prefixo de código (`100235440 - FUNGICIDA FOX XPRO 20L`). O
app compara pela mesma chave do dashboard (`_nome_validade_key`): sem o
prefixo, sem acento, maiúsculo, aceitando um nome contido no outro. A
consulta tenta primeiro um filtro barato no SQL (nome inteiro, depois a
palavra mais longa) e só varre a tabela quando os dois falham — o `LIKE` do
SQLite não ignora acento.

Quando não há lote para apontar, o motivo aparece escrito, porque os dois
casos são diferentes:

- `produto não está na lista de vencimentos` — a lista foi lida e este
  produto não está nela;
- `lista de vencimentos indisponível` — não deu para ler a lista (banco sem
  a tabela, falha na consulta). O saldo continua aparecendo normalmente.

Lote sem data de vencimento na planilha nunca é apontado como "o primeiro a
vencer": ele aparece rotulado como `sem data de vencimento na lista`.

## Passo 0 — unidades (ainda não confirmado no banco)

O app exibe o **número cru** de `qtd_sistema`, sem conversão, e **nenhuma
unidade vai colada no número**. As duas linhas que explicavam isso na tela
(`valor cru do sistema · conversão de unidade não confirmada` e `unidade
gravada no mapa: L`) foram retiradas a pedido do Leo — aquele espaço, logo
abaixo da quantidade, passou a ser do lote a carregar. A ressalva continua
valendo e está registrada aqui. O motivo:

**`qtd_sistema` conta embalagens, não litros** — três indícios no
`camda-estoque`:

1. `app_turso.py` calcula o volume como `qtd_sistema × tamanho da
   embalagem lido do nome do produto` (`extrair_litros`). Se o campo já
   estivesse em litros, multiplicar por 20 não faria sentido.
2. O próprio dashboard legenda os valores como "exibido em unidades".
3. `estoque_mestre.qtd_sistema` é `INTEGER` e vem direto da coluna de
   quantidade da planilha importada.

O valor conhecido reforça: **604 não é múltiplo de 20**. Se fossem litros
de um produto 20L, dariam 30,2 baldes — fração de balde lacrado. Como
contagem de baldes, 604 fecha (≈ 12.080 L).

**Consequência:** a conversão proposta (20L → dividir por 20) mostraria
30 no lugar de 604. Por isso ela **não** foi implementada.

Para confirmar no banco, rode no Turso (só leitura):

```sql
-- 1. O par de códigos do BORAL e a soma
SELECT codigo, produto, qtd_sistema, ultima_contagem
FROM   estoque_mestre
WHERE  UPPER(TRIM(codigo)) IN ('254185', 'US254185');

-- 2. Teste decisivo: se fosse litros, quase todo produto 20L teria
--    qtd_sistema múltiplo de 20. Se for embalagem, ~1 em 20 cai nisso.
SELECT COUNT(*)                                        AS produtos_20l,
       SUM(CASE WHEN qtd_sistema % 20 = 0 THEN 1 ELSE 0 END) AS multiplos_de_20
FROM   estoque_mestre
WHERE  UPPER(produto) LIKE '%20L%';

-- 3. mapa_posicoes.unidade é consistente?
SELECT unidade, COUNT(*) AS posicoes
FROM   mapa_posicoes
WHERE  produto_id IS NOT NULL
GROUP  BY unidade
ORDER  BY posicoes DESC;

-- 4. Onde a unidade da posição diverge da unidade padrão do produto
SELECT mp.nome, mp.unidade_pad, p.unidade, COUNT(*) AS posicoes
FROM   mapa_posicoes p
JOIN   mapa_produtos mp ON mp.produto_id = p.produto_id
WHERE  p.produto_id IS NOT NULL
  AND  IFNULL(p.unidade, '') <> IFNULL(mp.unidade_pad, '')
GROUP  BY mp.nome, mp.unidade_pad, p.unidade;
```

Sobre a consulta 3: pelo código, `mapa_posicoes.unidade` **não** é
confiável por construção. Ela vem de um selectbox preenchido à mão
(`["L","kg","un","cx","sc","fardo","m³"]`), cujo default é o
`unidade_pad` do produto — que por sua vez tem `DEFAULT 'L'` no esquema.
Um caminho do dashboard (divisão automática de paletes) grava `'un'`
fixo. E o número gravado em `mapa_posicoes.quantidade` vem da
distribuição proporcional de `qtd_sistema`, sem olhar para esse texto —
ou seja, o rótulo nunca influenciou a grandeza.

Quando a confirmação vier, a conversão entra no próprio número grande:
valor convertido em destaque e valor cru pequeno embaixo (como na maquete
`tag-estoque.html`), sem tomar o espaço do lote.

## Cache local

Em ⚙️, a chave **Cache local** (ligada por padrão) mantém uma cópia do
banco num arquivo do aparelho — o app abre e responde na hora, mesmo com
a internet ruim do galpão. Ali também ficam:

- **Sincronizar** — puxa as novidades do banco online;
- **Limpar cache local** — apaga o arquivo e baixa tudo de novo;
- a data e hora da **última sincronização**.

Quando a resposta vem do arquivo local, a tela do produto avisa com
`CACHE LOCAL · sincronizado há N min`; quando vem direto do banco, mostra
`consultado agora do banco`.

Como o app só lê, a réplica local é aberta em modo `replica` (nunca
`offline`): não existe gravação para empurrar de volta, então um token
read-only basta e não há risco de conflito de frames. Na primeira consulta
com o cache ainda vazio o app espera a carga inicial em vez de responder
"código não encontrado" — um cache vazio nunca é confundido com estoque
inexistente.

## Como gerar o APK (sem PC)

1. Vá em **Actions → Build & Release APK → Run workflow**.
2. Ao finalizar, baixe o APK em **Releases** (`app-release.apk`) ou nos
   **Artifacts** da execução.

O projeto Android é gerado pelo CI (`flutter create` no `build.yml`);
o repositório versiona apenas `lib/`, `test/`, assets e o workflow.

## Desenvolvimento local (opcional)

Pré-requisitos: Flutter + Android SDK.

```bash
flutter create --org com.camda --project-name scanner_camda .
flutter pub get
flutter run
```
