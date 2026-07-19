# ADR-0011: ソーシャルアイコンはホームに表示せず著者ページのみに表示する

- ステータス: 採用
- 日付: 2026-07-19

## コンテキスト

PaperModのテーマ標準では、`hugo.yaml` の `socialIcons` はホームの home-info ブロック下部（`partials/home_info.html` のfooter）に表示される。当ブログでは2026-03に `layouts/partials/home_info.html` を自作した際、このソーシャルアイコンfooterを含めなかった。

一方、自作の著者ページ（`layouts/_default/author.html`、`/authors/hiro/`）では `socialIcons` をFont Awesomeアイコンで表示している。

2026-07-19、テーマとオーバーライドのdiff総点検の際に、このfooter欠落が「テーマ追従漏れ」と誤認され、ホームへの復活が提案された。実際は意図した仕様であるため、記録として残す。

## 決定

- ソーシャルアイコン（X / Instagram / Threads / Medium）はホーム（`/`）には表示しない
- 表示場所は著者ページ（`/authors/hiro/`）のみとする
- `hugo.yaml` の `socialIcons` 設定は著者ページのデータソースとして維持する

## 結果・影響

- ホームは記事一覧とミラー案内に絞ったシンプルな構成を保つ
- テーマ本体の `home_info.html` とのdiffには social_icons footer の差分が常に現れるが、これは追従漏れではない
- `socialIcons` 設定がテーマ標準の表示位置で使われていなくても、設定削除は不可（著者ページが参照している）

## 却下した代替案

- **テーマ標準どおりホームのhome-infoブロックに表示する** — ホームの情報量を増やしたくない。プロフィール的な情報は著者ページに集約する方針のため却下
