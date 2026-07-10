#!/usr/bin/env ruby
# frozen_string_literal: true

# content/posts/**/index.md 本文中の、プラットフォーム移行由来の壊れたリンク形式を
# 通常の Markdown リンク `[リンクテキスト](URL)` に正規化する。
#
#   パターン1: Medium リンクカードの崩れ
#     [**タイトル**
#     _抜粋…_ドメイン](URL "URL")[](URL)
#     → [タイトル](URL)
#
#   パターン2: 旧ブログの「リンク: 」形式
#     リンク: [リンクテキスト](URL "タイトル属性").
#     → [リンクテキスト](URL)
#
# 安全策:
#   - 上記2パターンにマッチする行・ブロックのみを書き換え、他の本文・フロントマターには触れない
#   - 機械的に確信が持てない変則ケース（エスケープされたリンク、壊れた <a> タグ残骸、
#     閉じ構造が見つからないカード等）は変換せず、スキップしてファイル名を報告する
#
# Usage:
#   /opt/homebrew/opt/ruby/bin/ruby scripts/link_normalizer.rb --dry-run
#   /opt/homebrew/opt/ruby/bin/ruby scripts/link_normalizer.rb

require 'pathname'

POSTS_DIR = Pathname.new(__dir__).parent / 'content' / 'posts'

DRY_RUN = ARGV.include?('--dry-run')
MEDIA_CARD_MARKER_RE = /"\)\[\]\(http/.freeze

# ============================================================
# パターン1: Medium リンクカードの崩れ
# ============================================================
#
# 構造: `[**タイトル**` + 行末スペース2つ + 改行 + (抜粋)(ドメイン)`](URL "URL")[](URL)`
# 抜粋部分の書式（_..._ / \_..._ / 抜粋なし 等）は揺れがあるため、
# タイトル行を起点に「閉じ構造 `](URL "URL")[](URL)`」が見つかるまで
# 数行だけ行単位で読み進める方式で検出する（正規表現の暴走マッチを避けるため）。

TITLE_LINE_RE = /\A\[\*\*(.+)\*\*[ \t]*\z/.freeze
CARD_CLOSE_RE = /\]\((\S+)[ \t]+"[^"]*"\)\[\]\((\S+)\)\z/.freeze
MAX_CARD_LOOKAHEAD_LINES = 4 # タイトル行の後、閉じ構造を探す最大行数（通常は1行）

def strip_title_markup(title)
  t = title.strip
  # `[**_Title_**` のように **の内側が丸ごと _..._ (イタリック) で囲まれているケースを剥がす
  t = t[1..-2] if t.start_with?('_') && t.end_with?('_') && t.length > 1
  t
end

# content(1ファイル分の文字列)からパターン1のカードを検出する
# 戻り値: [{start_line:, end_line:, title:, href:}]
def find_media_cards(content)
  lines = content.split("\n", -1)
  cards = []

  i = 0
  while i < lines.length
    m = TITLE_LINE_RE.match(lines[i])
    unless m
      i += 1
      next
    end

    title = m[1]
    buffer = +''
    end_index = nil
    href = nil

    j = i + 1
    while j < lines.length && (j - i) <= MAX_CARD_LOOKAHEAD_LINES
      break if lines[j].strip.empty? # 空行に到達したらカードではないとみなし中断

      buffer << (buffer.empty? ? '' : "\n") << lines[j]
      if (cm = CARD_CLOSE_RE.match(buffer))
        # href (通常のリンクURL) と title属性URL・末尾の空リンク[](URL)のURLが一致することを確認
        if cm[1] == cm[2]
          href = cm[1]
          end_index = j
        end
        break
      end
      j += 1
    end

    if end_index
      cards << { start_line: i, end_line: end_index, title: strip_title_markup(title), href: href }
      i = end_index + 1
    else
      i += 1
    end
  end

  cards
end

