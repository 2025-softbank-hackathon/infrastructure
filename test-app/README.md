# 인프라 테스트 애플리케이션

간단한 Flask 애플리케이션으로 AWS 인프라의 모든 구성 요소를 테스트합니다.

## 테스트 항목

- ✅ **DynamoDB 연결**: 데이터 쓰기/읽기 테스트
- ✅ **Redis 연결**: ElastiCache 연결 및 데이터 저장 테스트
- ✅ **NAT Gateway**: Private Subnet에서 외부 인터넷 접근 테스트
- ✅ **Health Check**: ECS/ALB health check 엔드포인트

## 엔드포인트

| 엔드포인트 | 설명 |
|----------|------|
| `GET /` | Hello World + 환경 정보 |
| `GET /health` | Health check (ECS/ALB용) |
| `GET /test/all` | 모든 테스트 실행 (DynamoDB + Redis + NAT) |
| `GET /test/dynamodb` | DynamoDB만 테스트 |
| `GET /test/redis` | Redis만 테스트 |
| `GET /test/nat` | NAT Gateway (외부 통신)만 테스트 |

## 사용 방법

자세한 배포 및 테스트 가이드는 **[TEST_GUIDE.md](./TEST_GUIDE.md)** 참고

### 빠른 시작

```bash
# 1. Docker 이미지 빌드
docker build -t softbank-test:latest .

# 2. ECR에 푸시
docker tag softbank-test:latest <ACCOUNT>.dkr.ecr.ap-northeast-1.amazonaws.com/softbank-dev:test-v1
docker push <ACCOUNT>.dkr.ecr.ap-northeast-1.amazonaws.com/softbank-dev:test-v1

# 3. Terraform apply
cd ../terraform
terraform apply -var="container_image=<ACCOUNT>.dkr.ecr.ap-northeast-1.amazonaws.com/softbank-dev:test-v1"

# 4. 테스트
curl http://<ALB_DNS_NAME>/test/all
```

## 환경 변수

| 변수 | 설명 | 기본값 |
|-----|------|--------|
| `REDIS_HOST` | Redis 엔드포인트 | localhost |
| `REDIS_PORT` | Redis 포트 | 6379 |
| `DYNAMODB_TABLE_NAME` | DynamoDB 테이블 이름 | test-table |
| `AWS_REGION` | AWS 리전 | ap-northeast-1 |
| `PORT` | 애플리케이션 포트 | 8080 |

## 파일 구조

```
test-app/
├── app.py              # Flask 애플리케이션
├── requirements.txt    # Python 의존성
├── Dockerfile          # Docker 이미지 빌드
├── README.md           # 이 파일
└── TEST_GUIDE.md       # 상세 테스트 가이드
```
