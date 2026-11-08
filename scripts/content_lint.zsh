#!/bin/zsh
# content/posts 配下の移行残骸パターンを検出して件数を出力する。
# MIGRATION.md のフェーズ進捗確認用。修正前後で実行して差分を見る。
# 使い方: scripts/content_lint.zsh [-v]  (-v で該当ファイル一覧も出力)
#
# 記事単位モード: scripts/content_lint.zsh --post <記事ディレクトリ|index.md>...
#   新規インポート記事の整形（process_new_posts.rb ＋タグ付け）が完了したかを判定する。
#   問題のある記事ごとに内容を出力し、1件でもあれば exit 1。

setopt extendedglob

if [[ "$1" == "--post" ]]; then
  shift
  (( $# )) || { echo "usage: $0 --post <post dir|index.md>..." >&2; exit 2; }
  failed=0
  for arg in "$@"; do
    f=$arg
    [[ -d $f ]] && f=$f/index.md
    problems=()
    if [[ ! -f $f ]]; then
      echo "NG $arg"; echo "    index.md がない"; failed=1; continue
    fi
    d=${f:h}
    fm=$(awk 'NR==1 && /^---$/ {inf=1; next} inf && /^---$/ {exit} inf' "$f")
    body=$(awk 'c>=2 {print} /^---$/ && c<2 {c++}' "$f")

    grep -q '^draft: true' <<<"$fm" && problems+=("draft: true のまま")
    grep -qE '^tags: \[ *"|^tags:$' <<<"$fm" || problems+=("タグがない")

    # 本文先頭の見出しがタイトルと同じ（Mediumの重複タイトル）。比較は process_new_posts.rb と同じ正規化
    dup=$(perl -CSD -MUnicode::Normalize -e '
      local $/; my $t = <>;
      my ($fm, $body) = $t =~ /\A---\n(.*?)\n---\n(.*)\z/s or exit;
      my ($title) = $fm =~ /^title:\s*"?(.*?)"?\s*$/m;
      my ($h) = $body =~ /\A\s*#+[ \t]+([^\n]*)/ or exit;
      my $n = sub { my $s = NFC(shift); $s =~ s/\x{00A0}/ /g; $s =~ s/^\s+|\s+$//g; lc $s };
      print $h if $n->($h) eq $n->($title);
    ' "$f")
    [[ -n $dup ]] && problems+=("本文先頭にタイトルと同じ見出し: $dup")

    grep -qE '!\[[^]]*\]\(https?://|figure src="https?://' <<<"$body" && problems+=("リモート画像参照が残っている")
    grep -q 'cdn-images-1\.medium\.com' "$f" && problems+=("Medium画像URLが残っている")
    grep -q 'medium\.com/_/stat' <<<"$body" && problems+=("Medium計測ピクセルが残っている")
    grep -qF '![]()' <<<"$body" && problems+=("空画像 ![]()")

    # ローカル画像（本文・figure・cover）の実ファイル
    refs=(${(f)"$(
      { grep -oE '!\[[^]]*\]\([^)]+\)' <<<"$body" | sed -E 's/.*\(([^)]*)\).*/\1/'
        grep -oE 'figure src="[^"]+"' <<<"$body" | sed -E 's/.*src="([^"]*)"/\1/'
        grep -oE '^  image: "[^"]+"' <<<"$fm" | sed -E 's/.*"([^"]*)"/\1/'
      } | grep -vE '^https?://'
    )"})
    for img in ${refs:#}; do
      [[ -f "$d/$img" ]] || problems+=("参照切れ画像: $img")
    done

    for img in $d/^index.md(N.); do
      grep -qF "${img:t}" "$f" || problems+=("未参照ファイル: ${img:t}")
    done
    for img in $d/*.(jpg|jpeg|png|gif|webp)(N.); do
      case $(xxd -p -l 12 "$img") in
        ffd8ff*|89504e47*|47494638*|52494646????????57454250) ;;
        *) problems+=("実体が画像でない: ${img:t}") ;;
      esac
    done

    if (( ${#problems} )); then
      failed=1
      echo "NG $f"
      printf '    %s\n' "${problems[@]}"
    else
      echo "OK $f"
    fi
  done
  exit $failed
fi

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
