#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'yaml'
require 'json'
require 'optparse'
require 'open3'

POSTS_DIR = Pathname.new(__dir__).parent / 'content' / 'posts'

SYSTEM_PROMPT = <<~PROMPT.strip
  You are an assistant that tags Japanese blog posts.
  For each post provided (numbered [0], [1], etc.), generate 1-3 English tags.
  Return ONLY a JSON array in this exact format:
  [{"id": 0, "tags": ["tag1", "tag2"]}, {"id": 1, "tags": ["tag3"]}, ...]
  Rules:
  - Tags must be in English, lowercase (use hyphens for multi-word: j-league, apple-music)
  - 1-3 tags (1 is fine for short posts)
  - Prefer specific terms over generic ones (avoid "diary", "misc", "thoughts", "life")
  - Use proper nouns for products, artists, teams, works (apple, netflix, avispa-fukuoka)
PROMPT

class AutoTagger
  def initialize(dry_run:, targets:)
    @dry_run   = dry_run
    @targets   = targets
    @processed = []
    @failed    = []
    @skipped   = 0
  end

  def run
    posts = @targets.map { |t| Pathname.new(t).expand_path }

    puts "対象: #{posts.size}件 #{'(DRY RUN)' if @dry_run}"
    puts "---"
    $stdout.flush

    posts.each_slice(10).with_index do |batch_paths, batch_i|
      sleep 3 if batch_i > 0
      process_batch(batch_paths, batch_i, posts.size)
    end

    puts "---"
    puts "完了: #{@processed.size}件処理, #{@skipped}件スキップ, #{@failed.size}件エラー"
  end

  private

  def process_batch(paths, batch_i, total)
    batch_data = paths.filter_map { |path| read_post(path) }

    if batch_data.empty?
      paths.each { |_p| @skipped += 1 }
      return
    end

    batch_data.each_with_index { |d, i| d[:id] = i }
    tag_map = generate_tags_batch(batch_data)

    batch_data.each do |data|
      path   = data[:path]
      offset = batch_i * 10 + data[:id] + 1
      tags   = tag_map[data[:id]]

      if tags.nil?
        @failed << { path: path.to_s, error: 'タグ未返却' }
        $stderr.puts "[#{offset}/#{total}] ERROR #{path.relative_path_from(POSTS_DIR)}: タグ未返却"
        next
      end

      unless @dry_run
        write_tags(path, data[:fm_open], data[:fm_body], data[:fm_close], data[:body_text], tags)
        @processed << path.to_s
      end

      puts "[#{offset}/#{total}] #{path.relative_path_from(POSTS_DIR)} → #{tags.join(', ')}"
      $stdout.flush
    end
  end

  def read_post(path)
    content = File.read(path, encoding: 'utf-8')
    return nil unless content.match?(/\A---\s*\n/)

    content =~ /\A(---\s*\n)(.*?)(\n---\s*\n)(.*)\z/m
    fm_open, fm_body, fm_close, body_text = $1, $2, $3, $4
    return nil unless fm_open

    fm = YAML.safe_load(fm_body, permitted_classes: [Date, Time]) || {}
    if fm['draft']
      @skipped += 1
      return nil
    end

    title   = fm['title'].to_s.strip
    excerpt = body_text.to_s.gsub(/!\[.*?\]\(.*?\)/, '').gsub(/[#*`>\[\]]/, '').strip[0, 800]

    { path: path, id: nil, title: title, excerpt: excerpt,
      fm_open: fm_open, fm_body: fm_body, fm_close: fm_close, body_text: body_text }
  rescue Psych::Exception
    nil
  end

  def generate_tags_batch(posts_data)
    user_msg = posts_data.map { |d|
      "[#{d[:id]}]\nTitle: #{d[:title]}\nBody: #{d[:excerpt]}"
    }.join("\n\n---\n\n")

    out, err, status = Open3.capture3(
      'claude', '-p', user_msg,
      '--system-prompt', SYSTEM_PROMPT,
      '--no-session-persistence',
      '--output-format', 'text'
    )

    unless status.success?
      $stderr.puts "claude CLI error: #{err.strip}"
      return {}
    end

    json_text = out.force_encoding('UTF-8')[/\[.*\]/m]
    return {} unless json_text

    parsed = JSON.parse(json_text)
    parsed.each_with_object({}) do |entry, h|
      id   = entry['id']
      tags = Array(entry['tags']).map(&:to_s).map(&:strip).reject(&:empty?).first(3)
      h[id] = tags unless tags.empty?
    end
  rescue JSON::ParserError
    {}
  end

  def write_tags(path, fm_open, fm_body, fm_close, body_text, tags)
    tags_line = "tags: [#{tags.map { |t| "\"#{t}\"" }.join(', ')}]"

    new_fm_body = if fm_body =~ /^tags:/
      fm_body.sub(/^tags:.*$/, tags_line)
    elsif fm_body =~ /^slug:/
      fm_body.sub(/^(slug:.*)$/, "#{tags_line}\n\\1")
    else
      "#{fm_body}\n#{tags_line}"
    end

    File.write(path, "#{fm_open}#{new_fm_body}#{fm_close}#{body_text}", encoding: 'utf-8')
  end
end

# --- CLI ---

options = { dry_run: false }

OptionParser.new do |opts|
  opts.banner = "Usage: auto_tagger.rb [--dry-run] file1 [file2 ...]"
  opts.on('--dry-run', 'Preview tags without writing files') { options[:dry_run] = true }
end.parse!

if ARGV.empty?
  $stderr.puts "Error: specify at least one file"
  $stderr.puts "Usage: auto_tagger.rb [--dry-run] file1 [file2 ...]"
  exit 1
end

AutoTagger.new(dry_run: options[:dry_run], targets: ARGV).run
