import argparse
import logging
import os
import signal
import sys
import threading
import time
from pathlib import Path

from fishd import discovery
from fishd.server import make_server
from fishd.service import Service
from fishd.state import State

DEFAULT_STATE_DIR = Path.home() / "Library" / "Application Support" / "FishStack"
HOST = "127.0.0.1"


def stop_serving(service, root):
    service.shutdown()
    discovery.withdraw(root, os.getpid())


def exit_with_parent(stop):
    # The menu-bar app owns this process. When it dies, the server must not outlive it.
    parent = os.getppid()

    def watch():
        while True:
            time.sleep(1)
            if os.getppid() != parent:
                stop()
                os._exit(0)

    threading.Thread(target=watch, daemon=True).start()


def serve(args):
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stderr)
    state = State(args.state_dir)
    service = Service(state)
    server = make_server(HOST, args.port, service, state.api_key())
    port = server.server_address[1]
    service.origin = "http://%s:%d" % (HOST, port)
    root = discovery.home(args.home)
    if not discovery.publish(root, os.getpid(), port):
        logging.getLogger("fishd").warning(
            "another FishStack already publishes leases under %s; this server on port %d serves models but takes no leases",
            root,
            port,
        )

    def stop():
        stop_serving(service, root)

    def terminate(signum, frame):
        stop()
        os._exit(0)

    signal.signal(signal.SIGTERM, terminate)
    exit_with_parent(stop)
    service.start()
    logging.getLogger("fishd").info("serving on http://%s:%d, leases published under %s", HOST, port, root)
    server.serve_forever()


def main(argv=None):
    parser = argparse.ArgumentParser(prog="fishd", description="Serve the decision and embedding models on this Mac.")
    commands = parser.add_subparsers(dest="command", required=True)
    serve_parser = commands.add_parser("serve", help="run the model server on 127.0.0.1")
    serve_parser.add_argument("--port", type=int, default=8089)
    serve_parser.add_argument("--state-dir", type=Path, default=DEFAULT_STATE_DIR)
    serve_parser.add_argument("--home", type=Path, default=None, help="where run/daemon.json is written (default: $FISH_STACK_HOME or ~/.fishStack)")
    args = parser.parse_args(argv)
    if args.command == "serve":
        serve(args)


if __name__ == "__main__":
    main()
