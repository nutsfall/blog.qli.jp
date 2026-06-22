#!/usr/bin/env ruby
# frozen_string_literal: true

# Processes newly imported Medium posts:
#   1. Removes duplicate H3 title at top of body
#   2. Localizes first Medium CDN image:
#        - image before body text → cover.{ext} + cover: frontmatter
#        - image after body text  → local file + inline {{< figure >}}
#   3. Runs auto_tagger.rb for all Medium posts (Medium tags are not curated)
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
NBSP          = " "

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
        content.match?(MEDIUM_IMG_RE)
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

    # 1. 冒頭の重複H3タイトル削除（画像判定より先に行う）
    if title && !title.empty?
      h3_match = new_body.lstrip.match(/\A(### (.+))\n/)
      if h3_match
        h3_title = h3_match[2].strip.unicode_normalize(:nfc)
        if h3_title.downcase == title.downcase
          new_body.sub!(/\A\s*### #{Regexp.escape(h3_match[2])}\n\n?/, '')
          changes << "重複タイトル削除"
        end
      end
    end

    # 2. 画像のローカル化: 本文より前なら cover、後ろならインライン figure
    if (img_match = new_body.match(/^!\[\]\((#{MEDIUM_IMG_RE})\)[^\n]*\n/))
      img_url  = img_match[1]
      img_line = img_match[0]
      is_cover = new_body[0...img_match.begin(0)].strip.empty?

      # キャプション検出: 画像行の直後（空行1つ挟んでも可）の短い行、次が空行
      caption = nil
      caption_line = nil
      after_img = new_body[img_match.end(0)..]
      if (cap_m = after_img.match(/\A(\n?)([^\n]{1,200})\n(?:\n|\z)/))
        text = cap_m[2].strip.gsub(NBSP, ' ')
        unless text.empty? || text.start_with?('#', '!', '[')
          caption      = text
          caption_line = "#{cap_m[1]}#{cap_m[2]}\n"
        end
      end

      if is_cover
        ext = File.extname(URI.parse(img_url).path)
        ext = '.png' if ext.empty? || ext.length > 5
        filename = "cover#{ext}"

        download(img_url, path.dirname / filename) unless @dry_run

        unless new_fm.include?('cover:')
          cover_block  = "cover:\n  image: \"#{filename}\""
          cover_block += "\n  caption: \"#{caption.gsub('"', '\\"')}\"" if caption
          new_fm = new_fm.sub(/^(draft:.*)$/, "\\1\n#{cover_block}")
        end

        new_body.sub!(img_line, '')
        new_body.sub!(caption_line, '') if caption_line
        new_body.sub!(/\A\n+/, '')
        changes << "cover画像ローカル化(#{filename})"
      else
        filename = File.basename(URI.parse(img_url).path).gsub(/[^\w.\-]/, '_')
        filename = "image#{File.extname(filename)}" if filename.sub(/\..*\z/, '').empty?

        download(img_url, path.dirname / filename) unless @dry_run

        figure  = "{{< figure src=\"#{filename}\""
        figure += " caption=\"#{caption.gsub('"', '\\"')}\"" if caption
        figure += " >}}\n"

        new_body.sub!(img_line, figure)
        new_body.sub!(caption_line, '') if caption_line
        changes << "インライン画像ローカル化(#{filename})"
      end
    end

    # 3. Medium記事は常にauto_taggerにかける（Mediumのタグはルール未準拠）
    @needs_tag << path

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
          uri = URI.join(uri, res['location'])
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
