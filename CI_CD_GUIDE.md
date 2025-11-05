CI/CD 가이드현재 ECS는 새 이미지를 사용하도록 강제 업데이트 적용되어있음.

블루환경, 그린환경 강제 배포 명령어:

```bash
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --force-new-deployment \
  --region ap-northeast-2

aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-green \
  --force-new-deployment \
  --region ap-northeast-2
```


## 목표
코드를 빌드하고 Docker 이미지로 만들어 ECR에 업로드

**산출물**: `137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:v1.0.0`
---
## 사전 준비

환경 변수 설정:

```bash
export AWS_ACCOUNT_ID=137068226866
export AWS_REGION=ap-northeast-2
export ECR_REPOSITORY=chatapp-dev
export IMAGE_TAG=v1.0.0  # 버전에 맞게 변경
```
---
## Step 1: 애플리케이션 빌드 (자바 스프링 예시)

```bash
# 프로젝트 빌드
./gradlew clean bootJar

# 또는 Maven
./mvnw clean package

# 빌드 결과 확인
ls -lh build/libs/*.jar
```
---
## Step 2: Docker 이미지 빌드

### 중요: Apple Silicon Mac 사용 시 필수!

```bash
# 올바른 빌드 (AMD64 아키텍처)
docker build --platform linux/amd64 \
  -t chatapp:${IMAGE_TAG} \
  -t chatapp:latest \
  .

# 잘못된 빌드 (ARM64) - 이렇게 하면 ECS에서 에러!
docker build -t chatapp:${IMAGE_TAG} .
```

**에러 예시:** "exec format error" → 아키텍처 불일치

### Dockerfile 예시

```dockerfile
FROM openjdk:17-slim
WORKDIR /app
COPY build/libs/*.jar app.jar

# Health check (선택사항)
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s \
  CMD curl -f http://localhost:3000/health || exit 1

EXPOSE 3000
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 빌드 확인

```bash
# 이미지 목록 확인
docker images | grep chatapp

# 로컬 테스트 (선택사항)
docker run -p 3000:3000 chatapp:${IMAGE_TAG}

# 다른 터미널에서: curl http://localhost:3000/health
```

---
## Step 3: ECR에 푸시

### 3-1. ECR 로그인

```bash
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

성공 메시지: "Login Succeeded"

### 3-2. 이미지 태그

```bash
# 버전 태그
docker tag chatapp:${IMAGE_TAG} \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}

# latest 태그
docker tag chatapp:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest
```

### 3-3. ECR에 푸시

```bash
# 버전 태그 푸시
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}

# latest 태그 푸시
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest
```

### 3-4. 푸시 확인

```bash
# ECR 이미지 목록 확인
aws ecr describe-images \
  --repository-name ${ECR_REPOSITORY} \
  --region ${AWS_REGION} \
  --query 'sort_by(imageDetails,& imagePushedAt)[-5:].[imageTags[0],imagePushedAt]' \
  --output table
```

---
## Jenkins/GitHub Actions 통합

### Jenkins Pipeline 예시

```groovy
pipeline {
    agent any
    environment {
        AWS_ACCOUNT_ID = '137068226866'
        AWS_REGION = 'ap-northeast-2'
        ECR_REPOSITORY = 'chatapp-dev'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
    }
    stages {
        stage('Build') {
            steps {
                sh './gradlew clean bootJar'
            }
        }
        stage('Docker Build') {
            steps {
                sh """
                    docker build --platform linux/amd64 \
                      -t chatapp:${IMAGE_TAG} .
                """
            }
        }
        stage('Push to ECR') {
            steps {
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} | \
                      docker login --username AWS --password-stdin \
                      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                    docker tag chatapp:${IMAGE_TAG} \
                      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                    docker push \
                      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                """
            }
        }
        stage('Notify CD Team') {
            steps {
                // CD 팀에게 알림 (Slack, Email 등)
                echo "새 이미지 준비됨: ${ECR_REPOSITORY}:${IMAGE_TAG}"
            }
        }
    }
}
```

### GitHub Actions 예시

