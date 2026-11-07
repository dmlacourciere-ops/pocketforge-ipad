"""Serve only a compiled PocketForge web bundle, optionally on a private LAN."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from ipaddress import IPv4Address, IPv4Network
from pathlib import Path
import argparse
import socket


def private_lan_address():
    # UDP connect selects an OS route; no packet is sent without send/sendto.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.connect(('192.0.2.1', 9))
        address = probe.getsockname()[0]
    ip = IPv4Address(address)
    ranges = ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')
    if not any(ip in IPv4Network(network) for network in ranges):
        raise SystemExit('No private LAN address selected. Connect to your home Wi-Fi, then retry.')
    return address


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lan', action='store_true', help='Bind to the private LAN address for your own iPad.')
    parser.add_argument('--directory', type=Path, default=Path(__file__).resolve().parent / 'web')
    parser.add_argument('--port', type=int, default=8769)
    args = parser.parse_args()
    root = args.directory.resolve(strict=True)
    if not (root / 'flutter_bootstrap.js').is_file() or not (root / 'index.html').is_file():
        raise SystemExit('Point --directory at a compiled Flutter web bundle, or extract the browser ZIP first.')
    if any(path.is_symlink() for path in root.rglob('*')):
        raise SystemExit('The static app bundle must not contain linked files.')
    address = private_lan_address() if args.lan else '127.0.0.1'
    handler = partial(SimpleHTTPRequestHandler, directory=str(root))
    server = ThreadingHTTPServer((address, args.port), handler)
    print(f'\nPocketForge browser build: http://{address}:{args.port}\n', flush=True)
    if args.lan:
        print('Open that address in Safari on your iPad, on the same home network.', flush=True)
    print('This PC serves app files. Agent tools and game execution run in the browser.\n'
          'DeepSeek inference uses its API. Enter the key in PocketForge Settings.\n'
          'Keep this window open for loading/reloading. Ctrl+C stops the server.\n', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
