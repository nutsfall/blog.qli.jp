# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 変更前の同期

ファイルの変更やコンテンツ追加など、何らかの編集を行う前に必ず `git pull` を実行してリモートと同期すること（GitHub Actions による自動コミットが入っている可能性があるため）。

## New Post

```bash
scripts/hugo_new_post.zsh "Post Title"
```

Creates `content/posts/YYYYMM-UUID/index.md` with draft frontmatter.

## Architecture

### Stack

- **Hugo** (static site generator) + **PaperMod** theme (git submodule at `themes/PaperMod/`)
- **Cloudflare Workers** for hosting (`wrangler.toml`)
- **Firebase Realtime Database** for the anonymous like/clap system (`static/js/likes.js`, `static/js/firebase-config.js`)
- **GitHub Actions** for weekly automated Medium → Hugo post import (`.github/workflows/medium-import.yml`)

### Content Structure

Posts are Hugo page bundles: `content/posts/YYYYMM/UUID/index.md`

Key frontmatter fields:
```yaml
title: "..."
date: '2023-08-27T01:31:16.245Z'
slug: "uuid-here"           # Used in permalink: /:year:month:slug/
draft: false
source: "medium"            # Set by importer
original_url: "https://medium.com/..."
```

Permalink pattern (`hugo.yaml`): `/:year:month:slug/` → e.g. `/202308some-uuid/`

### Layout Overrides (`layouts/`)

Custom templates override PaperMod defaults:
- `_default/single.html` — adds Firebase like button and post metadata
- `_default/list.html` — paginated listing with home info section
- `partials/post_meta.html` — date · reading time · word count · author
- `partials/home_info.html` — homepage welcome message

### Like System

- Anonymous users identified by UUID stored in `localStorage` (`blog_user_key`)
- Post ID = Base64-encoded URL path
- Firebase project: `blog-qli-jp-handsclap` (Asia Southeast 1)
- Rules in `firebase-rules.json`

### Medium Import Automation

Weekly GitHub Actions job (Sunday 06:00 UTC = 15:00 JST):
1. Fetches Medium RSS feed for user `hiro`
2. Converts HTML → Markdown (Python: feedparser + BeautifulSoup + markdownify)
3. Creates page bundles with `source: medium` frontmatter
4. Auto-commits if new posts found

### Internationalization

- Language: Japanese (`ja`), `hasCJKLanguage: true`
- i18n strings: `i18n/` directory
- Search: Fuse.js with Japanese tokenization enabled

## Images

Images are stored in the page bundle alongside `index.md`.

**Cover image** (frontmatter):

```yaml
cover:
  image: "filename.jpeg"
```

**Inline images** (markdown body):

```markdown
![](filename.jpeg)
```

PaperMod automatically generates responsive srcset for cover images.

Available image shortcodes (from PaperMod):

- `{{< figure src="..." caption="..." align="center" >}}`
- `{{< inTextImg url="..." height="20" >}}` — for small inline icons

**Note:** The Medium importer does not download images. Images from Medium posts remain as external URLs in the content.

### Medium記事の画像対応

`git pull` 後に新しいMedium記事が追加されたら、外部画像URL（`cdn-images-1.medium.com`）をローカルに落とす。

1. 画像をページバンドルにダウンロード: `curl -L <url> -o content/posts/.../cover.png`
2. フロントマターに `cover:` を追加。キャプションテキストがあれば `caption:` も設定する
3. 本文中の `![]()` やキャプションのテキスト行は削除する（coverで表示されるので二重になるため）

```yaml
cover:
  image: "cover.png"
  caption: "キャプションテキスト"
```

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
- `auto_tagger.rb` — bulk-tags posts using Claude CLI (`claude -p`)
- `duplicate_post_cleaner.rb` — removes duplicate posts (85% similarity threshold)
- `convert_to_page_bundles.rb` — migrates flat `.md` files to page bundle structure
- `title_slug_updater.rb` — updates frontmatter titles/slugs
- `slug_generator.rb` — generates slugs from titles
- `extension_fixer.rb` — fixes incorrect file extensions
