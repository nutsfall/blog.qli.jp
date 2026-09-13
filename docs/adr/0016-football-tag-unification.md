# ADR-0016: サッカー関連のタグはイギリス英語の football に統一する

- ステータス: 採用
- 日付: 2026-09-13

## コンテキスト

サッカーを表すタグとして `soccer`（4記事）と `football`（3記事）が混在し、派生タグも `japan-soccer` と `soccer-tactics` があった。いずれもJリーグ・ワールドカップなどアソシエーションフットボールの記事で、アメリカンフットボールやラグビーの記事はない。

## 決定

サッカーを表すタグは、イギリス英語（Queen's English）に寄せて `football` に統一する。ADR-0015（film）と同じく、この語の選択についての決定であり、タグの綴り全般をイギリス英語にする決定ではない。

- `soccer` → `football`
- `japan-soccer` → `japan-football`
- `soccer-tactics` → `football-tactics`

既存記事は `auto_tagger.rb --apply` で置換し、`TAG_RULES` に同じ規約を追加して以後のタグ付けに反映する。

## 結果・影響

- サッカーの記事が `football` 系のタグに揃う
- 旧タグページ（`/tags/soccer/` など）は404になる。転送は設定しない

## 却下した代替案

- `soccer`: アメリカ英語で、映画を `film` に揃えた方針（ADR-0015）と向きが揃わない
