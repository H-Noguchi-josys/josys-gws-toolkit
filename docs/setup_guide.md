# gws CLI 導入ガイド

gws CLI（Google Workspace CLI）を Claude Code / Cursor から利用するための導入手順書。

作成日: 2026-03-31

---

## 1. gws CLI とは

Google Workspace の各サービス（Sheets, Drive, Slides, Gmail, Calendar）を CLI から操作するための Node.js ベースのツール。Claude Code / Cursor から Google Workspace リソースを直接作成・編集できるようになる。

---

## 2. 前提条件

| 項目 | 要件 |
|------|------|
| OS | macOS（Homebrew 利用可能） |
| GCP | josys-production プロジェクトへのアクセス権 |
| OAuth 同意画面 | テストユーザーとして登録済み（管理者に依頼） |
| AI ツール | Claude Code または Cursor がインストール済み |

### 必要な GCP 権限・ロール

gws CLI は OAuth 2.0 のユーザー認証を使用するため、GCP IAM ロールではなく **OAuth スコープ** と **API の有効化** が必要。

#### 有効化が必要な API（GCP コンソール > API とサービス > ライブラリ）

| API | 用途 | 必須/任意 |
|-----|------|----------|
| Google Sheets API | スプレッドシートの作成・編集 | 利用時必須 |
| Google Drive API | ファイル管理・共有設定 | 利用時必須 |
| Google Slides API | プレゼンテーションの作成・編集 | 利用時必須 |
| Gmail API | メール送受信 | 利用時必須 |
| Google Calendar API | カレンダー操作 | 利用時必須 |

> **注意**: API が有効化されていないと Exit Code 4 で失敗する。

#### OAuth 同意画面の設定（管理者が実施）

| 設定項目 | 値 |
|---------|-----|
| 公開ステータス | テスト（Testing） |
| ユーザーの種類 | 内部（Internal）または外部（External） |
| テストユーザー | 利用者の @josys.com アドレスを個別に追加 |

> テストステータスでは **最大100人** のテストユーザーを登録可能。テストユーザーに登録されていないアカウントは認証時に `403 access_denied` エラーになる。

#### OAuth スコープ（認証時に自動で要求される）

gws CLI は認証フロー中に必要なスコープを自動要求する。管理者が OAuth 同意画面でスコープを制限している場合は以下が許可されている必要がある:

| スコープ | 対象サービス |
|---------|------------|
| `https://www.googleapis.com/auth/spreadsheets` | Sheets |
| `https://www.googleapis.com/auth/drive` | Drive |
| `https://www.googleapis.com/auth/presentations` | Slides |
| `https://www.googleapis.com/auth/gmail.modify` | Gmail |
| `https://www.googleapis.com/auth/calendar` | Calendar |

#### 利用者に GCP IAM ロールは不要

gws CLI はユーザー個人の OAuth トークンで Google Workspace API を呼び出す。GCP プロジェクトの IAM ロール（`roles/editor` 等）は **不要**。必要なのは:

1. **OAuth 同意画面のテストユーザー登録**（管理者が実施）
2. **対象 API の有効化**（管理者がプロジェクトで1回だけ実施）
3. **`client_secret.json` の配布**（管理者から利用者へ）

---

## 3. セットアップ手順

### Step 1: gws CLI のインストール

```bash
brew install googleworkspace/tap/gws
```

インストール確認:

```bash
gws --version
# → 0.22.3 以上
```

### Step 2: OAuth クライアント情報の取得

管理者から `client_secret.json` を受け取る。

> **管理者向け**: GCP コンソール > API とサービス > 認証情報 > OAuth 2.0 クライアント ID からダウンロード。OAuth 同意画面で利用者をテストユーザーに追加すること。

### Step 3: 設定ディレクトリの作成と認証

```bash
# 設定ディレクトリを作成
mkdir -p ~/.config/gws-work

# client_secret.json を配置
cp /path/to/client_secret.json ~/.config/gws-work/

# 認証（ブラウザが開く）
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work gws auth login
```

ブラウザで Google アカウント（@josys.com）を選択し、権限を許可する。

### Step 4: 認証状態の確認

```bash
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work gws auth status 2>&1
```

`token_valid: true` が表示されれば成功。

### Step 5: 動作確認

```bash
# Drive のファイル一覧が取得できるか確認
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work gws drive files list --params '{
  "pageSize": 3,
  "fields": "files(id,name)"
}'
```

---

## 4. 環境変数の運用

全コマンドに `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work` を付与する必要がある。

```bash
# スクリプト内ではショートカットを使う
CFG="GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work"
$CFG gws sheets spreadsheets create --json '{...}'
```

