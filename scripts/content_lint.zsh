#!/bin/zsh
# content/posts 配下の移行残骸パターンを検出して件数を出力する。
# MIGRATION.md のフェーズ進捗確認用。修正前後で実行して差分を見る。
# 使い方: scripts/content_lint.zsh [-v]  (-v で該当ファイル一覧も出力)

setopt extendedglob
cd "$(dirname "$0")/.." || exit 1
verbose=0
[[ "$1" == "-v" ]] && verbose=1

check() {
  local label="$1"; shift
  local files
  files=$(grep -rlE "$@" content/posts --include=index.md 2>/dev/null)
  local count=0
  [[ -n "$files" ]] && count=$(echo "$files" | wc -l | tr -d ' ')
  printf '%-45s %5d\n' "$label" "$count"
  if (( verbose && count > 0 )); then
    echo "$files" | sed 's/^/    /'
  fi
}

echo "=== フロントマター ==="
check "空 categories: []"           '^categories: \[\]'
check "空 keywords: []"             '^keywords: \[\]'
check "空 description"              "^description: (''|\"\")\$"
check "date シングルクォート"       "^date: '"
check "draft: true"                 '^draft: true'

echo "=== 本文: 変換残骸 ==="
check "Medium計測ピクセル"          'medium\.com/_/stat'
check "Mediumリンクカード崩れ"      '"\)\[\]\(http'
check "旧ブログ リンク: 形式"       '^リンク: \['
check "空画像 ![]()"                '!\[\]\(\)'
check "リモート画像参照"            '!\[[^]]*\]\(https?://'
check "エスケープ残骸 \\_ \\*"      '\\[_*]'

echo "=== 本文: 定型ブロック ==="
check "posted with (Socialtunes等)" 'posted with'
check "商品紹介リスト (アーチスト等)" '^\*   (アーチスト|著者|作者|出版社|レーベル|価格|発売日): '

# 未正規化のAmazonリンク: `https://www.amazon.co.jp/dp/ASIN` 形式以外の amazon.co.jp URL を持つファイルを数える
# (リンクの href 部分 `](...)` のみを対象にする。リンクテキストに amazon.co.jp の文字列が
#  残っていても href が正規化済みなら対象外とする — テキストは意図的に変更していないため)
unnorm_count=0
unnorm_files=()
for f in content/posts/**/index.md(N); do
  total=$(grep -oE '\]\([^ )]*amazon\.co\.jp[^ )]*' "$f" 2>/dev/null | wc -l | tr -d ' ')
  (( total == 0 )) && continue
  normalized=$(grep -oE '\]\(https://www\.amazon\.co\.jp/dp/[A-Za-z0-9]{10}\)' "$f" 2>/dev/null | wc -l | tr -d ' ')
  if (( total != normalized )); then
    ((unnorm_count++))
    unnorm_files+=("$f")
  fi
done
printf '%-45s %5d\n' "未正規化のAmazonリンク" "$unnorm_count"
if (( verbose && unnorm_count > 0 )); then
  for f in "${unnorm_files[@]}"; do echo "    $f"; done
fi

echo "=== 画像ファイル整合性 ==="
broken=0; orphan=0
for f in content/posts/**/index.md(N); do
  d=${f:h}
  # 本文が参照するローカル画像で実ファイルがないもの
  grep -oE '!\[[^]]*\]\([^)h][^)]*\)' "$f" 2>/dev/null | sed -E 's/.*\(([^)]*)\).*/\1/' | while read -r img; do
    [[ -f "$d/$img" ]] || { ((broken++)); (( verbose )) && echo "    broken: $f -> $img"; }
  done
done
for img in content/posts/*/*/^index.md(N.); do
  grep -qF "${img:t}" "${img:h}/index.md" || { ((orphan++)); (( verbose )) && echo "    orphan: $img"; }
done
printf '%-45s %5d\n' "参照切れローカル画像" "$broken"
printf '%-45s %5d\n' "未参照の孤児ファイル" "$orphan"

# 画像拡張子なのに実体が画像でないファイル（マジックバイト検査）。
# ダウンロード失敗の残骸("bad request"テキストやHTMLエラーページ)の検出用。
# 判定ロジックは scripts/cover_migrator.rb の real_image? と同じ。
fake=0
for img in content/posts/*/*/*.(jpg|jpeg|png|gif|webp)(N.); do
  sig=$(xxd -p -l 12 "$img")
  case $sig in
    ffd8ff*) ;;                       # JPEG
    89504e47*) ;;                     # PNG
    47494638*) ;;                     # GIF
    52494646????????57454250) ;;     # WebP (RIFF....WEBP)
    *) ((fake++)); (( verbose )) && echo "    not-image: $img" ;;
  esac
done
printf '%-45s %5d\n' "実体が画像でない画像ファイル" "$fake"
