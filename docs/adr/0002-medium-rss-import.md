# ADR-0002: Mediumで執筆し、GitHub Actionsで週次RSS自動インポート

- ステータス: 採用
- 日付: 2025-09-15（2026-07-13 事後記録）

## コンテキスト

執筆はMediumで続けたいが、記事の正本は自分のリポジトリに置きたい。手動コピーは続かない。

## 決定

GitHub Actions（`.github/workflows/medium-import.yml`、毎週日曜 06:00 UTC）でMediumのRSSを取得し、HTML→Markdown変換（feedparser + BeautifulSoup + markdownify）してページバンドルを自動コミットする。インポート記事には `source: "medium"` と `original_url` をフロントマターに記録する。

## 結果・影響

- ローカルで編集する前には必ず `git pull` が必要（自動コミットと衝突するため。CLAUDE.mdの運用ルール）
- RSS変換の癖（重複H3タイトル、CDN画像URL、計測ピクセル、ルール外のタグ）はインポート後処理 `scripts/process_new_posts.rb` で吸収する
- RSSに載らない過去記事の `original_url` は取得できない（→ ADR-0009）
