---
name: membrain-review-queue
description: Use to run the review ceremony over knowledge waiting to be approved or rejected - the human gate between what an assistant proposed and what the team sees. Triggers on "review my pending", "what's waiting for me", "clear the queue", or at the start of a session when a queue has been sitting unattended.
---

# Run the Review Ceremony

Every entry in the queue was proposed by an assistant and is invisible to your
team until a person decides. That person is you. This skill is the ceremony that
makes the decision happen instead of deferring it forever.

## Why this exists

A review queue with nobody reviewing is not a safety control — it is a
graveyard that looks like one. The failure is boringly consistent: entries
accumulate, the queue becomes intimidating, and it is never opened again.

Then the queue is quietly worthless, and so is the gate.

Two habits prevent it: **review little and often**, and **reject freely**.
A queue you can clear in ten minutes is a queue you will actually open.

## How

```
list_my_pending()
```

For each entry, make one of three calls. Do not defer — deferring is what
created the backlog.

**Approve** — it is true, durable, and useful to someone who is not you.
It becomes visible to the team, attributed to its owner.

**Reject** — any of:
- restates what the code or docs already say
- true only for that one conversation
- too vague to act on ("be careful with migrations")
- unverified speculation
- contains something that should not travel: credentials, customer data,
  an exploitable description of an unfixed weakness

**Edit, then approve** — the lesson is real but the writing will not survive
without its author. Tighten it and approve.

Rejection is not failure. A queue where everything is approved means nobody is
actually reading. Expect to reject a large share, and do not feel bad about it.

## Doing it well

Work in **batches by theme**, not top to bottom. Ten near-duplicate entries
about the same migration are one decision, not ten — approve the clearest,
reject the rest as duplicates.

Ask of each entry: *would a teammate hitting this in three months be glad this
was here?* Not "is it true" — plenty of true things are noise.

Watch for near-duplicates of already-approved entries. Two entries saying almost
the same thing is worse than one, because now a reader has to work out which is
current.

## Reporting back

Give the user a count, not a transcript: *"72 pending → 50 approved, 22
rejected."* Then name the one or two entries that were genuinely valuable, and
any theme worth noticing — if six entries describe the same gotcha, that is a
signal about the codebase, not just the queue.

If the queue is empty, say so in one line and stop. Do not manufacture work.

## The honest caveat

Do not use a `reviewed_at`-style timestamp to decide what has been reviewed —
in practice these columns are often never populated, and trusting one will tell
you a queue is clean when it is not. Use the **status transition** (pending →
approved/rejected) as the only real signal that a human made a decision.
