# ADR-0004: Firebase Realtime Databaseによる匿名拍手システム

- ステータス: 採用
- 日付: 2025-09-25（2026-07-13 事後記録）

## コンテキスト

静的サイトにはリアクション機能がなく、ホスティング（Cloudflare Workers）側にも状態を持たせていない。ログイン不要の軽いリアクションだけ欲しい。

## 決定

- Firebase Realtime Database（プロジェクト `blog-qli-jp-handsclap`、Asia Southeast 1）に拍手数を保存する
- ユーザーは `localStorage` の UUID（`blog_user_key`）で匿名識別、記事IDはURLパスのBase64
- 実装は `static/js/likes.js`、アクセスルールは `firebase-rules.json`。記事ページのみ表示（一覧には出さない）

## 結果・影響

- アカウント登録なしで拍手できる。サーバー管理は不要
- `localStorage` ベースなのでブラウザを変えれば同一人物でも別ユーザー扱い（厳密な重複排除はしない、という割り切り）
