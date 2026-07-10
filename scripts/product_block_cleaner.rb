#!/usr/bin/env ruby
# frozen_string_literal: true

# content/posts/**/index.md 本文中の、
#   (A) Amazonアフィリエイトリンクの正規化
#   (B) 消滅済みサービス(Socialtunes)由来の商品紹介定型ブロックの簡素化
# を一括で行う。
#
# (A) Amazonリンク正規化
#   さまざまな形式の Amazon 商品リンクから ASIN を抽出し、
#   `https://www.amazon.co.jp/dp/ASIN` に統一する。リンクテキストは変更せず、
#   title 属性は削除する。ASIN が抽出できないリンク(検索URL等)はそのまま残す。
#
#   観測された形式:
#     - .../exec/obidos/ASIN/{ASIN}/{tag}/ref=nosim
#     - .../gp/product/{ASIN}?... / .../ebook/dp/{ASIN}/ / .../dp/{ASIN}...
#     - .../gp/redirect.html%3FASIN={ASIN}%26... (URLエンコード)
#     - .../exec/obidos/redirect?...&path=.../gp/redirect.html%253fASIN={ASIN}%2526...
#       (二重URLエンコード)
#     - rcm-jp.amazon.co.jp/e/cm?...&asins={ASIN} (広告ウィジェット埋め込みリンク)
#
# (B) 商品紹介定型ブロックの簡素化
#   "posted with [Socialtunes](...)" 行の直前(空行を挟んでもよい)に連続する、
#   既知ラベルの箇条書き行(アーチスト/レーベル/価格/発売日/発売元/メーカー/
#   スタジオ/売上ランキング/おすすめ度 等、`*` または `-` マーカー)を、
#   商品名リンク行を残したまま削除する。
#
#   安全策:
#     - 削除対象は "posted with" 行に直接連続する箇条書きブロックのみ
#       (事前調査により、リポジトリ内の該当ラベル箇条書きは全て posted-with
#        ブロックに属することを確認済み。それ以外の場所にある同名ラベルや
#        箇条書き文脈(例: 音楽リストの "*   [曲名](url)" + "*   :: アーティスト名")
#        には一切触れない)
#     - ブロック内に未知のラベル(箇条書きだが既知ラベルでない行)が混在する場合は
#       そのブロックの削除をスキップして報告する
#
# Usage:
#   /opt/homebrew/opt/ruby/bin/ruby scripts/product_block_cleaner.rb --dry-run [--diff-out=PATH]
#   /opt/homebrew/opt/ruby/bin/ruby scripts/product_block_cleaner.rb

require 'pathname'
require 'cgi'

POSTS_DIR = Pathname.new(__dir__).parent / 'content' / 'posts'

DRY_RUN = ARGV.include?('--dry-run')
diff_out_arg = ARGV.find { |a| a.start_with?('--diff-out=') }
DIFF_OUT = diff_out_arg ? diff_out_arg.split('=', 2)[1] : nil

# ============================================================
# (A) Amazonリンク正規化
# ============================================================

