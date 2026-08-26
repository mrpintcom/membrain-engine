---
name: membrain-recall
description: Use BEFORE starting non-trivial work in a codebase your team has worked in before - searches the shared team brain for decisions, gotchas and constraints already established, so you don't re-derive or contradict them. Triggers on "how do we", "what did we decide", "has anyone", or starting a new feature/investigation.
---

# Recall What The Team Already Knows

Most wasted work is rediscovery. Someone already found the gotcha, made the
decision, or hit the wall — it just never reached you. The team brain is where
that lands. Check it before you spend an hour re-deriving it.

## When to use this

- Starting a feature, migration, or investigation in unfamiliar code
- About to make an architectural choice someone may already have made
- You hit something surprising and want to know if it is known
- The user asks "how do we…", "what did we decide about…", "has anyone…"

**Do not** use it for questions the code answers directly. Read the code for
what the code says. Use the brain for what the code *cannot* say: why a choice
was made, what was tried and abandoned, what breaks in production.

## How

Call `search_team_knowledge` with a specific query. Prefer the concrete noun
over the category — `"alembic migration bootstrap empty database"` finds the
entry; `"database"` finds forty.

```
search_team_knowledge(query="<specific thing you are about to do>")
```

Run two or three searches with different phrasings before concluding nothing is
there. Entries were written by people describing a problem in their own words,
not indexed by yours.

## Reading what comes back

Each entry carries an owner and a status. Treat them differently:

- **Approved, shared** — someone reviewed this and chose to publish it. Use it.
- **Owner-private** — you may see your own. Do not assume teammates know it.

An entry is a record of what was true when someone wrote it. If it names a
file, function, or flag, **verify that still exists** before acting on it. A
confidently stale memory is worse than no memory, and stale entries are the
main way a shared brain loses trust.

## What to do with what you find

Say what you found and where it came from, in one line — "the team brain has a
note on this: migrations bootstrap on an empty DB, don't run `create_all`". Then
proceed. Do not paste whole entries into the conversation; summarise and cite.

If you find something that is now **wrong**, that is worth more than finding
something right. Say so explicitly and offer to correct it with
[membrain-remember](../membrain-remember/SKILL.md).

## If the brain is not reachable

Say so plainly and continue with the task. A missing brain is a degraded
search, not a blocker — never stall real work waiting on it, and never
pretend you checked when the call failed.
