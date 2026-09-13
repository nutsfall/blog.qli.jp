# ADR-0017: 日本人の人名タグは姓・名の順で書く

- ステータス: 採用
- 日付: 2026-09-13

## コンテキスト

人名タグの順序が揃っておらず、同じ人物が `shunji-iwai`（1記事）と `iwai-shunji`（5記事）、`chihiro-onitsuka` と `onitsuka-chihiro` に分かれていた。他にも `hidetoshi-nakata`、`tetsuya-komuro`、`ai-otsuka` が名・姓の順だった一方、`kobayashi-takeshi` や `utada-hikaru` など多くは姓・名の順だった。

## 決定

日本人の人名をローマ字でタグにするときは、文化庁が示す方針（日本人の姓名をローマ字で書く場合も姓・名の順とする）に合わせて、姓・名の順にする。

- `shunji-iwai` → `iwai-shunji`
- `chihiro-onitsuka` → `onitsuka-chihiro`
- `hidetoshi-nakata` → `nakata-hidetoshi`
- `tetsuya-komuro` → `komuro-tetsuya`
- `ai-otsuka` → `otsuka-ai`

既存記事は `auto_tagger.rb --apply` で置換し、`TAG_RULES` に同じ規約を追加して以後のタグ付けに反映する。

## 結果・影響

- 同一人物のタグが1つにまとまる
- 対象はローマ字の人名らしいタグを機械的に抽出して目視で判定したもので、抽出パターンに合わない表記の人名が残っている可能性はある
- 長音の表記（`yosui` / `yousui` など）の揺れはこの決定の対象外
- 旧タグページは404になる。転送は設定しない

## 却下した代替案

- 名・姓の順（英語圏の慣習）: ブログ内で姓・名の順のタグが多数派で、置換件数も少なく済む
