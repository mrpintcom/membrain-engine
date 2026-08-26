---
name: membrain-remember
description: Use when a durable lesson emerges that would save someone hours later - a non-obvious gotcha, a decision and its reasoning, a failure mode and its fix. Saves to the shared team brain as PENDING for the owner to review. Triggers on "remember this", "save that", "note for the team", or after debugging something surprising.
---

# Save a Lesson to the Team Brain

A memory system that stores everything is a search problem with extra steps.
This one is deliberately narrow: save the things that would have saved *you*
an hour, and let a human decide what the team sees.

## The rule that makes this work

**Nothing you save is visible to teammates until the owner approves it.**

`save_to_team_brain` writes a **pending** entry. It sits in a review queue until
a person reads it and shares it. That is not friction to be worked around — it
is the reason the brain stays worth reading. Memory amplifies: one bad write
becomes many bad reads.

So: save freely, but write as if a reviewer will read it. Because one will.

## What is worth saving

- A gotcha that cost real time and is not visible from the code
- A decision **and its reasoning** — "we chose X over Y because Z"
- A failure mode and the fix that actually worked
- A constraint that is not written down anywhere else

## What is not

- Anything the code already says. Do not narrate the codebase.
- Anything in git history, the changelog, or an existing doc
- Things true only for this conversation
- Speculation, or a fix you have not verified

If you are unsure, ask: *would a teammate hitting this in three months be glad
someone wrote it down?* If not, skip it.

## How

```
save_to_team_brain(
  content="<the lesson, stated so it is useful without this conversation>",
  ...
)
```

Write it **standalone**. "The retry logic is wrong" is useless in six weeks.
"Upstream 429s were amplified by 3x20s client retries, causing 60s hangs and DB
pool exhaustion; fixed by UPSTREAM_MAX_RETRIES=0" survives without you.

State the **why**, not just the what. The what is often recoverable from code.
The why almost never is.

## Before you save: check what you are about to send

The entry leaves this machine. Do not put in it:

- credentials, tokens, keys, connection strings — reference the env var instead
- customer or personal data
- anything a client contract covers
- an exploitable description of an unfixed vulnerability in your own systems

The gateway scans for PII on the way through, but a scanner is a backstop, not
a licence to be careless. Name the file and the shape of the problem; leave the
secret where it lives.

## After saving

Tell the user plainly: **saved as pending, not yet visible to the team, needs
owner review.** People assume "saved" means "shared". It does not, and quietly
letting them believe it is how a review queue silently fills with 4,000 entries
nobody reads.

Then point them at [membrain-review-queue](../membrain-review-queue/SKILL.md).
