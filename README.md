# claude-statusline

Status line for Claude Code: folder, git branch, session name, model, context usage, and the 5-hour and 7-day rate
limits with their time left. For a subordinate agent session it shows the task ids it is running ("kit-agent: #54").

Requires `jq` and `git`.

## Install

The script stays in this repo; `~/.claude/statusline.sh`, the path Claude Code uses by default, is a symlink to it.

```bash
ln -s <path-to-this-repo>/scripts/statusline.sh ~/.claude/statusline.sh
```

In `~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }
```

A Claude Code plugin cannot install this: Claude Code ignores `statusLine` in `plugin.json`, and a plugin's
`settings.json` only accepts `agent` and `subagentStatusLine`.

## Task ids (task-table contract)

The agent's ids come from the `task-table` plugin (repo `claude-task-plugin`). The script looks for
`.claude/task-table.json` from the session's `cwd` upwards and reads only these fields:

- `tasks[].owner` — compared with the first word of `session_name`.
- `tasks[].state` — only `running` is shown.
- `tasks[].id` — printed as `#<id>`.

Without that file, or without running tasks for the session, the plain session name is shown.

Cache files: `/tmp/statusline-rate-cache.json` and `/tmp/statusline-rate-week-cache.json` keep the last rate-limit values
for the turns where Claude Code does not send them.
