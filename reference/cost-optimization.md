# Cost Optimization

## Critical gotchas

- **Right-sizing without monitoring fails** - need 14+ days CloudWatch metrics, not guesses
- **Spot termination must be handled** - 2-min warning via instance metadata
- **RI/Savings Plans lock you in** - buy only for proven steady-state workloads (12+ months stable)
- **Orphaned resources are silent drains** - unattached EBS ($0.10/GB/mo), idle EIPs ($3.60/mo), unused ALBs ($16/mo)
- **Lambda memory affects CPU** - doubling memory doubles CPU, often cheaper per execution
- **Cross-region data transfer costs** - $0.02/GB adds up fast

## Quick cost check

```bash
# Current month spend by service
aws ce get-cost-and-usage --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) --granularity MONTHLY --metrics BlendedCost --group-by Type=DIMENSION,Key=SERVICE

# Daily spend last 7 days
aws ce get-cost-and-usage --time-period Start=$(date -u -d '7 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) --granularity DAILY --metrics BlendedCost
```

## Right-sizing EC2

```bash
# Get recommendations
aws compute-optimizer get-ec2-instance-recommendations

# CloudWatch CPU (last 14 days)
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value=i-xxxxx --start-time $(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 86400 --statistics Average,Maximum

# CPU < 20% avg, < 40% peak (14+ days) → downsize (m5.xlarge → m5.large)
# CPU > 70% sustained → upsize or add instances

# Resize
aws ec2 stop-instances --instance-ids i-xxxxx
aws ec2 wait instance-stopped --instance-ids i-xxxxx
aws ec2 modify-instance-attribute --instance-id i-xxxxx --instance-type '{"Value": "m5.large"}'
aws ec2 start-instances --instance-ids i-xxxxx

# Monitor 24-48h post-resize, reverse if service degrades
```

## Spot instances

```bash
# Request spot (70-90% cheaper)
aws ec2 request-spot-instances --spot-price "0.05" --instance-count 1 --type "one-time" --launch-specification '{
  "ImageId": "ami-xxx",
  "InstanceType": "m5.large",
  "KeyName": "mykey",
  "SecurityGroupIds": ["sg-xxx"],
  "SubnetId": "subnet-xxx"
}'

# batch jobs, CI/CD runners, dev/test, stateless workers - not for databases, SPOFs, long-running stateful

# Interruption warning (2-min, via metadata on spot instance)
curl -s http://169.254.169.254/latest/meta-data/spot/instance-action

# Spot fleet (multiple instance types for availability)
aws ec2 request-spot-fleet --spot-fleet-request-config file://fleet.json
```

## Reserved Instances / Savings Plans

```bash
# Check RI coverage
aws ce get-reservation-coverage --time-period Start=$(date -u -d '30 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) --granularity MONTHLY

# Purchase recommendations
aws ce get-reservation-purchase-recommendation --service EC2 --lookback-period-in-days SIXTY_DAYS --term-in-years ONE_YEAR --payment-option NO_UPFRONT

# 1yr RI = flexibility, 3yr RI = max discount, Savings Plans = flexible across Lambda/Fargate
# Buy only for proven steady-state (12+ months stable): databases, primary caches, core infra
```

## Waste identification

```bash
# Unattached EBS volumes ($0.10/GB/mo)
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[*].[VolumeId,Size,VolumeType]' --output table

# Idle Elastic IPs ($3.60/mo each)
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]' --output table

# Unused ALBs ($16/mo + $0.008/LCU-hour)
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerName,DNSName]'
aws elbv2 describe-target-health --target-group-arn <arn>

# Old EBS snapshots (>90 days)
aws ec2 describe-snapshots --owner-ids self --query "Snapshots[?StartTime<'$(date -u -d '90 days ago' +%Y-%m-%d)'].[SnapshotId,StartTime,VolumeSize]" --output table

# S3 lifecycle to Glacier
aws s3api put-bucket-lifecycle-configuration --bucket <bucket> --lifecycle-configuration '{
  "Rules": [{
    "Id": "archive-logs",
    "Status": "Enabled",
    "Prefix": "logs/",
    "Transitions": [{"Days": 90, "StorageClass": "GLACIER"}],
    "Expiration": {"Days": 365}
  }]
}'
```

## Lambda cost optimization

```bash
# Lambda cost last 30 days
aws ce get-cost-and-usage --time-period Start=$(date -u -d '30 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) --granularity MONTHLY --filter '{"Dimensions": {"Key": "SERVICE", "Values": ["AWS Lambda"]}}' --metrics BlendedCost

# Memory tuning: doubling memory doubles CPU
# too little memory → slow execution, high duration cost
# too much memory → fast execution, high memory cost
# Optimal: lowest memory where duration is acceptable

# Get duration stats
aws logs filter-log-events --log-group-name /aws/lambda/<func> --start-time $(date -u -d '7 days ago' +%s)000 --filter-pattern "[report_type=REPORT, ...]" --limit 100
```

## Auto Scaling schedules (dev/test)

```bash
# Scale down at night
aws autoscaling put-scheduled-update-group-action --auto-scaling-group-name dev-asg --scheduled-action-name night --recurrence "0 22 * * *" --min-size 0 --max-size 0 --desired-capacity 0

# Scale up morning (weekdays)
aws autoscaling put-scheduled-update-group-action --auto-scaling-group-name dev-asg --scheduled-action-name morning --recurrence "0 8 * * 1-5" --min-size 1 --max-size 3 --desired-capacity 2
```

## Cost anomaly detection

```bash
# Create monitor
aws ce create-anomaly-monitor --anomaly-monitor '{
  "MonitorName": "AllServices",
  "MonitorType": "DIMENSIONAL",
  "MonitorDimension": "SERVICE"
}'

# Subscribe to alerts
aws ce create-anomaly-subscription --anomaly-subscription '{
  "SubscriptionName": "DailyAlert",
  "Threshold": 100.0,
  "Frequency": "DAILY",
  "MonitorArnList": ["arn:aws:ce::<account>:anomalymonitor/<id>"],
  "Subscribers": [{"Type": "EMAIL", "Address": "ops@example.com"}]
}'

# Query anomalies
aws ce get-anomalies --date-interval Start=$(date -u -d '30 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d)
```

## Troubleshooting cost spikes

```bash
# Identify service causing spike (last 7 days)
aws ce get-cost-and-usage --time-period Start=$(date -u -d '7 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) --granularity DAILY --metrics BlendedCost --group-by Type=DIMENSION,Key=SERVICE

# If EC2: check recently launched instances
aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,LaunchTime]' --output table | sort -k3

# If data transfer: check NAT gateway
aws cloudwatch get-metric-statistics --namespace AWS/NATGateway --metric-name BytesOutToDestination --dimensions Name=NatGatewayId,Value=nat-xxxxx --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 86400 --statistics Sum

# If Lambda: check invocations (errors cause retries)
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Invocations --dimensions Name=FunctionName,Value=<func> --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 86400 --statistics Sum

# Runaway Auto Scaling, accidental large instance, data transfer loop, snapshot during high-write
```
