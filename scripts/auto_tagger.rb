#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude Codeセッション内で使う2段構成のタグ付けツール（LLM呼び出しは行わない）:
#   1. --extract: 対象記事のtitle/excerptとタグ付けルールをJSONで出力
#      → セッション内のClaudeがルールに従いタグを生成し、tags.jsonを作る
#   2. --apply:   tags.json ([{"path": "...", "tags": ["a", "b"]}]) をfrontmatterに書き込む
#
# Usage:
#   auto_tagger.rb --extract file1 [file2 ...]
#   auto_tagger.rb --apply tags.json [--dry-run]

require 'pathname'
require 'yaml'
require 'json'
require 'optparse'

POSTS_DIR = Pathname.new(__dir__).parent / 'content' / 'posts'

TAG_RULES = <<~RULES.strip
  - Tags must be in English, lowercase (use hyphens for multi-word: j-league, apple-music)
  - 1-3 tags (1 is fine for short posts)
  - Prefer specific terms over generic ones (avoid "diary", "misc", "thoughts", "life")
  - Use proper nouns for products, artists, teams, works (apple, netflix, avispa-fukuoka)
  - Prefer tags already used on this blog when appropriate
RULES

class AutoTagger
  def extract(targets)
    posts = targets.filter_map { |t|
      path = Pathname.new(t).expand_path
      data = read_post(path)
      next unless data

      { path: path.to_s, title: data[:title], excerpt: data[:excerpt] }
    }

    puts JSON.pretty_generate({ rules: TAG_RULES.lines.map(&:strip), posts: posts })
  end

  def apply(json_path, dry_run:)
    entries = JSON.parse(File.read(json_path, encoding: 'utf-8'))
    applied = 0
    failed  = 0

    entries.each do |entry|
      path = Pathname.new(entry['path']).expand_path
      tags = Array(entry['tags']).map(&:to_s).map(&:strip).reject(&:empty?).first(3)

      data = read_post(path)
      if data.nil? || tags.empty?
        failed += 1
        $stderr.puts "ERROR #{path}: #{data.nil? ? '読み込み失敗またはdraft' : 'タグが空'}"
        next
      end

      write_tags(path, data, tags) unless dry_run
      puts "#{path.relative_path_from(POSTS_DIR)} → #{tags.join(', ')}"
      applied += 1
    end

    puts "---"
    puts "完了: #{applied}件適用#{' (DRY RUN)' if dry_run}, #{failed}件エラー"
  end

  private

  def read_post(path)
    content = File.read(path, encoding: 'utf-8')
    return nil unless content.match?(/\A---\s*\n/)

    content =~ /\A(---\s*\n)(.*?)(\n---\s*\n)(.*)\z/m
    fm_open, fm_body, fm_close, body_text = $1, $2, $3, $4
    return nil unless fm_open

    fm = YAML.safe_load(fm_body, permitted_classes: [Date, Time]) || {}
    return nil if fm['draft']

    title   = fm['title'].to_s.strip
    excerpt = body_text.to_s.gsub(/!\[.*?\]\(.*?\)/, '').gsub(/[#*`>\[\]]/, '').strip[0, 800]

    { title: title, excerpt: excerpt,
      fm_open: fm_open, fm_body: fm_body, fm_close: fm_close, body_text: body_text }
  rescue Psych::Exception, Errno::ENOENT
    nil
  end

  def write_tags(path, data, tags)
    tags_line = "tags: [#{tags.map { |t| "\"#{t}\"" }.join(', ')}]"
    fm_body   = data[:fm_body]

    new_fm_body = if fm_body =~ /^tags:/
      fm_body.sub(/^tags:.*$/, tags_line)
    elsif fm_body =~ /^slug:/
      fm_body.sub(/^(slug:.*)$/, "#{tags_line}\n\\1")
    else
      "#{fm_body}\n#{tags_line}"
    end

    File.write(path, "#{data[:fm_open]}#{new_fm_body}#{data[:fm_close]}#{data[:body_text]}", encoding: 'utf-8')
  end
end

# --- CLI ---

mode    = nil
dry_run = false

parser = OptionParser.new do |opts|
  opts.banner = "Usage: auto_tagger.rb --extract file1 [file2 ...]\n       auto_tagger.rb --apply tags.json [--dry-run]"
  opts.on('--extract', '対象記事の情報をJSONで出力') { mode = :extract }
  opts.on('--apply', 'tags.jsonのタグをfrontmatterに適用') { mode = :apply }
  opts.on('--dry-run', '書き込まずにプレビュー') { dry_run = true }
end
parser.parse!

case mode
when :extract
  abort parser.banner if ARGV.empty?
  AutoTagger.new.extract(ARGV)
when :apply
  abort parser.banner unless ARGV.size == 1
  AutoTagger.new.apply(ARGV[0], dry_run: dry_run)
else
  abort parser.banner
end
