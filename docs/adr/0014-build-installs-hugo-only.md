# ADR-0014: Cloudflareのビルドでは Hugo だけをインストールする

- ステータス: 採用
- 日付: 2026-08-21

## コンテキスト

`build.sh`（Cloudflare Workers Builds のカスタムビルドコマンド）は Dart Sass・Go・Node.js・Hugo の4つを毎回ダウンロードしてインストールしていた。Hugo公式ドキュメントの Cloudflare ホスティング手順のテンプレートをそのまま持ってきたもので、当サイトが実際に何を使っているかとは無関係だった。

2026-08-20、PR #20 のビルドがこれを踏んで失敗した。

```
[custom build] Installing Go 1.25.1...
[custom build] gzip: stdin: not in gzip format
[custom build] tar: Child returned status 1
```

Go のダウンロードが0.5秒で完了しており（75MBのtarballでは有り得ない）、実体はHTTPエラーページだった。`curl -sLJO` は `-s` でエラー出力を抑制し `-f` を付けていないため、HTTPエラーでも終了コード0を返してエラーページをファイルとして保存する。失敗が表面化するのは `tar` の段階で、メッセージからは何が起きたのか読み取れない。URL自体は健在で、一時的な障害だった。

調査の結果、4つのうち Hugo 以外はどれも使われていないことが分かった。

- **Dart Sass** — `.scss` / `.sass` ファイルがプロジェクトにもテーマにも1つもない
- **Go** — `hugo.yaml` に `module:` ブロックがなく、テーマは git submodule 運用（ADR-0001）。Hugo Modules を使っていないので Go ツールチェインは不要
- **Node.js** — テーマの `head.html` が `js.Build` を使うが、これは Hugo に組み込まれた esbuild で動く。`wrangler` は Cloudflare 側が自前の Node.js で `npx wrangler versions upload` として起動しており（`build.sh` はその中から呼ばれる）、`build.sh` が入れる Node.js は誰も参照していない

`hugo` だけを PATH に置いた環境（Go・Dart Sass は未インストール、Node.js も除外）でクリーンクローンをビルドし、6212ページと `js.Build` 由来の検索バンドル `search.<hash>.js` が正常に生成されることを確認した。

## 決定

- `build.sh` がインストールするのは Hugo だけにする。Dart Sass・Go・Node.js のインストールは削除する
- ダウンロードは `curl -fsSL --retry 3 --retry-delay 2 -o <file>` で行う。`-f` によりHTTPエラーで即座に終了コード非0となり、`set -euo pipefail` がその場でビルドを止める。壊れたファイルが `tar` に渡ることはなくなる
- `mkdir` は `mkdir -p` にする。コンテナがキャッシュされて再実行された場合に `set -e` で落ちないようにするため

`export TZ=Europe/Oslo` は記事の日付表示に影響するため変更しない。

## 結果・影響

- デプロイごとのダウンロードが約130MB減り、ビルド時間が短縮される
- 外部ダウンロードの失敗点が4箇所から1箇所になった
- ダウンロードが失敗したとき、`gzip: stdin: not in gzip format` ではなく curl のHTTPエラーで止まるため原因が読める
- 将来 Sass を使う、あるいはテーマを Hugo Modules へ移行する場合は、`build.sh` に該当のインストールを戻す必要がある。本ADRを参照すれば「なぜ消えているのか」が分かる

## 却下した代替案

- **依存は残したまま `curl` に `-f --retry` だけ足す** — 失敗時のメッセージは読めるようになるが、使っていないものを毎回130MB落とし続ける理由がない
- **何もせずリトライだけする** — 今回は一時障害なのでリトライで復旧するが、使っていない依存を抱えている限り同じ失敗を繰り返す
- **`TZ=Europe/Oslo` も整理する** — Hugo公式テンプレート由来で当サイトに固有の意味はないが、変更すると記事の日付表示が変わりうるため触らない
