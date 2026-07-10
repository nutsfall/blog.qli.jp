#!/usr/bin/env ruby
# frozen_string_literal: true

# content/posts/**/index.md のフロントマターを正規化する。
#   1. 空フィールドの行を削除: categories: [] / keywords: [] / description（空文字）
#   2. draft: false の行を削除（Hugoのデフォルトのため冗長。draft: true は残す）
#   3. シングルクォート値をダブルクォートに統一（date / title / description）
#   4. 日付の値そのもの・キー順序は変更しない
#
# 安全策:
#   - フロントマター（先頭の "---" 〜 "---"）だけを書き換え、本文はバイト単位で不変であることをアサート
#   - 変更前後のフロントマターをYAMLとしてパースし、削除対象キーを除いて意味的に同一であることをアサート
#   - 1件でも不一致があれば例外を出して異常終了する
#
# Usage:
#   /opt/homebrew/opt/ruby/bin/ruby scripts/frontmatter_normalizer.rb --dry-run
#   /opt/homebrew/opt/ruby/bin/ruby scripts/frontmatter_normalizer.rb

require 'pathname'
require 'yaml'
require 'optparse'

POSTS_DIR = Pathname.new(__dir__).parent / 'content' / 'posts'

# フロントマター全体: 先頭 "---\n" 〜 "\n---\n" (本文は残り全部、バイト単位で温存する)
FRONTMATTER_RE = /\A(---\n)(.*?)(\n---\n)(.*)\z/m

# トップレベルキー行 (行頭に空白なし): "title:" "cover:" など
TOP_KEY_RE = /\A([A-Za-z_][A-Za-z0-9_]*):/

# 変換対象キー: シングルクォート値をダブルクォートへ変換する候補
QUOTE_CONVERT_KEYS = %w[date title description].freeze

class NormalizationError < StandardError; end

class FrontmatterBlock
  attr_reader :key, :lines

  def initialize(key, lines)
    @key = key
    @lines = lines # 生の行の配列（改行なし、元の順序のまま）
  end

  def raw
    lines.join("\n")
  end
end

