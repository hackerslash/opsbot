# AWS

## Critical gotchas

- **EC2 console output**: `aws ec2 get-console-output` is the ONLY way to see boot failures when SSH/SSM dead
- **Stop vs reboot**: Stop+start moves to new hardware (fixes hardware degradation), reboot keeps same hardware
- **EBS expand**: Both `modify-volume` AND filesystem resize (growpart + resize2fs) required
- **IAM Deny wins**: Explicit Deny always overrides Allow; check SCPs, resource policies, use `simulate-principal-policy`
- **ALB security group**: Instance SG must allow ALB's SG, not 0.0.0.0/0 (common 502 cause)
- **ASG debug**: Suspend HealthCheck process to prevent termination during investigation
- **S3 sync delete**: `--delete` flag needed for mirror behavior (default keeps destination files)

## Quick reference

```bash
aws ec2 describe-instances --instance-ids <i-xxx> --query 'Reservations[0].Instances[0].[State.Name,InstanceType,PrivateIpAddress,PublicIpAddress]' --output table
aws ec2 describe-instances --filters "Name=tag:Name,Values=*prod*" --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' --output table
aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::<account>:role/<role> --action-names s3:PutObject --resource-arns '*'  # Authoritative permission check
aws elbv2 describe-target-health --target-group-arn <arn>
aws lambda get-function --function-name <name> --query 'Configuration.[LastUpdateStatus,State,StateReason]'
```

## EC2

```bash
# When SSH unreachable
aws ec2 get-console-output --instance-id <i-xxx> --output text  # Kernel panics, OOM kills, boot errors
aws ssm start-session --target <i-xxx>                          # Alternative access

# Instance metadata (from within instance)
curl -s http://169.254.169.254/latest/meta-data/instance-id
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/  # Verify role attached
curl -s http://169.254.169.254/latest/user-data                            # Check user data script

# Terminate protection
aws ec2 describe-instance-attribute --instance-id <i-xxx> --attribute disableApiTermination
aws ec2 modify-instance-attribute --instance-id <i-xxx> --no-disable-api-termination
```

## EBS

```bash
# Attach volume
aws ec2 create-volume --availability-zone us-east-1a --size 100 --volume-type gp3
aws ec2 wait volume-available --volume-ids <vol-xxx>
aws ec2 attach-volume --volume-id <vol-xxx> --instance-id <i-xxx> --device /dev/sdf

# Expand volume (requires BOTH steps)
aws ec2 modify-volume --volume-id <vol-xxx> --size 200
aws ec2 describe-volumes-modifications --volume-ids <vol-xxx>
# Then on instance: sudo growpart /dev/nvme0n1 1; sudo resize2fs /dev/nvme0n1p1

# Snapshots
aws ec2 create-snapshot --volume-id <vol-xxx> --description "backup-2026-06-26"
aws ec2 create-volume --snapshot-id <snap-xxx> --availability-zone us-east-1a  # Restore
```

## IAM

```bash
# Simulate permissions (authoritative - don't guess)
aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::<account>:role/<role> --action-names s3:PutObject ssm:GetParameter --resource-arns '*'

# Check instance role
aws ec2 describe-instances --instance-ids <i-xxx> --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'

# Assume role for testing
aws sts assume-role --role-arn arn:aws:iam::<account>:role/<role> --role-session-name test-session
# Export credentials from response, then test
```

## S3

```bash
aws s3 presign s3://<bucket>/<key> --expires-in 3600  # Temporary URL for private object
aws s3 sync ./build/ s3://<bucket>/app/ --delete      # Mirror behavior (deletes removed files)
aws s3api list-objects-v2 --bucket <bucket> --query 'Contents[?Size>`104857600`].[Key,Size]'  # Find large files
aws configure set default.s3.max_concurrent_requests 50  # Speed up sync (default 10)
```

## ALB

```bash
# Unhealthy targets
aws elbv2 describe-target-health --target-group-arn <arn>
aws elbv2 describe-target-groups --target-group-arns <arn> --query 'TargetGroups[0].HealthCheckPath'
# Check: 1) app returns 2xx on health check path, 2) instance SG allows ALB's SG (not 0.0.0.0/0)

# Connection draining (default 300s - reduce for faster deploys)
aws elbv2 describe-target-group-attributes --target-group-arn <arn> --query 'Attributes[?Key==`deregistration_delay.timeout_seconds`]'
```

## Auto Scaling Group

```bash
aws autoscaling wait group-in-service --auto-scaling-group-name <asg>  # Block until healthy
aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg> --max-records 10  # Why it scaled
aws autoscaling start-instance-refresh --auto-scaling-group-name <asg> --preferences MinHealthyPercentage=90
aws autoscaling suspend-processes --auto-scaling-group-name <asg> --scaling-processes HealthCheck  # Debug without termination
```

## CloudWatch

```bash
# Metrics
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value=<i-xxx> --start-time 2026-06-26T00:00:00Z --end-time 2026-06-26T23:59:59Z --period 3600 --statistics Average

# Logs Insights (see logging.md, observability.md for patterns)
aws logs start-query --log-group-name /aws/lambda/<func> --start-time $(date -u -d '1 hour ago' +%s) --end-time $(date -u +%s) --query-string 'fields @timestamp, @message | filter @message like /ERROR/'
```

## Lambda

```bash
aws lambda get-function --function-name <name> --query 'Configuration.[LastUpdateStatus,State,StateReason]'  # Check state (Pending/Active/Failed)
aws lambda invoke --function-name <name> --payload '{"key":"value"}' --cli-binary-format raw-in-base64-out response.json
aws lambda get-function-concurrency --function-name <name>  # Check if throttled
aws lambda update-function-configuration --function-name <name> --environment Variables={KEY1=value1}
aws lambda wait function-updated --function-name <name>
```

## RDS

```bash
aws rds describe-db-instances --db-instance-identifier <id> --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,Engine]'
aws rds create-db-snapshot --db-instance-identifier <id> --db-snapshot-identifier <name>
aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier <id> --target-db-instance-identifier <new-id> --restore-time 2026-06-26T12:00:00Z
```

## Troubleshooting

**IAM denied despite correct policy**: Check Deny (always wins), SCPs, resource policies; use `simulate-principal-policy`

**EC2 stuck terminating**: `aws ec2 detach-volume --volume-id <vol-xxx> --force`

**ALB 502**: Target unhealthy, invalid HTTP response, timeout (default 60s), or SG blocking ALB→target

**Lambda cold start timeout**: See [serverless.md](serverless.md) for provisioned concurrency
