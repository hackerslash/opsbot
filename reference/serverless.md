# Serverless Operations

## Critical Gotchas

- **Lambda cold starts**: first invocation after idle or deployment takes 1-5s; use provisioned concurrency for latency-sensitive APIs
- **API Gateway 502**: often Lambda timeout or invalid HTTP response format; check Lambda logs first
- **Step Functions stuck**: failed states without catch/retry loop forever; always set timeout + retry/catch
- **EventBridge rule disabled**: silently stops triggering; check `State` field in describe-rule
- **Fargate task OOMKilled**: memory limit too low; check container exit code 137

## Quick Triage

```bash
aws lambda get-function --function-name <name>
aws logs tail /aws/lambda/<name> --since 30m --format short
aws logs tail /aws/apigateway/<api-id>/<stage> --since 1h --filter-pattern "ERROR"
aws stepfunctions list-executions --state-machine-arn <arn> --max-items 10
aws ecs describe-tasks --cluster <cluster> --tasks <task-id>
```

## Lambda

```bash
# Cold starts
aws logs filter-log-events --log-group-name /aws/lambda/<name> --filter-pattern "REPORT RequestId" --start-time $(date -u -d '1 hour ago' +%s)000 | jq '.events[].message' | grep "Init Duration"
aws lambda put-provisioned-concurrency-config --function-name <name> --provisioned-concurrent-executions 5

# Timeout
aws lambda get-function-configuration --function-name <name> | jq .Timeout
aws lambda update-function-configuration --function-name <name> --timeout 30

# Memory (also scales CPU)
aws logs filter-log-events --log-group-name /aws/lambda/<name> --filter-pattern "REPORT RequestId" | grep "Memory Used"
aws lambda update-function-configuration --function-name <name> --memory-size 1024

# Layers
aws lambda get-function --function-name <name> | jq '.Configuration.Layers'
aws lambda update-function-configuration --function-name <name> --layers <layer-arn>

# X-Ray tracing
aws lambda update-function-configuration --function-name <name> --tracing-config Mode=Active
aws xray get-trace-summaries --start-time $(date -u -d '1 hour ago' +%s) --end-time $(date -u +%s)

# Deployment
aws lambda update-function-code --function-name <name> --zip-file fileb://function.zip
aws lambda publish-version --function-name <name>
aws lambda create-alias --function-name <name> --name prod --function-version 2
aws lambda update-alias --function-name <name> --name prod --function-version 3

# Concurrency
aws lambda get-function-concurrency --function-name <name>
aws lambda put-function-concurrency --function-name <name> --reserved-concurrent-executions 10
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name ConcurrentExecutions --dimensions Name=FunctionName,Value=<name> --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Maximum
```

## API Gateway

```bash
# Logs (must enable in stage settings first)
aws logs tail /aws/apigateway/<api-id>/<stage> --since 1h
aws logs filter-log-events --log-group-name /aws/apigateway/<api-id>/<stage> --filter-pattern "status: 5??"

# Throttling
aws apigateway get-stage --rest-api-id <api-id> --stage-name prod | jq '.throttle'
aws apigateway update-stage --rest-api-id <api-id> --stage-name prod --patch-operations op=replace,path=/throttle/rateLimit,value=1000
aws apigateway update-stage --rest-api-id <api-id> --stage-name prod --patch-operations op=replace,path=/throttle/burstLimit,value=2000

# Custom authorizer
aws apigateway test-invoke-authorizer --rest-api-id <api-id> --authorizer-id <id> --headers Authorization="Bearer <token>"

# Deployment
aws apigateway get-deployments --rest-api-id <api-id>
aws apigateway create-deployment --rest-api-id <api-id> --stage-name prod
aws apigateway create-deployment --rest-api-id <api-id> --stage-name prod --canary-settings percentTraffic=10
aws apigateway update-stage --rest-api-id <api-id> --stage-name prod --patch-operations op=replace,path=/canarySettings/percentTraffic,value=50
```

## Step Functions

```bash
# Executions
aws stepfunctions list-executions --state-machine-arn <arn> --status-filter RUNNING
aws stepfunctions describe-execution --execution-arn <arn>
aws stepfunctions get-execution-history --execution-arn <arn> --max-results 100

# Stop stuck execution
aws stepfunctions stop-execution --execution-arn <arn> --cause "manual intervention"

# State inspection
aws stepfunctions get-execution-history --execution-arn <arn> | jq '.events[] | select(.type == "TaskFailed")'
```

## EventBridge

```bash
# Rules
aws events describe-rule --name <rule>
aws events list-targets-by-rule --rule <rule>
aws events list-rules --name-prefix prod-

# Enable/disable
aws events enable-rule --name <rule>
aws events disable-rule --name <rule>

# Test pattern matching
aws events test-event-pattern --event-pattern '{"source":["myapp"],"detail-type":["order"]}' --event '{"source":"myapp","detail-type":"order","detail":{}}'

# DLQ for failed targets
aws events describe-rule --name <rule> | jq '.Targets[].DeadLetterConfig'
aws sqs receive-message --queue-url <dlq-url> --max-number-of-messages 10
```

## Fargate

```bash
# Task status
aws ecs list-tasks --cluster <cluster>
aws ecs describe-tasks --cluster <cluster> --tasks <task-id>

# Logs
aws logs tail /ecs/<cluster>/<task-family> --since 30m --follow

# Resource tuning (update task definition)
aws ecs describe-task-definition --task-definition <family> | jq '.taskDefinition.cpu,.taskDefinition.memory'
aws ecs register-task-definition --family <family> --cpu 1024 --memory 2048 --container-definitions file://containers.json
aws ecs describe-tasks --cluster <cluster> --tasks <task-id> | jq '.tasks[].containers[].reason'
```

## Troubleshooting

```bash
# Lambda timeout
aws logs filter-log-events --log-group-name /aws/lambda/<name> --filter-pattern "Task timed out"
# increase timeout, optimize code, check downstream dependencies

# API Gateway 502
aws logs tail /aws/apigateway/<api-id>/<stage> --since 1h | grep 502
# Lambda timeout, invalid response format, Lambda permission issue - check Lambda logs for actual error

# Step Functions execution stuck
aws stepfunctions describe-execution --execution-arn <arn> | jq '.status'
aws stepfunctions get-execution-history --execution-arn <arn> | jq '.events[-5:]'
# stop-execution, add timeout + retry/catch to state definition

# EventBridge not triggering
aws events describe-rule --name <rule> | jq '.State'
aws events list-targets-by-rule --rule <rule>
aws lambda get-policy --function-name <name> | jq
# rule ENABLED? EventBridge has Lambda permission? test-event-pattern

# Fargate task OOMKilled (exit code 137)
aws ecs describe-tasks --cluster <cluster> --tasks <task-id> | jq '.tasks[].containers[].exitCode'
aws logs tail /ecs/<cluster>/<task-family> --since 1h | grep -i "out of memory"
# increase memory in task definition
```
