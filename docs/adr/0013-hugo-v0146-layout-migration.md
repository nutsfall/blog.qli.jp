# ADR-0013: レイアウトオーバーライドをHugo v0.146の新テンプレート体系へ移設する

- ステータス: 採用
- 日付: 2026-08-21

## コンテキスト

`themes/PaperMod` submodule が `f207ce6`（v8.0-109, 2026-04-11）で止まり、upstream master `d376885`（v8.0-139, 2026-08-02）に30コミット遅れていた（issue #19）。

単純なsubmodule更新ができなかったのは、upstream が Hugo v0.146 で導入された新テンプレート体系へ移行済み（`layouts/_default/` → `layouts/`、`layouts/partials/` → `layouts/_partials/`、`layouts/shortcodes/` → `layouts/_shortcodes/`、`layouts/_default/terms.html` → `layouts/taxonomy.html`）なのに対し、当リポジトリの自前オーバーライド11ファイルがすべて旧構造のままだったため。旧構造はHugoの後方互換で即座には壊れないが、テーマ側が新構造・オーバーライド側が旧構造という混在はどちらが効いているのか読みにくく、追従のたびに判断コストがかかる。

upstream の30コミットの実体はディレクトリのリネーム、CSS微調整（`header.css` / `md-content.css` / `post-entry.css` / `search.css` / `terms.css`）、`fastsearch.js` の書き直しで、テンプレートのロジック変更はほぼない。当方がオーバーライドしている9ファイルのうち upstream 側で中身が変わったのはインデント整形のみだった。

なお本件は deprecation 警告の解消が目的ではない。`.Language.LanguageDirection` / `.Language.LanguageCode` の2件は upstream 最新でも未修正で、更新後も出続ける。

## 決定

- submodule を `d376885` へ更新する
- オーバーライドを新体系のパスへ移設する。ADR-0001 の「テーマ本体（`themes/PaperMod/`）には手を入れず、カスタマイズは `layouts/` / `assets/` のオーバーライドに限定する」方針は不変

| 旧パス | 新パス |
|---|---|
| `layouts/_default/author.html` | `layouts/author.html` |
| `layouts/_default/single.html` | `layouts/single.html` |
| `layouts/_default/terms.html` | `layouts/taxonomy.html` |
| `layouts/partials/author.html` | `layouts/_partials/author.html` |
| `layouts/partials/extend_head.html` | `layouts/_partials/extend_head.html` |
| `layouts/partials/home_info.html` | `layouts/_partials/home_info.html` |
| `layouts/partials/templates/opengraph.html` | `layouts/_partials/templates/opengraph.html` |
| `layouts/partials/templates/twitter_cards.html` | `layouts/_partials/templates/twitter_cards.html` |
| `layouts/_default/list.html` | 削除 |
| `layouts/_internal/google_analytics.html` | 削除 |
| `layouts/partials/post_meta.html` | 削除 |

- 移設したファイルは upstream master 版を土台にし、維持すべきカスタマイズだけを当て直す。upstream 側のインデント整形は取り込み、次回追従時のdiffを最小に保つ

### 3ファイルを削除した理由

- **`layouts/_default/list.html`** — 唯一の差分だった `post-content md-content` を upstream が取り込んだ（`fe946d57`）ため、オーバーライドの内容が upstream `layouts/list.html` と末尾改行以外完全一致になり、存在意義が消滅した
- **`layouts/_internal/google_analytics.html`** — Hugo 0.146 で `_internal` の概念が廃止され、テーマの `head.html` の `partial "google_analytics.html"` は Hugo 埋め込みテンプレートへ解決されるようになった。このファイルは移設前からすでに無効だった（証拠: 更新前のビルド出力 `public/index.html` に、埋め込み版だけが持つ `doNotTrack` ガードが含まれ、gtagスニペットは1個だけだった）。GAは引き続き埋め込み版で動作する
- **`layouts/partials/post_meta.html`** — 現行オーバーライドの差分（`newScratch` → `slice`/`append` の書き換え、`<span>` ラッパ削除、`DateFormat` のデフォルト値）は意図的なカスタマイズではなくドリフトだった。`DateFormat` は `hugo.yaml` で設定済みのためデフォルト値の差は死んでいる。`<span>` ラッパについては、upstream版を採用すると読了時間・文字数・著者名が `<span>` で包まれるようになり生成HTMLは変化する（旧オーバーライド版とのビルド比較で4309ファイルに差分）。ただしテーマ・自前CSSのいずれにも `.post-meta` 配下の `span` に当たる規則はなく（`.post-meta` は color / font-size のみ、`.post-meta a` は span 内のリンクにも従来どおり当たる）、ブラウザ実測でも当該 span は `display: inline` かつ margin・padding ゼロで、meta行の文言・高さとも変化しなかった

