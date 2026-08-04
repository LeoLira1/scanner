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
- **Digitação manual**: o fallback quando o QR está sujo ou rasgado — e a
  forma de testar o app inteiro sem depender da câmera.

A permissão de câmera é pedida pelo Android na primeira leitura; se for
negada, a tela explica e oferece a digitação manual.

## Regra crítica: múltiplos códigos

Um produto da CAMDA pode ter mais de um código ativo — tipicamente um
numérico e um alfanumérico (`254185` e `US254185`), cada um com saldo
próprio em `estoque_mestre`. Ao ler qualquer código, o app resolve o
produto em `mapa_produtos`/`mapa_produtos_codigos` e **soma o
`qtd_sistema` de todos os códigos vinculados** — mesma lógica do
`db_mapa.py` do camda-estoque. Se o código lido não estiver vinculado a
nenhum produto do mapa, o app mostra o saldo da linha única com um aviso
de que o total pode estar incompleto.

## Passo 0 — unidades (ainda não confirmado no banco)

O app exibe o **número cru** de `qtd_sistema`, sem conversão. A unidade
não vai colada no número; ela aparece separada e rotulada como o que é
(`unidade gravada no mapa: L`). O motivo:

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

Quando a confirmação vier, a conversão entra no slot que hoje mostra
"valor cru do sistema": número convertido grande, valor cru pequeno
embaixo (como na maquete `tag-estoque.html`).

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
