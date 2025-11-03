# 아키텍처 개요

## 시스템 아키텍처

이 프로젝트는 AWS 서울 리전(ap-northeast-2)에서 해커톤 데모를 위한 실시간 채팅 애플리케이션 인프라를 구축합니다.

### 핵심 설계 원칙
- **단순 구성**: 관리 포인트 최소화
- **낮은 비용**: 해커톤/데모 특성에 맞는 최적화
- **빠른 롤백**: Blue/Green 배포로 안전한 카나리 전환
- **4분 데모**: 배포 과정 시각화 및 무중단 전환 시연

### 주요 구성 요소

#### 1. 프론트엔드 (정적 웹 호스팅)
- **CloudFront**: CDN을 통한 빠른 콘텐츠 전송
- **S3**: 정적 웹 호스팅 (HTML, CSS, JavaScript)

#### 2. 트래픽 진입
- **Public ALB**: IGW를 통한 직접 외부 접근
  - 포트 80 (HTTP), 443 (HTTPS) 오픈
  - 액세스 로그 → S3 전송

#### 3. 컴퓨트 계층
- **ECS Fargate**: 서버리스 컨테이너 실행 환경
  - Blue 서비스 (90% 트래픽) - 안정적인 프로덕션 버전
  - Green 서비스 (10% 트래픽) - 테스트용 신규 버전
  - 카나리 배포: 10% → 50% → 100% 점진적 전환
- **Application Load Balancer**: 트래픽 분산 및 가중치 기반 라우팅

#### 4. 데이터 계층
- **DynamoDB**: NoSQL 데이터베이스
  - `messages` 테이블: 채팅 메시지 저장
  - `connections` 테이블: WebSocket 연결 정보
  - `user-counter` 테이블: 자동 증가 사용자 ID 관리
- **ElastiCache Redis**: 인메모리 캐싱 및 세션 관리
  - **멀티 AZ 구성**: 프라이머리 1개 + 리드 리플리카 1개
  - cache.t4g.micro 인스턴스 타입
  - 자동 페일오버 활성화
  - 리전 엔드포인트 사용 (애플리케이션 수정 불필요)

#### 5. 네트워킹
- **VPC**: 격리된 네트워크 환경 (10.0.0.0/16)
  - 퍼블릭 서브넷 2개: ALB, NAT Gateway
  - 프라이빗 서브넷 2개: ECS Tasks, ElastiCache
- **IGW**: 인터넷 게이트웨이 연결
- **NAT Gateway**: 1개만 배치 (비용 절감)
  - 첫 번째 AZ(2a)에만 배치
  - 두 AZ의 프라이빗 서브넷이 공유 사용
- **VPC Endpoint**: DynamoDB 프라이빗 액세스

#### 6. 보안
- **ALB Security Group**: 443만 인바운드 오픈
- **ECS Security Group**: ALB에서만 인바운드 허용, 관리 포트 차단
- **Redis Security Group**: ECS에서만 접근 허용

#### 7. 관찰성 & 모니터링
- **CloudWatch 메트릭**:
  - ALB 타겟 헬시 카운트
  - 4xx/5xx 에러율
  - 응답 지연 P95
- **액세스 로그**: ALB → S3 전송
- **CloudWatch Logs**: ECS 컨테이너 로그 (7일 보관)
- **X-Ray**: 추론 경로만 경량 적용 (향후)

### 트래픽 흐름

1. **정적 콘텐츠**:
   ```
   사용자 → CloudFront → S3 → 사용자
   ```

2. **WebSocket 연결 & HTTP 요청**:
   ```
   사용자 → IGW → Public ALB → ECS Fargate (Private Subnet)
   ```

3. **데이터 액세스**:
   ```
   ECS Fargate → VPC Endpoint → DynamoDB
   ECS Fargate → ElastiCache Redis (리전 엔드포인트)
   ```

4. **외부 통신** (ECR 이미지 Pull 등):
   ```
   ECS Fargate (Private) → NAT Gateway (Public) → IGW → 인터넷
   ```

### Blue/Green 카나리 배포

- **Blue 서비스 (초기 90%)**: 안정적인 프로덕션 버전
- **Green 서비스 (초기 10%)**: 신규 버전 테스트

**카나리 전환 시나리오**:
1. Blue 90% / Green 10% (초기)
2. Blue 50% / Green 50% (중간 검증)
3. Blue 10% / Green 90% (전환 준비)
4. Blue 0% / Green 100% (전환 완료)

각 단계에서 CloudWatch 메트릭 모니터링 후 다음 단계로 진행.

### 보안

- **네트워크 격리**: 컴퓨트/데이터 계층은 Private Subnet에 배포
- **Security Groups**: 최소 권한 원칙
  - ALB: 80/443만 인바운드 허용
  - ECS: ALB에서만 인바운드 허용
  - Redis: ECS에서만 접근 허용
- **IAM Roles**: 최소 권한 원칙
- **암호화**:
  - DynamoDB 암호화 활성화
  - Redis at-rest 암호화 활성화
  - S3 암호화 활성화
- **CloudFront**: HTTPS 강제 (정적 콘텐츠)

### 확장성 & 가용성

- **멀티 AZ 배포**: 2개 AZ (ap-northeast-2a, 2c)
  - ALB: 2개 AZ에 분산
  - ECS Fargate: 2개 AZ에 배포 가능
  - Redis: 프라이머리 + 리드 리플리카 (자동 페일오버)
