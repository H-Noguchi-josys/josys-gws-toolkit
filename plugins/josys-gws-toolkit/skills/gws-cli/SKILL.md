---
name: gws-cli
description: gws CLI（Google Workspace CLI）の安全な使い方、環境設定、サービス別リファレンス、共通パターン
autoTrigger:
  - "gws"
  - "Google Workspace CLI"
  - "スプレッドシート作成"
  - "Google Sheets 作成"
  - "Google Drive"
  - "Google Slides"
---

# gws CLI ガイド

Google Workspace CLI (`gws`) を使用して Google Workspace サービスを操作するためのルール。

---

## 環境設定

### 認証プロファイル

仕事用アカウントで操作する。環境変数でプロファイルを切り替える。

```bash
# 仕事用（josys-production）— 常にこれを使う
export GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work
```

**全コマンドにこの環境変数を付与すること。** 省略すると `~/.config/gws` のデフォルトプロファイルが使われる。

### 認証状態の確認

操作前に必ず認証状態を確認する：

```bash
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work gws auth status 2>&1
```

`token_valid: true` を確認してから操作に進む。`false` の場合はユーザーに再認証を促す：

```
! GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work gws auth login
```

### 環境変数ショートカット

コマンドが長くなるため、スクリプト内では以下のパターンを推奨：

```bash
export GWS="GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work gws"
# 使用例: eval "$GWS sheets +read --params '...'"
```

---

## 安全ルール

### 必須

1. **--dry-run 先行**: 新しい操作パターンを初めて使うときは `--dry-run` で検証してから実行
2. **読み取り優先**: 不明な状態のリソースにはまず GET/list で現状確認
3. **破壊的操作禁止**: `delete`, `trash`, `remove` 系コマンドは Hook でブロック済み。必要な場合はユーザーに手動実行を依頼
4. **大量操作は分割**: `--page-all` 使用時は `--page-limit` を必ず設定（デフォルト10、最大50）
5. **機密データ注意**: Gmail の本文読み取り、Drive のファイルダウンロードは必要最小限に

### 推奨

- `--format table` で人間可読な出力を確認してからスクリプト化
- JSON パラメータは変数に格納してからコマンドに渡す（シェルエスケープ事故防止）
- スプレッドシート ID 等の識別子はハードコードせず変数化

---

## サービス別リファレンス

### Sheets（最頻出）

```bash
CFG="GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work"

# スプレッドシート作成
$CFG gws sheets spreadsheets create --json '{
  "properties": {"title": "タイトル"},
  "sheets": [{"properties": {"title": "シート1"}}]
}'

# 値の読み取り（ヘルパー）
$CFG gws sheets +read --params '{
  "spreadsheetId": "SHEET_ID",
  "range": "シート1!A1:Z100"
}'

# 値の追加（ヘルパー）
$CFG gws sheets +append --params '{
  "spreadsheetId": "SHEET_ID",
  "range": "シート1!A1"
}' --json '{
  "values": [["col1", "col2"], ["val1", "val2"]]
}'

# 値の更新
$CFG gws sheets spreadsheets values update --params '{
  "spreadsheetId": "SHEET_ID",
  "range": "シート1!A1",
  "valueInputOption": "USER_ENTERED"
}' --json '{
  "values": [["header1", "header2"], ["data1", "data2"]]
}'

# 書式の一括適用（batchUpdate）
$CFG gws sheets spreadsheets batchUpdate --params '{
  "spreadsheetId": "SHEET_ID"
}' --json '{
  "requests": [
    {
      "repeatCell": {
        "range": {"sheetId": 0, "startRowIndex": 0, "endRowIndex": 1},
        "cell": {
          "userEnteredFormat": {
            "backgroundColor": {"red": 0.26, "green": 0.26, "blue": 0.26},
            "textFormat": {"bold": true, "foregroundColor": {"red": 1, "green": 1, "blue": 1}}
          }
        },
        "fields": "userEnteredFormat(backgroundColor,textFormat)"
      }
    }
  ]
}'

# スプレッドシートのメタデータ取得
$CFG gws sheets spreadsheets get --params '{
  "spreadsheetId": "SHEET_ID",
  "fields": "properties.title,sheets.properties"
}'
```