> **Note**: 環境変数を省略すると `~/.config/gws`（デフォルト）が使われる。意図しないアカウントで操作するリスクがあるため、必ず明示的に指定する。

---

## 5. 安全弁の仕組み

このリポジトリでは **2層の安全弁** で AI コーディングツールの操作を制御している。

### 5.1 全体像

```
Claude Code / Cursor がコマンドを実行しようとする
  │
  ▼
┌──────────────────────────────────┐
│  第1層: Allowlist（許可リスト）    │  ← settings.local.json
│  許可されたコマンドパターン以外は  │
│  ユーザーに確認ダイアログを表示    │
└──────────┬───────────────────────┘
           │ 許可されたコマンド
           ▼
┌──────────────────────────────────┐
│  第2層: Hooks（自動ブロック）      │  ← settings.json
│  許可リストを通過しても、特定の    │
│  危険パターンは強制的に deny       │
└──────────┬───────────────────────┘
           │ 安全なコマンド
           ▼
        実行
```

### 5.2 第1層: Allowlist（`.claude/settings.local.json`）

`settings.local.json` の `permissions.allow` に登録されたコマンドパターンは、ユーザー確認なしで自動実行される。未登録のコマンドは実行前に確認ダイアログが表示される。

```json
{
  "permissions": {
    "allow": [
      "Bash(bq query:*)",
      "Bash(gcloud config:*)",
      "Bash(git log:*)",
      "Bash(git diff:*)",
      "WebSearch",
      ...
    ]
  }
}
```

**特徴**:
- `settings.local.json` は **Git 管理外**（個人設定）。各ユーザーが自分の許可範囲を定義する
- パターンは `Bash(コマンドプレフィックス:*)` 形式。`*` でサフィックスをワイルドカード許可
- 使い込むうちに許可パターンが蓄積されていく（Claude Code が確認時に「Always allow」を選ぶと追加される）

**gws CLI 関連で許可されるパターン例**:
- `Bash(GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work gws:*)` — gws 全コマンド
- 破壊操作も Allowlist 上は通過するが、第2層の Hook でブロックされる

### 5.3 第2層: Hooks（`.claude/settings.json`）

`settings.json` は **Git 管理下**（チーム共有）。リポジトリを clone した時点で全員に適用される。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/claude_block-bq-write.sh" },
          { "type": "command", "command": "bash .claude/hooks/claude_block-dataform-write.sh" },
          { "type": "command", "command": "bash .claude/hooks/claude_block-gws-destructive.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/claude_check-sql-format.sh" }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/claude_post-deliverable.sh" }
        ]
      }
    ]
  }
}
```

### 5.4 Hook 一覧

#### PreToolUse（実行前ブロック）

Bash コマンド実行前に stdin から `tool_input` を受け取り、危険な操作を `deny` する。

| Hook | 対象 | ブロック条件 | 許可条件 |
|------|------|-------------|---------|
| `claude_block-bq-write.sh` | BigQuery | `bq query` の DML/DDL（INSERT, UPDATE, DELETE, CREATE, DROP 等） | `--dry_run` 付き、SELECT のみ |
| `claude_block-dataform-write.sh` | Dataform | `dataform run`（本番テーブル書き込み） | `dataform compile`（コンパイルのみ） |
| `claude_block-gws-destructive.sh` | gws CLI | `delete`, `trash`, `remove`, `batchDelete`, Gmail `empty` | `--dry-run` 付き、読み取り系 |

#### PostToolUse（実行後チェック）

ファイル編集・作成後にフィードバックを返す。ブロックはしないが、AI に修正を促す。

| Hook | トリガー | 動作 |
|------|---------|------|
| `claude_check-sql-format.sh` | Edit / Write | SQL ファイルのフォーマットルール準拠をチェック |
| `claude_post-deliverable.sh` | Write | 成果物（新規ファイル）作成後のバリデーション |

### 5.5 Hook のアーキテクチャ: Cursor → Claude Code アダプター

Hook は Cursor 用フック（`.cursor/hooks/`）を SSOT（Single Source of Truth）として、Claude Code 用アダプター（`.claude/hooks/`）が変換して呼び出す二段構成。

```
Claude Code (PreToolUse)
  │ stdin: {"tool_input": {"command": "..."}}
  ▼
.claude/hooks/claude_block-*.sh (アダプター)
  │ command を抽出 → Cursor フォーマットに変換
  ▼
.cursor/hooks/block-*.sh (SSOT)
  │ 判定ロジック本体
  ▼
