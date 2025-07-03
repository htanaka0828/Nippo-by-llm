# 日報自動投稿システム (Nippo-by-llm)

GitHubのコミット履歴から今日の活動を取得し、LLMで自然な日報に変換してSlackに自動投稿するシステムです。

## 特徴

- **設定ファイル駆動**: `config.json`で監視対象を柔軟に設定
- **LLM活用**: Claude Codeで技術内容をビジネス価値に翻訳
- **完全自動化**: crontabで毎日自動実行可能
- **安全性重視**: 個人情報の保護と権限管理を徹底

## クイックスタート

### 1. 初期設定

```bash
# リポジトリのクローン
git clone <repository-url>
cd Nippo-by-llm

# 設定ファイルの作成
cp config_sample.json config.json
cp .env.sample .env

# 設定ファイルの編集
vi config.json  # 監視対象リポジトリを設定
vi .env         # SlackのBot Tokenとチャンネルを設定
```

### 2. GitHub CLI認証

```bash
# GitHub CLIの認証（組織アクセス権限付き）
gh auth refresh -s repo -s read:org -s user

# 認証確認
gh auth status
```

### 3. 実行

```bash
# コミット情報取得
./fetch.sh

# Claude Codeで日報作成・投稿（手動）
# "fetch_data/today_commits.jsonを読み込んで、ビジネス向けの日報をfetch_data/daily_report.mdに作成してください"

# または自動実行（CLAUDE.mdの手順に従って）
cat CLAUDE.md | claude -p "Nippo"
```

## ファイル構成

```
Nippo-by-llm/
├── fetch.sh              # GitHubコミット取得スクリプト
├── config.json           # 監視対象設定（git管理外）
├── config_sample.json    # 設定ファイルのサンプル
├── .env                  # 環境変数（git管理外）
├── .env.sample          # 環境変数のサンプル
├── CLAUDE.md            # Claude Code用実行手順
├── README.md            # このファイル
├── .gitignore           # Git除外設定
└── fetch_data/          # 一時データディレクトリ（git管理外）
    ├── today_commits.json      # 取得したコミット情報
    ├── daily_report.md         # 生成された日報
    └── *_YYYY-MM-DD.*          # 過去データ（日付付きリネーム）
```

## 設定ファイル

### config.json

監視対象のリポジトリとブランチを設定：

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

### .env

Slack投稿用の環境変数：

```bash
SLACK_BOT_TOKEN=xoxb-your-slack-bot-token-here
SLACK_CHANNEL=#daily-reports
```

## 自動化

### crontabで毎日自動実行

```bash
# 毎日18:00に実行
0 18 * * * cd /path/to/nippo-by-llm && cat CLAUDE.md | claude -p "Nippo"
```

## 必要な環境

### 必須ツール
- **GitHub CLI**: リポジトリへのアクセス権限
- **jq**: JSON処理
- **curl**: Slack API呼び出し
- **bash**: スクリプト実行環境

### LLM・AI環境（いずれか必須）
- **Claude Code**: 推奨。コマンドライン実行で完全自動化が可能
- **その他LLM**: ChatGPT、Copilot Chat等でも手動実行可能
- **人間による作業**: JSONデータを手動で日報に変換する場合

**注意**: このプロジェクトは技術的なコミット情報を人間に分かりやすい日報に変換するため、LLMまたは人間による情報整形が必要です。

### Claude Code自動承認設定

Claude Codeですべての動作を自動承認したい場合は、以下のいずれかの方法で設定できます：

#### 1. プロジェクト固有設定（推奨）
`.claude/settings.local.json` に：
```json
{
  "auto_approve": true,
  "hooks": {
    "pre_tool": "echo 'Auto-approving tool use'"
  }
}
```

#### 2. 環境変数設定（即座に適用）
```bash
export CLAUDE_AUTO_APPROVE=true
```

#### 3. グローバル設定ファイル（永続化）
`~/.config/claude/settings.json` または `~/.claude/settings.json` に：
```json
{
  "auto_approve": true,
  "hooks": {
    "pre_tool": "echo 'Auto-approving tool use'"
  }
}
```

#### 4. コマンドライン引数
```bash
claude --auto-approve
```

#### 5. セッション内設定
```bash
claude --setting auto_approve=true
```

## セキュリティ

- 設定ファイル（`config.json`）はgit管理外
- 環境変数（`.env`）はgit管理外
- 一時データ（`fetch_data/`）はgit管理外
- 個人情報はハードコードしない設計

## トラブルシューティング

### よくある問題

1. **コミットが検出されない**
   - `config.json`の`author`設定を確認
   - `fetch.sh`の`TODAY_START`/`TODAY_END`変数を確認

2. **リポジトリにアクセスできない**
   - GitHub CLIの認証を確認: `gh auth status`
   - 組織のSSO設定でCLI承認が必要な場合がある

3. **Slack投稿できない**
   - Bot Tokenの権限（`chat:write`）を確認
   - チャンネル名（`#`から始まる）を確認

### デバッグ

```bash
# 取得したコミット情報を確認
cat fetch_data/today_commits.json | jq '.'

# 特定組織のリポジトリ一覧を確認
gh api orgs/ORG-NAME/repos --jq '.[].name'

# 特定リポジトリのブランチ一覧を確認
gh api repos/ORG/REPO/branches --jq '.[].name'
```

## ライセンス

このプロジェクトは [WTFPL](http://www.wtfpl.net/) の下で公開されています。

```
        DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE 
                    Version 2, December 2004 

 Copyright (C) 2004 Sam Hocevar <sam@hocevar.net> 

 Everyone is permitted to copy and distribute verbatim or modified 
 copies of this license document, and changing it is allowed as long 
 as the name is changed. 

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE 
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION 

  0. You just DO WHAT THE FUCK YOU WANT TO.
```

**外部サービスについて:**
- GitHub API、Slack API、Claude Code等の外部サービスを利用する際は、それぞれのサービスの利用規約・ライセンスに従ってください
- 本プロジェクトのライセンスは、外部サービスの利用規約を上書きするものではありません

## 貢献

プルリクエストやイシューを歓迎します。機能追加や改善提案がございましたらお気軽にお知らせください。