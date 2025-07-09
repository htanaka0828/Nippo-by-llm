# 日報自動投稿システム

## プロジェクト概要
GitHubのコミット履歴から今日の活動を取得し、Slackの特定チャンネルに日報として自動投稿するシステム

## クイック実行（Claude Code用）

**ユーザーから「Nippo」と言われた場合の実行手順：**

事前準備が完了している前提で、以下の手順を順番に実行してください：

1. **GitHubアクティビティ取得** (`fetch.sh`)
2. **コミットログ整形** (Claude Codeが実行)
3. **Slack投稿** (Claude Codeが実行)
4. **処理済みファイルのリネーム** (Claude Codeが実行)

### 実行コマンド（設定ファイル駆動版）

```bash
# 1. GitHubコミット履歴を取得
./fetch.sh

# 2. 日報作成（Claude Codeが自動実行）
# fetch_data/today_commits.jsonを読み込んでSlack Block Kit形式の日報を作成

# 3. Slack投稿（Claude Codeが自動実行）
source .env
curl -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d @fetch_data/slack_blocks.json

# 4. 処理済みファイルのリネーム（Claude Codeが自動実行）
# .envから取得、なければ実行日を使用
if [ -f .env ]; then
  source .env
fi
if [ -z "$TARGET_DATE" ]; then
  TARGET_DATE=$(date +%Y-%m-%d)
fi
mv fetch_data/today_commits.json fetch_data/today_commits_${TARGET_DATE}.json
mv fetch_data/slack_blocks.json fetch_data/slack_blocks_${TARGET_DATE}.json

echo "日報をSlackに投稿しました！"
```

**重要**: 上記の手順2-4は、Claude Codeが「Nippo」コマンドで自動実行します。手動実行は不要です。

## 設定ファイルの管理

### config.json の設定
監視対象リポジトリ・ブランチは `config.json` で管理します：

```bash
# サンプルファイルをコピー
cp config_sample.json config.json

# 設定ファイルを編集
vi config.json
```

**設定例：**
```json
{
  "monitoring_targets": [
    {
      "org": "your-organization",
      "repo": "main-project",
      "branches": ["feature/*", "main"],
      "priority": "high",
      "description": "メインプロジェクト"
    }
  ],
  "global_settings": {
    "author": "your-github-username",
    "exclude_patterns": ["*/test/*", "*/temp/*"]
  }
}
```

**設定の特徴：**
- **組織・リポジトリ指定**: 具体的な名前またはワイルドカード (`repo-*`)
- **ブランチパターン**: `feature/*`, `main`, `develop` など
- **優先度設定**: `high`, `medium`, `low`
- **除外パターン**: テスト用ブランチなどを自動除外

## 必要な設定

### 対象日付の設定（オプション）
デフォルトでは実行日のコミットを取得しますが、.envファイルで任意の日付を指定できます：

```bash
# .envファイルに追加
TARGET_DATE=2025-07-07  # YYYY-MM-DD形式で指定
```

優先順位：
1. .envファイルのTARGET_DATE設定
2. fetch.sh内のデフォルト設定（実行日）

### GitHub CLI認証
```bash
# GitHub CLIの認証確認
gh auth status

# 必要に応じて再認証（組織アクセス権限付き）
gh auth refresh -s repo -s read:org -s user
```

### Slack Bot設定
1. Slack Appを作成してBot Tokenを取得
2. 以下のスコープを付与：
   - `chat:write`
   - `channels:read`
3. 環境変数ファイルを作成：
   ```bash
   # .env.sampleをコピーして.envファイルを作成
   cp .env.sample .env
   
   # .envファイルを編集してトークンとチャンネルを設定
   # SLACK_BOT_TOKEN=xoxb-your-actual-bot-token
   # SLACK_CHANNEL=#your-channel-name
   ```

## 実行の流れ

### 1. コミット情報取得
```bash
./fetch.sh
```
- `config.json` の設定に基づいて監視対象を処理
- 結果は `fetch_data/today_commits.json` に保存
- 優先度別統計も表示

### 2. 日報作成（Claude Code）
```bash
# Claude Codeに以下を指示：
# "fetch_data/today_commits.jsonを読み込んで、Slack Block Kit形式の日報JSONをfetch_data/slack_blocks.jsonに作成してください。技術的な内容をビジネス価値に翻訳し、プロジェクト別・優先度別に整理してください。"
```