.claude/hooks/ が結果を Claude Code フォーマットに逆変換
  │ deny → {"hookSpecificOutput": {"permissionDecision": "deny", ...}}
  ▼
Claude Code が deny を受け取り、操作を中止
```

この設計により:
- **判定ロジックは1箇所**（`.cursor/hooks/`）に集約
- Cursor と Claude Code の両方で同じルールが適用される
- `python .cursor/sync_to_claude.py` でアダプターを再生成可能

### 5.6 安全弁の使い分けまとめ

| 層 | ファイル | Git 管理 | 対象 | 役割 |
|----|---------|----------|------|------|
| 第1層 Allowlist | `settings.local.json` | **対象外**（個人） | 全コマンド | 確認なし実行の許可範囲を定義 |
| 第2層 Hooks | `settings.json` + `hooks/` | **対象**（チーム共有） | 特定の危険操作 | Allowlist を通過しても強制ブロック |

**ポイント**: Allowlist で利便性を確保しつつ、Hooks で絶対に防ぎたい操作を二重にガードする。Hook はリポジトリに含まれるため、clone するだけで全員に適用される。

---

## 6. ファイル構成と役割

```
.claude/
├── skills/
│   ├── gws-cli/
│   │   └── SKILL.md                  ← (A) コア・リファレンス
│   └── google-slides-generator/
│       └── SKILL.md                  ← (B) Slides 技術リファレンス
├── agents/
│   └── gws-operator.md              ← (C) Sub-agent 定義
├── commands/
│   ├── google-sheets-generator.md   ← (D) Sheets コマンド
│   └── google-slides-generator.md   ← (E) Slides コマンド
└── hooks/
    └── claude_block-gws-destructive.sh  ← (F) 安全Hook

.cursor/
└── skills/
    └── google-sheets-generator/
        ├── SKILL.md                  ← (G) Cursor用 Sheets スキル
        ├── scripts/sheets_helper.py  ← (H) Python ヘルパー
        ├── requirements.txt
        └── reference.md
```

### 各ファイルの役割

| ID | ファイル | 役割 |
|----|---------|------|
| A | `gws-cli/SKILL.md` | 全サービス共通のリファレンス（認証、安全ルール、コマンド例、カラーパレット、エラーコード） |
| B | `google-slides-generator/SKILL.md` | Slides 専用の技術リファレンス（ブランドカラー9色、フォント、ワークフロー、Python生成パターン） |
| C | `gws-operator.md` | Claude Code の Sub-agent 定義。Google Workspace 操作を委譲する専用エージェント |
| D | `google-sheets-generator.md` | `/google-sheets-generator` コマンド。Sheets 作成のステップバイステップ手順 |
| E | `google-slides-generator.md` | `/google-slides-generator` コマンド。Slides 作成の手順 |
| F | `claude_block-gws-destructive.sh` | 破壊的操作の自動ブロック Hook |
| G | Cursor 用 `SKILL.md` | Cursor AI 向け Sheets スキル（Python + ADC 認証方式） |
| H | `sheets_helper.py` | Cursor 用 Python ヘルパー関数群 |

---

## 7. Skills の構造

### (A) gws-cli — コア・リファレンス

Claude Code が gws 関連のキーワード（`gws`, `スプレッドシート作成`, `Google Drive` 等）を検知すると自動読み込みされるスキル。

| セクション | 内容 |
|-----------|------|
| 環境設定 | 認証プロファイル、状態確認方法 |
| 安全ルール | --dry-run 先行、破壊禁止、ページネーション制限 |
| サービス別リファレンス | Sheets / Drive / Slides / Gmail / Calendar の基本コマンド |
| カラーパレット | Sheets batchUpdate 用 RGB 0-1 値 |
| エラーハンドリング | Exit Code 0-5 と対処法 |

### (B) google-slides-generator — Slides 技術リファレンス

| セクション | 内容 |
|-----------|------|
| ブランドカラーパレット | Josys ブランド 9色（C_DARK, C_ACCENT, C_PRIMARY 等） |
| フォント規定 | Inter Tight、用途別サイズ |
| ワークフロー | create → delete default → batchUpdate → Drive移動 → 権限設定 |
| スライドタイプ | カバー、セクション区切り、コンテンツ、カード、KPI |
| Python 生成パターン | `/tmp/generate_slides.py` のテンプレート |

### (G) Cursor 用 Sheets スキル

Cursor AI 向けに Python (ADC認証) ベースの Sheets 生成ヘルパーを提供:

- `sheets_helper.py`: `create_spreadsheet`, `write_values`, `batch_format` 等の再利用関数
- ADC (Application Default Credentials) 認証方式を使用

---

## 8. Sub-agent: gws-operator

Claude Code の Agent ツールで呼び出される専用サブエージェント。

```
Agent(subagent_type="gws-operator", prompt="...")
```

### 責務

| 操作カテゴリ | サービス | 典型コマンド |
|---|---|---|
| スプレッドシート作成・編集 | Sheets | `spreadsheets create`, `values update`, `batchUpdate` |
| ファイル管理 | Drive | `files list`, `+upload`, `permissions create` |
| プレゼンテーション編集 | Slides | `presentations get`, `presentations batchUpdate` |
| メール送受信 | Gmail | `+send`, `+read`, `+triage` |
| カレンダー操作 | Calendar | `+agenda`, `+insert` |

### 内蔵する知識

- 認証手順（環境変数必須、状態確認）
- 安全ルール（--dry-run 先行、破壊禁止）
- Sheets 操作の順序制約（作成 → 値書き込み → 書式適用）
- Josys カラーパレット
- エラー対処テーブル
- 完了時の URL 報告義務

---

## 9. Commands（スラッシュコマンド）

### /google-sheets-generator

ブランドカラーに統一された Sheets を作成する。処理順序:

1. 認証確認
2. スプレッドシート作成
3. 値の書き込み（**必ず書式より先**）
4. 書式の一括適用（batchUpdate: ヘッダー + ゼブラ + 罫線 + フリーズ）
5. フォルダ作成 & 移動（任意）
6. URL 報告

### /google-slides-generator

ブランドカラーに統一された Slides を作成する。処理順序:

1. SKILL.md を読み込み
2. ユーザーと構成を対話で決定
3. Python スクリプト (`/tmp/generate_slides.py`) を作成
4. スクリプト実行
5. URL 報告

---

## 10. 全体アーキテクチャ

```
ユーザー
  │
  ├─ /google-sheets-generator ──→ Command (D) ──→ gws sheets ...
  ├─ /google-slides-generator ──→ Command (E) ──→ Python → gws slides ...
  │
  ├─ 自然言語で依頼 ──→ Claude Code
  │                       ├─ Skill (A) gws-cli を自動参照
  │                       ├─ Skill (B) google-slides-generator を自動参照
  │                       └─ Sub-agent (C) gws-operator に委譲
  │                             └─ Bash → gws CLI
  │                                  └─ Hook (F) が破壊操作をブロック
  │
  └─ Cursor AI ──→ Skill (G) + Helper (H) ──→ Python (ADC) → Sheets API