```yaml
name: CI - Build and Push to ECR
on:
  push:
    branches:
      - main
      - develop
env:
  AWS_REGION: ap-northeast-2
  ECR_REPOSITORY: chatapp-dev
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout
      uses: actions/checkout@v3
    - name: Set up JDK 17
      uses: actions/setup-java@v3
      with:
        java-version: '17'
        distribution: 'temurin'
    - name: Build with Gradle
      run: ./gradlew clean bootJar
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v1
    - name: Build and push Docker image
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker build --platform linux/amd64 \
          -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG \
          $ECR_REGISTRY/$ECR_REPOSITORY:latest
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
        echo "Image pushed: $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
```

---
## 이미지 태그 전략

### 권장 전략

1. Git Commit Hash (자동 추적)

```bash
IMAGE_TAG=$(git rev-parse --short HEAD)
# 예: git-abc1234
```

2. Semantic Versioning (명확한 버전)

```bash
IMAGE_TAG=v1.0.0
# v1.0.0, v1.1.0, v2.0.0
```

3. Build Number (CI 통합)

```bash
IMAGE_TAG=build-${BUILD_NUMBER}
# build-123, build-124
```

4. Timestamp (시간 추적)

```bash
IMAGE_TAG=$(date +%Y%m%d-%H%M%S)
# 20250104-123456
```

### 비권장: latest만 사용

문제점:
- 버전 추적 불가
- 롤백 어려움
- 어떤 코드인지 알 수 없음

---
## 트러블슈팅

### 1. ECR 로그인 실패

증상: "no basic auth credentials"

해결:

```bash
# 1. AWS 자격증명 확인
aws sts get-caller-identity

# 2. IAM 권한 확인 (ecr:GetAuthorizationToken 필요)
```

### 2. Docker 빌드 느림

증상: Apple Silicon Mac에서 AMD64 빌드 시 느림

해결: Docker Buildx 사용

```bash
docker buildx build --platform linux/amd64 -t chatapp:v1.0.0 .
```

### 3. ECR 푸시 실패

증상: "repository does not exist"

해결: ECR 리포지토리 확인

```bash
aws ecr describe-repositories --repository-names chatapp-dev --region ap-northeast-2

# 없으면 생성
aws ecr create-repository --repository-name chatapp-dev --region ap-northeast-2
```

### 4. Docker 용량 부족

```bash
# 정리
docker system prune -a --volumes

# 확인
docker system df
```

---
## CI 완료 체크리스트
- [ ] 코드 빌드 성공 (./gradlew bootJar)
- [ ] Docker 이미지 빌드 성공 (--platform linux/amd64 사용)
- [ ] ECR 로그인 성공
- [ ] 이미지 태그 명확함 (v1.0.0, git-abc1234 등)
- [ ] ECR 푸시 성공
- [ ] ECR에서 이미지 확인됨
- [ ] CD 팀에게 알림 전달 (이미지 태그 포함)
---

새 이미지 준비 완료
이미지 정보:
- 리포지토리: 137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev
- 태그: v1.0.0
- 전체 URL: 137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:v1.0.0
- 빌드 시간: 2025-11-04 10:30:00 KST
- Git Commit: abc1234

---
## 목표
ECR에 있는 Docker 이미지를 ECS Fargate에 배포
입력: `137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:v1.0.0`
결과: 사용자가 접근 가능한 애플리케이션
---
## 두 가지 배포 방법
| 방법 | 도구 | 장점 | 단점 | 추천 대상 |
|-----|------|------|------|----------|
| 방법 1 | AWS CLI 직접 | 간단, 빠름, 즉시 적용 | 수동, Blue/Green 수동 관리 | 소규모 팀, 빠른 배포 |
| 방법 2 | AWS CodeDeploy | Blue/Green 자동화, 롤백 자동화, 승인 단계 | 초기 설정 복잡 | 대규모 팀, 엔터프라이즈 |
---
## 방법 1: AWS CLI 직접 배포 (간단, 빠름)
### 특징
- CI 팀이 ECR에 이미지 푸시 완료
- CD 팀이 AWS CLI로 ECS 서비스 업데이트
- 2-3분 안에 배포 완료
### 사전 준비

