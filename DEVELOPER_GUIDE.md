# 개발자 가이드

단일 채팅방 실시간 채팅 애플리케이션 개발 가이드입니다.

## 핵심 기능

- **단일 채팅창**: 웹사이트 접속 즉시 하나의 채팅창만 표시
- **랜덤 닉네임**: 백엔드에서 Guest-1234 형식 자동 생성
- **로그인 없음**: 별도 인증 없이 즉시 채팅 가능
- **실시간 통신**: Redis Pub/Sub으로 메시지 브로드캐스트

## 아키텍처 흐름

```
클라이언트 → ALB → ECS(Fargate) 백엔드
                     ├─ (1) DynamoDB에 저장 (Single Source of Truth)
                     └─ (2) Redis Pub/Sub 발행 → 모든 인스턴스가 실시간 수신
```

**핵심:**
- DynamoDB: 영구 저장 (pk="CHAT" Query는 매우 빠름)
- Redis: 실시간 전파만 (저장 없음, Dual-Write 문제 없음)

---

## DynamoDB 테이블

### Messages 테이블

| 속성명 | 타입 | 키 타입 | 설명 |
|--------|------|---------|------|
| `pk` | String | **PK** | 고정값: "CHAT" |
| `timestamp` | Number | **SK** | 메시지 시간 (Unix ms) |
| `message_id` | String | - | 메시지 고유 ID (UUID) |
| `nickname` | String | - | Guest-1234 형식 |
| `message` | String | - | 메시지 내용 |
| `ttl` | Number | TTL | **1시간 후 자동 삭제** |

**장점:** 모든 메시지가 같은 파티션(pk="CHAT") → Query 한 번으로 최근 N개 빠르게 조회

---

## Redis 사용 (Pub/Sub + Rate Limiting만)

| 용도 | 타입 | 키/채널 | TTL | 설명 |
|------|------|---------|-----|------|
| 실시간 브로드캐스트 | Pub/Sub | `chat` | - | 메시지 전파 전용 (저장 안함) |
| Rate Limiting | String | `limit:{nickname}` | 60초 | 1분에 10개 제한 |

**중요 원칙:**
- **메시지를 Redis에 저장하지 않음** (Dual-Write 문제 방지)
- **DynamoDB가 Single Source of Truth** (Query 성능 충분히 빠름)
- **Redis Pub/Sub는 실시간 전달만** (데이터 저장 아님)

---

## 핵심 코드 예시

### 1. 엔티티

```java
@DynamoDbBean
public class ChatMessage {
    private String pk;
    private Long timestamp;
    private String messageId;
    private String nickname;
    private String message;
    private Long ttl;

    // DynamoDB SDK용 기본 생성자 (필수)
    public ChatMessage() {}

    public ChatMessage(String nickname, String message) {
        this.pk = "CHAT";  // 고정값
        this.messageId = UUID.randomUUID().toString();
        this.nickname = nickname;
        this.message = message;
        this.timestamp = Instant.now().toEpochMilli();
        this.ttl = Instant.now().getEpochSecond() + 3600;  // 1시간
    }

    @DynamoDbPartitionKey
    public String getPk() { return pk; }
    public void setPk(String pk) { this.pk = pk; }

    @DynamoDbSortKey
    public Long getTimestamp() { return timestamp; }
    public void setTimestamp(Long timestamp) { this.timestamp = timestamp; }

    public String getMessageId() { return messageId; }
    public void setMessageId(String messageId) { this.messageId = messageId; }

    public String getNickname() { return nickname; }
    public void setNickname(String nickname) { this.nickname = nickname; }

    public String getMessage() { return message; }
    public void setMessage(String message) { this.message = message; }

    public Long getTtl() { return ttl; }
    public void setTtl(Long ttl) { this.ttl = ttl; }
}
```

### 2. 닉네임 생성 (랜덤)

