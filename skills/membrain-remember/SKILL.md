---
name: membrain-remember
description: Use when a durable lesson emerges that would save someone hours later - a non-obvious gotcha, a decision and its reasoning, a failure mode and its fix. Saves to the shared team brain as PENDING for the owner to review. Triggers on "remember this", "save that", "note for the team", and ALSO fires on your own initiative at the end of a piece of work that taught something non-obvious - propose it to the human while they are still here to judge it.
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

## Vet it in the conversation, not in a queue

The most useful thing you can do is **propose the lesson while the human is
still here**, and let them judge it in two seconds. A queue is where good
intentions go to wait; the person who was present when the lesson happened is
the cheapest and best reviewer it will ever get.

So when a piece of work ends and it taught something non-obvious, say so —
briefly — and offer it:

> That took a while because upstream 429s were being amplified by client
> retries. Worth saving for the team? (**save** / **edit** / **skip**)

One or two candidates at most, stated in a single line each. Then do exactly
what they say and move on.

### When to offer, and when to shut up

This only works if it is rare. An assistant that asks after every turn gets
waved through on reflex, and a rubber-stamped gate is no gate at all — the same
failure as an unread queue, wearing a different hat.

The bar is the **work**, not the clock. Offer when a piece of work has just
ended AND it taught something that was not visible from the code:

- a bug is root-caused and the cause was not obvious
- a decision got made between real alternatives, for a reason
- something failed in a way that will happen again to someone else
- the human says a version of "huh, I didn't know that"

At most one offer per completed piece of work, and most completed work should
produce none. If you are reaching for something to offer, there is nothing to
offer.

**Do not offer:**

- mid-task — never interrupt work in flight
- when the lesson is only that the code does what the code says
- again for something already skipped in this conversation. Skip means skip;
  do not re-ask in different words later.

**"Skip" is a normal, healthy answer.** Treat it as information, not rejection.
If offers are usually being skipped, you are offering too much — raise the bar
rather than asking more insistently.

### A limit worth knowing about

Do not anchor any of this to "per session". You cannot observe how long a
session has run, and **after a context compaction you may no longer remember
what you offered or that it was skipped** — so a session-scoped budget silently
becomes no budget at all in a long working session, which is the common case.

Anchor to the completed piece of work instead. That is visible in the moment
and does not depend on remembering earlier turns.

Skips are conversation-local: nothing is written when a candidate is declined,
so a skip cannot survive a compaction or a `/clear`. Rejections *are* durable —
a saved entry that gets rejected stays rejected in the store, keyed by content
hash. The practical consequence: if you re-offer something after a compaction,
you have lost nothing but the human's patience, so keep the bar high enough
that the question rarely comes up.

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
letting them believe it is how a review queue silently fills with thousands of
entries nobody reads.

An entry vetted in the conversation still lands pending, because the second
gate is about *sharing*, not quality — the owner decides what the team sees.
But the queue should now be short and mostly worth approving, because the
judgement already happened while someone was watching. If the queue is still
growing faster than it drains, you are offering too much: see the bar above.

If there is a backlog, point them at
[membrain-review-queue](../membrain-review-queue/SKILL.md).
