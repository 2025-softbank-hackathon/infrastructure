# 테스트 애플리케이션 배포 및 테스트 가이드

## 0. 사전 준비: ECR 레포지토리 먼저 생성

```bash
cd terraform

# ECR 레포지토리만 먼저 생성
terraform apply -target=module.ecr

# 출력에서 ECR URL 확인 (예: 137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev)
```

## 1. Docker 이미지 빌드 및 푸시

### 1.1 ECR 로그인
```bash
cd test-app

# ECR 레포지토리 URI 확인
aws ecr describe-repositories --repository-names chatapp-dev --region ap-northeast-2

# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com
```

### 1.2 Docker 이미지 빌드
```bash
# 이미지 빌드
docker build -t chatapp-test:latest .

# 로컬 테스트 (옵션)
docker run -p 3000:3000 \
  -e REDIS_HOST=localhost \
  -e REDIS_PORT=6379 \
  -e DYNAMODB_TABLE_NAME=test-table \
  -e AWS_REGION=ap-northeast-2 \
  chatapp-test:latest

# 테스트 (다른 터미널에서)
curl http://localhost:3000/
```

### 1.3 ECR에 푸시
```bash
# 이미지 태그
docker tag chatapp-test:latest <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:test-v1

# ECR에 푸시
docker push 137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:test-v1
```

## 2. Terraform 변수 업데이트

`terraform.tfvars` 파일에서 container_image를 업데이트:

```hcl
container_image = "<AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:test-v1"
container_port   = 3000  # 테스트 앱 포트
```

또는 CLI에서 직접 지정:
```bash
cd ../terraform
terraform apply \
  -var="container_image=<AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:test-v1" \
  -var="container_port=3000"
```

## 3. Terraform Apply

```bash
cd ../terraform

# Plan 확인
terraform plan

# Apply 실행
terraform apply

# 주요 출력값 확인
# - alb_dns_name: ALB DNS 주소
# - blue_target_group_arn: Blue 타겟 그룹 ARN
# - green_target_group_arn: Green 타겟 그룹 ARN
# - ecs_cluster_name: ECS 클러스터 이름
# - redis_endpoint: Redis 엔드포인트
```

## 4. 배포 확인

### 4.1 ECS 서비스 상태 확인
```bash
# ECS 클러스터 확인
aws ecs list-services --cluster chatapp-dev-cluster --region ap-northeast-2

# Blue 서비스 상태
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue \
  --region ap-northeast-2

# Green 서비스 상태
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-green \
  --region ap-northeast-2

# 태스크 실행 확인
aws ecs list-tasks --cluster chatapp-dev-cluster --region ap-northeast-2
```

### 4.2 ALB 타겟 그룹 상태 확인
```bash
# Blue 타겟 그룹 health
aws elbv2 describe-target-health \
  --target-group-arn <BLUE_TARGET_GROUP_ARN> \
  --region ap-northeast-2

# Green 타겟 그룹 health
aws elbv2 describe-target-health \
  --target-group-arn <GREEN_TARGET_GROUP_ARN> \
  --region ap-northeast-2

# "healthy" 상태가 될 때까지 대기 (약 1-2분)
```

### 4.3 로그 확인
```bash
# CloudWatch Logs 확인
aws logs tail /ecs/chatapp-dev --follow --region ap-northeast-2

# 또는 특체 스트림 확인
aws logs tail /ecs/chatapp-dev --follow --filter-pattern "ERROR" --region ap-northeast-2
```

## 5. 애플리케이션 테스트

### 5.1 ALB DNS 주소 확인
```bash
# Terraform output에서 확인
terraform output alb_dns_name

# 또는 AWS CLI로 확인
aws elbv2 describe-load-balancers \
  --names chatapp-dev-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region ap-northeast-2
```

### 5.2 기본 엔드포인트 테스트

#### Hello World
```bash
curl http://<ALB_DNS_NAME>/

# 예상 응답:
# {
#   "message": "Hello World!",
#   "timestamp": "2025-11-04T...",
#   "environment": {
#     "redis_host": "...",
#     "redis_port": 6379,
#     "dynamodb_table": "chatapp-dev-messages",
#     "aws_region": "ap-northeast-2"
#   }
# }
```

#### Health Check
```bash
curl http://<ALB_DNS_NAME>/health

# 예상 응답:
# {"status": "healthy"}
```

### 5.3 전체 테스트 실행 (가장 중요!)
```bash
curl http://<ALB_DNS_NAME>/test/all

# 예상 응답 (모든 테스트 성공 시):
# {
#   "timestamp": "2025-11-04T...",
#   "overall_status": "✓ ALL TESTS PASSED",
#   "tests": {
#     "dynamodb": {
#       "status": "✓ SUCCESS",
#       "write": "OK",
#       "read": "OK",
#       "data": {...}
#     },
#     "redis": {
#       "status": "✓ SUCCESS",
#       "write": "OK",
#       "read": "OK",
#       "value": "..."
#     },
#     "nat_gateway": {
#       "status": "✓ SUCCESS",
#       "http_status": 200,
#       "message": "외부 인터넷 연결 성공 (NAT Gateway 작동)"
#     }
#   }
# }
```