환경 변수 설정:

```bash
export AWS_REGION=ap-northeast-2
export ECS_CLUSTER=chatapp-dev-cluster
export ECS_SERVICE=chatapp-dev-service-blue  # 또는 green
export IMAGE_TAG=v1.0.0  # CI 팀에게 받은 태그
```

### Step 1: 배포 실행

Blue 서비스에 배포 (Production, 90% 트래픽):

```bash
aws ecs update-service \
  --cluster ${ECS_CLUSTER} \
  --service ${ECS_SERVICE} \
  --force-new-deployment \
  --region ${AWS_REGION}
```

--force-new-deployment의 역할:
- 현재 Task Definition의 이미지를 다시 pull
- ECR의 latest 태그가 업데이트되었다면 새 이미지 사용
- 특정 태그 배포는 terraform으로 Task Definition 업데이트 필요

### Step 2: 배포 완료 대기

```bash
# 배포 완료 대기 (1-3분 소요)
aws ecs wait services-stable \
  --cluster ${ECS_CLUSTER} \
  --services ${ECS_SERVICE} \
  --region ${AWS_REGION}
```

### Step 3: 배포 확인

```bash
# 1. 서비스 상태 확인
aws ecs describe-services \
  --cluster ${ECS_CLUSTER} \
  --services ${ECS_SERVICE} \
  --region ${AWS_REGION} \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Events:events[0:3]}' \
  --output table

# 2. 실행 중인 태스크 확인
aws ecs list-tasks \
  --cluster ${ECS_CLUSTER} \
  --service-name ${ECS_SERVICE} \
  --region ${AWS_REGION}

# 3. 타겟 그룹 Health 확인
aws elbv2 describe-target-health \
  --target-group-arn <BLUE_TARGET_GROUP_ARN> \
  --region ${AWS_REGION}

# 4. ALB DNS 확인 및 테스트
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names chatapp-dev-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region ${AWS_REGION})
echo "ALB URL: http://${ALB_DNS}"

# Health Check 테스트
curl http://${ALB_DNS}/health

# API 테스트
curl -X POST http://${ALB_DNS}/api/join
```

### Step 4: 로그 확인

```bash
# 실시간 로그
aws logs tail /ecs/chatapp-dev --follow --region ${AWS_REGION}

# 최근 10분 로그
aws logs tail /ecs/chatapp-dev --since 10m --region ${AWS_REGION}

# 에러만 필터링
aws logs tail /ecs/chatapp-dev --follow --filter-pattern "ERROR" --region ${AWS_REGION}
```

### Jenkins 통합 (방법 1)

```groovy
stage('Deploy to ECS') {
    steps {
        sh """
            aws ecs update-service \
              --cluster chatapp-dev-cluster \
              --service chatapp-dev-service-blue \
              --force-new-deployment \
              --region ap-northeast-2
            aws ecs wait services-stable \
              --cluster chatapp-dev-cluster \
              --services chatapp-dev-service-blue \
              --region ap-northeast-2
        """
    }
}
stage('Verify Deployment') {
    steps {
        sh """
            ALB_DNS=\$(aws elbv2 describe-load-balancers \
              --names chatapp-dev-alb \
              --query 'LoadBalancers[0].DNSName' \
              --output text \
              --region ap-northeast-2)
            curl -f http://\${ALB_DNS}/health || exit 1
            echo "Deployment verified!"
        """
    }
}
```

---
## 방법 2: AWS CodeDeploy (전문적, 자동화)
### 특징
- Blue/Green 배포 자동화
- 자동 Health Check 및 롤백
- 승인 단계 추가 가능
- 배포 이력 관리
### CodeDeploy 구성 요소

