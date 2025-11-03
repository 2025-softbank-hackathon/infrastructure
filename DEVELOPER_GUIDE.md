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
                     ├─ (1) DynamoDB에 메시지 저장
                     ├─ (2) Redis에 Publish
                     └─ (3) 구독 중인 다른 인스턴스가 실시간 전송
```

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

## Redis 캐시

| 용도 | 타입 | 키 | TTL |
|------|------|-----|-----|
| 온라인 사용자 | Set | `online:users` | - |
| 최근 메시지 캐시 | List | `recent:messages` | 1시간 |
| Rate Limiting | String | `limit:{userId}` | 60초 |

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

    @DynamoDbSortKey
    public Long getTimestamp() { return timestamp; }

    // getters/setters...
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

### 4. Redis Pub/Sub

```java
@Service
public class RedisPubSubService {
    private final RedisTemplate<String, Object> redis;
    private static final String CHANNEL = "chat";

    // 메시지 발행
    public void publish(ChatMessage msg) {
        redis.convertAndSend(CHANNEL, msg);
    }

    // 메시지 캐싱
    public void cacheMessage(ChatMessage msg) {
        redis.opsForList().leftPush("recent:messages", msg);
        redis.opsForList().trim("recent:messages", 0, 99);
        redis.expire("recent:messages", 1, TimeUnit.HOURS);
    }

    // Rate Limiting
    public boolean checkLimit(String nickname) {
        Long count = redis.opsForValue().increment("limit:" + nickname);
        if (count == 1) redis.expire("limit:" + nickname, 60, TimeUnit.SECONDS);
        return count <= 10;
    }
}
```

---

### 5. API Controller

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
        // Rate Limiting
        if (!redisService.checkLimit(dto.nickname())) {
            throw new RuntimeException("Too many messages");
        }

        // 1. DynamoDB에 저장
        ChatMessage msg = new ChatMessage(dto.nickname(), dto.message());
        messageRepo.save(msg);

        // 2. Redis에 캐싱
        redisService.cacheMessage(msg);

        // 3. Redis Pub/Sub로 브로드캐스트
        redisService.publish(msg);
    }

    @GetMapping("/messages")
    public List<ChatMessage> getMessages() {
        return messageRepo.getRecent(100);
    }

    record JoinResponse(String nickname) {}
    record MessageDto(String nickname, String message) {}
}
```

---

## API 사용법 예시

```bash
# 1. 입장 (닉네임 받기)
curl -X POST http://localhost:8080/api/join
# → {"nickname": "Guest-1234"}

# 2. 메시지 전송
curl -X POST http://localhost:8080/api/send \
  -H "Content-Type: application/json" \
  -d '{"nickname":"Guest-1234","message":"안녕하세요!"}'

# 3. 메시지 조회 (최근 100개)
curl http://localhost:8080/api/messages
```

## 구현 체크리스트

- [ ] DynamoDB 테이블 생성 (pk="CHAT", TTL 1시간)
- [ ] Redis 연결 설정
- [ ] 닉네임 랜덤 생성 (Guest-XXXX)
- [ ] 메시지 저장 → Redis Publish 플로우
- [ ] Redis Subscribe 리스너 구현
- [ ] WebSocket 또는 SSE로 클라이언트 실시간 전송