### 5.4 개별 테스트

#### DynamoDB만 테스트
```bash
curl http://<ALB_DNS_NAME>/test/dynamodb
```

#### Redis만 테스트
```bash
curl http://<ALB_DNS_NAME>/test/redis
```

#### NAT Gateway (외부 인터넷 연결)만 테스트
```bash
curl http://<ALB_DNS_NAME>/test/nat

# 이 테스트가 성공하면 Private Subnet → NAT Gateway → Internet이 정상 작동하는 것
```

## 6. 테스트 시나리오별 확인사항

### ✅ DynamoDB 연결 확인
- `/test/dynamodb` 또는 `/test/all`이 성공하면 OK
- DynamoDB에 데이터 쓰기/읽기가 정상 작동
- IAM 권한 정상
- VPC에서 DynamoDB Public Endpoint 접근 가능

### ✅ Redis 연결 확인
- `/test/redis` 또는 `/test/all`이 성공하면 OK
- ElastiCache Redis에 연결 성공
- Security Group 규칙 정상
- Private Subnet 내 통신 정상

### ✅ NAT Gateway 확인
- `/test/nat` 또는 `/test/all`이 성공하면 OK
- Private Subnet → NAT Gateway → Internet Gateway 경로 정상
- 외부 API 호출 가능
- 응답 데이터가 다시 NAT를 통해 들어옴

### ✅ Blue/Green 배포 확인
```bash
# Blue 타겟 그룹 직접 테스트 (ALB listener rule로 가능하다면)
# 현재 구성에서는 ALB가 weight로 분산하므로 여러번 호출해서 확인

# 10번 호출해서 응답 분포 확인
for i in {1..10}; do
  curl -s http://<ALB_DNS_NAME>/ | jq -r '.timestamp'
  sleep 1
done
```

## 7. 문제 해결 (Troubleshooting)

### 7.1 Health Check 실패
```bash
# 1. ECS 태스크 로그 확인
aws logs tail /ecs/chatapp-dev --follow --region ap-northeast-2

# 2. 태스크가 계속 재시작되는지 확인
aws ecs describe-tasks \
  --cluster chatapp-dev-cluster \
  --tasks <TASK_ARN> \
  --region ap-northeast-2

# 3. Security Group 확인
# - ECS SG에서 ALB SG로부터의 인바운드 허용 확인
# - ALB SG에서 3000 포트 허용 확인
```

### 7.2 DynamoDB 테스트 실패
```bash
# 1. IAM 권한 확인
aws iam get-role --role-name chatapp-dev-ecs-task-role

# 2. DynamoDB 테이블 존재 확인
aws dynamodb describe-table \
  --table-name chatapp-dev-messages \
  --region ap-northeast-2

# 3. 환경 변수 확인 (ECS 태스크 정의에서)
aws ecs describe-task-definition \
  --task-definition chatapp-dev-task-blue \
  --region ap-northeast-2 | jq '.taskDefinition.containerDefinitions[0].environment'
```

### 7.3 Redis 테스트 실패
```bash
# 1. Redis 엔드포인트 확인
aws elasticache describe-replication-groups \
  --replication-group-id chatapp-dev-redis \
  --region ap-northeast-2

# 2. Security Group 확인
# - Redis SG에서 ECS SG로부터 6379 포트 허용 확인

# 3. ECS 태스크에서 직접 Redis 연결 테스트
aws ecs execute-command \
  --cluster chatapp-dev-cluster \
  --task <TASK_ARN> \
  --container chatapp-container \
  --interactive \
  --command "/bin/sh"

# 컨테이너 안에서:
# apt-get update && apt-get install -y redis-tools
# redis-cli -h <REDIS_HOST> ping
```

### 7.4 NAT Gateway 테스트 실패
```bash
# 1. NAT Gateway 상태 확인
aws ec2 describe-nat-gateways --region ap-northeast-2

# 2. Route Table 확인
aws ec2 describe-route-tables --region ap-northeast-2

# Private Subnet의 Route Table에 0.0.0.0/0 → NAT Gateway 경로 확인

# 3. ECS 태스크에서 직접 외부 연결 테스트
aws ecs execute-command \
  --cluster chatapp-dev-cluster \
  --task <TASK_ARN> \
  --container chatapp-container \
  --interactive \
  --command "/bin/sh"

# 컨테이너 안에서:
# curl https://httpbin.org/json
```

## 8. 정리 (Clean Up)

테스트 완료 후:

```bash
# Terraform으로 인프라 삭제
cd terraform
terraform destroy

# Docker 이미지 정리
docker rmi chatapp-test:latest
docker rmi <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:test-v1
```

## 9. 성공 기준

✅ **모든 테스트가 통과하면 인프라 구성 완료!**

```
✓ DynamoDB 연결 성공
✓ Redis 연결 성공
✓ NAT Gateway를 통한 외부 통신 성공
✓ Health Check 정상
✓ ALB를 통한 접근 가능
✓ Blue/Green 서비스 모두 healthy
```

이제 실제 애플리케이션을 배포할 준비가 완료되었습니다!
