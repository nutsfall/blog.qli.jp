# ADR-0003: 記事はUUID slugのページバンドル（content/posts/YYYYMM/UUID/）

- ステータス: 採用
- 日付: 2025-09-15〜19（2026-07-13 事後記録）

## コンテキスト

旧ブログ・Mediumからの移行記事はタイトル由来のslugが日本語だったり欠けていたりして一貫しない。また画像を記事ごとに同梱管理したい。

## 決定

- slugは記事ごとに発行するUUIDとし、パーマリンクは `/:year:month:slug/`（例: `/202308<uuid>/`）
- ディレクトリはHugoページバンドル `content/posts/YYYYMM/UUID/index.md`。画像は同ディレクトリに置く
- 新規記事は `scripts/hugo_new_post.zsh` がこの構造で作成する

## 結果・影響

- URLとファイルパスがタイトル変更の影響を受けず安定する
- 一方でURLから記事内容が推測できないが、これは許容する。人間可読slugへの移行は [#15](https://github.com/nutsfall/blog.qli.jp/issues/15) で検討し、現状維持（UUID slug継続）で確定した（URL変更はリンク切れを伴うため）
- 202410に旧記事を一括インポートした際の日付・ディレクトリ整理もこのパターンに合わせた
