#!/usr/bin/env bash
# 段子工厂 v4：GitHub issue 进，PR 合并出。
# 用法: ./run.sh [--once]

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

EVERY=${EVERY:-10}
ONCE=0
[ "${1:-}" = "--once" ] && ONCE=1

export COMIC_TOOL="$ROOT/../comic-tools/comicgen.py"

WORKTREES="$ROOT/.worktrees"
INBOX="$ROOT/.inbox"
TRIAGE="$ROOT/.triage"
mkdir -p "$WORKTREES" "$INBOX" "$TRIAGE" "$ROOT/logs" "$ROOT/images"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

ask() {
  cmd --yolo -p "$(cat "prompts/$1.md")

$2" >> "$ROOT/logs/$3.log" 2>&1
}

gh_read() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    sleep 2
  done
  return 1
}

gh_write() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    sleep 2
  done
  return 1
}

create_pr() {
  local n="$1" branch="$2" attempt pr
  for attempt in 1 2 3; do
    if pr=$(gh pr view "$branch" --json number -q .number 2>/dev/null); then
      printf '%s\n' "$pr"
      return 0
    fi
    gh pr create --base main --head "$branch" \
      --title "add joke #$n" --body "Fixes #$n" >/dev/null 2>&1 || true
    if pr=$(gh pr view "$branch" --json number -q .number 2>/dev/null); then
      printf '%s\n' "$pr"
      return 0
    fi
    sleep 3
  done
  return 1
}

merge_pr() {
  local pr="$1" attempt
  for attempt in 1 2 3; do
    if gh pr merge "$pr" --squash --delete-branch >/dev/null 2>&1; then
      return 0
    fi
    if [ "$(gh pr view "$pr" --json state -q .state 2>/dev/null)" = "MERGED" ]; then
      return 0
    fi
    sleep 3
  done
  return 1
}

ensure_labels() {
  gh label create triaged --description "机器收过单，等人放行" --color 0e8a16 >/dev/null 2>&1 || true
  gh label create ready --description "人已放行，可以开工" --color 1d76db >/dev/null 2>&1 || true
  gh label create processing --description "机器正在做" --color fbca04 >/dev/null 2>&1 || true
  gh label create needs-human --description "机器做不下去，等人处理" --color d93f0b >/dev/null 2>&1 || true
  gh label create not-a-joke-idea --description "不是段子灵感，已关闭" --color 6a737d >/dev/null 2>&1 || true
}

# 单实例，防止两个工厂抢单
PIDFILE="$ROOT/.run.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  log "已经有一个工厂在跑（PID $(cat "$PIDFILE")），退出"
  exit 1
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
ensure_labels

triage_one() {
  local n="$1" decision comment
  log "收单 #$n"
  gh_read gh issue view "$n" --json title,body -q '.title + "\n\n" + .body' > "$TRIAGE/$n.raw.md" \
    || { log "#$n 读取失败，跳过"; return 0; }
  rm -f "$TRIAGE/$n.md"

  if ! ask triage "读 .triage/$n.raw.md，写 .triage/$n.md" "triage-$n"; then
    log "#$n 收单调用失败，跳过"
    return 0
  fi
  if [ ! -s "$TRIAGE/$n.md" ]; then
    log "#$n 没有写出收单结论，跳过"
    return 0
  fi

  decision=$(grep -oE '决定[:：][[:space:]]*(accept|reject)' "$TRIAGE/$n.md" \
    | head -1 | grep -oE 'accept|reject' || true)
  comment=$(grep -E '^评论[:：]' "$TRIAGE/$n.md" | head -1 \
    | sed 's/^评论[:：][[:space:]]*//' || true)

  if [ -z "$decision" ]; then
    gh issue comment "$n" --body "收单没跑出结论，请稍后再试。" >/dev/null 2>&1 || true
    gh_write gh issue edit "$n" --add-label "needs-human" >/dev/null || true
    log "#$n 收单结论格式不对，停下"
    return 0
  fi
  [ -n "$comment" ] || comment="收单完成。"

  if [ "$decision" = "reject" ]; then
    gh issue comment "$n" --body "$comment" >/dev/null 2>&1 || log "#$n 评论失败"
    gh_write gh issue edit "$n" --add-label "not-a-joke-idea" >/dev/null || true
    gh_write gh issue close "$n" --reason "not planned" >/dev/null || true
    log "#$n 已拒绝并关闭"
  else
    gh issue comment "$n" --body "$comment" >/dev/null 2>&1 || log "#$n 评论失败"
    gh_write gh issue edit "$n" --add-label "triaged" >/dev/null || true
    log "#$n 收单通过，等 ready"
  fi
  return 0
}

scan_triage() {
  local n count=0 list
  if ! list=$(gh_read gh issue list --state open --limit 100 --json number,labels \
    -q '.[] | select((.labels | map(.name) | index("triaged") | not) and (.labels | map(.name) | index("ready") | not) and (.labels | map(.name) | index("processing") | not) and (.labels | map(.name) | index("not-a-joke-idea") | not)) | .number'); then
    log "读取 issue 列表失败，跳过"
    return 0
  fi
  for n in $list; do
    triage_one "$n"
    count=$((count + 1))
    [ "$count" -ge 3 ] && break
  done
  if [ "$count" -eq 0 ]; then
    log "扫描新 issue … 无"
  fi
  return 0
}

