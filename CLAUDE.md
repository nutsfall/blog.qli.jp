# CLAUDE.md

## 変更前の同期

ファイルの変更やコンテンツ追加など、何らかの編集を行う前に必ず `git pull` を実行してリモートと同期すること（GitHub Actions による自動コミットが入っている可能性があるため）。

## New Post

```bash
scripts/hugo_new_post.zsh "Post Title"
```

Creates `content/posts/YYYYMM/UUID/index.md` with draft frontmatter.

## Medium記事のインポート後処理

`git pull` 後に新しいMedium記事があれば：

```bash
/opt/homebrew/opt/ruby/bin/ruby scripts/process_new_posts.rb
```

## 詳細ドキュメント

作業内容に応じて読み込むこと：

- コード・テンプレート・設定を触るとき → `CLAUDE-architecture.md`
- コンテンツ作業（画像・タグ・スクリプト）→ `CLAUDE-content.md`
