#!/bin/bash
# gws CLI の破壊的操作（delete, trash, remove）をブロックする PreToolUse Hook
#
# ブロック対象:
#   - drive files delete / drive files trash
#   - gmail users messages delete / trash / batchDelete
#   - calendar events delete
#   - sheets spreadsheets delete (シート削除)
#   - drive permissions delete
#   - 全サービスの delete/trash/remove メソッド
#
# 許可:
#   - --dry-run 付きのコマンドは全て許可
#   - 読み取り系（get, list, +read, +triage, +agenda）は全て許可

input=$(cat)

# Extract command from Claude Code's tool_input
command=$(echo "$input" | jq -r '.tool_input.command // empty')
# クォート内文字列を除去して誤検知を防止
cmd_stripped=$(echo "$command" | sed "s/'[^']*'//g" | sed 's/"[^"]*"//g')

# Only process gws commands
if ! echo "$cmd_stripped" | grep -qE '(^|\s)gws\s'; then
  exit 0
fi

# Allow --dry-run (safe validation only)
if echo "$cmd_stripped" | grep -q '\-\-dry-run'; then
  exit 0
fi

# Block destructive operations
# Pattern: gws <service> ... delete|trash|remove|batchDelete
if echo "$cmd_stripped" | grep -qiE '\b(delete|trash|remove|batchDelete)\b'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "gws CLI の破壊的操作（delete/trash/remove）はブロックされています。手動で実行してください: '"$(echo "$command" | sed 's/"/\\"/g')"'"
    }
  }'
  exit 0
fi

# Block emptying Gmail trash (permanent deletion)
if echo "$cmd_stripped" | grep -qiE 'gmail.*users.*messages.*empty'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Gmail のゴミ箱を空にする操作はブロックされています。手動で実行してください。"
    }
  }'
  exit 0
fi