```
┌────────────────────────────────────────┐
│ appspec.yml                            │  ← 배포 설정 파일
│ - Task Definition 경로                 │
│ - Health Check 설정                    │
│ - 트래픽 전환 설정                      │
└────────────────────────────────────────┘
                ↓
┌────────────────────────────────────────┐
│ CodeDeploy Application                 │  ← 배포 그룹
│ - ECS 클러스터 연결                     │
│ - Blue/Green 설정                      │
└────────────────────────────────────────┘
                ↓
┌────────────────────────────────────────┐
│ Deployment                             │  ← 실제 배포 실행
│ 1. Green 환경에 새 버전 배포            │
│ 2. Health Check 통과 확인              │
│ 3. 트래픽 Green으로 전환               │
│ 4. Blue 환경 종료                      │
└────────────────────────────────────────┘
```

### appspec.yml 작성

프로젝트 루트에 appspec.yml 생성:

```yaml
version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: "arn:aws:ecs:ap-northeast-2:137068226866:task-definition/chatapp-dev-task-blue:1"
        LoadBalancerInfo:
          ContainerName: "chatapp-container"
          ContainerPort: 3000
        PlatformVersion: "LATEST"
        NetworkConfiguration:
          AwsvpcConfiguration:
            Subnets:
              - "subnet-xxxxx"
              - "subnet-yyyyy"
            SecurityGroups:
              - "sg-xxxxx"
            AssignPublicIp: "DISABLED"
Hooks:
  - BeforeInstall: "BeforeInstall"
  - AfterInstall: "AfterInstall"
  - AfterAllowTestTraffic: "AfterAllowTestTraffic"
  - BeforeAllowTraffic: "BeforeAllowTraffic"
  - AfterAllowTraffic: "AfterAllowTraffic"
```

### CodeDeploy Application 생성 (초기 1회)

```bash
# 1. CodeDeploy Application 생성
aws deploy create-application \
  --application-name chatapp-ecs-app \
  --compute-platform ECS \
  --region ap-northeast-2

# 2. Deployment Group 생성
aws deploy create-deployment-group \
  --application-name chatapp-ecs-app \
  --deployment-group-name chatapp-blue-green \
  --deployment-config-name CodeDeployDefault.ECSAllAtOnce \
  --service-role-arn arn:aws:iam::137068226866:role/CodeDeployServiceRole \
  --ecs-services clusterName=chatapp-dev-cluster,serviceName=chatapp-dev-service-blue \
  --load-balancer-info targetGroupPairInfoList='[{targetGroups:[{name=chatapp-dev-blue-tg},{name=chatapp-dev-green-tg}],prodTrafficRoute={listenerArns=[arn:aws:elasticloadbalancing:ap-northeast-2:137068226866:listener/app/chatapp-dev-alb/xxxxx]}}]' \
  --blue-green-deployment-configuration 'terminateBlueInstancesOnDeploymentSuccess={action=TERMINATE,terminationWaitTimeInMinutes=5},deploymentReadyOption={actionOnTimeout=CONTINUE_DEPLOYMENT}' \
  --region ap-northeast-2
```

### 배포 실행

```bash
# 새 Task Definition 등록
NEW_TASK_DEF=$(aws ecs register-task-definition \
  --cli-input-json file://task-definition.json \
  --region ap-northeast-2 \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

# CodeDeploy로 배포
aws deploy create-deployment \
  --application-name chatapp-ecs-app \
  --deployment-group-name chatapp-blue-green \
  --revision '{
    "revisionType": "AppSpecContent",
    "appSpecContent": {
      "content": "{\"version\":0.0,\"Resources\":[{\"TargetService\":{\"Type\":\"AWS::ECS::Service\",\"Properties\":{\"TaskDefinition\":\"'${NEW_TASK_DEF}'\",\"LoadBalancerInfo\":{\"ContainerName\":\"chatapp-container\",\"ContainerPort\":3000}}}}]}"
    }
  }' \
  --region ap-northeast-2
```

### 배포 상태 확인

```bash
# 배포 목록
aws deploy list-deployments \
  --application-name chatapp-ecs-app \
  --deployment-group-name chatapp-blue-green \
  --region ap-northeast-2

# 특정 배포 상태
aws deploy get-deployment \
  --deployment-id d-XXXXXXXXX \
  --region ap-northeast-2
```

### Jenkins 통합 (방법 2)

