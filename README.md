# Softbank Infrastructure

AWS-based Real-time Chat Application Infrastructure with Blue/Green Deployment

## Project Overview

This project uses Terraform to build a scalable and secure real-time chat application infrastructure on AWS, optimized for **hackathon demonstrations**.

### Key Features

- **WebSocket** real-time communication
- **Blue/Green Deployment** strategy for zero-downtime updates
- Live demonstration of traffic shifting (90/10 → 50/50 → 10/90)
- Cost-optimized for hackathon/development (~$50-70/month)
- Fully managed AWS services

### Hackathon Demo Highlights

This infrastructure is designed to demonstrate **zero-downtime deployment** in a 4-minute live presentation:
1. Users connected to Blue environment (90% traffic)
2. Live traffic shift to 50/50 split
3. Complete shift to Green environment (90% traffic)
4. **No user disconnections** throughout the entire process

See [DEMO_GUIDE.md](./DEMO_GUIDE.md) for the complete presentation script.

## 아키텍처

자세한 아키텍처 설명은 [ARCHITECTURE.md](./ARCHITECTURE.md)를 참조하세요.

### 사용된 AWS 서비스

- **Compute**: ECS Fargate
- **Network**: VPC, ALB, API Gateway, CloudFront
- **Database**: DynamoDB, ElastiCache Redis
- **Storage**: S3
- **Security**: IAM, Security Groups, VPC Endpoints
- **Monitoring**: CloudWatch (향후 X-Ray 추가)

## Prerequisites

### 필수 도구

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- AWS 계정 및 적절한 IAM 권한

### AWS CLI 설정

#### 1. AWS CLI 설치

**macOS (Homebrew)**:
```bash
brew install awscli
```

**Linux**:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Windows**:
```powershell
# MSI 인스톨러 다운로드 및 실행
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```

#### 2. AWS 자격 증명 설정

```bash
aws configure
```

입력 항목:
- **AWS Access Key ID**: IAM 사용자의 Access Key
- **AWS Secret Access Key**: IAM 사용자의 Secret Key
- **Default region name**: `ap-northeast-1` (도쿄 리전)
- **Default output format**: `json`

자격 증명은 `~/.aws/credentials`에 저장됩니다:
```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
```

설정 확인:
```bash
aws sts get-caller-identity
```

#### 3. 프로파일 사용 (옵션)

여러 AWS 계정을 사용하는 경우:
```bash
aws configure --profile softbank
```

Terraform에서 프로파일 사용:
```bash
export AWS_PROFILE=softbank
```

## 프로젝트 구조

```
.
├── README.md
├── ARCHITECTURE.md
└── terraform/
    ├── main.tf                    # 메인 설정
    ├── variables.tf               # 변수 정의
    ├── outputs.tf                 # 출력값
    ├── versions.tf                # Provider 버전
    ├── terraform.tfvars.example   # 변수값 예제
    └── modules/
        ├── vpc/                   # VPC 모듈
        ├── security-groups/       # Security Groups
        ├── iam/                   # IAM Roles
        ├── dynamodb/              # DynamoDB 테이블
        ├── elasticache/           # Redis 클러스터
        ├── alb/                   # Application Load Balancer
        ├── ecs/                   # ECS Fargate
        ├── api-gateway/           # API Gateway WebSocket
        └── cloudfront/            # CloudFront + S3
```

## 시작하기

### 1. 저장소 클론

```bash
git clone <repository-url>
cd softbank-infrastructure
```

### 2. Terraform 변수 설정

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` 파일을 편집하여 필요한 값을 설정:

```hcl
aws_region   = "ap-northeast-1"
project_name = "chatapp"
environment  = "dev"

# 컨테이너 이미지 (실제 이미지로 변경 필요)
container_image = "your-ecr-repo/chatapp:latest"

