# 해커톤 발표 시연 가이드

## 시연 개요

**주제**: AWS Blue/Green 무중단 배포 실시간 시연
**소요 시간**: 4분
**목표**: 사용자 접속 중인 채팅 서비스를 무중단으로 새 버전 배포

---

## 사전 준비 (발표 전)

### 1. 인프라 배포 완료 확인
```bash
cd terraform
terraform output
```

중요한 출력값 확인:
- `alb_dns_name`: ALB 주소
- `cloudfront_domain_name`: 웹사이트 주소
- `api_gateway_websocket_url`: WebSocket API 주소

### 2. Blue 환경 확인
```bash
# Blue 서비스 상태 확인
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

예상 출력:
```json
{
  "Status": "ACTIVE",
  "Running": 1,
  "Desired": 1
}
```

### 3. Green 환경 확인
```bash
# Green 서비스 상태 확인
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-green \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

### 4. 현재 트래픽 분산 확인
```bash
# ALB Target Group 상태 확인
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_target_group_arn)

aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw green_target_group_arn)
```

### 5. 참관자들에게 링크 공유
- CloudFront URL을 슬랙/이메일로 공유
- 발표 5분 전에 접속해달라고 요청
- 채팅방에서 메시지를 보내달라고 요청

---

## 발표 시연 스크립트 (4분)

### 00:00 - 00:30 | 상황 설명 (30초)

**스크립트**:
> "안녕하세요. 지금 여러분이 접속하신 채팅 서비스는 현재 Blue 환경에서 90% 트래픽을 처리하고 있습니다.
> 지금부터 4분 동안 새로운 버전을 Green 환경으로 배포하면서,
> 여러분의 채팅 연결이 끊기지 않는 무중단 배포를 실시간으로 보여드리겠습니다."

**화면 보여주기**:
```bash
# 현재 상태 확인
terraform output blue_weight
terraform output green_weight
```

### 00:30 - 01:00 | 1단계: Green 환경 준비 확인 (30초)

**스크립트**:
> "먼저 Green 환경이 정상적으로 동작하는지 확인하겠습니다."

**명령어 실행**:
```bash
# Green Task 상태 확인
aws ecs list-tasks \
  --cluster chatapp-dev-cluster \
  --service-name chatapp-dev-service-green

# Green Target Health 확인
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw green_target_group_arn) \
  --query 'TargetHealthDescriptions[0].TargetHealth.State'
```

예상 출력: `"healthy"`

### 01:00 - 02:00 | 2단계: 50/50 트래픽 전환 (1분)

**스크립트**:
> "Green 환경이 정상이니, 트래픽을 50:50으로 분산하겠습니다.
> 여러분의 채팅은 계속 유지됩니다."

**명령어 실행**:
```bash
# terraform.tfvars 수정
cat > terraform/terraform.tfvars <<EOF
aws_region   = "ap-northeast-1"
project_name = "chatapp"
environment  = "dev"

blue_weight  = 50
green_weight = 50

# ... 나머지 설정 ...
EOF

# Terraform 적용
cd terraform
terraform apply -auto-approve
```

**대기 중 설명**:
> "Terraform이 ALB의 Listener Rule을 업데이트하고 있습니다.
> 이 과정에서도 기존 연결은 유지되며, 새로운 연결만 50:50으로 분산됩니다."

**완료 후**:
```bash
# 적용 확인
terraform output blue_weight
terraform output green_weight
```

### 02:00 - 03:00 | 3단계: Green 90% 전환 (1분)

**스크립트**:
> "50:50에서 문제가 없으니, Green으로 90% 트래픽을 이동하겠습니다."

**명령어 실행**:
```bash
# terraform.tfvars 수정
cat > terraform/terraform.tfvars <<EOF
aws_region   = "ap-northeast-1"
project_name = "chatapp"
environment  = "dev"

blue_weight  = 10
green_weight = 90

# ... 나머지 설정 ...
EOF

# Terraform 적용
cd terraform
terraform apply -auto-approve
```

**참관자들에게 질문**:
> "채팅 연결이 끊긴 분 계신가요?"
> (손을 들어달라고 요청)

### 03:00 - 03:45 | 4단계: 모니터링 확인 (45초)

**스크립트**:
> "CloudWatch에서 실시간 메트릭을 확인해보겠습니다."

