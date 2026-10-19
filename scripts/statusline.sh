#!/usr/bin/env bash

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
folder=$(basename "$cwd")

agent=$(echo "$input" | jq -r '.session_name // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')

# Git branch (skip optional locks)
branch=""
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

# Context percentage
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')

# 5-hour rate limit
CACHE_FILE="/tmp/statusline-rate-cache.json"
five_raw=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_pct="${five_raw:-0}"
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

if [ -n "$five_raw" ]; then
  echo "$input" | jq '{five_hour: .rate_limits.five_hour}' > "$CACHE_FILE"
elif { [ -z "$five_raw" ] || [ "$five_pct" = "0" ]; } && [ -f "$CACHE_FILE" ]; then
  five_pct=$(jq -r '.five_hour.used_percentage // 0' "$CACHE_FILE")
  five_resets=$(jq -r '.five_hour.resets_at // empty' "$CACHE_FILE")
fi

# 7-day (weekly) rate limit
WEEK_CACHE_FILE="/tmp/statusline-rate-week-cache.json"
week_raw=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_pct="${week_raw:-0}"
week_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -n "$week_raw" ]; then
  echo "$input" | jq '{seven_day: .rate_limits.seven_day}' > "$WEEK_CACHE_FILE"
elif { [ -z "$week_raw" ] || [ "$week_pct" = "0" ]; } && [ -f "$WEEK_CACHE_FILE" ]; then
  week_pct=$(jq -r '.seven_day.used_percentage // 0' "$WEEK_CACHE_FILE")
  week_resets=$(jq -r '.seven_day.resets_at // empty' "$WEEK_CACHE_FILE")
fi

# Color palette
C_FOLDER='\033[38;5;117m'       # Sky blue (folder)
C_BRANCH_MAIN='\033[38;5;83m'   # Bright green (main/master branch)
C_BRANCH_OTHER='\033[38;5;75m'  # Cornflower blue (other branches)
C_AGENT='\033[38;5;208m'        # Claude orange (agent/session name)
C_MODEL='\033[38;5;228m'        # Light yellow (model name)
C_CTX='\033[38;5;208m'          # Claude orange (context progress)
C_RATE='\033[38;5;117m'         # Sky blue (5h cycle + time left)
C_RATE_WEEK='\033[38;5;39m'     # Blue (weekly cycle + time left, matches "Update installed" message)
NC='\033[0m'

# Build a progress bar (10 chars wide) given a percentage value
build_bar() {
  local pct="$1"
  local width=10
  local filled bar_empty bar_str i
  filled=$(echo "$pct $width" | awk '{f=int($1/100*$2+0.5); if(f>$2)f=$2; print f}')
  bar_empty=$(( width - filled ))
  bar_str=""
  i=0; while [ "$i" -lt "$filled" ]; do bar_str="${bar_str}█"; i=$(( i + 1 )); done
  i=0; while [ "$i" -lt "$bar_empty" ]; do bar_str="${bar_str}░"; i=$(( i + 1 )); done
  printf '%s' "$bar_str"
}

# Time remaining from unix epoch (resets_at) to now
time_remaining() {
  local resets_at="$1"
  local now
  now=$(date +%s)
  local diff=$(( resets_at - now ))
  if [ "$diff" -le 0 ]; then
    echo "0m"
    return
  fi
  # 25h or more: days + hours. 24h or less: current hours + minutes format.
  if [ "$diff" -ge 90000 ]; then
    local d=$(( diff / 86400 ))
    local dh=$(( (diff % 86400) / 3600 ))
    echo "${d}d${dh}h"
    return
  fi
  local h=$(( diff / 3600 ))
  local m=$(( (diff % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then
    echo "${h}h${m}m"
  else
    echo "${m}m"
  fi
}

# Folder
printf "${C_FOLDER}%s${NC}" "$folder"

# Git branch
if [ -n "$branch" ]; then
  if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    printf " ${C_BRANCH_MAIN}(%s)${NC}" "$branch"
  else
    printf " ${C_BRANCH_OTHER}(%s)${NC}" "$branch"
  fi
fi

# Agent (session name). Subordinate agents show their running task ids from the workspace
# task table (.claude/task-table.json, found walking up from cwd; task-table plugin), matched
# by the session name's first word against each task's owner.
find_task_table() {
  local dir="$1"
  while [ -n "$dir" ]; do
    [ -f "$dir/.claude/task-table.json" ] && { printf '%s' "$dir/.claude/task-table.json"; return 0; }
    [ "$dir" = "/" ] && return 1
    dir=$(dirname "$dir")
  done
  return 1
}

if [ -n "$agent" ]; then
  agent_key="${agent%% *}"
  agent_task=""
  task_table=$(find_task_table "$cwd") && agent_task=$(jq -r --arg o "$agent_key" \
    '[.tasks[] | select(.owner == $o and .state == "running") | "#\(.id)"] | join(" ")' "$task_table" 2>/dev/null)
  if [ -n "$agent_task" ]; then
    printf " ${C_AGENT}%s: %s${NC}" "$agent_key" "$agent_task"
  else
    printf " ${C_AGENT}%s${NC}" "$agent"
  fi
fi

# Model
if [ -n "$model" ]; then
  printf " ${C_MODEL}%s${NC}" "$model"
fi

# Context progress bar
if [ -n "$used_pct" ]; then
  bar=$(build_bar "$used_pct")
  pct_display=$(printf "%.0f" "$used_pct")
  printf " ${C_CTX}[%s %s%%]${NC}" "$bar" "$pct_display"
fi

# 5-hour cycle progress bar + time remaining
if [ -n "$five_pct" ]; then
  bar5=$(build_bar "$five_pct")
  five_display=$(printf "%.0f" "$five_pct")
  time_left=""
  if [ -n "$five_resets" ]; then
    time_left=" $(time_remaining "$five_resets")"
  fi
  printf " ${C_RATE}5h:[%s %s%%%s]${NC}" "$bar5" "$five_display" "$time_left"
fi

# 7-day (weekly) cycle progress bar + time remaining
if [ -n "$week_pct" ]; then
  bar_week=$(build_bar "$week_pct")
  week_display=$(printf "%.0f" "$week_pct")
  time_left_week=""
  if [ -n "$week_resets" ]; then
    time_left_week=" $(time_remaining "$week_resets")"
  fi
  printf " ${C_RATE_WEEK}7d:[%s %s%%%s]${NC}" "$bar_week" "$week_display" "$time_left_week"
fi
