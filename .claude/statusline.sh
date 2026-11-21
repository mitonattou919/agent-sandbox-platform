#!/usr/bin/env bash

input="$(cat)"

# jq は1回だけ呼んでまとめて受け取る (タブだと空欄が詰められてずれるので \x1f 区切り)
IFS=$'\x1f' read -r model cwd context pr five week < <(
  jq -r '[
    .model.display_name // "-",
    .workspace.current_dir // "-",
    .context_window.used_percentage // 0,
    .pr.number // "",
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.seven_day.used_percentage // ""
  ] | map(tostring) | join("\u001f")' <<<"$input"
)

repo="${cwd##*/}"

# detached HEAD の時は短いコミットハッシュを出す
branch="$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)"
if [ -z "$branch" ]; then
  branch="$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)"
fi
if [ -n "$branch" ]; then
  repo="$repo ($branch)"
fi

gh_identity="${SBX_GITHUB_IDENTITY:-}"
if [ -z "$gh_identity" ] && command -v gh >/dev/null 2>&1; then
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/gh-login"
  # キャッシュが無いか空か1時間以上古い時だけ取り直す (REST /user はアプリトークンで403になるのでGraphQL)
  if [ -z "$(find "$cache" -mmin -60 -size +0 2>/dev/null)" ]; then
    mkdir -p "${cache%/*}"
    # macOS には timeout が無いので gtimeout → 無ければタイムアウト無しで実行
    to=()
    if command -v timeout >/dev/null 2>&1; then
      to=(timeout 3)
    elif command -v gtimeout >/dev/null 2>&1; then
      to=(gtimeout 3)
    fi
    "${to[@]}" gh api graphql -f query='{viewer{login}}' --jq .data.viewer.login >"$cache" 2>/dev/null || : >"$cache"
  fi
  gh_identity="$(cat "$cache" 2>/dev/null)"
fi

printf '[%s] %s | gh:%s | ctx:%s%%' \
  "$model" \
  "$repo" \
  "${gh_identity:-unknown}" \
  "${context%.*}"

if [ -n "$five" ]; then
  printf ' | 5h:%s%%' "${five%.*}"
fi

if [ -n "$week" ]; then
  printf ' | 7d:%s%%' "${week%.*}"
fi

if [ -n "$pr" ]; then
  printf ' | pr#%s' "$pr"
fi

printf '\n'