**AWS 콘솔 화면 공유**:
1. CloudWatch → Metrics → ECS
   - CPU Utilization
   - Memory Utilization
2. ALB → Target Groups
   - Healthy Host Count
   - Request Count per Target

**또는 CLI로 확인**:
```bash
# ALB 메트릭 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw alb_arn | cut -d/ -f2-) \
  --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average
```

### 03:45 - 04:00 | 마무리 (15초)

**스크립트**:
> "지금까지 Blue 환경에서 Green 환경으로 무중단 배포를 완료했습니다.
> 전체 과정에서 단 한 명의 사용자도 연결이 끊기지 않았고,
> 이것이 바로 Blue/Green 배포의 핵심입니다.
> 감사합니다!"

---

## 백업 플랜 (문제 발생 시)

### Green 환경 문제 발생 시
```bash
# 즉시 Blue로 롤백
cat > terraform/terraform.tfvars <<EOF
blue_weight  = 100
green_weight = 0
EOF

terraform apply -auto-approve
```

### Terraform 적용 실패 시
```bash
# AWS CLI로 직접 수정
aws elbv2 modify-listener \
  --listener-arn <LISTENER_ARN> \
  --default-actions Type=forward,ForwardConfig='{
    "TargetGroups": [
      {"TargetGroupArn": "<BLUE_TG_ARN>", "Weight": 100},
      {"TargetGroupArn": "<GREEN_TG_ARN>", "Weight": 0}
    ]
  }'
```

---

## 시연 체크리스트

### 발표 30분 전
- [ ] 인프라 배포 완료 확인
- [ ] Blue/Green 환경 모두 healthy 확인
- [ ] CloudFront 도메인 접속 테스트
- [ ] WebSocket 연결 테스트
- [ ] 화면 공유 설정 확인

### 발표 10분 전
- [ ] 참관자들에게 링크 공유
- [ ] 채팅방 접속 요청
- [ ] 현재 Blue weight = 90%, Green weight = 10% 확인
- [ ] 터미널 준비 (2개 창)
  - 창 1: Terraform 명령어
  - 창 2: AWS CLI 모니터링

### 발표 직전
- [ ] 모든 명령어 복사해두기
- [ ] terraform.tfvars 백업
- [ ] Rollback 명령어 준비

### 발표 후
- [ ] Blue weight를 100으로 되돌리기 (비용 절감)
- [ ] 시연 성공 여부 기록
- [ ] 피드백 수집

---

## 추가 팁

### 시연을 더 드라마틱하게 만들기

1. **실시간 차트 준비**:
   - CloudWatch Dashboard 미리 생성
   - 30초 간격 자동 갱신 설정

2. **참관자 참여 유도**:
   - 채팅방에서 "Blue" 또는 "Green" 입력하게 하기
   - 서버에서 응답으로 현재 환경 표시

3. **시각화**:
   - 터미널 폰트 크기 크게
   - `watch` 명령어로 실시간 모니터링
   ```bash
   watch -n 1 'aws ecs describe-services \
     --cluster chatapp-dev-cluster \
     --services chatapp-dev-service-blue chatapp-dev-service-green \
     --query "services[*].{Service:serviceName,Running:runningCount}"'
   ```

4. **음향 효과** (선택):
   - 배포 시작: `say "Deployment started"`
   - 배포 완료: `say "Deployment successful"`

---

## 예상 질문 & 답변

**Q: Blue/Green 배포 비용이 2배 아닌가요?**
A: 잠깐 동안만 2배이고, 배포 후 이전 환경을 축소하면 됩니다. 해커톤에서는 시연 목적으로 둘 다 유지했습니다.

**Q: 데이터베이스는 어떻게 관리하나요?**
A: DynamoDB는 Blue/Green과 무관하게 단일 인스턴스를 공유합니다. 스키마 변경이 필요하면 backward compatible하게 설계합니다.

**Q: WebSocket 연결이 끊기지 않는 이유는?**
A: 기존 연결은 유지하고, 새 연결만 새 타겟으로 라우팅하기 때문입니다. ALB의 connection draining 기능 덕분입니다.

**Q: 실패하면 어떻게 하나요?**
A: 즉시 트래픽을 100% Blue로 되돌립니다. 1분 안에 롤백 가능합니다.
