#!/usr/bin/env ruby
# frozen_string_literal: true

# Moves the leading inline image (placed before any body text) of a post into
# the `cover:` frontmatter, to unify old posts' look with newly imported
# Medium posts. Mirrors process_new_posts.rb's cover-detection logic and
# frontmatter output format (cover: image/caption keys, quote style), but
# operates on already-local image files (no download) and does not rename
# the image file.
#
# Usage: ruby scripts/cover_migrator.rb [--dry-run]
# Run after: git pull

require 'pathname'
require 'yaml'
require 'optparse'

POSTS_DIR = Pathname.new(__dir__).parent / 'content' / 'posts'

LOCAL_IMG_RE = /^!\[([^\]]*)\]\(([^)\s]+)\)[^\n]*\n/
NBSP         = " "

# 叙述文の検出: 日本語の句読点を含む行は本文段落であってキャプションではない。
# （旧記事一括cover化の際、本文冒頭段落のほぼ全件がキャプションとして誤検出された教訓。
#   真正キャプションは「Some rights reserved by ...」等のクレジットや短い名詞句。
#   半角の ! ? はクレジット表記やURLに現れうるため対象にしない。迷う場合は本文に残す側に倒す。）
NARRATIVE_RE = /[。、！？]/

class CoverMigrator
  def initialize(dry_run:)
    @dry_run       = dry_run
    @processed     = []
    @captioned     = []   # [[path, caption], ...]
    @skipped       = []   # [[path, reason], ...]
  end

  def run
    targets = find_targets
    puts "対象候補: #{targets.size}件 #{'(DRY RUN)' if @dry_run}"
    puts "---"

    targets.each { |path| process(path) }

    puts "---"
    puts "cover化: #{@processed.size}件"
    unless @captioned.empty?
      puts "--- caption設定 (#{@captioned.size}件、要目視確認) ---"
      @captioned.each { |path, caption| puts "#{path.relative_path_from(POSTS_DIR)}: #{caption}" }
    end
    unless @skipped.empty?
      puts "--- skip (#{@skipped.size}件) ---"
      @skipped.each { |path, reason| puts "#{path.relative_path_from(POSTS_DIR)}: #{reason}" }
    end
  end

  private

  def find_targets
    POSTS_DIR.glob('**/*.md').select do |path|
      content = File.read(path, encoding: 'utf-8') rescue next
      !content.match?(/^cover:/) && content.match?(LOCAL_IMG_RE)
    end.sort
  end

  def process(path)
    content = File.read(path, encoding: 'utf-8')
    return unless content =~ /\A(---\s*\n)(.*?)(\n---\s*\n)(.*)\z/m

    fm_open, fm_body, fm_close, body = $1, $2, $3, $4

    img_match = body.match(LOCAL_IMG_RE)
    return unless img_match # no local image at all

    img_url  = img_match[2]
    img_line = img_match[0]

    if img_url =~ %r{\Ahttps?://}
      @skipped << [path, "リモートURL画像は対象外(#{img_url})"]
      return
    end

    is_cover = body[0...img_match.begin(0)].strip.empty?
    unless is_cover
      # 本文より後の画像は対象外(触らない)
      return
    end

    unless (path.dirname / img_url).file?
      @skipped << [path, "画像ファイルが存在しない(#{img_url})"]
      return
    end

    unless real_image?(path.dirname / img_url)
      @skipped << [path, "実体が画像ではない(#{img_url})"]
      return
    end

    new_fm   = fm_body.dup
    new_body = body.dup

    # キャプション検出: 画像行の直後（空行1つ挟んでも可）の短い行、次が空行
    caption = nil
    caption_line = nil
    after_img = new_body[img_match.end(0)..]
    if (cap_m = after_img.match(/\A(\n?)([^\n]{1,200})\n(?:\n|\z)/))
      text = cap_m[2].strip.gsub(NBSP, ' ')
      unless text.empty? || text.start_with?('#', '!', '[') || text.match?(NARRATIVE_RE)
        caption      = text
        caption_line = "#{cap_m[1]}#{cap_m[2]}\n"
      end
    end

    cover_block  = "cover:\n  image: \"#{img_url}\""
    cover_block += "\n  caption: \"#{caption.gsub('"', '\\"')}\"" if caption
    new_fm = "#{new_fm}\n#{cover_block}"

    new_body.sub!(img_line, '')
    new_body.sub!(caption_line, '') if caption_line
    new_body.sub!(/\A\n+/, '')

    File.write(path, "#{fm_open}#{new_fm}#{fm_close}#{new_body}", encoding: 'utf-8') unless @dry_run

    label = "cover画像化(#{img_url})"
    label += " + caption" if caption
    puts "#{path.relative_path_from(POSTS_DIR)}: #{label}"

    @processed << path
    @captioned << [path, caption] if caption
  rescue => e
    $stderr.puts "ERROR #{path}: #{e.message}"
  end

  # マジックバイトで実体が画像であることを検証（拡張子が画像でも中身が
  # "bad request" テキストやHTMLエラーページであるダウンロード残骸が存在するため。
  # PaperModのcover.htmlは画像サイズを読むので、壊れ画像をcoverにするとビルドが落ちる）
  def real_image?(file)
    head = File.binread(file, 12)
    return false if head.nil? || head.bytesize < 4
    head.start_with?("\xFF\xD8\xFF".b) ||                    # JPEG
      head.start_with?("\x89PNG".b) ||                       # PNG
      head.start_with?("GIF8".b) ||                          # GIF
      (head.start_with?("RIFF".b) && head[8, 4] == 'WEBP')   # WebP
  rescue StandardError
    false
  end
end

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = "Usage: cover_migrator.rb [--dry-run]"
  opts.on('--dry-run', 'Preview without writing files') { options[:dry_run] = true }
end.parse!

CoverMigrator.new(dry_run: options[:dry_run]).run