draw() {
  local n="$1" wt="$2" attempt
  for attempt in 1 2 3; do
    log "draw.md 配图：${n}（第 ${attempt} 次）"
    ( cd "$wt" && ask draw "画 $n" "draw-$n-$attempt" ) || true
    if [ -s "$wt/images/$n.jpg" ] || [ -s "$wt/images/$n.png" ]; then
      return 0
    fi
    [ "$attempt" -lt 3 ] && sleep 10
  done
  return 1
}

fail() {
  local n="$1" msg="$2" branch="joke/$1" ahead
  log "#$n 失败：$msg"
  gh issue comment "$n" --body "$msg" >/dev/null 2>&1 || true
  gh issue edit "$n" --add-label "needs-human" --remove-label "processing" >/dev/null 2>&1 || true
  git worktree remove --force "$WORKTREES/$n" 2>/dev/null || true
  ahead=$(git rev-list --count "origin/main..$branch" 2>/dev/null || echo 1)
  if [ "$ahead" -eq 0 ]; then
    git branch -D "$branch" >/dev/null 2>&1 || true
  fi
}

process_one() {
  local n="$1" wt="$WORKTREES/$1" branch="joke/$1" round pr

  log "开工 #$n"
  gh_write gh issue edit "$n" --add-label "processing" >/dev/null \
    || { log "#$n 加 processing 标签失败，跳过"; return 0; }

  gh_read gh issue view "$n" --json body -q .body > "$INBOX/$n.md" \
    || { fail "$n" "读取 issue 失败。"; return 0; }
  git fetch origin main >/dev/null 2>&1

  if ! git worktree add "$wt" -b "$branch" origin/main >/dev/null; then
    fail "$n" "建 worktree 失败，分支可能已经存在。"
    return 0
  fi
  mkdir -p "$wt/issues" "$wt/pr" "$wt/.triage"
  cp "$INBOX/$n.md" "$wt/issues/$n.raw.md"
  cp "$TRIAGE/$n.md" "$wt/.triage/$n.md" 2>/dev/null || true

  ( cd "$wt" && ask idea "把 $n 收成工单" "idea-$n" ) \
    || { fail "$n" "选题失败，见 logs/idea-$n.log"; return 0; }

  ( cd "$wt" && ask write "处理 $n" "write-$n" ) \
    || { fail "$n" "写稿失败，见 logs/write-$n.log"; return 0; }

  for round in 1 2 3; do
    ( cd "$wt" && ask review "审 $n" "review-$n-$round" ) || true
    if grep -q '^结论: PASS' "$wt/pr/$n.md" 2>/dev/null; then
      break
    fi
    if [ "$round" -eq 3 ]; then
      fail "$n" "审稿连续三轮没通过，需要人工看一眼。"
      return 0
    fi
    ( cd "$wt" && ask write "处理 ${n}（按审稿意见返工）" "write-$n-$round" ) || true
  done

  if [ ! -s "$wt/pr/$n.entry.md" ]; then
    fail "$n" "审稿通过，但没有生成 entry 文件。"
    return 0
  fi

  author=$(gh_read gh issue view "$n" --json author -q .author.login || echo unknown)
  if ! grep -q '^灵感：' "$wt/pr/$n.entry.md"; then
    [ -n "$(tail -c 1 "$wt/pr/$n.entry.md")" ] && printf '\n' >> "$wt/pr/$n.entry.md"
    printf '灵感：[@%s](https://github.com/%s)\n' "$author" "$author" >> "$wt/pr/$n.entry.md"
  fi

  if ! grep -q "^## $n$" "$wt/joke.md"; then
    printf '\n' >> "$wt/joke.md"
    cat "$wt/pr/$n.entry.md" >> "$wt/joke.md"
  fi

  draw "$n" "$wt" || log "#$n 配图失败，跳过"

  ( cd "$wt" && ./verify.sh "$n" ) \
    || { fail "$n" "verify.sh 没过。"; return 0; }

  ( cd "$wt" && \
    git add joke.md images && \
    git -c user.name="joke-factory" \
        -c user.email="joke-factory@users.noreply.github.com" \
        commit -m "add joke #$n" >/dev/null && \
    git push -u origin "$branch" >/dev/null ) \
    || { fail "$n" "提交或 push 失败。"; return 0; }

  pr=$(create_pr "$n" "$branch") \
    || { fail "$n" "开 PR 失败。"; return 0; }
  log "#$n 已开 PR #$pr"

  if ! merge_pr "$pr"; then
    fail "$n" "PR #$pr 合并失败，分支和 PR 留着等人工。"
    return 0
  fi

  log "#$n 已合并 PR #$pr"
  git worktree remove --force "$wt" 2>/dev/null || true
  git branch -D "$branch" >/dev/null 2>&1 || true
  git checkout main >/dev/null 2>&1 || true
  git pull --ff-only >/dev/null 2>&1 || log "本地 main 拉取失败，请手动 git pull"
  gh issue edit "$n" --remove-label "processing" >/dev/null 2>&1 || true
  return 0
}

scan_ready() {
  local n
  if ! n=$(gh_read gh issue list --state open --label ready --limit 20 --json number,labels \
    -q '.[] | select((.labels | map(.name) | index("processing") | not) and (.labels | map(.name) | index("needs-human") | not)) | .number' \
    | head -1); then
    log "读取 ready 列表失败，跳过"
    return 0
  fi
  if [ -z "$n" ]; then
    log "扫描 ready … 无"
    return 0
  fi
  process_one "$n"
  return 0
}

log "段子工厂已启动 · $REPO"
while :; do
  scan_triage
  scan_ready
  [ "$ONCE" -eq 1 ] && break
  sleep "$EVERY"
done
