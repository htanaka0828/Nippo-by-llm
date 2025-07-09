#!/bin/bash

# 設定駆動型コミット取得スクリプト
# JSONコンフィグベースのスマート検索

set -e

# 設定ファイルパス
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
DATA_DIR="fetch_data"

# .envファイルを読み込み（存在する場合）
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

# 基本設定
USERNAME=$(gh api user --jq '.login')

# TARGET_DATEの設定（.env > 実行日の優先順位）
if [ -n "$TARGET_DATE" ]; then
    # .envで設定されている場合はそれを使用
    echo "対象日付を.envから取得: $TARGET_DATE"
else
    # .envに設定がない場合は実行日を使用
    TARGET_DATE=$(date +%Y-%m-%d)
fi

TARGET_DATE_START="${TARGET_DATE}T00:00:00Z"
TARGET_DATE_END="${TARGET_DATE}T23:59:59Z"

echo "=== 設定駆動型コミット履歴取得開始 ==="
echo "ユーザー: $USERNAME"
echo "対象日: $TARGET_DATE"
echo "設定ファイル: $CONFIG_FILE"
echo ""

# 設定ファイル存在確認
if [ ! -f "$CONFIG_FILE" ]; then
    echo "エラー: 設定ファイル $CONFIG_FILE が見つかりません"
    exit 1
fi

# グローバル設定読み込み
AUTHOR=$(jq -r '.global_settings.author // "'"$USERNAME"'"' "$CONFIG_FILE")
MAX_COMMITS=$(jq -r '.global_settings.max_commits_per_branch // 50' "$CONFIG_FILE")
PARALLEL_JOBS=$(jq -r '.global_settings.parallel_jobs // 10' "$CONFIG_FILE")

echo "グローバル設定:"
echo "- 作成者: $AUTHOR"
echo "- 最大コミット数/ブランチ: $MAX_COMMITS"
echo "- 並列ジョブ数: $PARALLEL_JOBS"
echo ""

# 作業用ディレクトリ準備
mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

> today_commits.json
echo "[]" > today_commits.json

# ワイルドカードパターンマッチング関数
matches_pattern() {
    local text="$1"
    local pattern="$2"
    
    case "$text" in
        $pattern) return 0 ;;
        *) return 1 ;;
    esac
}

# 除外パターンチェック関数
should_exclude() {
    local full_path="$1"
    
    exclude_patterns=$(jq -r '.global_settings.exclude_patterns[]? // empty' "$CONFIG_FILE")
    
    while IFS= read -r pattern; do
        if [ -n "$pattern" ] && matches_pattern "$full_path" "$pattern"; then
            return 0  # 除外
        fi
    done <<< "$exclude_patterns"
    
    return 1  # 除外しない
}

# 監視対象の処理
target_count=$(jq '.monitoring_targets | length' "$CONFIG_FILE")
echo "監視対象: ${target_count}個の設定"
echo ""

