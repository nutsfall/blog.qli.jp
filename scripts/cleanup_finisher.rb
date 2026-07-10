#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: UTF-8

# MIGRATION.md Phase 6 の細かい残骸整理。
#
#   --escape            (A) Medium export のエスケープ残骸 \_ \* を除去
#   --escape-brackets   (A') 同上、\[ \] を除去（HTML差分検証で個別に安全性確認するため分離）
#   --headings          (B) 記事内の最上位見出しを ## に揃え、階層を相対的に繰り上げ
#
# フロントマターとフェンスコードブロック（```）内は対象外。
#
# Usage:
#   ruby scripts/cleanup_finisher.rb --escape [--dry-run]
#   ruby scripts/cleanup_finisher.rb --escape-brackets [--dry-run]
#   ruby scripts/cleanup_finisher.rb --headings [--dry-run]

require 'find'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

DRY_RUN = ARGV.include?('--dry-run')
MODE_ESCAPE = ARGV.include?('--escape')
MODE_ESCAPE_BRACKETS = ARGV.include?('--escape-brackets')
MODE_HEADINGS = ARGV.include?('--headings')

unless MODE_ESCAPE || MODE_ESCAPE_BRACKETS || MODE_HEADINGS
  warn 'Usage: cleanup_finisher.rb (--escape|--escape-brackets|--headings) [--dry-run]'
  exit 1
end

POSTS_DIR = File.expand_path('../content/posts', __dir__)

# frontmatter (--- ... ---) とコードブロック(```...```)本体を除いた
# 「本文の地の文」の行インデックスだけを true にした配列を返す。
def body_line_flags(lines)
  flags = Array.new(lines.size, false)
  in_frontmatter = false
  frontmatter_done = false
  in_code = false

  lines.each_with_index do |line, i|
    if !frontmatter_done && line.strip == '---'
      if !in_frontmatter && i.zero?
        in_frontmatter = true
        next
      elsif in_frontmatter
        in_frontmatter = false
        frontmatter_done = true
        next
      end
    end
    next if in_frontmatter

    if line.lstrip.start_with?('```')
      in_code = !in_code
      next
    end
    next if in_code

    flags[i] = true
  end

  flags
end

def process_escape(path, chars)
  content = File.read(path)
  lines = content.split("\n", -1)
  flags = body_line_flags(lines)
  char_re = Regexp.union(chars) # chars: array of single-char strings

  changed = false
  new_lines = lines.each_with_index.map do |line, i|
    unless flags[i]
      next line
    end

    # インラインコード `...` の中は対象外
    segments = line.split(/(`[^`]*`)/)
    new_segments = segments.map do |seg|
      if seg.start_with?('`') && seg.end_with?('`') && seg.length >= 2
        seg
      else
        replaced = seg.gsub(/\\(#{char_re})/) { Regexp.last_match(1) }
        changed ||= (replaced != seg)
        replaced
      end
    end
    new_segments.join
  end

  return false unless changed

  new_content = new_lines.join("\n")
  File.write(path, new_content) unless DRY_RUN
  true
end

def process_headings(path)
  content = File.read(path)
  lines = content.split("\n", -1)
  flags = body_line_flags(lines)

  heading_idx = []
  min_level = nil

  lines.each_with_index do |line, i|
    next unless flags[i]

    if line =~ /^(\#{1,6})\s/
      level = Regexp.last_match(1).length
      heading_idx << [i, level]
      min_level = level if min_level.nil? || level < min_level
    end
  end

  return false if heading_idx.empty?
  return false if min_level == 2 # すでに ## 始まり

  shift = min_level - 2 # 繰り上げ量
  return false if shift <= 0

  heading_idx.each do |i, level|
    new_level = level - shift
    new_level = 1 if new_level < 1
    lines[i] = lines[i].sub(/^\#{1,6}/, '#' * new_level)
  end

  new_content = lines.join("\n")
  File.write(path, new_content) unless DRY_RUN
  true
end

files = Dir.glob(File.join(POSTS_DIR, '**', 'index.md')).sort

changed_files = []
files.each do |f|
  # draft記事は対象外
  next if File.read(f, encoding: 'UTF-8').lines.first(10).any? { |l| l.strip == 'draft: true' }

  changed =
    if MODE_ESCAPE
      process_escape(f, %w[_ *])
    elsif MODE_ESCAPE_BRACKETS
      process_escape(f, %w[[ ]])
    elsif MODE_HEADINGS
      process_headings(f)
    end
  changed_files << f if changed
end

label = MODE_ESCAPE ? 'escape' : (MODE_ESCAPE_BRACKETS ? 'escape-brackets' : 'headings')
puts "[#{label}]#{DRY_RUN ? ' (dry-run)' : ''} changed #{changed_files.size} files"
changed_files.each { |f| puts "  #{f.sub(POSTS_DIR + '/', '')}" }
