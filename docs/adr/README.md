# Architecture Decision Records

このブログの設計・運用に関する決定の記録。コードや設定から読み取れない「なぜそうしたか」「何を却下したか」を残す。

## いつ参照するか

- **既存の仕組み（スクリプト・テンプレート・運用ルール）を変更・置き換える前** — 関連ADRの経緯と「却下した代替案」を確認し、過去に却下された案を知らずに再提案・再実装しない
- 「なぜこうなっているのか」という疑問が出たとき
- 新しい提案が既存ADRと矛盾しないかの確認

## いつ書くか・更新するか

**新しいADRを書く：**

- アーキテクチャ・ツール・スクリプトの構成・運用ルールに影響する決定をしたとき
- 「やらない」と決めたとき（不作為の決定も記録する。例: ADR-0009）
- GitHub Issueでの検討が決定に至ったとき（検討中はIssue、決まったらADR）

**既存ADRを更新する：**

- 決定を覆すとき — 古いADRの本文は書き換えず、新しいADRを作り、古い方のステータスを「廃止（ADR-XXXXで置換）」に変える。一覧表も更新する
- ステータス行への注記（再検討Issueへのリンク等）のみ、既存ADRに追記してよい

**書かないもの：** 単発のバグ修正、個別記事への対応、コードを読めばわかること。判断に迷ったら「1年後に『なぜ？』と聞かれうるか」で決める。

## 書き方

- 番号は連番（`NNNN-slug.md`）、一度発行した番号は再利用しない
- 追加したら一覧表に行を足す

## フォーマット

```markdown
# ADR-NNNN: タイトル（決定内容がわかる一文）

- ステータス: 採用 | 廃止（ADR-XXXXで置換）
- 日付: YYYY-MM-DD

## コンテキスト
## 決定
## 結果・影響
## 却下した代替案（あれば）
```

2025〜2026年の決定は2026-07-13にgit履歴・MIGRATION.md・GitHub Issuesから事後記録したもの（各ADRに注記）。

## 一覧

| ADR | タイトル | ステータス |
|---|---|---|
| [0001](0001-hugo-papermod-cloudflare.md) | Hugo + PaperMod + Cloudflare Workers による静的ブログ | 採用 |
| [0002](0002-medium-rss-import.md) | Mediumで執筆し、GitHub Actionsで週次RSS自動インポート | 採用 |
| [0003](0003-uuid-slug-page-bundle.md) | 記事はUUID slugのページバンドル（content/posts/YYYYMM/UUID/） | 採用 |
| [0004](0004-firebase-likes.md) | Firebase Realtime Databaseによる匿名拍手システム | 採用 |
| [0005](0005-image-localization.md) | 画像はページバンドルへローカル化（冒頭=cover、本文=figure） | 採用 |
| [0006](0006-caption-heuristic.md) | caption自動検出はヒューリスティック維持、誤検出は手動修正 | 採用 |
| [0007](0007-tag-rules.md) | タグ規約（英語小文字・1〜3個・具体的）とauto_taggerへの一元化 | 採用 |
| [0008](0008-bulk-content-migration-policy.md) | 大量コンテンツ修正はスクリプト一括適用＋lint前後比較で行う | 採用 |
| [0009](0009-no-original-url-backfill.md) | 旧記事1832件のoriginal_url補完は行わない | 採用 |
| [0010](0010-auto-tagger-two-step.md) | auto_taggerからclaude -p を排除し--extract/--applyの2段構成にする | 採用 |
