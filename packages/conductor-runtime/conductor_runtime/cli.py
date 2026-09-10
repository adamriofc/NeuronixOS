"""
Command-Line Interface entrypoint for NEURONIX Conductor Runtime Broker.
"""

import sys
import argparse
import asyncio
import signal
from pathlib import Path

from .server import ConductorServer, resolve_socket_path


def parse_args():
    parser = argparse.ArgumentParser(
        description="NEURONIX Conductor Capability Runtime & Zero-Idle Broker"
    )
    parser.add_argument(
        "--socket",
        type=str,
        default=None,
        help="Custom UNIX domain socket path (defaults to $XDG_RUNTIME_DIR/conductor.sock)"
    )
    return parser.parse_args()


async def run_server(socket_path: Path):
    server = ConductorServer(socket_path=socket_path)
    await server.start()
    print(f"NEURONIX Conductor Runtime active on {server.socket_path}")

    stop_event = asyncio.Event()

    def _sig_handler():
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _sig_handler)
        except NotImplementedError:
            pass

    try:
        await stop_event.wait()
    finally:
        print("Shutting down Conductor Runtime...")
        await server.stop()
        print("Conductor Runtime stopped cleanly.")


def main():
    args = parse_args()
    sock = resolve_socket_path(args.socket)
    try:
        asyncio.run(run_server(sock))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
