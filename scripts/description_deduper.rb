#!/usr/bin/env ruby
# frozen_string_literal: true

# content/posts/**/index.md のフロントマター description が、本文冒頭の段落と
# 実質重複している（Mediumのsubtitle由来）場合に description を削除する。
#
# 削除条件（いずれか）:
#   a. 正規化した description が本文冒頭段落と一致
#   b. 正規化した description（末尾の省略記号・句読点を除いたもの）が本文冒頭段落の前方一致
#   c. 正規化した description が本文の最初の見出しテキストと完全一致
#
# 正規化: Markdown記法（画像・リンク・強調・エスケープ残骸のバックスラッシュ）を除去し、
# 全ての空白文字（半角/全角スペース・タブ・改行）を除去する。
# 比較時は末尾の省略記号（…/...）と句読点の差を無視する。
# （本文側は過去のコミット 9d028f9c で数字・英字まわりに半角スペースが挿入されているが
#   description は未加工のため、空白を全除去しないと一致しないケースが多い）
#
# 上記に該当しないが類似度が高いものは削除せず「要判断」として一覧出力する。
# 明らかに独自の要約（本文と別の文章）は変更しない。
#
# 安全策:
#   - フロントマター（先頭の "---" 〜 "---"）だけを書き換え、本文はバイト単位で不変であることをアサート
#   - 変更前後のフロントマターをYAMLとしてパースし、description を除いて意味的に同一であることをアサート
#
# Usage:
#   /opt/homebrew/opt/ruby/bin/ruby scripts/description_deduper.rb --dry-run
#   /opt/homebrew/opt/ruby/bin/ruby scripts/description_deduper.rb

require 'pathname'
require 'yaml'
require 'optparse'

Encoding.default_external = Encoding::UTF_8
$stdout.set_encoding('UTF-8')

POSTS_DIR = Pathname.new(__dir__).parent / 'content' / 'posts'

FRONTMATTER_RE = /\A(---\n)(.*?)(\n---\n)(.*)\z/m
TOP_KEY_RE = /\A([A-Za-z_][A-Za-z0-9_]*):/