for ((i=0; i<target_count; i++)); do
    target=$(jq ".monitoring_targets[$i]" "$CONFIG_FILE")
    
    org=$(echo "$target" | jq -r '.org')
    repo_pattern=$(echo "$target" | jq -r '.repo')
    priority=$(echo "$target" | jq -r '.priority')
    description=$(echo "$target" | jq -r '.description')
    branches_json=$(echo "$target" | jq -r '.branches[]')
    
    echo "[$((i+1))/$target_count] 処理中: $org/$repo_pattern ($priority)"
    echo "  説明: $description"
    
    # リポジトリパターンに基づいて実際のリポジトリ一覧を取得
    if [[ "$repo_pattern" == *"*"* ]]; then
        # ワイルドカード含む場合は組織のリポジトリ一覧から検索
        actual_repos=$(gh api "orgs/$org/repos?per_page=100" --jq '.[].name' 2>/dev/null | \
            while IFS= read -r repo_name; do
                if matches_pattern "$repo_name" "$repo_pattern"; then
                    echo "$repo_name"
                fi
            done)
    else
        # 具体的なリポジトリ名の場合
        actual_repos="$repo_pattern"
    fi
    
    if [ -z "$actual_repos" ]; then
        echo "  警告: マッチするリポジトリが見つかりません"
        continue
    fi
    
    # 各リポジトリの処理
    echo "$actual_repos" | while IFS= read -r repo_name; do
        repo_full="$org/$repo_name"
        echo "  リポジトリ: $repo_full"
        
        # リポジトリのブランチ一覧取得
        all_branches=$(gh api "repos/$repo_full/branches?per_page=100" --jq '.[].name' 2>/dev/null || echo "")
        
        if [ -z "$all_branches" ]; then
            echo "    警告: ブランチ取得失敗"
            continue
        fi
        
        # 設定されたブランチパターンとマッチするブランチを検索
        matched_branches=""
        
        echo "$branches_json" | while IFS= read -r branch_pattern; do
            if [ -n "$branch_pattern" ]; then
                echo "$all_branches" | while IFS= read -r actual_branch; do
                    if matches_pattern "$actual_branch" "$branch_pattern"; then
                        full_branch_path="$org/$repo_name/$actual_branch"
                        
                        # 除外パターンチェック
                        if ! should_exclude "$full_branch_path"; then
                            echo "    ✓ $actual_branch (パターン: $branch_pattern)"
                            
                            # コミット検索
                            commits=$(gh api "repos/$repo_full/commits?sha=$actual_branch&since=$TARGET_DATE_START&until=$TARGET_DATE_END&per_page=$MAX_COMMITS" \
                                --jq "map(select(.commit.author.email == \"$AUTHOR@gmail.com\" or .author.login == \"$AUTHOR\")) | 
                                map({
                                    repository: \"$repo_full\",
                                    branch: \"$actual_branch\",
                                    sha: .sha,
                                    message: .commit.message,
                                    date: .commit.author.date,
                                    url: .html_url,
                                    priority: \"$priority\",
                                    description: \"$description\"
                                })" 2>/dev/null || echo "[]")
                            
                            commit_count=$(echo "$commits" | jq '. | length' 2>/dev/null || echo "0")
                            
                            if [ "$commit_count" -gt 0 ]; then
                                echo "      → コミット発見: ${commit_count}件"
                                
                                # 結果をマージ（重複除去＋排他制御付き）
                                (
                                    flock 200
                                    temp_file="../$DATA_DIR/tmp_commits_$$.json"
                                    if jq -s --argjson new_commits "$commits" '.[0] + $new_commits | unique_by(.sha) | sort_by(.date)' "../$DATA_DIR/today_commits.json" > "$temp_file" 2>/dev/null; then
                                        mv "$temp_file" "../$DATA_DIR/today_commits.json"
                                    else
                                        rm -f "$temp_file"
                                    fi
                                ) 200>/tmp/commit_merge.lock
                            fi
                        else
                            echo "    ✗ $actual_branch (除外パターンにマッチ)"
                        fi
                    fi
                done
            fi
        done
    done
    
    echo ""
done

cd ..

# 結果の統計と表示
total_commits=$(cat "$DATA_DIR/today_commits.json" | jq '. | length' 2>/dev/null || echo "0")
unique_repos=$(cat "$DATA_DIR/today_commits.json" | jq -r '.[].repository' 2>/dev/null | sort -u | wc -l || echo "0")
unique_branches=$(cat "$DATA_DIR/today_commits.json" | jq -r '.[] | .repository + "/" + .branch' 2>/dev/null | sort -u | wc -l || echo "0")

echo "=== 設定駆動型取得完了 ==="
echo "総コミット数: $total_commits"
echo "対象リポジトリ数: $unique_repos"
echo "対象ブランチ数: $unique_branches"

if [ "$total_commits" -gt 0 ]; then
    echo ""
    echo "優先度別統計:"
    cat "$DATA_DIR/today_commits.json" | jq -r 'group_by(.priority) | .[] | "\(.[0].priority): \(length)件"' | sort
    
    echo ""
    echo "【JSONデータ取得完了】"
    echo "$DATA_DIR/today_commits.json に保存されました。"
    echo "Claude Code等のLLMツールでこのJSONを読み込んで日報を作成してください。"
    echo "対象日付: $TARGET_DATE"
else
    echo ""
    echo "本日はコミットが検出されませんでした。"
    echo ""
    echo "確認事項:"
    echo "1. 設定ファイルの監視対象が正しいか"
    echo "2. ブランチパターンが実際のブランチ名とマッチするか"
    echo "3. 除外パターンで対象ブランチが除外されていないか"
fi

echo ""
echo "設定管理のヒント:"
echo "- $CONFIG_FILE を編集して監視対象を変更"
echo "- ワイルドカード (*) でパターンマッチング"
echo "- priority で重要度設定"
echo "- exclude_patterns で不要ブランチを除外"
