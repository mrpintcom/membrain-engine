#!/usr/bin/env python3
"""mcp_observer.py — a deliberately honest MCP server that records what it is sent.

Wire this into any MCP client (Claude Code, Cursor, Claude Desktop, …) exactly
as you would a real third-party server. It advertises one plausible tool and,
for every JSON-RPC message it receives, appends the raw message to a log file.

It is a MEASUREMENT INSTRUMENT, not an attack. It does not exfiltrate anything,
does not open a socket, and writes only to a local file you choose. It is the
smallest honest answer to a question most people have never actually tested:

    when I connect an MCP server, what does the operator of that server see?

Run it yourself. Do not take anyone's word for it — including ours.

Usage (standalone, for a protocol smoke test):
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
        | MCP_OBSERVER_LOG=/tmp/obs.jsonl python3 mcp_observer.py

Usage (as a real MCP server), in your client's MCP config:
    {"mcpServers": {"notes": {"command": "python3",
     "args": ["/abs/path/mcp_observer.py"],
     "env": {"MCP_OBSERVER_LOG": "/abs/path/observed.jsonl"}}}}

Environment:
    MCP_OBSERVER_LOG   where to append observations (default: ./observed.jsonl)

stdout is the protocol channel and carries ONLY JSON-RPC. Everything the
instrument records goes to the log file; diagnostics go to stderr.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from typing import Any

# The spec revision we claim if the client does not state one. We echo the
# client's own value when it sends one, which is what a real server does and
# keeps this compatible across client versions.
FALLBACK_PROTOCOL_VERSION = "2025-06-18"

LOG_PATH = os.environ.get("MCP_OBSERVER_LOG", "observed.jsonl")

# One plausible, boring tool. The point of the experiment is that a tool does
# not need to look invasive to receive invasive arguments — the model decides
# what to put in `content`, and it is usually more than the user typed.
TOOLS = [
    {
        "name": "save_note",
        "description": (
            "Save a note for the user. Use this whenever the user asks to save, "
            "record, or remember something."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "Short title for the note"},
                "content": {"type": "string", "description": "Full note body"},
            },
            "required": ["title", "content"],
        },
    }
]


def observe(direction: str, payload: Any) -> None:
    """Append one observation. Never writes to stdout — that is the protocol."""
    record = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "direction": direction,
        "payload": payload,
    }
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError as exc:  # pragma: no cover - diagnostics only
        print(f"mcp_observer: could not write log: {exc}", file=sys.stderr)


def send(msg: dict) -> None:
    observe("server->client", msg)
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def result(req_id: Any, payload: dict) -> None:
    send({"jsonrpc": "2.0", "id": req_id, "result": payload})


def handle(msg: dict) -> None:
    method = msg.get("method")
    req_id = msg.get("id")

    # Notifications carry no id and must not be answered.
    if req_id is None and method is not None:
        return

    if method == "initialize":
        params = msg.get("params") or {}
        send(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": params.get("protocolVersion", FALLBACK_PROTOCOL_VERSION),
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "notes", "version": "1.0.0"},
                },
            }
        )
    elif method == "tools/list":
        result(req_id, {"tools": TOOLS})
    elif method == "tools/call":
        # A real notes server would persist here. We only acknowledge, so the
        # session continues naturally and the transcript stays realistic.
        name = (msg.get("params") or {}).get("name")
        result(
            req_id,
            {"content": [{"type": "text", "text": f"Saved via {name}."}], "isError": False},
        )
    elif method == "ping":
        result(req_id, {})
    elif method in ("resources/list", "prompts/list"):
        # Declared unsupported in capabilities, but some clients probe anyway.
        key = method.split("/")[0]
        result(req_id, {key: []})
    else:
        send(
            {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"},
            }
        )


def main() -> int:
    observe("session", {"event": "start", "log": os.path.abspath(LOG_PATH)})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            # Record the raw bytes rather than dropping them: what a client
            # sends when it malfunctions is itself worth seeing.
            observe("client->server", {"unparseable": line[:4000]})
            continue
        observe("client->server", msg)
        if isinstance(msg, dict):
            handle(msg)
    observe("session", {"event": "end"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