```java
@Service
public class NicknameService {
    private final Random random = new Random();

    public String generateNickname() {
        int num = 1000 + random.nextInt(9000);  // 1000-9999
        return "Guest-" + num;
    }
}
```

### 3. 메시지 저장/조회

```java
@Repository
public class MessageRepository {
    private final DynamoDbTable<ChatMessage> table;

    public void save(ChatMessage msg) {
        table.putItem(msg);
    }

    public List<ChatMessage> getRecent(int limit) {
        // Query로 효율적 조회 (Scan 아님!)
        return table.query(QueryEnhancedRequest.builder()
            .queryConditional(QueryConditional.keyEqualTo(
                Key.builder().partitionValue("CHAT").build()))
            .scanIndexForward(false)  // 최신순
            .limit(limit)
            .build())
            .items().stream().toList();
    }
}
```

---

### 4. Redis Pub/Sub (캐시 저장 없음, 전파만)

```java
@Service
public class RedisPubSubService {
    private final RedisTemplate<String, Object> redis;
    private static final String CHANNEL = "chat";

    // 실시간 브로드캐스트 (저장 안함!)
    public void publish(ChatMessage msg) {
        redis.convertAndSend(CHANNEL, msg);
    }

    // Rate Limiting
    public boolean checkLimit(String nickname) {
        Long count = redis.opsForValue().increment("limit:" + nickname);
        if (count == 1) {
            redis.expire("limit:" + nickname, 60, TimeUnit.SECONDS);
        }
        return count <= 10;  // 1분에 10개 제한
    }
}
```

**핵심:** Redis는 메시지를 **저장하지 않고** Pub/Sub로 **전달만** 합니다!

---

### 5. Redis Subscriber (WebSocket으로 클라이언트 전송)

```java
@Component
public class RedisMessageListener implements MessageListener {
    private final SimpMessagingTemplate messagingTemplate;

    @Override
    public void onMessage(Message message, byte[] pattern) {
        // Redis Pub/Sub에서 메시지 수신
        ChatMessage msg = (ChatMessage) redisTemplate
            .getValueSerializer()
            .deserialize(message.getBody());

        // WebSocket으로 모든 클라이언트에게 브로드캐스트
        messagingTemplate.convertAndSend("/topic/messages", msg);
    }
}

// Redis 리스너 설정
@Configuration
public class RedisConfig {
    @Bean
    RedisMessageListenerContainer container(RedisConnectionFactory factory,
                                            MessageListener listener) {
        RedisMessageListenerContainer container = new RedisMessageListenerContainer();
        container.setConnectionFactory(factory);
        container.addMessageListener(listener, new ChannelTopic("chat"));
        return container;
    }
}
```

---

### 6. API Controller

```java
@RestController
@RequestMapping("/api")
public class ChatController {
    private final NicknameService nicknameService;
    private final MessageRepository messageRepo;
    private final RedisPubSubService redisService;

    @PostMapping("/join")
    public JoinResponse join() {
        String nickname = nicknameService.generateNickname();
        return new JoinResponse(nickname);
    }

    @PostMapping("/send")
    public void send(@RequestBody MessageDto dto) {
        // Rate Limiting 체크
        if (!redisService.checkLimit(dto.nickname())) {
            throw new RuntimeException("Too many messages");
        }

        // 1. DynamoDB에 저장 (Single Source of Truth)
        ChatMessage msg = new ChatMessage(dto.nickname(), dto.message());
        messageRepo.save(msg);

        // 2. Redis Pub/Sub로 브로드캐스트 (저장 안함!)
        redisService.publish(msg);
    }

    @GetMapping("/messages")
    public List<ChatMessage> getMessages() {
        // DynamoDB에서 직접 조회 (충분히 빠름!)
        return messageRepo.getRecent(100);
    }

    record JoinResponse(String nickname) {}
    record MessageDto(String nickname, String message) {}
}
```

---

---

## 환경 변수 설정

