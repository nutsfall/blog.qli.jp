#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'yaml'

POSTS_DIR = Pathname.new(__dir__).parent / 'content' / 'posts'

# tag → 正規形（nilは削除）
REMAP = {
  'yamazaki-reina'       => 'yamazaki-rena',
  'hitoto-yo'            => 'hitotoyo',
  'hitoto-you'           => 'hitotoyo',
  'naoto-inti-raymi'     => 'naoto-intiraymi',
  'shibazaki-tomoka'     => 'shibasaki-tomoka',
  'akai-kouen'           => 'akai-koen',
  '3.11'                 => '3-11',
  '3/11'                 => '3-11',
  '2011-earthquake'      => '3-11',
  'last.fm'              => 'last-fm',
  'movabletype'          => 'movable-type',
  'beats-studio-3'       => 'beats-studio3',
  '2025-recap'           => 'year-in-review',
  # 日本語タグを削除
  '箱根'                  => nil,
  '赤い公園'              => nil,
  '打ち上げ花火下から見るか横から見るか' => nil,
  # 大文字→小文字
  'Apple'                => 'apple',
  'MacBook'              => 'macbook',
  'OmniFocus'            => 'omnifocus',
  'Productivity'         => 'productivity',
  'Things'               => 'things',
}.freeze

# 2024年ふりかえり記事に year-in-review を追加
ADD_TAG = {
  '2024年のふりかえり — 映画編' => 'year-in-review',
  '2024年のふりかえり — 音楽編' => 'year-in-review',
}.freeze

updated = 0

POSTS_DIR.glob('**/index.md').sort.each do |path|
  content = File.read(path, encoding: 'utf-8')
  next unless content.match?(/\A---\s*\n/)

  content =~ /\A(---\s*\n)(.*?)(\n---\s*\n)(.*)\z/m
  fm_open, fm_body, fm_close, body_text = $1, $2, $3, $4
  next unless fm_open

  fm = YAML.safe_load(fm_body, permitted_classes: [Date, Time]) || {}
  tags = Array(fm['tags']).map(&:to_s)
  title = fm['title'].to_s

  original_tags = tags.dup

  # リマップ適用
  tags = tags.flat_map { |t| REMAP.key?(t) ? [REMAP[t]].compact : [t] }.uniq

  # タイトルベースでタグ追加
  if ADD_TAG.key?(title) && !tags.include?(ADD_TAG[title])
    tags << ADD_TAG[title]
  end

  next if tags == original_tags

  tags_line = "tags: [#{tags.map { |t| "\"#{t}\"" }.join(', ')}]"
  new_fm_body = fm_body.sub(/^tags:.*$/, tags_line)
  File.write(path, "#{fm_open}#{new_fm_body}#{fm_close}#{body_text}", encoding: 'utf-8')

  puts "#{path.relative_path_from(POSTS_DIR)}"
  puts "  #{original_tags.inspect} → #{tags.inspect}"
  updated += 1
end

puts "\n#{updated}件更新"
