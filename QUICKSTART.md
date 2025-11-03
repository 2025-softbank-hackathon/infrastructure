# 빠른 시작 가이드 - 해커톤 데모

## TL;DR - 5분 만에 배포하기

```bash
# 1. AWS CLI 설정
aws configure

# 2. Terraform 설정
cd terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 편집 - s3_bucket_name과 container_image 설정

# 3. 배포
terraform init
terraform apply -auto-approve

# 4. URL 확인
terraform output cloudfront_domain_name
terraform output alb_dns_name
```

---

## 데모 전 체크리스트 (10분 전)

```bash
# Blue 환경 확인
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue \
  --region ap-northeast-2 \
  --query 'services[0].{Running:runningCount,Status:status}'

# Green 환경 확인
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-green \
  --region ap-northeast-2 \
  --query 'services[0].{Running:runningCount,Status:status}'

# ALB DNS 또는 CloudFront URL 공유용
terraform output alb_dns_name
terraform output cloudfront_domain_name

# 현재 트래픽 분배 확인
terraform output blue_weight
terraform output green_weight
```

---

## 라이브 데모 명령어 (복사 & 붙여넣기 준비)

### 1단계: 초기 상태 보여주기 (0-1분)
```bash
terraform output blue_weight   # 90
terraform output green_weight  # 10
```

### 2단계: 50/50 분할 (1-2분)
```bash
cd terraform
cat > terraform.tfvars << EOF
# AWS 기본 설정
aws_region   = "ap-northeast-2"
project_name = "chatapp"
environment  = "dev"

# VPC 설정
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["ap-northeast-2a", "ap-northeast-2c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# ECS 설정
container_image  = "nginx:latest"  # TODO: 실제 채팅 앱 이미지로 변경
container_port   = 3000
fargate_cpu      = 256
fargate_memory   = 512
desired_count    = 1

# Blue/Green 배포 설정 - 50/50 분할
blue_weight  = 50
green_weight = 50

# ElastiCache Redis (멀티 AZ)
redis_node_type       = "cache.t4g.micro"
redis_num_cache_nodes = 2
redis_engine_version  = "7.0"

# DynamoDB
dynamodb_billing_mode = "PAY_PER_REQUEST"

# S3
s3_bucket_name = ""
EOF

terraform apply -auto-approve
```

### 3단계: Green 90% (2-3분)
```bash
# 가중치만 변경
cat > terraform.tfvars << EOF
# AWS 기본 설정
aws_region   = "ap-northeast-2"
project_name = "chatapp"
environment  = "dev"

# VPC 설정
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["ap-northeast-2a", "ap-northeast-2c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# ECS 설정
container_image  = "nginx:latest"
container_port   = 3000
fargate_cpu      = 256
fargate_memory   = 512
desired_count    = 1

# Blue/Green 배포 설정 - Green 90%
blue_weight  = 10
green_weight = 90

# ElastiCache Redis (멀티 AZ)
redis_node_type       = "cache.t4g.micro"
redis_num_cache_nodes = 2
redis_engine_version  = "7.0"

# DynamoDB
dynamodb_billing_mode = "PAY_PER_REQUEST"

# S3
s3_bucket_name = ""
EOF

terraform apply -auto-approve
```

### 긴급 롤백
```bash
# Blue 100%로 즉시 롤백
terraform apply -var="blue_weight=100" -var="green_weight=0" -auto-approve
```

---

## 모니터링 명령어

### 실시간 ECS 상태
```bash
watch -n 2 'aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue chatapp-dev-service-green \
  --region ap-northeast-2 \
  --query "services[*].{Service:serviceName,Running:runningCount,Status:status}"'
```

### ALB 타겟 헬스 체크
```bash
# Blue 타겟
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_target_group_arn) \
  --region ap-northeast-2 \
  --query 'TargetHealthDescriptions[*].{IP:Target.Id,Health:TargetHealth.State}'

# Green 타겟
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw green_target_group_arn) \
  --region ap-northeast-2 \
  --query 'TargetHealthDescriptions[*].{IP:Target.Id,Health:TargetHealth.State}'
```

### CloudWatch 로그 (실시간)
```bash
aws logs tail /ecs/chatapp-dev --follow --format short --region ap-northeast-2
```