- **DynamoDB**: On-Demand 모드로 자동 확장
- **ECS Auto Scaling**: 향후 구현 가능
- **NAT Gateway**: 1개 사용 (비용 우선)
  - 프로덕션 환경에서는 각 AZ마다 NAT 배치 권장

### 해커톤/데모용 비용 최적화

- **단일 NAT Gateway**: 1개만 사용, 두 AZ가 공유 (월 ~$32 절감)
- **최소 ECS Tasks**: Blue=1, Green=1 (데모용 최소 구성)
- **작은 인스턴스**:
  - Fargate: 256 CPU, 512 MB 메모리
  - Redis: cache.t4g.micro
- **Redis 멀티 AZ**: 프라이머리 1 + 리플리카 1 (가용성 확보)
  - 비용: 월 ~$15 (t4g.micro 2개)
- **백업 비활성화**: ElastiCache 스냅샷 비활성화
- **On-Demand DynamoDB**: 사용한 만큼만 과금
- **Auto Scaling 없음**: 데모용 고정 리소스
- **로그 보관 기간**: 7일로 제한

**예상 비용**: 월 ~$70-90 (해커톤/데모 환경)

### 가용 영역(AZ) 구성

#### 멀티 AZ 전략
- **리전**: ap-northeast-2 (서울)
- **AZ**: 2개 (ap-northeast-2a, ap-northeast-2c)

#### 리소스 배치
- **퍼블릭 서브넷 2개**:
  - ALB ENI가 각 AZ에 배치 (AWS 요구사항)
  - NAT Gateway는 첫 번째 AZ(2a)에만 1개 배치
- **프라이빗 서브넷 2개**:
  - ECS Fargate 태스크가 배포 가능 (Blue/Green 각 1개)
  - Redis: 프라이머리(AZ-a) + 리플리카(AZ-c)

#### NAT Gateway 트레이드오프
- **현재 구성**: 1개 NAT (비용 우선)
  - 두 AZ의 프라이빗 서브넷이 단일 NAT 공유
  - 해당 AZ 장애 시 외부 통신 불가 (ECR 이미지 Pull 등)
  - **데모 특성상 허용 가능**
- **AWS 권장**: 각 AZ마다 NAT 1개씩 (고가용성 우선)
  - 프로덕션 환경에서는 권장

## 아키텍처 다이어그램

프로젝트 루트의 이미지 파일에서 전체 아키텍처 다이어그램을 확인하세요.

## 향후 개선 사항 (프로덕션)

- [ ] **고가용성**: 각 AZ마다 NAT Gateway 배치
- [ ] **Auto Scaling**: ECS 서비스 자동 확장 정책
- [ ] **도메인**: Route53 + ACM 인증서를 통한 HTTPS
- [ ] **보안 강화**: WAF 규칙, GuardDuty, Security Hub
- [ ] **CI/CD**: CodePipeline을 통한 자동 배포
- [ ] **모니터링 고도화**: X-Ray 전면 적용, 커스텀 메트릭
- [ ] **로그 분석**: CloudWatch Logs Insights, Athena
- [ ] **백업**: ElastiCache 스냅샷, DynamoDB PITR 활성화

## 해커톤 데모 시나리오 (4분)

### 목표
**100명의 사용자**가 **5분간 채팅**하는 동안 **무중단 카나리 배포 시연**

### 데모 환경
- **예상 사용자**: 최대 100명
- **사용 시간**: 5분 내외
- **리전**: ap-northeast-2 (서울)
- **초기 상태**: Blue 90% / Green 10%

### 데모 전 준비
1. Blue 서비스와 Green 서비스 모두 헬시 상태 확인
2. CloudWatch 대시보드 준비 (메트릭, 로그)
3. ALB DNS 또는 CloudFront URL을 청중과 공유
4. 100명 사용자 접속 및 채팅 시작

### 데모 진행 (4분 타임라인)

#### **0-1분**: 현재 상태 확인
- Blue 90% / Green 10% 트래픽 분산 확인
- CloudWatch 메트릭 표시:
  - 타겟 헬시 카운트
  - 4xx/5xx 에러율
  - 응답 지연 P95
- 사용자들 채팅 정상 동작 확인

#### **1-2분**: 카나리 50% 전환
- Terraform 또는 AWS CLI로 가중치 변경: Blue 50% / Green 50%
- 실시간 메트릭 모니터링
- **연결 끊김 없음** 강조

#### **2-3분**: 카나리 90% 전환
- 가중치 변경: Blue 10% / Green 90%
- Green 서비스로 대부분 트래픽 이동
- 에러율 변화 없음 확인

#### **3-4분**: 완전 전환 및 모니터링
- 가중치 변경: Blue 0% / Green 100%
- 배포 완료, 모든 트래픽이 Green으로 이동
- CloudWatch 로그에서 연결 상태 확인
- S3 ALB 액세스 로그 언급

### 핵심 메시지
- ✅ **무중단 배포**: 사용자 연결 끊김 없음
- ✅ **점진적 전환**: 10% → 50% → 90% → 100% 카나리 배포
- ✅ **빠른 롤백**: 문제 발생 시 가중치만 변경하면 즉시 롤백
- ✅ **실시간 모니터링**: CloudWatch로 즉각 대응 가능
- ✅ **비용 효율**: 해커톤 특성에 맞는 최적화 (~$70-90/월)

### 롤백 시나리오 (필요시)
Green 서비스에 문제 발견 시:
```bash
# 즉시 Blue로 롤백
terraform apply -var="blue_weight=100" -var="green_weight=0"
# 또는 AWS CLI
aws elbv2 modify-listener --listener-arn <ARN> ...
```
**30초 이내 롤백 완료**