### 維持したカスタマイズ

- **`layouts/single.html`** — Firebase拍手ボタン（ADR-0004）。`post_meta.html` 直後の `hideLikes` ガード付き `#like-btn` と、`/js/firebase-config.js` / `/js/likes.js` の module script 2行
- **`layouts/taxonomy.html`** — 記事1件のみのタグを一覧から隠す `{{- if gt $count 1 }}`（ADR-0007関連）
- **`layouts/_partials/author.html`** — 著者名を `/authors/<name>/` へのリンクにする
- **`layouts/_partials/extend_head.html`** — `/css/likes.css` の読み込み
- **`layouts/_partials/home_info.html`** — `social_icons.html` を呼ぶ `<footer>` の削除。**これはADR-0011の意図的な削除であり、テーマ追従漏れではない**。一方 `markdownify` は upstream の `RenderString` 形へ戻した。結果、テーマとの差分はADR-0011由来の1点のみになった
- **`layouts/_partials/templates/opengraph.html` / `twitter_cards.html`** — `.Params.cover.image` 分岐の削除（ADR-0005の画像ローカル化が前提）。分岐を残すと、Medium由来のファイル名（例 `1__uVd5GPPBdU82kq4IrVH5Xg.jpeg`）を持つ記事で `absURL` がサイトルート直下を指す壊れたURLになる。`cover:` を持つ記事96件のうちファイル名が `cover.*` なのは16件だけなので影響は大きい
- **`layouts/author.html`** — テーマに対応物がない独自ファイル。`content/author.md` の `layout: "author"` から解決される。新体系でもfront matterのlayout名は `layouts/<name>.html` に解決される（upstream自身が `layout: archives` / `layout: search` を `layouts/archives.html` / `layouts/search.html` で受けている）

## 結果・影響

- `layouts/` 配下は9ファイルから8ファイルへ減り、すべて新体系のパスになった。旧 `layouts/_default/` `layouts/partials/` `layouts/_internal/` は消滅した
- テーマとの差分が「意図的なカスタマイズ」だけになり、次回のsubmodule追従でdiffを読む負荷が下がった
- upstream のCSS変更（`.post-entry:hover` が `scale(0.96)` → `translateY(-2px)` + border-color、`.menu .active` が下線化、`.searchResults li` がflex + カード化、`terms-tags` の `gap`/`border-radius`）がそのまま反映される
- `opengraph.html` は `partial "_funcs/get-page-images"`、`twitter_cards.html` は `partial "templates/_funcs/get-page-images"` とパスが不一致だが、これは upstream 由来なのでそのまま踏襲する（統一しない）

## 却下した代替案

- **submodule更新だけ行い、オーバーライドは旧構造のまま据え置く** — Hugoの後方互換で当面は動くが、テーマ新構造とオーバーライド旧構造の混在で解決先が読みにくくなる。後方互換がいつ外れるかも不明なため却下
- **`post_meta.html` のオーバーライドを新パスへ移すだけに留める** — 差分がドリフトでしかなく、upstream版との生成HTMLの違いも見た目に影響しない `<span>` ラッパだけであることを確認できたため、保守対象として残す理由がない
- **`_funcs/get-page-images` のパス不一致を統一する** — upstream由来の差異であり、こちらで直すとテーマとの差分が増えて追従コストになるため却下
