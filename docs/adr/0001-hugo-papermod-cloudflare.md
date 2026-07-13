# ADR-0001: Hugo + PaperMod + Cloudflare Workers による静的ブログ

- ステータス: 採用
- 日付: 2025-09-12〜16（2026-07-13 事後記録）

## コンテキスト

旧ブログ → Medium と渡ってきた記事群を、自分の管理下のドメイン（blog.qli.jp）で長期保存・公開したい。記事は日本語中心で1800件超。

## 決定

- 静的サイトジェネレータとして **Hugo** を採用（2025-09-12 初コミット）
- テーマは **PaperMod**（git submodule、`layouts/` のオーバーライドでカスタマイズ。2025-09-15）
- ホスティングは **Cloudflare Workers**（`wrangler.toml`。2025-09-16）

## 結果・影響

- 1800件超でもビルドが高速。記事はすべてMarkdown + gitで管理される
- テーマ本体には手を入れず、カスタマイズは `layouts/` / `assets/` のオーバーライドに限定する
- 日本語対応は `hasCJKLanguage: true`、検索はFuse.js（日本語トークナイズ有効）