IMAGE_RE = /!\[[^\]]*\]\([^)]*\)/.freeze
LINK_RE = /\[([^\]]*)\]\([^)]*\)/.freeze
EMPHASIS_CHARS_RE = /[*_`\\]/.freeze
WHITESPACE_RE = /[ \t\n\r　]+/.freeze
ELLIPSIS_RE = /(…|\.\.\.)+\z/.freeze
TRAILING_PUNCT_RE = /[。、．，.,!?！？]+\z/.freeze

SIMILARITY_THRESHOLD = 0.5

class DeduperError < StandardError; end

class FrontmatterBlock
  attr_reader :key, :lines

  def initialize(key, lines)
    @key = key
    @lines = lines
  end

  def raw
    lines.join("\n")
  end
end

# ---- テキスト正規化 -------------------------------------------------------

def normalize_text(text)
  return '' if text.nil?

  t = text.dup
  t = t.gsub(IMAGE_RE, '')
  t = t.gsub(LINK_RE) { Regexp.last_match(1) }
  t = t.gsub(EMPHASIS_CHARS_RE, '')
  t.gsub(WHITESPACE_RE, '')
end

# 比較用コア: 末尾の省略記号（…/...）と句読点を取り除いたもの
def comparison_core(text)
  text.sub(ELLIPSIS_RE, '').sub(TRAILING_PUNCT_RE, '')
end

# 標準的なレーベンシュタイン距離（2行DP）
def levenshtein(a, b)
  return b.length if a.empty?
  return a.length if b.empty?

  prev = (0..b.length).to_a
  a.each_char.with_index do |ca, i|
    cur = [i + 1]
    b.each_char.with_index do |cb, j|
      cost = ca == cb ? 0 : 1
      cur << [prev[j + 1] + 1, cur[j] + 1, prev[j] + cost].min
    end
    prev = cur
  end
  prev.last
end

def similarity(a, b)
  return 1.0 if a == b
  return 0.0 if a.empty? || b.empty?

  1.0 - (levenshtein(a, b).to_f / [a.length, b.length].max)
end

# 本文冒頭の最初のテキスト段落を取り出す
# （先頭の空行・画像のみの行・見出し行はスキップしてから最初の段落を探す。
#   見出し直下にタイトルの繰り返しではなく実質的な導入文が来るMedium由来の記事が多いため）
def first_paragraph(body)
  lines = body.lines(chomp: true)
  i = 0

  loop do
    break if i >= lines.size

    stripped = lines[i].strip
    if stripped.empty?
      i += 1
    elsif stripped =~ /\A(!\[[^\]]*\]\([^)]*\)\s*)+\z/
      i += 1
    elsif stripped.start_with?('#')
      i += 1
    else
      break
    end
  end

  return nil if i >= lines.size

  para_lines = []
  while i < lines.size && !lines[i].strip.empty?
    para_lines << lines[i]
    i += 1
  end
  para_lines.join(' ')
end

# 本文の最初のテキスト段落より前にある最初の見出しのテキストを返す（なければnil）
# Medium由来の記事でsubtitleが本文冒頭の見出しになっているケースの検出用
def first_heading(body)
  body.lines(chomp: true).each do |line|
    stripped = line.strip
    next if stripped.empty?
    next if stripped =~ /\A(!\[[^\]]*\]\([^)]*\)\s*)+\z/
    return stripped.sub(/\A#+\s*/, '') if stripped.start_with?('#')

    return nil # 見出しより先にテキスト段落が来た
  end
  nil
end

# ---- 本体 ------------------------------------------------------------------

class DescriptionDeduper
  def initialize(dry_run:)
    @dry_run = dry_run
    @to_delete = []   # [path, reason, description, paragraph]
    @to_review = []   # [path, reason, description, paragraph, score]
    @kept = 0
    @no_paragraph = []
    @skipped = []
  end

  def run
    files = POSTS_DIR.glob('**/index.md').sort
    targets = files.select { |f| File.read(f, encoding: 'utf-8') =~ /^description:/ }
    puts "description あり: #{targets.size}件 #{'(DRY RUN)' if @dry_run}"
    puts '---'

    targets.each { |f| process(f) }

    report
  end

  private

  def process(path)
    content = File.read(path, encoding: 'utf-8')

    unless content =~ FRONTMATTER_RE
      @skipped << [path, 'フロントマター形式が想定と不一致']
      return
    end

    fm_open, fm_body, fm_close, body = $1, $2, $3, $4

    old_hash = YAML.safe_load(fm_body, permitted_classes: [], aliases: false)
    raise DeduperError, 'フロントマターがHashでない' unless old_hash.is_a?(Hash)

    description = old_hash['description']
    return if description.nil? || description == ''

    desc_norm = normalize_text(description)
    desc_core = comparison_core(desc_norm)
    para_raw = first_paragraph(body)
    heading_raw = first_heading(body)

    # c. 最初の見出しテキストと完全一致
    if heading_raw && !desc_core.empty? &&
       desc_core == comparison_core(normalize_text(heading_raw))
      delete_description!(path, content, fm_open, fm_body, fm_close, body, old_hash,
                           reason: '本文の最初の見出しと完全一致')
      @to_delete << [path, '見出し一致', description, heading_raw]
      return
    end

    if para_raw.nil?
      @no_paragraph << [path, description]
      return
    end

    para_norm = normalize_text(para_raw)
    para_core = comparison_core(para_norm)

    # a. 本文冒頭段落と一致（末尾の省略記号・句読点の差は無視）
    if !desc_core.empty? && desc_core == para_core
      delete_description!(path, content, fm_open, fm_body, fm_close, body, old_hash,
                           reason: '本文冒頭段落と一致')
      @to_delete << [path, '一致', description, para_raw]
      return
    end

    # b. 前方一致（Mediumのsubtitle切り詰め。省略記号の有無は問わない）
    if !desc_core.empty? && para_norm.start_with?(desc_core)
      delete_description!(path, content, fm_open, fm_body, fm_close, body, old_hash,
                           reason: '本文冒頭段落の前方一致')
      @to_delete << [path, '前方一致', description, para_raw]
      return
    end

    score = similarity(desc_norm, para_norm)
    if score >= SIMILARITY_THRESHOLD
      @to_review << [path, description, para_raw, score]
    else
      @kept += 1
    end
  rescue DeduperError => e
    @skipped << [path, e.message]
  rescue Psych::SyntaxError => e
    @skipped << [path, "YAML parse error: #{e.message}"]
  end

  def delete_description!(path, content, fm_open, fm_body, fm_close, body, old_hash, reason:)
    blocks = split_blocks(fm_body)
    new_blocks = blocks.reject { |b| b.key == 'description' }
    raise DeduperError, "description ブロックが見つからない (#{reason})" if new_blocks.size == blocks.size

    new_fm_body = new_blocks.map(&:raw).join("\n")
    new_content = "#{fm_open}#{new_fm_body}#{fm_close}#{body}"

    verify!(path, new_content, old_hash, body)

    File.write(path, new_content, encoding: 'utf-8') unless @dry_run
  end

  def split_blocks(fm_body)
    blocks = []
    current_key = nil
    current_lines = []

    fm_body.each_line(chomp: true) do |line|
      if line =~ TOP_KEY_RE
        blocks << FrontmatterBlock.new(current_key, current_lines) if current_key
        current_key = $1
        current_lines = [line]
      else
        raise DeduperError, "想定外の行（トップレベルキーなしで開始）: #{line.inspect}" if current_key.nil?

        current_lines << line
      end
    end
    blocks << FrontmatterBlock.new(current_key, current_lines) if current_key
    blocks
  end

  def verify!(path, new_content, old_hash, expected_body)
    unless new_content =~ FRONTMATTER_RE
      raise DeduperError, '書き換え後の内容がフロントマター形式にマッチしない'
    end

    _new_fm_open, new_fm_body, _new_fm_close, new_body = $1, $2, $3, $4

    unless new_body == expected_body
      raise DeduperError, '本文がバイト単位で変化している'
    end

    new_hash = YAML.safe_load(new_fm_body, permitted_classes: [], aliases: false)
    raise DeduperError, '書き換え後のフロントマターがHashでない' unless new_hash.is_a?(Hash)

    expected_hash = old_hash.reject { |k, _| k == 'description' }

    return if new_hash == expected_hash

    diff_keys = (expected_hash.keys | new_hash.keys).select { |k| expected_hash[k] != new_hash[k] }
    raise DeduperError, "意味的な差分を検出: #{diff_keys.map { |k| "#{k.inspect}: #{expected_hash[k].inspect} -> #{new_hash[k].inspect}" }.join(', ')}"
  end

  def report
    puts "削除: #{@to_delete.size}件"
    puts "要判断（類似度 >= #{SIMILARITY_THRESHOLD}）: #{@to_review.size}件"
    puts "独自の要約として保持: #{@kept}件"
    puts "本文冒頭にテキスト段落が見つからない: #{@no_paragraph.size}件"
    puts "スキップ/エラー: #{@skipped.size}件"
    puts '---'

    puts '=== 削除対象 ==='
    @to_delete.each do |path, reason, desc, para|
      puts "[#{reason}] #{path}"
      puts "  description: #{desc.inspect}"
      puts "  本文冒頭:     #{para.inspect}"
    end

    puts '---'
    puts '=== 要判断 ==='
    @to_review.sort_by { |r| -r[3] }.each do |path, desc, para, score|
      puts "[similarity=#{score.round(3)}] #{path}"
      puts "  description: #{desc.inspect}"
      puts "  本文冒頭:     #{para.inspect}"
    end

    if @no_paragraph.any?
      puts '---'
      puts '=== テキスト段落なし（要確認） ==='
      @no_paragraph.each do |path, desc|
        puts "#{path}"
        puts "  description: #{desc.inspect}"
      end
    end

    if @skipped.any?
      puts '---'
      puts '=== スキップ/エラー ==='
      @skipped.each { |path, reason| puts "  #{path}: #{reason}" }
    end
  end
end

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = 'Usage: description_deduper.rb [--dry-run]'
  opts.on('--dry-run', 'プレビューのみ（書き込みしない）') { options[:dry_run] = true }
end.parse!

deduper = DescriptionDeduper.new(dry_run: options[:dry_run])
deduper.run
