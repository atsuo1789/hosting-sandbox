#!/usr/bin/env bash
# 「申し込み」を模したスクリプト
# 使い方: ./scripts/apply.sh <環境名> [レプリカ数]
set -euo pipefail

NAME="${1:?環境名を指定してください（例: team-b-dev）}"
REPLICAS="${2:-1}"

# --- 申し込み内容の検証（＝基盤側が担う責務の一つ） ---
if ! [[ "$NAME" =~ ^[a-z0-9]([-a-z0-9]{0,38}[a-z0-9])?$ ]]; then
  echo "環境名は英小文字・数字・ハイフンのみ（40文字以内）で指定してください" >&2
  exit 1
fi
if ! [[ "$REPLICAS" =~ ^[1-5]$ ]]; then
  echo "レプリカ数は1〜5で指定してください" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/gitops/apps/$NAME"
if [[ -e "$DIR" ]]; then
  echo "環境 $NAME は既に存在します" >&2
  exit 1
fi

# --- 申し込み内容から values.yaml を生成 ---
mkdir -p "$DIR"
cat > "$DIR/values.yaml" <<VALUES
# 申し込み: $NAME ($(date '+%Y-%m-%d %H:%M'))
replicaCount: $REPLICAS
relay:
  envName: $NAME
VALUES

# --- GitOpsリポジトリにコミット（以降はArgo CDが反映） ---
cd "$ROOT"
git add "gitops/apps/$NAME"
git commit -m "申し込み: $NAME (replicas=$REPLICAS)"
git push
echo "申し込み完了: $NAME （Argo CDが数分以内に反映します）"
