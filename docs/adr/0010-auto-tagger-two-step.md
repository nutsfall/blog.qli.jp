# ADR-0010: auto_taggerからclaude -p を排除し--extract/--applyの2段構成にする

- ステータス: 採用
- 日付: 2026-07-13

## コンテキスト

`auto_tagger.rb` はタグ生成を `claude -p`（Claude Code CLIのヘッドレス実行）に依存していた。Claude Codeセッション内から呼ぶとネスト実行になり、CLI認証切れ（401）でタグ付けが止まる事象が発生。タグ付けの運用自体がClaude Codeセッション経由（`git pull` → `process_new_posts.rb`）なので、外部プロセスとしてLLMを呼ぶ必然性がない。

## 決定

スクリプトからLLM呼び出しを排除し、2段構成にする:

1. `auto_tagger.rb --extract <file>...` — 対象記事のtitle/excerptとタグ規約をJSONで出力
2. セッション内のClaudeが規約（ADR-0007）に従いタグを生成し、`[{"path": ..., "tags": [...]}]` を作成
3. `auto_tagger.rb --apply tags.json` — frontmatterへ書き込み（`--dry-run` 対応）

`process_new_posts.rb` は末尾で `--extract` 出力を表示するだけにし、タグ生成・適用はインポート後処理を実行したセッションが引き継ぐ。

## 結果・影響

- CLI認証状態に依存しなくなり、APIキーも不要
- タグ付けが「スクリプト実行1発」ではなく、セッションによる生成ステップを挟む半自動になる（規約準拠と既存タグとの一貫性はセッション側が担保する）

## 却下した代替案

- Anthropic API直叩き — APIキーの管理と課金が発生する。呼ぶモデルはセッション内のClaudeと同じ
- CLI再認証して現状維持 — 認証切れのたびに人手が要り、ネスト実行の脆さも残る
