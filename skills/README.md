# MemBrain skills for Claude Code

Four skills that make a shared, governed brain something an assistant actually
uses — rather than a server sitting in a config file that nothing ever calls.

| Skill | Fires when | Needs the gateway? |
|---|---|---|
| `membrain-recall` | before non-trivial work in familiar code | yes |
| `membrain-remember` | a durable lesson emerges — offers it in-conversation | yes |
| `membrain-review-queue` | knowledge is waiting on a human decision | yes |
| `membrain-mcp-audit` | "what can my MCP servers actually see?" | **no** |

`membrain-mcp-audit` is deliberately standalone. It runs a measurement against
your own setup and reports what it finds, including when the answer is "nothing
leaked" — which is what it found on Claude Code. You do not need to run MemBrain
to get value from it, and you should not have to.

## Install

```bash
git clone https://github.com/mrpintcom/membrain-engine.git /tmp/membrain-engine
mkdir -p ~/.claude/skills
cp -r /tmp/membrain-engine/skills/membrain-* ~/.claude/skills/
```

Restart Claude Code. Skills load from `~/.claude/skills/` (user-wide) or
`.claude/skills/` (per project — commit these to share them with your team).

## Connect the brain

Three of the four call the built-in `team-brain` MCP server. It ships in the
**community build and needs no licence**:

```bash
claude mcp add --transport http team-brain \
  "http://<gateway-host>:8001/mcp/v1/team-brain" \
  --header "x-membrain-api-key: <your key>"
```

Tools exposed: `search_team_knowledge`, `save_to_team_brain`, `list_my_pending`,
`recall_episodes`.

Without it, the three brain skills degrade honestly — they say the brain is
unreachable and get on with the task, rather than stalling or pretending.

## The idea behind them

Saving is not sharing. `save_to_team_brain` writes a **pending** entry that no
teammate sees until a person approves it, because memory amplifies — one bad
write becomes many bad reads.

That gate only works if someone opens the queue. The most common failure is not
a bad entry; it is a queue nobody reviews, which looks like a safety control and
is a graveyard. `membrain-review-queue` exists to make the ceremony small and
frequent enough that it actually happens.

## Optional: capture at compaction

`hooks/compaction-capture.sh` is a `PreCompact` hook. Compaction is the one
moment you *know* detail is about to be destroyed, which makes it the only time
"is anything here worth keeping?" is a well-posed question — and unlike "once
per session", it is a boundary the assistant can actually observe, because the
system announces it.

```bash
mkdir -p ~/.claude/hooks
cp /tmp/membrain-engine/skills/hooks/compaction-capture.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/compaction-capture.sh
```

Then in `~/.claude/settings.json` (merge with existing hooks, do not replace):

```json
{ "hooks": { "PreCompact": [ { "hooks": [
  { "type": "command",
    "command": "$HOME/.claude/hooks/compaction-capture.sh",
    "timeout": 5 } ] } ] } }
```

**It saves nothing.** Auto-compaction fires on volume, often while you are away
or mid-task, and a hook that wrote entries unsupervised would rebuild the exact
pile the review gate exists to prevent. It only makes sure the *opportunity*
survives the compaction — a human still judges, one turn later.

It nudges harder on a manual `/compact` (you are present and deliberate) than
on an automatic one (you may be mid-flow), records a pointer to the
pre-compaction transcript at `~/.claude/membrain/last-compaction`, and never
copies transcript content — duplicating a whole conversation to a second file
is a privacy liability, not a feature.

Verify it after installing by running `/compact` and watching whether the
assistant offers a lesson when the work warranted one, and stays quiet when it
did not.

## Writing your own

A skill is a directory with a `SKILL.md` carrying `name` and `description`
frontmatter. The description is the trigger — write it as *when to use this*,
not *what this is*, because that is what gets matched against a user's request.