**作成される日報の特徴：**
- Slack Block Kit形式でリッチなUI表示
- 技術的な内容をビジネス価値に翻訳
- プロジェクト別・優先度別に整理
- ヘッダー、セクション、箇条書きを適切に配置
- **事実のみを記載**：コミット履歴にない推測や想定は含めない
- **チャンネル設定**: 環境変数 `SLACK_CHANNEL` から自動取得

**ファイル処理について：**
- Claude Codeでは slack_blocks.json の作成のみ実行
- ファイルのリネームはSlack投稿完了後に実行
- 次回実行時のデータ混在を防止

**重要**: slack_blocks.json作成時は、チャンネル指定を環境変数 `SLACK_CHANNEL` から取得してください。
```bash
# .envファイルのSLACK_CHANNEL変数を使用
source .env
# JSONファイル内のchannelフィールドに$SLACK_CHANNELの値を設定
```

### 3. Slack投稿（Block Kit形式）
```bash
# 環境変数を読み込み
source .env

# Block Kit形式のJSONファイルを使用してSlackに投稿
curl -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d @fetch_data/slack_blocks.json

# 投稿完了後、処理済みファイルを日付付きでリネーム
mv fetch_data/today_commits.json fetch_data/today_commits_$(date +%Y-%m-%d).json
mv fetch_data/slack_blocks.json fetch_data/slack_blocks_$(date +%Y-%m-%d).json

echo "日報をSlackに投稿しました！"
```

## 自動化オプション

### crontabで定期実行
```bash
# crontabに追加（毎日18:00に実行） 
# CLAUDE.mdの手順に従って自動実行
0 18 * * * cd /path/to/nippo-by-llm && cat CLAUDE.md | claude -p "Nippo"
```

**従来方式での自動化:**
```bash
# 手動でコマンドを組み合わせる場合（Block Kit形式）
0 18 * * * cd /path/to/nippo-by-llm && ./fetch.sh && claude -p "fetch_data/today_commits.jsonを読み込んで、Slack Block Kit形式の日報JSONをfetch_data/slack_blocks.jsonに作成してください" && source .env && curl -X POST https://slack.com/api/chat.postMessage -H "Authorization: Bearer $SLACK_BOT_TOKEN" -H "Content-Type: application/json" -d @fetch_data/slack_blocks.json && TARGET_DATE=${TARGET_DATE:-$(date +%Y-%m-%d)} && mv fetch_data/today_commits.json fetch_data/today_commits_${TARGET_DATE}.json && mv fetch_data/slack_blocks.json fetch_data/slack_blocks_${TARGET_DATE}.json && echo "日報投稿完了: $(date)"
```

### GitHub Actionsで実行
`.github/workflows/daily-report.yml` を作成して自動化可能

## データ構造

### fetch_data/today_commits.json
```json
[
  {
    "repository": "org/repo-name",
    "branch": "feature/new-feature",
    "sha": "abc123...",
    "message": "Add new feature implementation",
    "date": "2025-07-03T10:30:00Z",
    "url": "https://github.com/org/repo/commit/abc123",
    "priority": "high",
    "description": "メインプロジェクト"
  }
]
```

## トラブルシューティング

### 設定ファイルが見つからない
```bash
# エラー: 設定ファイル config.json が見つかりません
cp config_sample.json config.json
```

### リポジトリが見つからない場合
1. **GitHub CLI認証の確認**
   ```bash
   gh auth status
   gh auth refresh -s repo -s read:org
   ```

2. **組織のSSO設定**
   - 組織管理者にGitHub CLI承認を依頼
   - `gh api repos/ORG/REPO` で直接アクセステスト

3. **設定ファイルの確認**
   ```bash
   # リポジトリ一覧の確認
   gh api orgs/ORG/repos --jq '.[].name'
   
   # ブランチ一覧の確認
   gh api repos/ORG/REPO/branches --jq '.[].name'
   ```

### コミットが検出されない場合
1. **日付範囲の確認**: `fetch.sh` の`TODAY_START`と`TODAY_END`変数の設定
2. **作成者の確認**: `config.json` の `author` 設定
3. **ブランチパターンの確認**: `branches` 配列の設定
4. **除外パターンの確認**: `exclude_patterns` の設定

## API制限と制約事項
- **GitHub API制限**: 1時間5000回（認証済み）
- **組織アクセス**: SAML/SSO設定により追加承認が必要な場合あり
- **Slackメッセージ制限**: 4000文字（長大な日報は分割投稿を検討）
- **タイムゾーン**: 現在はUTC基準、必要に応じて `.env` で `TZ=Asia/Tokyo` 設定