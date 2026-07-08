# networking — VPC, security groups, routing, DNS

## Critical gotchas

- **Security groups are stateful, NACLs are stateless** — SG allows return traffic automatically, NACL needs explicit inbound+outbound rules including ephemeral ports 1024-65535
- **App bound to 127.0.0.1 can't receive external traffic** — must bind to 0.0.0.0
- **ALB requires security group rule allowing ALB SG, not 0.0.0.0/0** — instance SG must reference ALB SG for proper routing
- **Public subnet needs IGW route + public IP** — route table 0.0.0.0/0 → IGW + instance has public IP or EIP
- **Private subnet needs NAT gateway in public subnet** — route table 0.0.0.0/0 → NAT, NAT itself in public subnet with IGW route
- **RDS security group must allow app SG, not CIDR** — use source security group reference for dynamic instance IPs
- **VPC needs enableDnsSupport + enableDnsHostnames for internal DNS**
- **Connection tracking exhaustion causes random drops despite correct firewall rules** — check nf_conntrack_count vs nf_conntrack_max

## Quick reference

```bash
# Triage
curl -v --max-time 5 https://<domain>
bash scripts/connect.sh run <target> "ss -tlnp | grep :<port>"
bash scripts/connect.sh run <target> "curl -v --max-time 5 https://api.github.com"

# Security groups
aws ec2 describe-instances --instance-ids <i-xxxxx> --query 'Reservations[0].Instances[0].SecurityGroups[*].[GroupId,GroupName]' --output table
aws ec2 describe-security-groups --group-ids <sg-xxxxx> --query 'SecurityGroups[0].{Ingress:IpPermissions,Egress:IpPermissionsEgress}'
aws ec2 authorize-security-group-ingress --group-id <sg-xxxxx> --protocol tcp --port 443 --cidr 0.0.0.0/0  # MUTATING
aws ec2 revoke-security-group-ingress --group-id <sg-xxxxx> --protocol tcp --port 22 --cidr 203.0.113.0/24  # MUTATING

# NACLs (check only if SG correct but connectivity fails)
aws ec2 describe-network-acls --filters Name=association.subnet-id,Values=<subnet-xxxxx> --query 'NetworkAcls[0].{ID:NetworkAclId,Rules:Entries}' --output table

# Routing
SUBNET=$(aws ec2 describe-instances --instance-ids <i-xxxxx> --query 'Reservations[0].Instances[0].SubnetId' --output text)
aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=$SUBNET --query 'RouteTables[0].Routes' --output table
aws ec2 describe-nat-gateways --nat-gateway-ids <nat-xxxxx>
aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=<vpc-xxxxx>

# DNS
bash scripts/connect.sh run <target> "cat /etc/resolv.conf; nslookup <domain>"
aws route53 list-hosted-zones --output table
aws route53 list-resource-record-sets --hosted-zone-id <Z-xxxxx> --output table
dig NS <domain> +short  # verify NS records point to Route 53

# Connection testing
bash scripts/connect.sh run <target> "timeout 5 bash -c '</dev/tcp/<host>/<port>' && echo open || echo closed"
bash scripts/connect.sh run <target> "traceroute <host>"
nc -zv <instance-ip> <port>  # from local machine
aws ec2 describe-instances --instance-ids <i-xxxxx> --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' --output table

# ALB health checks
bash scripts/connect.sh run <target> "curl -f http://localhost:<port><health-path>"
aws elbv2 describe-target-health --target-group-arn <arn>

# VPN / Direct Connect
aws ec2 describe-vpn-connections --vpn-connection-ids <vpn-xxxxx>
bash scripts/connect.sh run <target> "ping -c 3 <on-prem-ip>"

# ENI
aws ec2 describe-network-interfaces --filters Name=attachment.instance-id,Values=<i-xxxxx> --query 'NetworkInterfaces[*].[NetworkInterfaceId,PrivateIpAddress,Status]' --output table
aws ec2 detach-network-interface --attachment-id <eni-attach-xxxxx>  # MUTATING

# Connection tracking (intermittent failures)
bash scripts/connect.sh run <target> "sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max"
bash scripts/connect.sh run <target> "sysctl net.ipv4.ip_local_port_range"
aws cloudwatch get-metric-statistics --namespace AWS/NATGateway --metric-name ErrorPortAllocation --dimensions Name=NatGatewayId,Value=<nat-xxxxx> --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Sum

# VPC Flow Logs (for hard-to-trace issues)
aws ec2 create-flow-logs --resource-type VPC --resource-ids <vpc-xxxxx> --traffic-type ALL --log-destination-type cloud-watch-logs --log-group-name /aws/vpc/flowlogs/<vpc-name>  # MUTATING
# Query: fields @timestamp, srcAddr, dstAddr, dstPort, action | filter dstPort = 443 | sort @timestamp desc
```

## Troubleshooting patterns

**Can curl locally but not from outside:**
- Check `ss -tlnp` — app bound to 127.0.0.1 instead of 0.0.0.0?
- Check security group allows inbound on port
- Check instance has public IP: `aws ec2 describe-instances --instance-ids <i-xxxxx> --query 'Reservations[0].Instances[0].PublicIpAddress'`
- Allocate EIP if needed: `ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text); aws ec2 associate-address --instance-id <i-xxxxx> --allocation-id $ALLOC_ID`

**Intermittent failures despite correct firewall rules:**
- Connection tracking exhaustion: `sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max` — increase max or tune timeouts (see [harden.md](harden.md))
- Ephemeral port exhaustion: `sysctl net.ipv4.ip_local_port_range` — widen range if needed
- NAT gateway connection limits: check CloudWatch ErrorPortAllocation metric

**Outbound works, inbound fails:**
- Instance has no public IP or route table missing 0.0.0.0/0 → IGW
- Check: `aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=<subnet-xxxxx> | grep igw-`

**RDS connection timeout:**
- RDS security group doesn't allow inbound from app SG: `aws rds describe-db-instances --db-instance-identifier <db-name> --query 'DBInstances[0].VpcSecurityGroups'`
- Test TCP: `bash scripts/connect.sh run <target> "timeout 5 bash -c '</dev/tcp/<db-endpoint>/5432' && echo open || echo timeout"`