### Drive

```bash
CFG="GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work"

# ファイル検索
$CFG gws drive files list --params '{
  "q": "name contains '\''レポート'\'' and mimeType = '\''application/vnd.google-apps.spreadsheet'\''",
  "pageSize": 10,
  "fields": "files(id,name,mimeType,modifiedTime)"
}'

# ファイルアップロード（ヘルパー）
$CFG gws drive +upload /path/to/file.csv --params '{
  "name": "アップロード名",
  "parents": ["FOLDER_ID"]
}'

# フォルダ作成
$CFG gws drive files create --json '{
  "name": "フォルダ名",
  "mimeType": "application/vnd.google-apps.folder",
  "parents": ["PARENT_FOLDER_ID"]
}'

# ファイル移動
$CFG gws drive files update --params '{
  "fileId": "FILE_ID",
  "addParents": "DEST_FOLDER_ID",
  "removeParents": "SRC_FOLDER_ID"
}'

# 権限設定
$CFG gws drive permissions create --params '{
  "fileId": "FILE_ID"
}' --json '{
  "role": "reader",
  "type": "domain",
  "domain": "josys.com"
}'
```

### Slides

```bash
CFG="GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work"

# プレゼンテーション取得
$CFG gws slides presentations get --params '{
  "presentationId": "PRES_ID"
}'

# テキスト置換（batchUpdate）
$CFG gws slides presentations batchUpdate --params '{
  "presentationId": "PRES_ID"
}' --json '{
  "requests": [
    {
      "replaceAllText": {
        "containsText": {"text": "{{placeholder}}", "matchCase": true},
        "replaceText": "実際の値"
      }
    }
  ]
}'
```

### Gmail

```bash
CFG="GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work"

# 未読メール一覧（ヘルパー）
$CFG gws gmail +triage

# メッセージ読み取り（ヘルパー）
$CFG gws gmail +read --params '{"messageId": "MSG_ID"}'

# メール送信（ヘルパー）
$CFG gws gmail +send --json '{
  "to": "recipient@example.com",
  "subject": "件名",
  "body": "本文"
}'
```

### Calendar

```bash
CFG="GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work"

# 予定一覧（ヘルパー）
$CFG gws calendar +agenda

# イベント作成（ヘルパー）
$CFG gws calendar +insert --json '{
  "summary": "会議名",
  "start": {"dateTime": "2026-03-30T10:00:00+09:00"},
  "end": {"dateTime": "2026-03-30T11:00:00+09:00"},
  "attendees": [{"email": "user@josys.com"}]
}'
```

---

## カラーパレット（Sheets batchUpdate 用 RGB 0-1）

| 用途 | HEX | RGB (0-1) |
|------|-----|-----------|
| メイン黒（ヘッダー背景） | 434343 | `{"red": 0.26, "green": 0.26, "blue": 0.26}` |
| グレー（ゼブラ偶数行） | EFEFEF | `{"red": 0.94, "green": 0.94, "blue": 0.94}` |
| オレンジ（セカンダリ） | FF6D01 | `{"red": 1.0, "green": 0.43, "blue": 0.004}` |
| 白 | FFFFFF | `{"red": 1.0, "green": 1.0, "blue": 1.0}` |
| ボーダー | D0D0D0 | `{"red": 0.82, "green": 0.82, "blue": 0.82}` |

---

## エラーハンドリング

| Exit Code | 意味 | 対処 |
|-----------|------|------|
| 0 | 成功 | — |
| 1 | API エラー | レスポンスの `error.message` を確認 |
| 2 | 認証エラー | `gws auth status` → 再ログインを促す |
| 3 | バリデーション | パラメータ/JSON の形式を修正 |
| 4 | Discovery エラー | API が有効か確認（`enabled_apis` に含まれるか） |
| 5 | 内部エラー | `--dry-run` で再現確認、issue 報告 |

