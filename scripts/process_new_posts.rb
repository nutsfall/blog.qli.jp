#!/usr/bin/env ruby
# frozen_string_literal: true

# Processes newly imported Medium posts:
#   1. Downloads cover image from Medium CDN → localizes to cover.{ext}
#   2. Adds cover: frontmatter (with caption if found)
#   3. Removes inline image line + caption from body
#   4. Removes duplicate H3 title at top of body
#   5. Runs auto_tagger.rb for posts with empty tags
#
# Usage: ruby scripts/process_new_posts.rb [--dry-run]
# Run after: git pull

require 'pathname'
require 'yaml'
require 'uri'
require 'net/http'
require 'open3'
require 'optparse'

POSTS_DIR   = Pathname.new(__dir__).parent / 'content' / 'posts'
RUBY_BIN    = '/opt/homebrew/opt/ruby/bin/ruby'
AUTO_TAGGER = Pathname.new(__dir__) / 'auto_tagger.rb'

MEDIUM_IMG_RE = /https?:\/\/cdn-images-1\.medium\.com\/[^\s\)"]+/

class PostProcessor
  def initialize(dry_run:)
    @dry_run   = dry_run
    @processed = []
    @needs_tag = []
  end

  def run
    targets = find_targets
    if targets.empty?
      puts "処理対象なし"
      return
    end

    puts "対象: #{targets.size}件 #{'(DRY RUN)' if @dry_run}"
    puts "---"

    targets.each { |path| process(path) }

    unless @needs_tag.empty?
      puts "---"
      tag_cmd = [RUBY_BIN, AUTO_TAGGER.to_s]
      tag_cmd << '--dry-run' if @dry_run
      tag_cmd += @needs_tag.map(&:to_s)
      system(*tag_cmd)
    end

    puts "---"
    puts "完了: #{@processed.size}件処理"
  end

  private

  def find_targets
    POSTS_DIR.glob('**/*.md').select do |path|
      content = File.read(path, encoding: 'utf-8') rescue next
      content.match?(/^source:\s*["']?medium/) &&
        (content.match?(MEDIUM_IMG_RE) || content.match?(/^tags:\s*\[\]\s*$/))
    end.sort
  end

  def process(path)
    content = File.read(path, encoding: 'utf-8')
    return unless content =~ /\A(---\s*\n)(.*?)(\n---\s*\n)(.*)\z/m

    fm_open, fm_body, fm_close, body = $1, $2, $3, $4
    fm    = YAML.safe_load(fm_body, permitted_classes: [Date, Time]) || {}
    title = fm['title'].to_s.strip.unicode_normalize(:nfc)

    new_fm   = fm_body.dup
    new_body = body.dup
    changes  = []

    # 1. 画像のローカル化
    if (img_match = body.match(/^(!\[\]\((#{MEDIUM_IMG_RE})\))\s*\n/))
      img_url   = img_match[2]
      full_line = img_match[0]

      ext = File.extname(URI.parse(img_url).path)
      ext = '.png' if ext.empty? || ext.length > 5
      filename = "cover#{ext}"

      # キャプション検出: 画像行の直後（空行1つ挟んでも可）の短い行、次が空行
      caption = nil
      caption_line = nil
      after_img = body[img_match.end(0)..]
      if after_img =~ /\A(\n?)([^\n]{1,200})\n\n/m
        line = $2.strip.gsub(" ", ' ')
        unless line.empty? || line.start_with?('#', '!', '[')
          caption      = line
          caption_line = "#{$1}#{$2}\n"
        end
      end

      download(img_url, path.dirname / filename) unless @dry_run

      unless new_fm.include?('cover:')
        cover_block  = "cover:\n  image: \"#{filename}\""
        cover_block += "\n  caption: \"#{caption.gsub('"', '\\"')}\"" if caption
        new_fm = new_fm.sub(/^(draft:.*)$/, "\\1\n#{cover_block}")
      end

      new_body.sub!(full_line, '')
      new_body.sub!(caption_line, '') if caption_line
      changes << "画像ローカル化(#{filename})"
    end

    # 2. 冒頭の重複H3タイトル削除
    if title && !title.empty?
      h3_match = new_body.lstrip.match(/\A(### (.+))\n/)
      if h3_match
        h3_title = h3_match[2].strip.unicode_normalize(:nfc)
        if h3_title == title
          new_body.sub!(/^### #{Regexp.escape(h3_match[2])}\n\n?/, '')
          changes << "重複タイトル削除"
        end
      end
    end

    # 3. タグが空なら後でauto_taggerにかける
    @needs_tag << path if fm_body.match?(/^tags:\s*\[\]\s*$/)

    if changes.any?
      File.write(path, "#{fm_open}#{new_fm}#{fm_close}#{new_body}", encoding: 'utf-8') unless @dry_run
      puts "#{path.relative_path_from(POSTS_DIR)}: #{changes.join(', ')}"
      @processed << path
    end
  rescue => e
    $stderr.puts "ERROR #{path}: #{e.message}"
  end

  def download(url, dest)
    uri = URI.parse(url)
    10.times do
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                      open_timeout: 10, read_timeout: 30) do |http|
        res = http.get(uri.request_uri, 'User-Agent' => 'Mozilla/5.0')
        case res
        when Net::HTTPSuccess
          raise "Empty response: #{url}" if res.body.empty?
          File.binwrite(dest, res.body)
          return
        when Net::HTTPRedirection
          uri = URI.parse(res['location'])
        else
          raise "HTTP #{res.code}: #{url}"
        end
      end
    end
    raise "Too many redirects: #{url}"
  end
end

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = "Usage: process_new_posts.rb [--dry-run]"
  opts.on('--dry-run', 'Preview without writing files') { options[:dry_run] = true }
end.parse!

PostProcessor.new(dry_run: options[:dry_run]).run