```groovy
stage('Deploy with CodeDeploy') {
    steps {
        sh """
            # Task Definition 업데이트
            NEW_TASK_DEF=\$(aws ecs register-task-definition \
              --family chatapp-dev-task-blue \
              --container-definitions '[{"name":"chatapp-container","image":"137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:${IMAGE_TAG}","portMappings":[{"containerPort":3000}]}]' \
              --region ap-northeast-2 \
              --query 'taskDefinition.taskDefinitionArn' \
              --output text)
            # CodeDeploy 배포
            aws deploy create-deployment \
              --application-name chatapp-ecs-app \
              --deployment-group-name chatapp-blue-green \
              --revision revisionType=AppSpecContent,appSpecContent={content='{...}'} \
              --region ap-northeast-2
        """
    }
}
```


---
## Blue/Green 배포 전략
### 현재 구성

```
ALB
├─ 90% → Blue Target Group → chatapp-dev-service-blue
└─ 10% → Green Target Group → chatapp-dev-service-green
```

### 배포 시나리오

#### 시나리오 1: Blue만 업데이트 (일반)

```bash
# Blue 서비스 업데이트
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --force-new-deployment \
  --region ap-northeast-2
```

**결과:** 90% 트래픽이 새 버전으로 전환

#### 시나리오 2: Green에 먼저 배포 (안전)

```bash
# 1. Green에 새 버전 배포
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-green \
  --force-new-deployment \
  --region ap-northeast-2

# 2. Green 서비스 안정화 대기
aws ecs wait services-stable \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-green \
  --region ap-northeast-2

# 3. Green 테스트 (10% 트래픽으로)
curl http://chatapp-dev-alb-xxxxx.ap-northeast-2.elb.amazonaws.com/health

# 4. 문제 없으면 Blue도 업데이트
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --force-new-deployment \
  --region ap-northeast-2
```

#### 시나리오 3: 트래픽 비율 변경 (Canary)

```bash
# Green에 새 버전 배포 후 트래픽 점진적 증가
cd terraform

# terraform.tfvars 수정
blue_weight = 50   # Blue 50%
green_weight = 50  # Green 50%
terraform apply

# 문제 없으면 Green 100%
blue_weight = 0
green_weight = 100
terraform apply
```

---
## 롤백 가이드

### 방법 1: 이전 이미지로 롤백

```bash
# 1. ECR에서 이전 버전 확인
aws ecr describe-images \
  --repository-name chatapp-dev \
  --region ap-northeast-2 \
  --query 'sort_by(imageDetails,& imagePushedAt)[-10:].[imageTags[0],imagePushedAt]' \
  --output table

# 2. 이전 버전을 latest로 재지정
PREVIOUS_TAG=v0.9.9
docker pull 137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:${PREVIOUS_TAG}
docker tag 137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:${PREVIOUS_TAG} \
           137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:latest
docker push 137068226866.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:latest

# 3. ECS 재배포
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --force-new-deployment \
  --region ap-northeast-2
```

### 방법 2: Task Definition 버전으로 롤백

```bash
# 1. Task Definition 버전 목록
aws ecs list-task-definitions \
  --family-prefix chatapp-dev-task-blue \
  --sort DESC \
  --region ap-northeast-2

# 2. 이전 버전으로 롤백 (예: revision 5)
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --task-definition chatapp-dev-task-blue:5 \
  --region ap-northeast-2
```

### 방법 3: Blue/Green 스왑

```bash
# Green이 정상이고 Blue가 문제라면
cd terraform

# terraform.tfvars
blue_weight = 10   # Blue를 10%로
green_weight = 90  # Green을 90%로
terraform apply
```

---
## 자주 사용하는 명령어

```bash
# 서비스 상태 한눈에 보기
aws ecs describe-services \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue chatapp-dev-service-green \
  --region ap-northeast-2 \
  --query 'services[*].{Name:serviceName,Status:status,Running:runningCount,Desired:desiredCount}' \
  --output table

# 실시간 로그
aws logs tail /ecs/chatapp-dev --follow --region ap-northeast-2

# ALB URL 확인
aws elbv2 describe-load-balancers \
  --names chatapp-dev-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region ap-northeast-2
```

