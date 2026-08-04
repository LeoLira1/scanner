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

## Regra crítica: múltiplos códigos

Um produto da CAMDA pode ter mais de um código ativo — tipicamente um
numérico e um alfanumérico (`254185` e `US254185`), cada um com saldo
próprio em `estoque_mestre`. Ao ler qualquer código, o app resolve o
produto em `mapa_produtos`/`mapa_produtos_codigos` e **soma o
`qtd_sistema` de todos os códigos vinculados** — mesma lógica do
`db_mapa.py` do camda-estoque. Se o código lido não estiver vinculado a
nenhum produto do mapa, o app mostra o saldo da linha única com um aviso
de que o total pode estar incompleto.

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
