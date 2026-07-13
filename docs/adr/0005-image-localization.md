# ADR-0005: 画像はページバンドルへローカル化（冒頭=cover、本文=figure）

- ステータス: 採用
- 日付: 2026-05-26（process_new_posts.rb導入）〜2026-07-10（Phase 7で旧記事へ適用）（2026-07-13 事後記録）

## コンテキスト

Mediumインポート記事の画像は `cdn-images-1.medium.com` へのremote参照で、Mediumの都合で消えうる。記事の正本をリポジトリに置く方針（ADR-0002）と矛盾する。

## 決定

画像はすべてページバンドル内にダウンロードし、位置で扱いを分ける:

- **本文より前にある画像**（重複H3除去後の先頭）→ `cover:` フロントマターの `cover.{ext}` にし、本文から行を削除
- **本文中の画像** → ローカルファイル + `{{< figure src="..." >}}` ショートコードに置換
- ファイル名は内容がわかる説明的な名前を優先する（例: `tullys-glass.jpeg`）

新規インポートは `scripts/process_new_posts.rb`、旧記事の一括cover化は `scripts/cover_migrator.rb`（Phase 7、52記事）で適用した。

## 結果・影響

- 画像の生殺与奪をMediumに握られない。PaperModがcoverのレスポンシブsrcsetを自動生成する
- キャプションの自動判別という難問が発生した（→ ADR-0006）