# S3 버킷 이름 (고유한 이름으로 변경)
s3_bucket_name = "chatapp-dev-static-20240101"
```

### 3. Terraform 초기화

```bash
terraform init
```

### 4. 인프라 계획 확인

```bash
terraform plan
```

### 5. 인프라 배포

```bash
terraform apply
```

배포 확인 메시지가 나타나면 `yes`를 입력합니다.

### 6. 출력값 확인

배포가 완료되면 다음과 같은 출력값을 확인할 수 있습니다:

```bash
terraform output
```

주요 출력값:
- `api_gateway_websocket_url`: WebSocket API 엔드포인트
- `cloudfront_domain_name`: 정적 웹사이트 도메인
- `alb_dns_name`: ALB DNS 이름
- `redis_endpoint`: Redis 엔드포인트

### 7. 연결 테스트

**WebSocket 연결 테스트** (wscat 사용):
```bash
# wscat 설치
npm install -g wscat

# WebSocket 연결 테스트
WS_URL=$(terraform output -raw api_gateway_websocket_url)
wscat -c $WS_URL
```

**ALB 헬스 체크**:
```bash
# Blue 타겟 그룹 상태 확인
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_target_group_arn) \
  --query 'TargetHealthDescriptions[*].TargetHealth.State'

# 예상 출력: ["healthy"]
```

**완전한 테스트 가이드**: [TEST_GUIDE.md](./TEST_GUIDE.md) 참조

## DynamoDB 테이블 구조

### 1. Messages 테이블 (`chatapp-dev-messages`)

채팅 메시지를 저장하는 테이블입니다.

| 속성명 | 타입 | 설명 |
|--------|------|------|
| roomId (PK) | String | 채팅방 ID |
| timestamp (SK) | Number | 메시지 타임스탬프 (Unix time) |
| userId | String | 사용자 ID |
| message | String | 메시지 내용 |
| ttl | Number | TTL (자동 삭제 시간) |

**GSI**: `userId-timestamp-index`
- Hash Key: userId
- Range Key: timestamp

### 2. Connections 테이블 (`chatapp-dev-connections`)

WebSocket 연결 정보를 저장하는 테이블입니다.

| 속성명 | 타입 | 설명 |
|--------|------|------|
| connectionId (PK) | String | WebSocket 연결 ID |
| userId | String | 사용자 ID (user1, user2, ...) |
| connectedAt | Number | 연결 시간 |
| ttl | Number | TTL (자동 삭제 시간) |

**GSI**: `userId-index`
- Hash Key: userId

### 3. User Counter 테이블 (`chatapp-dev-user-counter`)

자동 증가 사용자 ID를 관리하는 테이블입니다.

| 속성명 | 타입 | 설명 |
|--------|------|------|
| counterId (PK) | String | 카운터 ID (예: "userCounter") |
| currentValue | Number | 현재 카운터 값 |

## 배포 후 작업

### 1. Docker 이미지 빌드 및 푸시

실제 채팅 애플리케이션 이미지를 ECR에 푸시해야 합니다:

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-northeast-1.amazonaws.com

# 이미지 빌드
docker build -t chatapp .

# 태그 지정
docker tag chatapp:latest <account-id>.dkr.ecr.ap-northeast-1.amazonaws.com/chatapp:latest

# 푸시
docker push <account-id>.dkr.ecr.ap-northeast-1.amazonaws.com/chatapp:latest
```

### 2. ECS 서비스 업데이트

새 이미지를 배포하려면:

```bash
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --force-new-deployment
```

### 3. 정적 웹사이트 배포

S3에 정적 파일 업로드:

```bash
aws s3 sync ./frontend/build s3://<bucket-name>/
```

CloudFront 캐시 무효화:

```bash
aws cloudfront create-invalidation \
  --distribution-id <distribution-id> \
  --paths "/*"
```

## Hackathon Live Demo (4-Minute Presentation)

### Pre-Demo Setup (Before Presentation)

1. **Deploy infrastructure** (~10 minutes):
   ```bash
   cd terraform
   terraform apply
   ```

2. **Verify both environments are healthy**:
   ```bash
   # Check Blue service
   aws ecs describe-services \
     --cluster chatapp-dev-cluster \
     --services chatapp-dev-service-blue \
     --query 'services[0].runningCount'

   # Check Green service
   aws ecs describe-services \
     --cluster chatapp-dev-cluster \
     --services chatapp-dev-service-green \
     --query 'services[0].runningCount'
   ```
   Both should return `1`.

3. **Share CloudFront URL** with audience (5 minutes before demo)
   ```bash
   terraform output cloudfront_domain_name
   ```