class FrontmatterNormalizer
  def initialize(dry_run:)
    @dry_run = dry_run
    @stats = Hash.new(0)
    @changed_files = []
    @skipped = []
  end

  def run
    files = POSTS_DIR.glob('**/index.md').sort
    puts "対象: #{files.size}件 #{'(DRY RUN)' if @dry_run}"
    puts '---'

    files.each { |f| process(f) }

    puts '---'
    report
  end

  private

  def process(path)
    content = File.read(path, encoding: 'utf-8')

    unless content =~ FRONTMATTER_RE
      @skipped << [path, 'フロントマター形式が想定と不一致（正規表現マッチ失敗）']
      return
    end

    fm_open, fm_body, fm_close, body = $1, $2, $3, $4

    old_hash = YAML.safe_load(fm_body, permitted_classes: [], aliases: false)
    raise NormalizationError, 'フロントマターがHashでない' unless old_hash.is_a?(Hash)

    blocks = split_blocks(fm_body)

    deleted_keys = []
    new_blocks = []

    blocks.each do |blk|
      case blk.key
      when 'categories'
        if old_hash['categories'] == []
          deleted_keys << 'categories'
          @stats[:removed_categories] += 1
          next
        end
      when 'keywords'
        if old_hash['keywords'] == []
          deleted_keys << 'keywords'
          @stats[:removed_keywords] += 1
          next
        end
      when 'description'
        v = old_hash['description']
        if v.nil? || v == ''
          deleted_keys << 'description'
          @stats[:removed_description] += 1
          next
        end
      when 'draft'
        if old_hash['draft'] == false
          deleted_keys << 'draft'
          @stats[:removed_draft_false] += 1
          next
        end
      end

      new_blocks << maybe_convert_quote(blk, old_hash)
    end

    new_fm_body = new_blocks.map(&:raw).join("\n")

    return if new_fm_body == fm_body # 変更なし

    new_content = "#{fm_open}#{new_fm_body}#{fm_close}#{body}"

    verify!(path, content, new_content, old_hash, deleted_keys, body)

    File.write(path, new_content, encoding: 'utf-8') unless @dry_run
    @changed_files << path
    @stats[:files_changed] += 1
  rescue NormalizationError => e
    @skipped << [path, e.message]
  rescue Psych::SyntaxError => e
    @skipped << [path, "YAML parse error: #{e.message}"]
  end

  # フロントマター本文をトップレベルキーごとのブロックに分割する。
  # インデントされた行（cover: の子要素や折り返し継続行）は直前のブロックに属する。
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
        raise NormalizationError, "想定外の行（トップレベルキーなしで開始）: #{line.inspect}" if current_key.nil?

        current_lines << line
      end
    end
    blocks << FrontmatterBlock.new(current_key, current_lines) if current_key
    blocks
  end

  def maybe_convert_quote(blk, old_hash)
    return blk unless QUOTE_CONVERT_KEYS.include?(blk.key)

    first_line = blk.lines.first
    # "key: '..." の形（シングルクォート開始）のみ変換対象
    return blk unless first_line =~ /\A#{Regexp.escape(blk.key)}: '/

    value = old_hash[blk.key]
    raise NormalizationError, "#{blk.key}: シングルクォートだが値がString型でない (#{value.class})" unless value.is_a?(String)

    new_line = "#{blk.key}: #{yaml_double_quote(value)}"
    @stats[:"quote_converted_#{blk.key}"] += 1
    FrontmatterBlock.new(blk.key, [new_line])
  end

  def yaml_double_quote(str)
    out = +'"'
    str.each_char do |c|
      case c
      when '\\' then out << '\\\\'
      when '"' then out << '\\"'
      when "\n" then out << '\\n'
      when "\t" then out << '\\t'
      else out << c
      end
    end
    out << '"'
    out
  end

  def verify!(path, old_content, new_content, old_hash, deleted_keys, expected_body)
    unless new_content =~ FRONTMATTER_RE
      raise NormalizationError, '書き換え後の内容がフロントマター形式にマッチしない'
    end

    new_fm_open, new_fm_body, new_fm_close, new_body = $1, $2, $3, $4

    # 本文はバイト単位で不変
    unless new_body == expected_body
      raise NormalizationError, '本文がバイト単位で変化している'
    end

    new_hash = YAML.safe_load(new_fm_body, permitted_classes: [], aliases: false)
    raise NormalizationError, '書き換え後のフロントマターがHashでない' unless new_hash.is_a?(Hash)

    expected_hash = old_hash.reject { |k, _| deleted_keys.include?(k) }

    unless new_hash == expected_hash
      diff_keys = (expected_hash.keys | new_hash.keys).select { |k| expected_hash[k] != new_hash[k] }
      raise NormalizationError, "意味的な差分を検出: #{diff_keys.map { |k| "#{k.inspect}: #{expected_hash[k].inspect} -> #{new_hash[k].inspect}" }.join(', ')}"
    end

    # 日付の値そのものは不変であること（キーが残っている場合）
    if old_hash.key?('date') && new_hash.key?('date') && old_hash['date'] != new_hash['date']
      raise NormalizationError, "date の値が変化している: #{old_hash['date'].inspect} -> #{new_hash['date'].inspect}"
    end
  end

  def report
    puts "処理ファイル数: #{@stats[:files_changed]} / #{POSTS_DIR.glob('**/index.md').size}"
    puts "  categories: [] 削除: #{@stats[:removed_categories]}"
    puts "  keywords: [] 削除: #{@stats[:removed_keywords]}"
    puts "  description (空) 削除: #{@stats[:removed_description]}"
    puts "  draft: false 削除: #{@stats[:removed_draft_false]}"
    puts "  date クォート変換: #{@stats[:quote_converted_date]}"
    puts "  title クォート変換: #{@stats[:quote_converted_title]}"
    puts "  description クォート変換: #{@stats[:quote_converted_description]}"

    if @skipped.any?
      puts '---'
      puts "スキップ/エラー: #{@skipped.size}件"
      @skipped.each { |path, reason| puts "  #{path}: #{reason}" }
    end
  end
end

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = 'Usage: frontmatter_normalizer.rb [--dry-run]'
  opts.on('--dry-run', 'プレビューのみ（書き込みしない）') { options[:dry_run] = true }
end.parse!

normalizer = FrontmatterNormalizer.new(dry_run: options[:dry_run])
normalizer.run

exit(normalizer.instance_variable_get(:@skipped).any? ? 1 : 0)
