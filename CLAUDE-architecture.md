# Architecture

## Stack

- **Hugo** (static site generator) + **PaperMod** theme (git submodule at `themes/PaperMod/`)
- **Cloudflare Workers** for hosting (`wrangler.toml`)
- **Firebase Realtime Database** for the anonymous like/clap system (`static/js/likes.js`, `static/js/firebase-config.js`)
- **GitHub Actions** for weekly automated Medium → Hugo post import (`.github/workflows/medium-import.yml`)

選定の経緯・却下した代替案は `docs/adr/` を参照（ADR-0001〜0004）。

## Content Structure

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

## Layout Overrides (`layouts/`)

Custom templates override PaperMod defaults. Paths follow the Hugo v0.146+ template system (`layouts/` root + `layouts/_partials/`).

移設の経緯・削除したオーバーライドの理由は ADR-0013 を参照。

- `single.html` — adds the Firebase like button and the like/config scripts
- `taxonomy.html` — hides tags that have only one post
- `author.html` — standalone author page (`/authors/hiro/`), resolved from the `layout: "author"` front matter in `content/author.md`
- `_partials/author.html` — links the author name to `/authors/<name>/`
- `_partials/extend_head.html` — loads `/css/likes.css`
- `_partials/home_info.html` — homepage welcome message (social icons intentionally omitted, ADR-0011)
- `_partials/templates/opengraph.html` / `twitter_cards.html` — always derive og:image / twitter:image from page-bundle resources (ADR-0005)

## Like System

- Anonymous users identified by UUID stored in `localStorage` (`blog_user_key`)
- Post ID = Base64-encoded URL path
- Firebase project: `blog-qli-jp-handsclap` (Asia Southeast 1)
- Rules in `firebase-rules.json`

## Medium Import Automation

Weekly GitHub Actions job (Sunday 06:00 UTC = 15:00 JST):
1. Fetches Medium RSS feed for user `hiro`
2. Converts HTML → Markdown (Python: feedparser + BeautifulSoup + markdownify)
3. Creates page bundles with `source: medium` frontmatter
4. Auto-commits if new posts found

## Internationalization

- Language: Japanese (`ja`), `hasCJKLanguage: true`
- i18n strings: `i18n/` directory
- Search: Fuse.js with Japanese tokenization enabled
