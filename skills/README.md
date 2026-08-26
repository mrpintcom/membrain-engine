# MemBrain skills for Claude Code

Four skills that make a shared, governed brain something an assistant actually
uses — rather than a server sitting in a config file that nothing ever calls.

| Skill | Fires when | Needs the gateway? |
|---|---|---|
| `membrain-recall` | before non-trivial work in familiar code | yes |
| `membrain-remember` | a durable lesson emerges | yes |
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

## Writing your own

A skill is a directory with a `SKILL.md` carrying `name` and `description`
frontmatter. The description is the trigger — write it as *when to use this*,
not *what this is*, because that is what gets matched against a user's request.
