#!/usr/bin/env python3

"""
Script to resolve given node paths to a node host:port pairs @ given ZooKeeper instance.
"""

import argparse
import json
import logging
import re
import sys
from ipaddress import ip_address
from json import JSONDecodeError

from kazoo.client import KazooClient
from kazoo.exceptions import NoAuthError, NoNodeError

logging.basicConfig()

__version__ = 1.0
__author__ = 'stuchl4n3k'

DEBUG = False


def debug(what: str):
    if DEBUG:
        print("[#]", what)


def say(what: str):
    print("[+]", what)


def err(what: str):
    print("[!]", what)


def parse_args():
    parser = argparse.ArgumentParser(description='Script to resolve given node paths to a node host:port pairs @ '
                                                 'given ZooKeeper instance. By {author}'.format(author=__author__))
    parser.add_argument('-v', '---version', action='version', version='%(prog)s {version}'.format(version=__version__))
    parser.add_argument('-V', '---verbose', help="be more verbose", action='store_true')
    parser.add_argument("ip", metavar='IP', help="ZooKeeper IP/hostname")
    parser.add_argument("-p", "--port", help="ZooKeeper port (defaults to 2181)", default=2181, type=int)
    parser.add_argument('nodepaths', metavar='PATH', help="node path you want to resolve", nargs='+')
    return parser.parse_args()


def zk_resolve_node(zk: KazooClient, node_path: str):
    host = None
    port = 9092

    try:
        data, stat = zk.get(node_path)
    except NoNodeError as e:
        debug('Node with given path \'%s\' does not exist. Skipping.' % node_path)
        return None, None
    except NoAuthError as e:
        debug('Node with given path \'%s\' requires authentication. Skipping.' % node_path)
        return None, None

    if not data:
        debug('No data available for node \'%s\'. Skipping.' % node_path)
        return None, None

    try:
        data = data.decode('utf-8')
    except UnicodeDecodeError as e:
        err('Could not decode UNICODE response for node path \'%s\' (got \'%s\'). Skipping' % (node_path, data))
        return None, None

    # Typically this would be JSON, but this is not a rule.
    if str(data).startswith('{') and str(data).endswith('}'):
        try:
            data = json.loads(data)
            if 'host' in data:
                host = data['host']
            if 'port' in data:
                port = data['port']
        except JSONDecodeError as e:
            err('Could not decode JSON response for node path \'%s\' (got \'%s\'). Skipping.' % (node_path, data))
            return None, None
    else:
        # OK, not JSON -> assume this is a raw IP or hostname and optional port.
        res = re.match(r'(.+):([0-9]+)', data)
        if res:
            host = res.group(1)
            port = res.group(2)
        else:
            host = data

    return host, port


def is_ip(host: str):
    try:
        ip_address(host)
        return True
    except ValueError:
        return False


def has_tld(host: str):
    return True if re.match(r'([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}', host, re.IGNORECASE) else False


def main(argv):
    global DEBUG

    # Parse inputs.
    args = parse_args()
    zk_ip = args.ip
    zk_port = args.port
    zk_node_paths = args.nodepaths
    DEBUG = args.verbose

    # Start KazooClient.
    zk = KazooClient(hosts=zk_ip + ':' + str(zk_port), read_only=True)
    zk.start()

    for node_path in zk_node_paths:
        host, port = zk_resolve_node(zk, node_path)
        if not host:
            continue
        elif host == 'localhost':
            debug('Host path \'%s\' resolves to loopback. Skipping.' % node_path)
            continue
        elif is_ip(host):
            ip = ip_address(host)

            if ip.is_loopback:
                debug('Host path \'%s\' resolves to loopback. Skipping.' % node_path)
                continue
            elif ip.is_private:
                debug('Host path \'%s\' resolves to a private range. Skipping.' % node_path)
                continue
        elif not has_tld(host):
            debug('Host path \'%s\' does not resolve to IP nor to a TLD (got \'%s\'). Skipping.' % (node_path, host))
            continue

        print('%s --> %s:%s' % (node_path, host, port))

    zk.stop()


if __name__ == "__main__":
    main(sys.argv)
