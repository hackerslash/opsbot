# Message Queues & Event Streams

## Critical Gotchas

- **SQS visibility timeout**: messages become visible again if processing exceeds timeout; set higher than max processing time
- **RabbitMQ memory alarms**: when triggered, all connections blocked; purge queues or add memory
- **Kafka consumer lag**: rebalancing pauses all consumers in group; use static membership for long processing
- **SNS filter policies**: case-sensitive JSON matching; test with `publish --message-attributes` before production
- **DLQ not working**: `maxReceiveCount` applies per-message, not per-consumer; check DLQ has no consumers

## Quick Triage

```bash
# SQS queue depth
aws sqs get-queue-attributes --queue-url <url> --attribute-names ApproximateNumberOfMessages,ApproximateAgeOfOldestMessage

# RabbitMQ
curl -u guest:guest http://localhost:15672/api/queues/%2F/my-queue | jq '.messages,.consumers'

# Kafka consumer lag
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group my-group --describe

# Local services
systemctl status rabbitmq-server kafka
```

## AWS SQS

```bash
# Queue operations
aws sqs create-queue --queue-name my-queue --attributes VisibilityTimeout=30,MessageRetentionPeriod=345600
aws sqs list-queues; aws sqs get-queue-url --queue-name my-queue
aws sqs get-queue-attributes --queue-url <url> --attribute-names All

# DLQ
aws sqs set-queue-attributes --queue-url <main> --attributes '{"RedrivePolicy":"{\"deadLetterTargetArn\":\"<dlq-arn>\",\"maxReceiveCount\":\"3\"}"}'
aws sqs receive-message --queue-url <dlq> --max-number-of-messages 10 --visibility-timeout 0
aws sqs purge-queue --queue-url <dlq>

# Message operations
aws sqs send-message --queue-url <url> --message-body "text"
aws sqs receive-message --queue-url <url> --max-number-of-messages 10 --wait-time-seconds 20
aws sqs delete-message --queue-url <url> --receipt-handle <handle>
```

## AWS SNS

```bash
# Topic operations
aws sns create-topic --name my-topic
aws sns list-topics; aws sns list-subscriptions-by-topic --topic-arn <arn>

# Subscriptions
aws sns subscribe --topic-arn <arn> --protocol email --notification-endpoint user@example.com
aws sns subscribe --topic-arn <arn> --protocol sqs --notification-endpoint <queue-arn>
aws sns unsubscribe --subscription-arn <sub-arn>

# Publishing
aws sns publish --topic-arn <arn> --message "text"
aws sns publish --topic-arn <arn> --message file://msg.json --message-attributes '{"key":{"DataType":"String","StringValue":"val"}}'

# Filter policies (subscriptions receive only matching messages)
aws sns set-subscription-attributes --subscription-arn <arn> --attribute-name FilterPolicy --attribute-value '{"event_type":["order_created"]}'
```

## RabbitMQ

```bash
# Service management
systemctl status rabbitmq-server; systemctl restart rabbitmq-server
rabbitmqctl status; rabbitmqctl list_queues name messages consumers

# Queue operations
rabbitmqctl list_queues name messages consumers message_bytes memory
rabbitmqctl purge_queue my-queue
rabbitmqctl delete_queue my-queue

# Vhost and permissions
rabbitmqctl add_vhost production; rabbitmqctl set_permissions -p production myuser ".*" ".*" ".*"

# Memory alarms (blocks all connections)
rabbitmqctl status | grep mem_alarm
rabbitmqctl set_vm_memory_high_watermark 0.6

# Management API
curl -u guest:guest http://localhost:15672/api/overview
curl -u guest:guest http://localhost:15672/api/queues
curl -u guest:guest http://localhost:15672/api/queues/%2F/my-queue | jq '.messages,.consumers,.message_stats'
```

## Kafka

```bash
# Cluster status
kafka-broker-api-versions.sh --bootstrap-server localhost:9092
kafka-topics.sh --bootstrap-server localhost:9092 --list

# Topic operations
kafka-topics.sh --bootstrap-server localhost:9092 --create --topic my-topic --partitions 3 --replication-factor 2
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic my-topic
kafka-topics.sh --bootstrap-server localhost:9092 --alter --topic my-topic --partitions 6

# Consumer groups
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group my-group --describe
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group my-group --reset-offsets --to-earliest --topic my-topic --execute

# Produce/consume (testing)
kafka-console-producer.sh --bootstrap-server localhost:9092 --topic my-topic
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic my-topic --from-beginning

# Performance tuning
kafka-configs.sh --bootstrap-server localhost:9092 --entity-type topics --entity-name my-topic --alter --add-config retention.ms=86400000
kafka-configs.sh --bootstrap-server localhost:9092 --entity-type topics --entity-name my-topic --alter --add-config compression.type=lz4
```

## Troubleshooting

```bash
# Queue depth growing
aws cloudwatch get-metric-statistics --namespace AWS/SQS --metric-name ApproximateNumberOfMessagesVisible --dimensions Name=QueueName,Value=my-queue --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average
rabbitmqctl list_queues name messages consumers | grep my-queue
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group my-group --describe
# consumers running? processing time within visibility timeout? prefetch count too low? memory alarm? LAG column growing?

# Messages in DLQ
aws sqs receive-message --queue-url <dlq> --max-number-of-messages 10 --attribute-names All
# Check message attributes for OriginalMessageId, error details - malformed JSON, missing fields, exception in handler

# RabbitMQ memory alarm
rabbitmqctl status | grep mem_alarm
free -h; rabbitmqctl list_queues name messages message_bytes | sort -k3 -n -r
# purge queues, increase vm_memory_high_watermark, add memory, enable lazy queues

# SNS subscription not receiving
aws sns get-subscription-attributes --subscription-arn <arn>
aws sqs get-queue-attributes --queue-url <url> --attribute-names Policy
# subscription confirmed? filter policy matching? SQS queue policy allows SNS?
```