### CloudWatch 메트릭 확인
```bash
# ALB 4xx 에러
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_4XX_Count \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw alb_arn_suffix) \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --region ap-northeast-2
```

---

## 데모 후 - 정리

```bash
# S3 버킷 비우기 (ALB 로그, CloudFront)
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive --region ap-northeast-2

# 모든 리소스 삭제
terraform destroy -auto-approve
```

**정리 소요 시간**: ~10분
**삭제하지 않을 경우 비용**: 월 ~$70-90

---

## 문제 해결

### 문제: Terraform apply 실패
```bash
# Terraform 상태 초기화
rm -rf .terraform .terraform.lock.hcl
terraform init
```

### 문제: ECS 태스크가 시작되지 않음
```bash
# 로그 확인
aws logs tail /ecs/chatapp-dev --follow --region ap-northeast-2

# 태스크 상태 확인
aws ecs describe-tasks \
  --cluster chatapp-dev-cluster \
  --region ap-northeast-2 \
  --tasks $(aws ecs list-tasks \
    --cluster chatapp-dev-cluster \
    --service-name chatapp-dev-service-blue \
    --region ap-northeast-2 \
    --query 'taskArns[0]' --output text)
```

### 문제: 웹사이트에 연결할 수 없음
```bash
# ALB 상태 확인
aws elbv2 describe-load-balancers \
  --region ap-northeast-2 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `chatapp`)].{DNS:DNSName,State:State.Code}'

# 타겟 헬스 확인
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_target_group_arn) \
  --region ap-northeast-2
```

---

## 주요 Terraform Outputs

```bash
# 모든 중요 URL 가져오기
terraform output -json | jq -r '
  {
    cloudfront: .cloudfront_domain_name.value,
    alb: .alb_dns_name.value,
    redis: .redis_endpoint.value
  }
'
```

---

## 프레젠테이션 팁

1. **2개의 터미널 창 준비**:
   - 창 1: Terraform 명령어
   - 창 2: 모니터링 (watch 명령어)

2. **시인성을 위해 터미널 폰트 크기 증가**

3. **프레젠테이션 전 최소 1회 전체 데모 테스트**

4. **텍스트 파일에 롤백 명령어 준비**

5. **타이머 설정** - 각 단계는 약 1분

6. **청중에게 질문**: "트래픽 전환 후 연결 끊긴 분 계신가요?"

7. **CloudWatch 대시보드 표시** - 시각적 효과

---

## 비용 최적화

### 개발 중 (데모 외 시간)
```bash
# 필요하지 않을 때 ECS 태스크 중지
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --region ap-northeast-2 \
  --desired-count 0

aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-green \
  --region ap-northeast-2 \
  --desired-count 0
```

### 데모 전 재개
```bash
# 태스크 다시 시작
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --region ap-northeast-2 \
  --desired-count 1

aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-green \
  --region ap-northeast-2 \
  --desired-count 1
```

**절감 효과**: 데모 외 시간에 Fargate 비용 ~80% 절감

---

## 중요 참고사항

- **리전**: ap-northeast-2 (서울)
- **NAT Gateway**: 24/7 실행 (월 ~$64, 2개) - 중지 불가
- **Redis**: 멀티 AZ (프라이머리 + 리플리카) - 월 ~$15
- **인프라 삭제/재생성**: 총 ~20분 소요
- **CloudFront**: 최초 배포 시 ~15분 소요
- **ALB**: 활성화까지 ~5분 소요
- **프레젠테이션 1일 전 첫 데모 리허설 권장**

## 멀티 AZ 고가용성 구성

현재 구성은 2개의 가용 영역(ap-northeast-2a, ap-northeast-2c)을 사용합니다:
- **ALB**: 2개 AZ에 분산 배치 (AWS 요구사항)
- **NAT Gateway**: 각 AZ마다 1개씩 배치 (총 2개 - 고가용성)
- **Redis**: 멀티 AZ (프라이머리 + 리드 리플리카) - 자동 페일오버
- **ECS Fargate**: 2개 AZ에 배포 가능
- **고가용성**: AZ 단위 장애 시에도 서비스 지속 가능
