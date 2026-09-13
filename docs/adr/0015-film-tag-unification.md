# ADR-0015: 映画関連のタグはイギリス英語の film に統一する

- ステータス: 採用
- 日付: 2026-09-13

## コンテキスト

ADR-0007のタグ規約は映画を表す語を定めておらず、`film`（35記事）・`movies`（7）・`movie`（7）が混在していた。派生タグも `film-review` / `movie-review`、`japanese-film` / `japanese-cinema` が並存し、タグページが分散していた。

## 決定

映画関連のタグはイギリス英語に寄せて `film` をベースにする。

- `movie`, `movies` → `film`
- `movie-review` → `film-review`
- `japanese-cinema` → `japanese-film`
- 作品名などの固有名詞に含まれる語はそのまま（`unfair-the-movie`）
- `theater` / `online-theater` は舞台・イベントの記事で映画ではないため対象外

既存15記事は `auto_tagger.rb --apply` で置換し、`TAG_RULES` に同じ規約を追加して以後のタグ付けに反映する。

## 結果・影響

- 映画の記事が `film` 系のタグページに集約される
- Mediumインポート時に `movies` などが付いていても再付与で `film` になる

## 却下した代替案

- `movies`: 口語的でブログの温度感には合うが、`music` や `photography` など他のジャンルタグが単数形である中で浮き、イギリス英語に寄せる方針にも合わない
- `movie`: 単数形だと「ある1本の映画」の意味になり、ジャンル名として据わりが悪い
- `cinema`: 芸術・産業としての映画や映画館を指し、個別の鑑賞記事のタグとしては広すぎる
