# Content Workflow

## Medium記事のインポート後処理

`git pull` 後に新しいMedium記事が追加されたら、以下を実行する：

```bash
/opt/homebrew/opt/ruby/bin/ruby scripts/process_new_posts.rb
```

以下をまとめて自動処理する：
- 冒頭の重複H3タイトルを削除（タイトルと大文字小文字違いでも一致させる）
- 外部画像URL（`cdn-images-1.medium.com`）をページバンドルにダウンロード。画像の位置で扱いを分ける：
  - **本文より前にある画像**（重複H3除去後に本文先頭）→ `cover:` フロントマターを追加し、本文から画像・キャプション行を削除
  - **本文の後にある画像** → インライン画像としてローカル化し、`![]()` とキャプション行を `{{< figure >}}` ショートコードに置換
- キャプションテキストがあれば cover の `caption:` / figure の `caption=` に設定
- タグ付け対象の `auto_tagger.rb --extract` 出力を表示（Mediumのタグはルール未準拠のため常に再付与）。Claude Codeセッションがこの出力からタグを生成し、`--apply` で適用する

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

All posts have a `tags:` field in frontmatter. タグ規約の正本は `scripts/auto_tagger.rb` の `TAG_RULES`（`--extract` の出力に含まれる）。規約の内容と経緯は [ADR-0007](docs/adr/0007-tag-rules.md)。

When adding or fixing tags on any post — including reducing excess tags — always use `auto_tagger.rb` instead of editing frontmatter manually. The script is a two-step tool driven from a Claude Code session (no LLM call inside the script):

```bash
/opt/homebrew/opt/ruby/bin/ruby scripts/auto_tagger.rb --extract <file>...        # 対象記事のtitle/excerptとルールをJSONで出力
# → セッション内のClaudeがルールに従いタグを生成し、[{"path": ..., "tags": [...]}] 形式のJSONを作る
/opt/homebrew/opt/ruby/bin/ruby scripts/auto_tagger.rb --apply tags.json --dry-run # プレビュー
/opt/homebrew/opt/ruby/bin/ruby scripts/auto_tagger.rb --apply tags.json           # 適用
```

To check tag counts across all posts:

```bash
/opt/homebrew/opt/ruby/bin/ruby scripts/tag_checker.rb
```


## Maintenance Scripts (Ruby)

Located in `scripts/`:
- `process_new_posts.rb` — post-import processor for Medium posts (image localize, H3 removal, tagging)
- `auto_tagger.rb` — two-step tagger (`--extract` / `--apply`) driven from a Claude Code session
- `duplicate_post_cleaner.rb` — removes duplicate posts (85% similarity threshold)
- `convert_to_page_bundles.rb` — migrates flat `.md` files to page bundle structure
- `title_slug_updater.rb` — updates frontmatter titles/slugs
- `slug_generator.rb` — generates slugs from titles
- `extension_fixer.rb` — fixes incorrect file extensions
