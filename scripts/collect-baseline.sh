#!/usr/bin/env bash
# Mac mini 上で実行する、読み取り専用のベースライン採取スクリプト。
# 何も作成・変更・削除しない。出力は標準出力のみ。
#
# 使い方:
#   scripts/collect-baseline.sh [既存Sandbox名 ...] > baseline-$(date +%F).baseline.txt
#
# 注意:
#   - 出力には tailnet のホスト名などが含まれうる。docs/baseline.md へ転記する前に
#     必ず目視で確認し、秘密情報やペアリングURLを含めないこと。
#   - *.baseline.txt は .gitignore 対象(コミットされない)。

set -u

run() {
  echo
  echo "### \$ $*"
  if command -v "$1" >/dev/null 2>&1; then
    "$@" 2>&1 || echo "(exit status: $?)"
  else
    echo "(command not found: $1)"
  fi
}

echo "# collected at: $(date -u +%FT%TZ)"
echo "# host: $(uname -srm)"

run sbx --version
run sbx ls
run sbx policy ls
for name in "$@"; do
  run sbx policy ls "$name"
done
run tailscale version
run tailscale serve status
run sbx env --help
run sbx env plan --help
