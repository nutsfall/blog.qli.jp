# Architecture

## Stack

- **Hugo** (static site generator) + **PaperMod** theme (git submodule at `themes/PaperMod/`)
- **Cloudflare Workers** for hosting (`wrangler.toml`)
- **Firebase Realtime Database** for the anonymous like/clap system (`static/js/likes.js`, `static/js/firebase-config.js`)
- **GitHub Actions** for weekly automated Medium → Hugo post import (`.github/workflows/medium-import.yml`)

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

Custom templates override PaperMod defaults:
- `_default/single.html` — adds Firebase like button and post metadata
- `_default/list.html` — paginated listing with home info section
- `partials/post_meta.html` — date · reading time · word count · author
- `partials/home_info.html` — homepage welcome message

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
