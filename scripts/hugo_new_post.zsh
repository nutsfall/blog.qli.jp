#!/bin/zsh

# Hugo新規記事作成スクリプト (シンプル版)

# 設定
CONTENT_DIR="content/posts"

# 関数: UUIDを生成
generate_uuid() {
    # macOS/Linux対応のUUID生成
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # フォールバック: 現在時刻とランダム値を使用
        printf "%08x-%04x-%04x-%04x-%012x" \
            $(date +%s) \
            $((RANDOM % 65536)) \
            $((RANDOM % 65536)) \
            $((RANDOM % 65536)) \
            $((RANDOM * RANDOM % 281474976710656))
    fi
}

# 関数: Front matterを生成
create_front_matter() {
    local title="$1"
    local uuid="$2"
    local datetime="$3"
    
    cat << EOF
---
title: "$title"
date: "$datetime"
slug: "$uuid"
description: ""
tags: []
categories: []
draft: true
---

記事の内容をここに書いてください。

EOF
}

# メイン処理
main() {
    local title
    
    # 引数があればそれを使用、なければデフォルト
    if [[ $# -eq 0 ]]; then
        # デフォルトタイトル（現在の日時ベース）
        title="新規記事 $(date +"%Y-%m-%d %H:%M")"
    else
        # タイトルを取得（全引数を結合）
        title="$*"
    fi
    
    # UUID生成
    local uuid=$(generate_uuid)
    
    # 現在の日時を取得
    local current_date=$(date +%Y%m)
    local iso_datetime=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    
    # ディレクトリ名を生成 (YYYYMM/UUID)
    local directory_name="${current_date}/${uuid}"
    
    # フルパスを作成
    local post_dir="$CONTENT_DIR/$directory_name"
    local post_file="$post_dir/index.md"
    
    # content/postsディレクトリの存在確認
    if [[ ! -d "$CONTENT_DIR" ]]; then
        echo "エラー: $CONTENT_DIR ディレクトリが見つかりません"
        exit 1
    fi
    
    # ディレクトリが既に存在するかチェック（UUIDなので基本的にはありえないが念のため）
    if [[ -d "$post_dir" ]]; then
        echo "エラー: ディレクトリ $directory_name は既に存在します"
        exit 1
    fi
    
    # ディレクトリを作成
    mkdir -p "$post_dir"
    
    # 記事ファイルを作成
    create_front_matter "$title" "$uuid" "$iso_datetime" > "$post_file"
    
    # 結果を表示
    echo "✅ 新規記事を作成しました:"
    echo "   📁 ディレクトリ: $directory_name"
    echo "   📄 ファイル: $post_file"
    echo "   🆔 Slug: $uuid"
    echo "   📝 タイトル: $title"
    echo ""
    echo "📝 エディタで開くには:"
    echo "   code '$post_file'"
    echo "   vim '$post_file'"
    echo ""
    echo "🚀 下書き状態で作成されました (draft: true)"
}

# ヘルプ表示
show_help() {
    cat << EOF
Hugo新規記事作成スクリプト (シンプル版)

使用法:
    $0 ["記事タイトル"]

例:
    $0 "新しい記事のタイトル"
    $0 "Hello World記事"
    $0                          # タイトルなしでも作成可能

特徴:
    - YYYYMM/UUID 形式のディレクトリを作成
    - slug は UUID のみ
    - 常に draft: true で作成
    - シンプルで高速
    - 引数なしの場合は自動でタイトル生成

生成される構造:
    content/posts/202509/uuid/index.md
EOF
}

# コマンドライン引数の処理
case "${1:-}" in
    -h|--help|help)
        show_help
        exit 0
        ;;
esac

# メイン処理実行
main "$@"