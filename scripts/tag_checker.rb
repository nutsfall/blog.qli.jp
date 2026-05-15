#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'yaml'

POSTS_DIR = Pathname.new(__dir__).parent / 'content' / 'posts'

total     = 0
no_tags   = 0
too_many  = 0

POSTS_DIR.glob('**/index.md').sort.each do |path|
  content = File.read(path, encoding: 'utf-8')
  next unless content.match?(/\A---\s*\n/)

  content =~ /\A---\s*\n(.*?)\n---\s*\n/m
  fm = YAML.safe_load($1, permitted_classes: [Date, Time]) || {}
  next if fm['draft']

  total += 1
  slug  = fm['slug'].to_s
  tags  = Array(fm['tags']).reject(&:empty?)
  count = tags.size

  no_tags  += 1 if count == 0
  too_many += 1 if count > 3

  tag_str = count > 0 ? tags.join(', ') : '(none)'
  puts "%-40s  %d  %s" % [slug, count, tag_str]
end

puts "---"
puts "総記事数: #{total}  タグなし: #{no_tags}  タグ過多(4+): #{too_many}"