```

### レイヤー構造

```
┌─────────────────────────────────────────────────┐
│  ユーザーインターフェース                           │
│  ・Claude Code: スラッシュコマンド / 自然言語       │
│  ・Cursor: AI チャット                             │
├─────────────────────────────────────────────────┤
│  ルーティング                                      │
│  ・Command → 直接実行                              │
│  ・自然言語 → Skill 参照 or Sub-agent 委譲          │
├─────────────────────────────────────────────────┤
│  知識層（Skills）                                   │
│  ・(A) gws-cli: 全サービス共通リファレンス           │
│  ・(B) google-slides-generator: Slides 専用知識     │
│  ・(G) Cursor Sheets: Python ヘルパー              │
├─────────────────────────────────────────────────┤
│  実行層                                            │
│  ・gws CLI（Node.js）→ Google Workspace API        │
│  ・Python スクリプト → Slides API / Sheets API     │
├─────────────────────────────────────────────────┤
│  安全層                                            │
│  ・(F) PreToolUse Hook: 破壊操作ブロック            │
│  ・OAuth 同意画面: テストユーザー制限               │
└─────────────────────────────────────────────────┘
```

---

## 11. トラブルシューティング

| 症状 | 原因 | 対処 |
|------|------|------|
| `token_valid: false` | トークン期限切れ | `gws auth login` で再認証 |
| Exit Code 2 | 認証エラー | 環境変数 `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` のパスを確認 |
| Exit Code 3 | パラメータ不正 | `gws schema <method>` で API 仕様を確認 |
| Exit Code 4 | API 未有効化 | GCP コンソールで該当 API を有効化 |
| 破壊操作がブロックされる | Hook が作動（正常動作） | 必要なら手動でコマンド実行 |
| Sheets の書式が反映されない | 値書き込み前に書式適用した | 値 → 書式の順序を厳守 |
| `gws: command not found` | 未インストール | Step 1 のインストール手順を実行 |
| OAuth でエラー | テストユーザー未登録 | 管理者に OAuth 同意画面への追加を依頼 |