### 중요: 포트 설정 (필수!)
**애플리케이션은 반드시 3000 포트에서 실행되어야 합니다.**

`application.properties`:
```properties
server.port=3000
```

또는 `application.yml`:
```yaml
server:
  port: 3000
```

### AWS 리소스 환경 변수

애플리케이션에서 사용할 환경 변수:

```yaml
# application.yml
server:
  port: 3000  # 필수! ALB와 ECS가 3000 포트를 사용

spring:
  data:
    redis:
      host: ${REDIS_HOST}  # ElastiCache Redis 엔드포인트
      port: ${REDIS_PORT}  # 기본: 6379

cloud:
  aws:
    region:
      static: ${AWS_REGION}  # ap-northeast-2
    dynamodb:
      table-name: ${DYNAMODB_TABLE_NAME}  # chatapp-dev-messages
```

**Terraform에서 자동 설정되는 환경 변수** (ECS Task Definition):
- `REDIS_HOST`: ElastiCache Redis 엔드포인트
- `REDIS_PORT`: 6379
- `DYNAMODB_TABLE_NAME`: DynamoDB 테이블 이름
- `AWS_REGION`: ap-northeast-2

**로컬 개발 시**:
```bash
export REDIS_HOST=localhost
export REDIS_PORT=6379
export AWS_REGION=ap-northeast-2
export DYNAMODB_TABLE_NAME=chatapp-dev-messages
```

---

## API 사용법 예시

```bash
# ALB DNS 확인 (Terraform output)
ALB_URL=$(cd terraform && terraform output -raw alb_dns_name)

# 1. 입장 (닉네임 받기)
curl -X POST http://$ALB_URL/api/join
# → {"nickname": "Guest-1234"}

# 2. 메시지 전송
curl -X POST http://$ALB_URL/api/send \
  -H "Content-Type: application/json" \
  -d '{"nickname":"Guest-1234","message":"안녕하세요!"}'

# 3. 메시지 조회 (최근 100개)
curl http://$ALB_URL/api/messages

# 4. Health Check
curl http://$ALB_URL/health
```

---

## 의존성 (build.gradle 또는 pom.xml)

### Gradle
```gradle
dependencies {
    // Spring Boot
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-websocket'

    // DynamoDB
    implementation 'software.amazon.awssdk:dynamodb-enhanced:2.20.0'

    // Redis
    implementation 'org.springframework.boot:spring-boot-starter-data-redis'

    // WebSocket (STOMP)
    implementation 'org.springframework:spring-messaging'
    implementation 'org.springframework:spring-websocket'
}
```

### Maven
```xml
<dependencies>
    <!-- Spring Boot -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-websocket</artifactId>
    </dependency>

    <!-- DynamoDB -->
    <dependency>
        <groupId>software.amazon.awssdk</groupId>
        <artifactId>dynamodb-enhanced</artifactId>
        <version>2.20.0</version>
    </dependency>

    <!-- Redis -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-redis</artifactId>
    </dependency>
</dependencies>
```

---

## 구현 체크리스트

### 인프라 (Terraform으로 자동 생성)
- [x] DynamoDB 테이블 생성 (pk="CHAT", TTL 1시간)
- [x] ElastiCache Redis 클러스터 (Multi-AZ)
- [x] ECS Fargate 환경 변수 설정
- [x] ALB 및 Target Groups

### 백엔드 구현
- [ ] Spring Boot 프로젝트 생성
- [ ] DynamoDB 연결 및 엔티티 작성
- [ ] Redis 연결 설정 (Pub/Sub + Rate Limiting)
- [ ] 닉네임 랜덤 생성 서비스 (Guest-XXXX)
- [ ] 메시지 저장 플로우 구현 (DynamoDB → Redis Pub/Sub)
- [ ] Redis Subscriber 리스너 구현
- [ ] WebSocket 설정 (STOMP 또는 Raw WebSocket)
- [ ] REST API 엔드포인트 (/join, /send, /messages)
- [ ] Health Check 엔드포인트 (/health)