def normalize_media_cards(content, report)
  cards = find_media_cards(content)
  return content if cards.empty?

  lines = content.split("\n", -1)
  # 末尾から置換していくと行番号がずれない
  cards.reverse_each do |card|
    replacement = "[#{card[:title]}](#{card[:href]})"
    report[:media_diffs] << [lines[card[:start_line]..card[:end_line]].join("\n"), replacement] if report[:media_diffs].length < 40
    lines[card[:start_line]..card[:end_line]] = replacement
    report[:media_converted] += 1
  end
  lines.join("\n")
end

# ============================================================
# パターン2: 旧ブログの「リンク: 」形式
# ============================================================
#
# 例: リンク: [リンクテキスト](URL "タイトル属性").
#     リンク: [リンクテキスト](URL).
#     リンク: [リンクテキスト]({{< ref "posts/..." >}}).
#
# タイトル属性・文末ピリオドの有無は揺れを許容する。
# エスケープされたブラケット `\[...\]`（リンクとして機能していない残骸）や
# 壊れた <a> タグの残骸は変換対象外としてスキップする。

OLD_LINK_LINE_RE = /\A(リンク: )\[(.+)\]\((.*)\)\.?[ \t]*\z/.freeze

def normalize_old_links(content, file, report)
  lines = content.split("\n", -1)
  changed = false

  lines.map! do |line|
    m = OLD_LINK_LINE_RE.match(line)
    unless m
      # 「リンク: 」で始まるがパターンに一致しない行はスキップとして記録
      if line.start_with?('リンク: ')
        report[:old_link_skips] << "#{file}: #{line.strip}"
      end
      next line
    end

    text = m[2]
    paren_content = m[3].strip

    url =
      if (tm = /\A(\S+)[ \t]+"[^"]*"\z/.match(paren_content))
        tm[1]
      else
        paren_content
      end

    replacement = "[#{text}](#{url})"
    report[:old_link_diffs] << [line, replacement] if report[:old_link_diffs].length < 40
    changed = true
    report[:old_link_converted] += 1
    replacement
  end

  changed ? lines.join("\n") : content
end

# ============================================================
# メイン処理
# ============================================================

def process_file(path, report)
  original = File.read(path, encoding: 'UTF-8')

  content = normalize_media_cards(original, report)
  content = normalize_old_links(content, path, report)

  if MEDIA_CARD_MARKER_RE.match?(content)
    report[:media_remaining_files] << path
  end

  return if content == original

  if DRY_RUN
    report[:changed_files] << path
  else
    File.write(path, content, encoding: 'UTF-8')
    report[:changed_files] << path
  end
end

def main
  report = {
    media_converted: 0,
    media_diffs: [],
    media_remaining_files: [],
    old_link_converted: 0,
    old_link_diffs: [],
    old_link_skips: [],
    changed_files: []
  }

  files = Dir.glob(POSTS_DIR / '**' / 'index.md').sort

  files.each do |f|
    process_file(f, report)
  end

  puts "=== #{DRY_RUN ? 'DRY RUN' : 'APPLY'} ==="
  puts "対象ファイル数: #{files.length}"
  puts "変更ファイル数: #{report[:changed_files].length}"
  puts
  puts "パターン1 (Mediumカード) 変換件数: #{report[:media_converted]}"
  puts "パターン1 未変換(マーカー残存)ファイル数: #{report[:media_remaining_files].length}"
  report[:media_remaining_files].each { |f| puts "  skip: #{f}" }
  puts
  puts "パターン2 (リンク: 形式) 変換件数: #{report[:old_link_converted]}"
  puts "パターン2 スキップ件数: #{report[:old_link_skips].length}"
  report[:old_link_skips].each { |s| puts "  skip: #{s}" }

  if DRY_RUN
    puts
    puts "=== パターン1 サンプル diff (最大#{report[:media_diffs].length}件) ==="
    report[:media_diffs].each do |before, after|
      puts "  before: #{before.inspect}"
      puts "  after:  #{after.inspect}"
      puts
    end

    puts "=== パターン2 サンプル diff (最大#{report[:old_link_diffs].length}件) ==="
    report[:old_link_diffs].each do |before, after|
      puts "  before: #{before.inspect}"
      puts "  after:  #{after.inspect}"
      puts
    end
  end
end

main if __FILE__ == $PROGRAM_NAME