# タイトル属性 "..." の中には ")" (例: "風のクロマ (初回限定盤)") が含まれることがあるため、
# URL部分とタイトル部分("..."で囲まれる)を分けて構造的にマッチする。
# URL部分は ")" を含まない前提(実データで確認済み)とし、リンクの外側にある
# 直後の丸括弧(例: "...pv)(9月スタート)")まで貪欲にマッチしないようにする。
# リンクテキスト部分には "\[雑誌\]" のようにエスケープされた "]" が含まれることがあるため、
# `\.` (エスケープされた1文字) を優先的に許容し、真の閉じ括弧で正しく止まるようにする。
AMAZON_LINK_RE = /\[((?:\\.|[^\]\\])*)\]\(([^\s)]*amazon\.co\.jp[^\s)]*)(?:[ \t]+"([^"]*)")?\)/.freeze
ASIN_CHARS = 'A-Za-z0-9'
ASIN_EXTRACT_PATTERNS = [
  %r{/dp/([#{ASIN_CHARS}]{10})(?=[/?%&]|\z)},
  %r{/ASIN/([#{ASIN_CHARS}]{10})(?=[/?%&]|\z)},
  %r{/gp/product/([#{ASIN_CHARS}]{10})(?=[/?%&]|\z)},
  /[?&]asins?=([#{ASIN_CHARS}]{10})(?![#{ASIN_CHARS}])/i
].freeze

# %XX エンコードを変化しなくなるまで(最大5回)デコードする。
# 二重URLエンコードされたリダイレクトURL (exec/obidos/redirect 等) に対応するため。
def fully_decode(str)
  decoded = str
  5.times do
    next_decoded = CGI.unescape(decoded)
    break if next_decoded == decoded

    decoded = next_decoded
  end
  decoded
end

def extract_asin(url)
  decoded = fully_decode(url)
  ASIN_EXTRACT_PATTERNS.each do |re|
    m = re.match(decoded)
    return m[1] if m
  end
  nil
end

def normalize_amazon_links(content, file, report)
  changed = false

  new_content = content.gsub(AMAZON_LINK_RE) do
    full_match = Regexp.last_match(0)
    text = Regexp.last_match(1)
    url = Regexp.last_match(2)

    asin = extract_asin(url)

    unless asin
      report[:amazon_skips] << "#{file}: #{url}"
      next full_match
    end

    changed = true
    report[:amazon_converted] += 1
    new_url = "https://www.amazon.co.jp/dp/#{asin}"
    report[:amazon_diffs] << [full_match, "[#{text}](#{new_url})"] if report[:amazon_diffs].length < 60
    "[#{text}](#{new_url})"
  end

  changed ? new_content : content
end

# ============================================================
# (B) 商品紹介定型ブロックの簡素化 (Socialtunes)
# ============================================================

POSTED_WITH_RE = /\Aposted with \[Socialtunes\]\([^)]*\)(?:[ \t]+at[ \t]+\d{4}\/\d{2}\/\d{2})?[ \t]*\z/.freeze
KNOWN_LABELS = %w[
  アーチスト アーティスト 著者 作者 出版社 レーベル 価格 発売日 発売元
  メーカー 売上ランキング スタジオ
].freeze
LABEL_BULLET_RE = /\A[*-][ \t]+(#{KNOWN_LABELS.join('|')})[：:]/.freeze
OSUSUME_BULLET_RE = /\A[*-][ \t]+おすすめ度[ \t]*\z/.freeze
ANY_BULLET_RE = /\A[*-][ \t]+/.freeze

def known_label_bullet?(line)
  LABEL_BULLET_RE.match?(line) || OSUSUME_BULLET_RE.match?(line)
end

def simplify_product_blocks(content, file, report)
  lines = content.split("\n", -1)
  posted_indices = []
  lines.each_with_index { |line, i| posted_indices << i if POSTED_WITH_RE.match?(line) }
  return content if posted_indices.empty?

  ranges_to_delete = []

  posted_indices.each do |i|
    j = i - 1
    j -= 1 while j >= 0 && lines[j].strip.empty?

    k = j
    while k >= 0 && ANY_BULLET_RE.match?(lines[k])
      k -= 1
    end

    bullet_lines = lines[(k + 1)..j] || []

    if bullet_lines.empty?
      report[:block_skips] << "#{file}:#{i + 1}: posted-with行の直前に箇条書きが見つからない"
      next
    end

    unless bullet_lines.all? { |b| known_label_bullet?(b) }
      report[:block_skips] << "#{file}:#{i + 1}: 未知のラベルが混在 -> #{bullet_lines.map(&:strip).inspect}"
      next
    end

    # 箇条書きブロックの直前の空行(商品リンク行との区切り)も削除範囲に含める
    start = k + 1
    if k >= 0 && lines[k].strip.empty?
      start = k
    end

    ranges_to_delete << (start..i)
    report[:block_removed] += 1
  end

  return content if ranges_to_delete.empty?

  # 末尾側から削除すると添字がずれない
  ranges_to_delete.sort_by(&:first).reverse_each do |range|
    lines.slice!(range)
  end

  # 削除の結果生じた3行以上連続の空行を1行の空行に畳む(直接の後始末のみ、他箇所は変更しない)
  new_content = lines.join("\n").gsub(/\n{3,}/, "\n\n")
  new_content
end

# ============================================================
# メイン処理
# ============================================================

def process_file(path, report)
  original = File.read(path, encoding: 'UTF-8')

  content = normalize_amazon_links(original, path, report)
  content = simplify_product_blocks(content, path, report)

  return if content == original

  report[:changed_files] << path
  File.write(path, content, encoding: 'UTF-8') unless DRY_RUN
end

def main
  report = {
    amazon_converted: 0,
    amazon_diffs: [],
    amazon_skips: [],
    block_removed: 0,
    block_skips: [],
    changed_files: []
  }

  files = Dir.glob(POSTS_DIR / '**' / 'index.md').sort
  originals = DRY_RUN ? files.each_with_object({}) { |f, h| h[f] = File.read(f, encoding: 'UTF-8') } : nil

  files.each { |f| process_file(f, report) }

  puts "=== #{DRY_RUN ? 'DRY RUN' : 'APPLY'} ==="
  puts "対象ファイル数: #{files.length}"
  puts "変更ファイル数: #{report[:changed_files].length}"
  puts
  puts "(A) Amazonリンク変換件数: #{report[:amazon_converted]}"
  puts "(A) ASIN抽出できずスキップ: #{report[:amazon_skips].length}"
  report[:amazon_skips].each { |s| puts "    skip: #{s}" }
  puts
  puts "(B) 定型ブロック削除件数: #{report[:block_removed]}"
  puts "(B) 変則ケースでスキップ: #{report[:block_skips].length}"
  report[:block_skips].each { |s| puts "    skip: #{s}" }

  if DRY_RUN && DIFF_OUT
    tmp_old = "#{DIFF_OUT}.old.tmp"
    tmp_new = "#{DIFF_OUT}.new.tmp"
    File.open(DIFF_OUT, 'w:UTF-8') do |out|
      report[:changed_files].each do |f|
        # process_file は dry-run でも書き込みしないので、実ファイルは元のまま。
        # ここでは変換後の内容を再計算して比較する。
        old_content = originals[f]
        recomputed = normalize_amazon_links(old_content, f, { amazon_converted: 0, amazon_diffs: [], amazon_skips: [] })
        recomputed = simplify_product_blocks(recomputed, f, { block_removed: 0, block_skips: [] })
        out.puts "=== #{f} ==="
        File.write(tmp_old, old_content, encoding: 'UTF-8')
        File.write(tmp_new, recomputed, encoding: 'UTF-8')
        diff_text = `diff -u #{tmp_old} #{tmp_new}`
        diff_text.force_encoding('UTF-8')
        out.puts diff_text
        out.puts
      end
    end
    File.delete(tmp_old) if File.exist?(tmp_old)
    File.delete(tmp_new) if File.exist?(tmp_new)
    puts
    puts "diff出力: #{DIFF_OUT}"
  end
end

main if __FILE__ == $PROGRAM_NAME