### 중요 원칙
- [ ] Redis에 메시지 저장하지 않기 (Dual-Write 방지)
- [ ] DynamoDB를 Single Source of Truth로 사용
- [ ] Rate Limiting 구현 (1분에 10개 제한)
- [ ] TTL 1시간 설정 확인

### 프론트엔드 (선택사항)
- [ ] WebSocket 클라이언트 연결
- [ ] 메시지 송수신 UI
- [ ] CloudFront를 통한 정적 파일 배포

---

## 추가 참고 사항

### DynamoDB Query 성능
- **pk="CHAT"** 단일 파티션 사용으로 **핫 파티션 위험**이 있으나, 해커톤 규모(100명, 5분)에서는 문제없음
- 프로덕션에서는 여러 채팅방이 있다면 `pk=ROOM:{room_id}` 형태로 분산 권장

### Redis Pub/Sub 주의사항
- **메시지 손실 가능**: Subscriber가 없으면 메시지가 사라짐 (괜찮음, DynamoDB가 영구 저장)
- **저장 안함**: Redis는 메모리 절약을 위해 메시지를 저장하지 않음

### WebSocket vs SSE
- **WebSocket**: 양방향 통신 (채팅에 적합)
- **SSE (Server-Sent Events)**: 단방향 (서버 → 클라이언트만)

현재 아키텍처는 **WebSocket** 권장 (ALB가 WebSocket 업그레이드 지원)

---

## 배포 가이드 (AWS ECS)

### 인프라 정보
| 항목 | 값 |
|-----|---|
| **AWS 리전** | `ap-northeast-2` (서울) |
| **ECR 리포지토리** | `chatapp-dev` |
| **컨테이너 포트** | `3000` (필수!) |
| **ECS 클러스터** | `chatapp-dev-cluster` |
| **Blue 서비스** | `chatapp-dev-service-blue` (90% 트래픽) |
| **Green 서비스** | `chatapp-dev-service-green` (10% 트래픽) |

### Dockerfile 예시
```dockerfile
FROM openjdk:17-slim
WORKDIR /app
COPY build/libs/*.jar app.jar

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# 포트 노출
EXPOSE 3000

# 실행
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 빠른 배포 (AWS CLI)

```bash
# 1. 프로젝트 빌드
./gradlew bootJar  # 또는 ./mvnw package

# 2. ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com

# 3. Docker 이미지 빌드 & 태그
docker build -t chatapp:v1.0.0 .
docker tag chatapp:v1.0.0 <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:v1.0.0

# 4. ECR에 푸시
docker push <AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/chatapp-dev:v1.0.0

# 5. ECS 서비스 업데이트 (Blue 배포)
aws ecs update-service \
  --cluster chatapp-dev-cluster \
  --service chatapp-dev-service-blue \
  --force-new-deployment \
  --region ap-northeast-2

# 6. 배포 완료 대기
aws ecs wait services-stable \
  --cluster chatapp-dev-cluster \
  --services chatapp-dev-service-blue \
  --region ap-northeast-2

echo "✅ 배포 완료!"
```

### 배포 확인
```bash
# ALB DNS 확인
aws elbv2 describe-load-balancers \
  --names chatapp-dev-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region ap-northeast-2

# Health Check
curl http://<ALB_DNS_NAME>/health

# API 테스트
curl -X POST http://<ALB_DNS_NAME>/api/join
```

### 로그 확인
```bash
# 실시간 로그
aws logs tail /ecs/chatapp-dev --follow --region ap-northeast-2

# 에러만 필터링
aws logs tail /ecs/chatapp-dev --follow --filter-pattern "ERROR" --region ap-northeast-2
```

**자세한 배포 가이드**: `test-app/TEST_GUIDE.md` 참고
