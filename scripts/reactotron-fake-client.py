#!/usr/bin/env -S uv run --quiet --with websockets python3
"""A React Native app, as far as the Reactotron relay is concerned.

Connects to the relay, introduces itself, registers a custom command, and
answers every request the State, REPL and Commands screens make — the way
`reactotron-redux` does. It is how those three screens were verified without
ever rendering them, and it is the reproduction for the >64 KB stream bug
(see `--big`).

    ./scripts/reactotron-fake-client.py            # a normal client
    ./scripts/reactotron-fake-client.py --big      # answer repl with 200 KB

Open Reactotron in either app first: the relay binds 9090 only once something
subscribes to the topic, so with nothing watching there is nothing to connect
to. Whichever app is holding 9090 is the one this talks to, which is worth
remembering when both are running.
"""
import asyncio
import functools
import json
import sys

import websockets

# Unbuffered: this script blocks forever waiting for commands, so a buffered
# stdout shows nothing at all and reads as "it did not connect".
print = functools.partial(print, flush=True)  # noqa: A001

STORE = {
    "user": {"name": "Ada", "id": 42},
    "cart": {"total": 0, "items": []},
    "flags": {"beta": True},
}

BIG = "--big" in sys.argv


def dig(store, path):
    node = store
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


async def main() -> None:
    async with websockets.connect("ws://127.0.0.1:9090") as socket:
        async def say(kind, payload):
            await socket.send(json.dumps({"type": kind, "payload": payload}))
            print("->", kind)

        await say("client.intro", {"clientId": "fake-client", "name": "Fake Client"})
        # A real client announces its custom commands unprompted, on connect.
        await say("customCommand.register", {
            "id": 1, "command": "ping", "title": "Ping the server",
            "args": [{"name": "host", "type": "string"}],
        })
        print("connected — open Reactotron and press things")

        watching: list[str] = []
        while True:
            command = json.loads(await socket.recv())
            kind, payload = command.get("type"), command.get("payload")
            body = payload if isinstance(payload, dict) else {}
            print("<-", kind)

            if kind == "state.values.request":
                await say("state.values.response", {"value": STORE, "valid": True})
            elif kind == "state.backup.request":
                await say("state.backup.response", {"state": STORE})
            elif kind == "state.values.subscribe":
                watching = list(body.get("paths") or [])
                if watching:
                    await say("state.values.change", {
                        "changes": [{"path": p, "value": dig(STORE, p)} for p in watching]})
            elif kind == "state.action.dispatch":
                action = body.get("action") or {}
                if action.get("type") == "INCREMENT":
                    STORE["cart"]["total"] += 1
                await say("state.action.complete", {"name": action.get("type")})
                if watching:
                    await say("state.values.change", {
                        "changes": [{"path": p, "value": dig(STORE, p)} for p in watching]})
            elif kind == "state.restore.request":
                STORE.clear()
                STORE.update(body.get("state") or {})
                await say("state.restore.response", {"ok": True})
            elif kind == "repl.ls":
                await say("repl.ls.response", ["store", "api"])
            elif kind == "repl.execute":
                # --big is the stream-socket reproduction: a payload over ~64 KB
                # never reaches the timeline and takes the subscription with it.
                if BIG:
                    await say("repl.execute.response", {"blob": "x" * 200_000})
                elif payload == "store.getState()":
                    await say("repl.execute.response", STORE)
                else:
                    await say("repl.execute.response", None)
            elif kind == "custom":
                await say("log", {
                    "level": "debug",
                    "message": f"ran {body.get('command')} {body.get('args')}",
                })


try:
    asyncio.run(main())
except KeyboardInterrupt:
    pass
