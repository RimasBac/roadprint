#!/usr/bin/env python3
"""Agent CLI. Use --operator only in a board-authorized SSH session."""
import argparse
import json
import os
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--operator', action='store_true')
sub = parser.add_subparsers(dest='command', required=True)
watch = sub.add_parser('watch')
watch.add_argument('pr', type=int)
watch.add_argument('--issue')
approve = sub.add_parser('approve')
approve.add_argument('pr', type=int)
approve.add_argument('sha')
approve.add_argument('--reason', required=True)
enable = sub.add_parser('enable')
enable.add_argument('value', choices=['true', 'false'])
args = parser.parse_args()
if args.operator:
    from coordinator import board_token
    token = board_token()
else:
    token = os.environ.get('PAPERCLIP_API_KEY')
if not token:
    raise SystemExit('Run inside an authenticated Paperclip agent session, or use --operator as the board.')
data = vars(args).copy()
data.pop('operator')
data.pop('command')
if args.command == 'enable':
    data = {'enabled': args.value == 'true'}
request = urllib.request.Request('http://127.0.0.1:3111/' + args.command,
    data=json.dumps(data).encode(), headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
with urllib.request.urlopen(request, timeout=180) as response:
    print(response.read().decode())
