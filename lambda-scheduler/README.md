# Lambda 스케줄러 - 야간 인프라 자동 중단/재가동

## 개요

비용 절감을 위해 사용하지 않는 시간대(00:00-08:00 KST)에 인프라를 자동으로 중단하고 재가동합니다.

## 스케줄

| 시간 | 동작 | Lambda 함수 | Cron (UTC) |
|------|------|-------------|------------|
| **00:00 KST** | 인프라 중단 | `stop_infrastructure` | `cron(0 15 * * ? *)` |
| **08:00 KST** | 인프라 재가동 | `start_infrastructure` | `cron(0 23 * * ? *)` |

## 중단되는 리소스

### ECS 서비스
- **chatapp-dev-service-blue**: desired_count 1 → 0
- **chatapp-dev-service-green**: desired_count 1 → 0

**비용 절감 효과:**
- Fargate 과금 중단: 약 **$0.02/시간 × 8시간 = $0.16/일**
- 월간 약 **$4.8** 절감

### 유지되는 리소스 (계속 과금)
-  **ElastiCache Redis**: 중단 불가능 (계속 과금)
-  **ALB**: 유지 (비용 절감 효과 적음)
-  **NAT Gateway**: 유지 (삭제/재생성 복잡)
-  **DynamoDB**: Pay-per-request이므로 사용 안 하면 비용 없음

## 배포 방법

### 1. Lambda ZIP 파일 생성

```bash
cd lambda-scheduler

# ZIP 파일 생성
chmod +x deploy.sh
./deploy.sh

# 또는 수동으로
zip stop_infrastructure.zip stop_infrastructure.py
zip start_infrastructure.zip start_infrastructure.py
```

### 2. Terraform으로 배포

```bash
cd ../terraform

# main.tf에 모듈 추가 확인
# (아래 섹션 참고)

# 배포
terraform apply
```

### 3. main.tf에 모듈 추가

`terraform/main.tf` 파일 끝에 추가:

```hcl
# Lambda 스케줄러 모듈 (야간 인프라 자동 중단/재가동)
module "lambda_scheduler" {
  source = "./modules/lambda-scheduler"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  cluster_name        = module.ecs.cluster_name
  blue_service_name   = module.ecs.blue_service_name
  green_service_name  = module.ecs.green_service_name
  blue_desired_count  = var.desired_count
  green_desired_count = 1
}
```

### 4. 배포 확인

```bash
# Lambda 함수 확인
aws lambda list-functions --region ap-northeast-2 | grep infrastructure

# EventBridge 규칙 확인
aws events list-rules --region ap-northeast-2 | grep infrastructure

# 수동 테스트 (즉시 실행)
aws lambda invoke \
  --function-name chatapp-dev-stop-infrastructure \
  --region ap-northeast-2 \
  output.json

cat output.json

# 인프라 상태 확인
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue chatapp-dev-service-green \
  --region ap-northeast-2 \
  --query 'services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount}'
```

## 수동 제어

### 즉시 중단

```bash
aws lambda invoke \
  --function-name chatapp-dev-stop-infrastructure \
  --region ap-northeast-2 \
  /tmp/output.json && cat /tmp/output.json
```

### 즉시 재가동

```bash
aws lambda invoke \
  --function-name chatapp-dev-start-infrastructure \
  --region ap-northeast-2 \
  /tmp/output.json && cat /tmp/output.json
```

### 스케줄 일시 중지

```bash
# Stop 스케줄 비활성화
aws events disable-rule \
  --name chatapp-dev-stop-infrastructure \
  --region ap-northeast-2

# Start 스케줄 비활성화
aws events disable-rule \
  --name chatapp-dev-start-infrastructure \
  --region ap-northeast-2
```

### 스케줄 재활성화

```bash
# Stop 스케줄 활성화
aws events enable-rule \
  --name chatapp-dev-stop-infrastructure \
  --region ap-northeast-2

# Start 스케줄 활성화
aws events enable-rule \
  --name chatapp-dev-start-infrastructure \
  --region ap-northeast-2
```

## 로그 확인

```bash
# Stop 함수 로그
aws logs tail /aws/lambda/chatapp-dev-stop-infrastructure \
  --follow \
  --region ap-northeast-2

# Start 함수 로그
aws logs tail /aws/lambda/chatapp-dev-start-infrastructure \
  --follow \
  --region ap-northeast-2

# 최근 실행 로그
aws logs tail /aws/lambda/chatapp-dev-stop-infrastructure \
  --since 1h \
  --region ap-northeast-2
```

