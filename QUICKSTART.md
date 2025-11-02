# Quick Start Guide - Hackathon Demo

## TL;DR - 5 Minutes to Deploy

```bash
# 1. Configure AWS CLI
aws configure

# 2. Setup Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - set s3_bucket_name and container_image

# 3. Deploy
terraform init
terraform apply -auto-approve

# 4. Get URLs
terraform output cloudfront_domain_name
terraform output api_gateway_websocket_url
```

---

## Pre-Demo Checklist (10 Minutes Before)

```bash
# Verify Blue environment
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue \
  --query 'services[0].{Running:runningCount,Status:status}'

# Verify Green environment
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-green \
  --query 'services[0].{Running:runningCount,Status:status}'

# Get CloudFront URL to share
terraform output cloudfront_domain_name

# Verify current traffic split
terraform output blue_weight
terraform output green_weight
```

---

## Live Demo Commands (Copy & Paste Ready)

### Stage 1: Show Initial State (Minute 0-1)
```bash
terraform output blue_weight
terraform output green_weight
```

### Stage 2: 50/50 Split (Minute 1-2)
```bash
cd terraform
cat > terraform.tfvars << EOF
aws_region   = "ap-northeast-1"
project_name = "chatapp"
environment  = "dev"
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["ap-northeast-1a", "ap-northeast-1c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
container_image  = "nginx:latest"
container_port   = 3000
fargate_cpu      = 256
fargate_memory   = 512
desired_count    = 1
blue_weight  = 50
green_weight = 50
redis_node_type       = "cache.t3.micro"
redis_num_cache_nodes = 1
redis_engine_version  = "7.0"
dynamodb_billing_mode = "PAY_PER_REQUEST"
s3_bucket_name = ""
EOF

terraform apply -auto-approve
```

### Stage 3: Green 90% (Minute 2-3)
```bash
# Just change the weights
blue_weight  = 10
green_weight = 90

# Re-run the same command with updated values
cat > terraform.tfvars << EOF
aws_region   = "ap-northeast-1"
project_name = "chatapp"
environment  = "dev"
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["ap-northeast-1a", "ap-northeast-1c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
container_image  = "nginx:latest"
container_port   = 3000
fargate_cpu      = 256
fargate_memory   = 512
desired_count    = 1
blue_weight  = 10
green_weight = 90
redis_node_type       = "cache.t3.micro"
redis_num_cache_nodes = 1
redis_engine_version  = "7.0"
dynamodb_billing_mode = "PAY_PER_REQUEST"
s3_bucket_name = ""
EOF

terraform apply -auto-approve
```

### Emergency Rollback
```bash
# Rollback to Blue 100%
blue_weight  = 100
green_weight = 0

terraform apply -auto-approve
```

---

## Monitoring Commands

### Real-time ECS Status
```bash
watch -n 2 'aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue chatapp-dev-service-green \
  --query "services[*].{Service:serviceName,Running:runningCount,Status:status}"'
```

### ALB Target Health
```bash
# Blue targets
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_target_group_arn) \
  --query 'TargetHealthDescriptions[*].{IP:Target.Id,Health:TargetHealth.State}'

# Green targets
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw green_target_group_arn) \
  --query 'TargetHealthDescriptions[*].{IP:Target.Id,Health:TargetHealth.State}'
```

### CloudWatch Logs (Live)
```bash
aws logs tail /ecs/chatapp-dev --follow --format short
```

---

## After Demo - Cleanup

```bash
# Empty S3 bucket
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive

# Destroy everything
terraform destroy -auto-approve
```

**Cleanup time**: ~10 minutes
**Cost if not deleted**: ~$50-70/month

---

## Troubleshooting

### Issue: Terraform apply fails
```bash
# Reset Terraform state
rm -rf .terraform .terraform.lock.hcl
terraform init
```

### Issue: ECS task won't start
```bash
# Check logs
aws logs tail /ecs/chatapp-dev --follow

# Check task status
aws ecs describe-tasks \
  --cluster chatapp-dev-cluster \
  --tasks $(aws ecs list-tasks \
    --cluster chatapp-dev-cluster \
    --service-name chatapp-dev-service-blue \
    --query 'taskArns[0]' --output text)
```

### Issue: Cannot connect to website
```bash
# Check ALB status
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `chatapp`)].{DNS:DNSName,State:State.Code}'

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_target_group_arn)
```

---

## Key Terraform Outputs

```bash
# Get all important URLs
terraform output -json | jq -r '
  {
    cloudfront: .cloudfront_domain_name.value,
    websocket: .api_gateway_websocket_url.value,
    alb: .alb_dns_name.value,
    redis: .redis_endpoint.value
  }
'
```

---

## Presentation Tips

1. **Prepare 2 terminal windows**:
   - Window 1: Terraform commands
   - Window 2: Monitoring (watch command)

2. **Increase terminal font size** for visibility

3. **Test the full demo** at least once before presentation

4. **Have rollback commands ready** in a text file

5. **Set a timer** - each stage should be ~1 minute

6. **Ask audience**: "Is anyone disconnected?" after each traffic shift

7. **Show CloudWatch dashboard** for visual appeal

---

## Cost Optimization

### During Development
```bash
# Stop ECS tasks when not needed
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --desired-count 0

aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-green \
  --desired-count 0
```

### Resume Before Demo
```bash
# Start tasks again
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --desired-count 1

aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-green \
  --desired-count 1
```

**Savings**: Reduces Fargate costs by ~80% during non-demo hours

---

## Important Notes

- NAT Gateway runs 24/7 (~$32/month) - cannot be stopped
- Destroying/recreating infrastructure takes ~20 minutes total
- CloudFront takes ~15 minutes to deploy initially
- ALB takes ~5 minutes to become active
- First demo rehearsal recommended 1 day before presentation