---

## Tips

- `gws schema <service.resource.method>` でパラメータの詳細を確認できる
- `--format csv` は BQ ロード用データ出力に便利
- `--page-all --page-limit 5 --format csv` でページネーション付き CSV 出力
- 複雑な JSON は `/tmp/gws_payload.json` に書き出してから `--json "$(cat /tmp/gws_payload.json)"` で渡す

---

## ハマりどころ（実戦で繰り返し発生した問題）

### Sheets: チャートの凡例がデータ値になる

**最頻出**。`addChart` の `startRowIndex` がヘッダー行を含んでいないと、凡例に列名ではなくデータの最初の値が表示される。

```
スプシの行番号（1-indexed）と API の rowIndex（0-indexed）は異なる。
スプシ row 36 = API startRowIndex 35
```

**対策**: チャート作成前に `+read` でヘッダー行の 0-indexed 位置を確認し、`startRowIndex` にその値を設定する。`headerCount: 1` も必ず指定。

### Sheets: データ書き換え後のチャート範囲ずれ

データ行を追加・削除した後、既存チャートの `startRowIndex` / `endRowIndex` は自動更新されない場合がある。

**対策**: データ構造を変更したらチャートを削除→再作成する。`updateChartSpec` で範囲だけ更新するより確実。

### Sheets: valueInputOption の選択

- `USER_ENTERED`: 数式・日付を解釈する。ただし `5400` のような数値が日付（1914-10-13）にパースされることがある
- `RAW`: 文字列としてそのまま書き込む。数値データはこちらが安全

**対策**: 数値データは `RAW`、数式や `%` 表示が必要な場合は `USER_ENTERED` を使い分ける。

### Sheets: deleteChart ではなく deleteEmbeddedObject

チャート削除は `deleteChart` ではなく `deleteEmbeddedObject` を使う：
```json
{"deleteEmbeddedObject": {"objectId": 12345678}}
```

### Slides: スライド順序変更後の要素編集

ユーザーがスライドを手動で並び替えた後、`pres['slides'][3]` のようなインデックス指定で要素を取得すると別のスライドを編集してしまう。

**対策**: 編集前に必ず全スライドの `objectId` とテキスト内容を取得し直し、`objectId` で特定する。インデックスに依存しない。

### Slides: ROUND_RECTANGLE の角丸は変更不可

Slides API では `ROUND_RECTANGLE` の角丸半径を変更できない。`shapeType` の事後変更も不可。

**対策**: 角ばったカードが必要なら最初から `RECTANGLE` で作成する。

### Slides: outline.solidFill は不正

Slides API の outline プロパティは `solidFill` ではなく `outlineFill` を使う：
```json
{"outline": {"outlineFill": {"solidFill": {"color": {"rgbColor": {...}}}}}}
```

### シェル: JSON 内の特殊文字

`--json` に直接渡す JSON に日本語、`¥`、シングルクォートが含まれるとシェルが壊れる。

**対策**: 必ずファイル経由で渡す：
```bash
cat > /tmp/payload.json << 'ENDJSON'
{"values": [["日本語テキスト"]]}
ENDJSON
gws sheets spreadsheets values update --json "$(cat /tmp/payload.json)"
```

### BQ CLI: 複数ステートメントの実行

`bq query < file.sql` で セミコロン区切りの複数ステートメントは正しく実行されない（SQL テキストが出力される）。

**対策**: パートごとにインラインで `bq query "..."` を実行するか、1ファイル1ステートメントにする。

### BQ CLI: UNION ALL 前の ORDER BY

UNION ALL の前に ORDER BY があると BQ が構文エラーを出す。

**対策**: 各パートの ORDER BY を削除し、最終 SELECT の後にのみ ORDER BY を置く。

### gws-operator エージェントの Bash 権限

gws-operator エージェントが Bash 実行を拒否されることがある。

**対策**: gws CLI 操作はエージェントに委任するより直接 Bash で実行する方が確実。エージェントは設計・計画に使い、実行は自分で行う。