## 스케줄 변경

스케줄을 변경하려면 `terraform/modules/lambda-scheduler/main.tf`에서 cron 표현식을 수정:

```hcl
# 예시: 자정(00:00) → 새벽 2시(02:00)로 변경
schedule_expression = "cron(0 17 * * ? *)"  # 02:00 KST

# 예시: 오전 8시(08:00) → 오전 7시(07:00)로 변경
schedule_expression = "cron(0 22 * * ? *)"  # 07:00 KST
```

### Cron 표현식 가이드 (UTC 기준)

| KST 시간 | UTC 시간 | Cron 표현식 |
|---------|---------|-------------|
| 00:00 | 15:00 (전날) | `cron(0 15 * * ? *)` |
| 01:00 | 16:00 (전날) | `cron(0 16 * * ? *)` |
| 02:00 | 17:00 (전날) | `cron(0 17 * * ? *)` |
| 07:00 | 22:00 (전날) | `cron(0 22 * * ? *)` |
| 08:00 | 23:00 (전날) | `cron(0 23 * * ? *)` |
| 09:00 | 00:00 | `cron(0 0 * * ? *)` |

**주의**: KST는 UTC+9이므로, KST 시간에서 9시간을 빼면 UTC 시간이 됩니다.

## 모니터링

### CloudWatch 대시보드

```bash
# 메트릭 확인
aws cloudwatch get-metric-statistics \
  --namespace Infrastructure/Scheduler \
  --metric-name InfrastructureStatus \
  --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average \
  --region ap-northeast-2
```

**메트릭 값:**
- `0`: 인프라 중단 (Stopped)
- `1`: 인프라 실행 중 (Running)

### 알림 설정 (선택사항)

```bash
# SNS 토픽 생성
aws sns create-topic \
  --name infrastructure-scheduler-alerts \
  --region ap-northeast-2

# 이메일 구독
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-northeast-2:137068226866:infrastructure-scheduler-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region ap-northeast-2

# Lambda 함수에 SNS 알림 추가 (선택사항)
# stop_infrastructure.py와 start_infrastructure.py에 SNS 코드 추가 필요
```

## 트러블슈팅

### 1. Lambda 함수가 실행되지 않음

```bash
# EventBridge 규칙 상태 확인
aws events describe-rule \
  --name chatapp-dev-stop-infrastructure \
  --region ap-northeast-2

# 규칙이 ENABLED 상태인지 확인
```

### 2. ECS 서비스가 중단되지 않음

```bash
# Lambda 로그 확인
aws logs tail /aws/lambda/chatapp-dev-stop-infrastructure \
  --since 10m \
  --region ap-northeast-2

# IAM 권한 확인
aws iam get-role-policy \
  --role-name chatapp-dev-lambda-scheduler \
  --policy-name chatapp-dev-lambda-ecs-policy \
  --region ap-northeast-2
```

### 3. 서비스가 자동으로 재시작됨

ECS 서비스의 `desired_count`를 0으로 설정해도 자동으로 재시작되는 경우:

```bash
# 서비스 설정 확인
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue \
  --region ap-northeast-2

# deployment configuration 확인
# deploymentConfiguration.minimumHealthyPercent가 0인지 확인
```

## 비용 절감 효과 (예상)

### 현재 구성 기준

**일일 비용:**
- Fargate (2 tasks × 0.25 vCPU, 0.5GB): $0.02/시간
- 8시간 중단: $0.16/일

**월간 비용:**
- 30일 기준: $4.8/월

**연간 비용:**
- $57.6/년

## 주의사항

⚠️ **운영 환경에서 사용 시 주의**
- 개발/테스트 환경에서만 사용 권장
- Production 환경에서는 신중하게 사용

⚠️ **데이터 손실 위험 없음**
- ECS 서비스만 중단하므로 데이터 손실 없음
- DynamoDB, Redis 데이터는 그대로 유지

⚠️ **재가동 시간 확인**
- 서비스 재가동 후 안정화까지 약 2-3분 소요
- 08:00에 즉시 사용 가능하지 않을 수 있음

## 제거 방법

스케줄러를 제거하려면:

```bash
cd terraform

# main.tf에서 lambda_scheduler 모듈 제거 또는 주석 처리

# Terraform apply
terraform apply

# 또는 Lambda 함수만 삭제
aws lambda delete-function \
  --function-name chatapp-dev-stop-infrastructure \
  --region ap-northeast-2

aws lambda delete-function \
  --function-name chatapp-dev-start-infrastructure \
  --region ap-northeast-2
```

---