#!/bin/bash

DEBUG=1
ZOO_IP=''
ZOO_PORT=2181
KAFKA_PORT=9092
KAFKA_MAX_MESSAGES=10
KAFKA_TIMEOUT="3s"
KAFKA_MESSAGE_DELIM="\n\n"
KAFKACAT="kafkacat"
PYTHON="python3"

function count_lines {
    echo -n "$1" | grep -c '^'
}

function count_messages {
    echo -n "$1" | grep -c '^{"topic":'
}

function debug {
    if [[ ${DEBUG} == 1 ]]; then
        echo "[#] $1"
    fi
}

function say {
    echo "[+] $1"
}

function err {
    echo "[!] $1"
}

function zk_dump_paths {
    ZOO_IP=$1
    ZOO_PORT=$2

    echo 'dump' | nc -q 3 -w 3 ${ZOO_IP} ${ZOO_PORT} `# Request ZooKeeper server dump.` | \
        sed -n '/^Sessions/,$ p'    `# Take everything from Sessions line till EOF.` | \
        sed -n '1,/^Connections/ p' `# Take everything from start till optional Connections line.` | \
        sed -n 's/\t//p'            `# Node paths start with a TAB and are absolute.` | \
        sed -n -r 's/(.+)\s*/\1/p'  `# Trim trailing whitespace.`
}

function zk_resolve_paths {
    ZOO_IP=$1
    ZOO_PORT=$2
    NODE_PATHS=$3

    VERBOSE=''
    if [[ ${DEBUG} == 1 ]]; then
        VERBOSE='-V'
    fi
    ${PYTHON} ./zk-resolve-nodes.py ${VERBOSE} ${ZOO_IP} -p ${ZOO_PORT} ${NODE_PATHS}
}

function kafka_interrogate_node {
    NODE=$1

    debug "Interrogating node ${NODE}..."
    TOPICS=`kafkacat -b ${NODE} -L  | sed -n -r 's/^\s+topic "([^"]+)" .+:/\1/p'`
    TOPICS_COUNT=`count_lines "${TOPICS}"`

    say "Got ${TOPICS_COUNT} topics for node ${NODE}."
    if [[ ${TOPICS_COUNT} == 0 ]]; then
        continue
    fi

    # Attempt to consume messages for each topic.
    debug "Consuming messages max ${KAFKA_MAX_MESSAGES} for every topic..."
    for TOPIC in ${TOPICS}; do
        kafka_consume_topic ${NODE} ${TOPIC}
    done
}

function kafka_consume_topic {
    NODE=$1
    TOPIC=$2
    MESSAGES=`timeout ${KAFKA_TIMEOUT} ${KAFKACAT} -q -e -b ${NODE} -t ${TOPIC} -C -o beginning -c ${KAFKA_MAX_MESSAGES} -J -D "${KAFKA_MESSAGE_DELIM}"`
    if [[ ! -z ${MESSAGES} ]]; then
        MESSAGES_COUNT=`count_messages "${MESSAGES}"`
        say "Got ${MESSAGES_COUNT} messages in topic ${TOPIC} @ ${NODE}."
        echo "${MESSAGES}"
    fi
}

# Sanity checks:
# todo

# Input checks:
if [[ -z "$1" ]]; then
    echo "[!] No IP given!"
    exit 1
else
    ZOO_IP=$1
fi

if [[ ! -z "$2" ]]; then
    ZOO_PORT=$2
fi

# Probe the ZooKeeper instance to get a list of connected brokers.
debug "Requesting dump for ${ZOO_IP}:${ZOO_PORT} ..."
NODE_PATHS=`zk_dump_paths ${ZOO_IP} ${ZOO_PORT}`
NODE_PATHS_COUNT=`count_lines "${NODE_PATHS}"`
if [[ ${NODE_PATHS_COUNT} == 0 ]]; then
    say "No connected nodes found. Bailing out."
    exit 0
fi
say "Found ${NODE_PATHS_COUNT} connected nodes:"
echo "${NODE_PATHS}"

# Resolve each node path to IP:PORT pair.
say "Resolving node paths..."
RESOLVE_OUTPUT=`zk_resolve_paths ${ZOO_IP} ${ZOO_PORT} "${NODE_PATHS}"`
echo "${RESOLVE_OUTPUT}"

# Filter only the resolved nodes.
NODES=`echo "${RESOLVE_OUTPUT}" | grep -E -o --color=never '.+ \-\-> (.+):([0-9]+)' | sed -n -r 's/.+ \-\-> (.+):([0-9]+)/\1:\2/p'`
NODES_COUNT=`count_lines "${NODES}"`
if [[ ${NODES_COUNT} == 0 ]]; then
    say "Got no resolved nodes. Bailing out."
    exit 0
fi

# Attempt to connect to every node using kafkacat.
for NODE in ${NODES}; do
    kafka_interrogate_node ${NODE}
done