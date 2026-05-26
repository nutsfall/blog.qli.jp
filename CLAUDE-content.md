# Content Workflow

## Medium記事のインポート後処理

`git pull` 後に新しいMedium記事が追加されたら、以下を実行する：

```bash
/opt/homebrew/opt/ruby/bin/ruby scripts/process_new_posts.rb
```

以下をまとめて自動処理する：
- 外部画像URL（`cdn-images-1.medium.com`）をページバンドルにダウンロードし `cover:` フロントマターを追加
- キャプションテキストがあれば `caption:` も設定
- 本文中の `![]()` とキャプション行を削除（cover で表示されるため）
- 冒頭の重複H3タイトルを削除
- `tags: []` の記事に `auto_tagger.rb` でタグを付与

処理後に内容を確認してコミットする。

```bash
/opt/homebrew/opt/ruby/bin/ruby scripts/process_new_posts.rb --dry-run  # プレビュー
```

## Images

Images are stored in the page bundle alongside `index.md`.

**Cover image** (frontmatter):

```yaml
cover:
  image: "filename.jpeg"
  caption: "キャプションテキスト"   # optional
```

**Inline images** (markdown body):

```markdown
![](filename.jpeg)
```

PaperMod automatically generates responsive srcset for cover images.

Available image shortcodes (from PaperMod):

- `{{< figure src="..." caption="..." align="center" >}}`
- `{{< inTextImg url="..." height="20" >}}` — for small inline icons

## Tags

All posts have a `tags:` field in frontmatter. Tags follow these rules:

- **English, lowercase** — use hyphens for multi-word: `j-league`, `apple-music`
- **1–3 tags per post** (1 is fine for short posts)
- **Specific over generic** — avoid `diary`, `misc`, `thoughts`, `life`
- **Proper nouns welcome** — products, artists, teams, works: `apple`, `netflix`, `avispa-fukuoka`

When adding or fixing tags on any post — including reducing excess tags — always use `auto_tagger.rb` instead of editing frontmatter manually.

```bash
/opt/homebrew/opt/ruby/bin/ruby scripts/auto_tagger.rb <file>           # tag a specific post
/opt/homebrew/opt/ruby/bin/ruby scripts/auto_tagger.rb --dry-run <file> # preview without writing
```

To check tag counts across all posts:

```bash
/opt/homebrew/opt/ruby/bin/ruby scripts/tag_checker.rb
```

Uses `claude -p` (no API key needed). Requires Claude Code CLI to be authenticated.

## Maintenance Scripts (Ruby)

Located in `scripts/`:
- `process_new_posts.rb` — post-import processor for Medium posts (image localize, H3 removal, tagging)
- `auto_tagger.rb` — bulk-tags posts using Claude CLI (`claude -p`)
- `duplicate_post_cleaner.rb` — removes duplicate posts (85% similarity threshold)
- `convert_to_page_bundles.rb` — migrates flat `.md` files to page bundle structure
- `title_slug_updater.rb` — updates frontmatter titles/slugs
- `slug_generator.rb` — generates slugs from titles
- `extension_fixer.rb` — fixes incorrect file extensions