### Live Demo Script

**Minute 0-1**: Show current state
```bash
terraform output blue_weight  # Shows: 90
terraform output green_weight  # Shows: 10
```

**Minute 1-2**: Shift to 50/50
```bash
# Edit terraform.tfvars
blue_weight  = 50
green_weight = 50

terraform apply -auto-approve
```

**Minute 2-3**: Shift to Green-dominant
```bash
# Edit terraform.tfvars
blue_weight  = 10
green_weight = 90

terraform apply -auto-approve
```

**Minute 3-4**: Verify no disconnections
- Ask audience: "Did anyone get disconnected?"
- Show CloudWatch metrics

**Complete demo script**: See [DEMO_GUIDE.md](./DEMO_GUIDE.md)

### Emergency Rollback

If issues occur during demo:
```bash
# Immediate rollback to Blue 100%
blue_weight  = 100
green_weight = 0

terraform apply -auto-approve
```

## 모니터링

### CloudWatch Logs

ECS 로그 확인:
```bash
aws logs tail /ecs/chatapp-dev --follow
```

API Gateway 로그 확인:
```bash
aws logs tail /aws/apigateway/chatapp-dev --follow
```

### CloudWatch Metrics

AWS 콘솔에서 다음 메트릭 확인:
- ECS Service CPU/Memory 사용률
- ALB Request Count, Target Response Time
- DynamoDB Read/Write Capacity
- ElastiCache CPU, Network I/O

## Cost Estimation

**Hackathon-Optimized Configuration** (Tokyo Region):

### Resource Breakdown
- **ECS Fargate**: ~$15-20/month
  - Blue: 1 task (0.25 vCPU, 0.5 GB)
  - Green: 1 task (0.25 vCPU, 0.5 GB)
- **ALB**: ~$20-25/month (single ALB)
- **NAT Gateway**: ~$32/month (single NAT, cost-optimized)
- **ElastiCache (t3.micro)**: ~$12/month (single node, no backups)
- **DynamoDB (On-Demand)**: ~$5/month (low traffic)
- **API Gateway**: ~$3/month (WebSocket, low volume)
- **CloudFront**: ~$1/month (minimal traffic)
- **VPC, Security Groups**: Free

**Total Estimated Cost**: ~$50-70/month

### Cost Savings vs. Production Setup
| Item | Production | Hackathon | Savings |
|------|-----------|-----------|---------|
| NAT Gateway | 2 AZs | 1 AZ | ~$32/mo |
| ECS Tasks | 4+ tasks | 2 tasks | ~$30/mo |
| ElastiCache | Multi-node | Single node | ~$15/mo |
| Backups | Enabled | Disabled | ~$10/mo |
| **Total Savings** | | | **~$87/mo** |

### Tips to Reduce Costs Further
1. **Stop during non-demo hours**: Scale ECS tasks to 0
2. **Use Fargate Spot**: ~70% cheaper (but may interrupt)
3. **Delete after hackathon**: Don't forget to `terraform destroy`!

## Resource Cleanup

**IMPORTANT**: After the hackathon, destroy all resources to avoid ongoing charges!

### Quick Cleanup

```bash
# 1. Empty S3 bucket first
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive

# 2. Destroy all infrastructure
cd terraform
terraform destroy -auto-approve
```

### Verify Deletion

```bash
# Check ECS clusters
aws ecs list-clusters

# Check ALBs
aws elbv2 describe-load-balancers

# Check NAT Gateways
aws ec2 describe-nat-gateways --filter "Name=state,Values=available"
```

**Estimated time**: ~10 minutes

### Cost Alert

If you forget to delete, monthly charges will continue (~$50-70/month). Set up a CloudWatch billing alarm!

## 문제 해결

### Terraform 초기화 오류

```bash
rm -rf .terraform .terraform.lock.hcl
terraform init
```

### AWS 자격 증명 오류

```bash
aws configure list
aws sts get-caller-identity
```

### ECS 태스크 시작 실패

CloudWatch Logs에서 오류 확인:
```bash
aws logs tail /ecs/chatapp-dev --follow
```

## 참고 자료

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/intro.html)
- [API Gateway WebSocket](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-websocket-api.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
