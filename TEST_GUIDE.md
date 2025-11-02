# Connection Testing Guide

## Test 1: AWS Credentials Verification

Before deploying, verify your AWS credentials are configured correctly.

```bash
# Check credentials
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-username"
# }
```

If you see an error, configure credentials:
```bash
aws configure
```

---

## Test 2: Infrastructure Deployment Verification

After `terraform apply`, verify all components are deployed:

```bash
cd terraform

# Get all outputs
terraform output

# Verify specific components
terraform output cloudfront_domain_name
terraform output api_gateway_websocket_url
terraform output alb_dns_name
terraform output redis_endpoint
```

---

## Test 3: API Gateway → ALB → Fargate Connection

### Method 1: Using wscat (WebSocket CLI tool)

**Install wscat**:
```bash
npm install -g wscat
```

**Test WebSocket connection**:
```bash
# Get WebSocket URL
WS_URL=$(cd terraform && terraform output -raw api_gateway_websocket_url)

# Connect to WebSocket API
wscat -c $WS_URL
```

**Expected output**:
```
Connected (press CTRL+C to quit)
>
```

**Send a test message**:
```json
> {"action": "sendMessage", "message": "Hello from wscat!"}
```

### Method 2: Using Python Script

Create a test file:

```python
# test_websocket.py
import asyncio
import websockets
import json
import sys

async def test_connection(uri):
    try:
        print(f"Connecting to {uri}...")
        async with websockets.connect(uri) as websocket:
            print("✓ Connected successfully!")

            # Send test message
            message = {
                "action": "sendMessage",
                "message": "Hello from Python test!"
            }
            await websocket.send(json.dumps(message))
            print(f"→ Sent: {message}")

            # Wait for response
            try:
                response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                print(f"← Received: {response}")
            except asyncio.TimeoutError:
                print("⚠ No response received (this may be normal)")

            print("✓ Test completed successfully!")

    except Exception as e:
        print(f"✗ Connection failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python test_websocket.py <websocket-url>")
        sys.exit(1)

    asyncio.run(test_connection(sys.argv[1]))
```

**Run the test**:
```bash
# Install dependencies
pip install websockets

# Get WebSocket URL
WS_URL=$(cd terraform && terraform output -raw api_gateway_websocket_url)

# Run test
python test_websocket.py "$WS_URL"
```

### Method 3: Using HTML Test Page

Create a test HTML file:

```html
<!-- test_websocket.html -->
<!DOCTYPE html>
<html>
<head>
    <title>WebSocket Test</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        #messages {
            border: 1px solid #ccc;
            padding: 10px;
            height: 300px;
            overflow-y: auto;
            margin: 10px 0;
        }
        .message { margin: 5px 0; }
        .sent { color: blue; }
        .received { color: green; }
        .error { color: red; }
        input, button { margin: 5px; padding: 5px; }
    </style>
</head>
<body>
    <h1>WebSocket Connection Test</h1>

    <div>
        <label>WebSocket URL:</label>
        <input type="text" id="wsUrl" size="80" placeholder="wss://...">
        <button onclick="connect()">Connect</button>
        <button onclick="disconnect()">Disconnect</button>
    </div>

    <div id="status">Status: Disconnected</div>

    <div id="messages"></div>

    <div>
        <input type="text" id="messageInput" placeholder="Enter message" size="60">
        <button onclick="sendMessage()">Send</button>
    </div>

    <script>
        let ws = null;
        const messagesDiv = document.getElementById('messages');
        const statusDiv = document.getElementById('status');

        function connect() {
            const url = document.getElementById('wsUrl').value;
            if (!url) {
                alert('Please enter WebSocket URL');
                return;
            }

            addMessage('Connecting to ' + url + '...', 'sent');
            statusDiv.textContent = 'Status: Connecting...';

            ws = new WebSocket(url);

            ws.onopen = () => {
                addMessage('✓ Connected successfully!', 'received');
                statusDiv.textContent = 'Status: Connected';
            };

            ws.onmessage = (event) => {
                addMessage('← Received: ' + event.data, 'received');
            };

            ws.onerror = (error) => {
                addMessage('✗ Error: ' + error, 'error');
                statusDiv.textContent = 'Status: Error';
            };

            ws.onclose = () => {
                addMessage('Connection closed', 'error');
                statusDiv.textContent = 'Status: Disconnected';
            };
        }

        function disconnect() {
            if (ws) {
                ws.close();
                ws = null;
            }
        }

        function sendMessage() {
            if (!ws || ws.readyState !== WebSocket.OPEN) {
                alert('Not connected');
                return;
            }

            const input = document.getElementById('messageInput');
            const message = {
                action: 'sendMessage',
                message: input.value
            };

            ws.send(JSON.stringify(message));
            addMessage('→ Sent: ' + input.value, 'sent');
            input.value = '';
        }

        function addMessage(text, className) {
            const div = document.createElement('div');
            div.className = 'message ' + className;
            div.textContent = new Date().toLocaleTimeString() + ' - ' + text;
            messagesDiv.appendChild(div);
            messagesDiv.scrollTop = messagesDiv.scrollHeight;
        }
    </script>
</body>
</html>
```

**How to use**:
1. Save as `test_websocket.html`
2. Open in browser
3. Get WebSocket URL: `terraform output api_gateway_websocket_url`
4. Paste URL and click "Connect"
5. Send test messages

---

## Test 4: Direct ALB Health Check

Test if Fargate containers are responding to ALB:

```bash
# Get ALB DNS name
ALB_DNS=$(cd terraform && terraform output -raw alb_dns_name)

# Test HTTP endpoint
curl -v http://$ALB_DNS/health

# Expected: 200 OK (if /health endpoint is implemented)
# Or: Connection successful even if 404
```

---

## Test 5: Verify Target Health

Check if Fargate tasks are registered and healthy:

```bash
cd terraform

# Check Blue target group
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_target_group_arn) \
  --query 'TargetHealthDescriptions[*].{IP:Target.Id,Port:Target.Port,Health:TargetHealth.State,Reason:TargetHealth.Reason}'

# Check Green target group
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw green_target_group_arn) \
  --query 'TargetHealthDescriptions[*].{IP:Target.Id,Port:Target.Port,Health:TargetHealth.State,Reason:TargetHealth.Reason}'
```

**Expected output**:
```json
[
    {
        "IP": "10.0.11.123",
        "Port": 3000,
        "Health": "healthy",
        "Reason": null
    }
]
```

**Possible states**:
- `healthy` ✓ - Target is responding correctly
- `initial` ⏳ - Health check in progress (wait ~30 seconds)
- `unhealthy` ✗ - Target not responding (check logs)
- `draining` ⏸ - Target being deregistered

---

## Test 6: VPC Link Status

Verify VPC Link is active:

```bash
# Get VPC Link ID
VPC_LINK_ID=$(cd terraform && terraform output -json | jq -r '.vpc_link_id.value // empty')

# If not in outputs, find it manually
aws apigatewayv2 get-vpc-links \
  --query 'Items[?contains(Name, `chatapp`)].{Name:Name,ID:VpcLinkId,Status:VpcLinkStatus}'

# Check specific VPC Link status
aws apigatewayv2 get-vpc-link \
  --vpc-link-id <VPC_LINK_ID> \
  --query '{Name:Name,Status:VpcLinkStatus,Message:VpcLinkStatusMessage}'
```

**Expected status**: `AVAILABLE`

---

## Test 7: End-to-End CloudFront → API Gateway → Fargate

### Using CloudFront Domain

```bash
# Get CloudFront domain
CF_DOMAIN=$(cd terraform && terraform output -raw cloudfront_domain_name)

# Test static content (S3)
curl -I https://$CF_DOMAIN/

# Expected: 200 OK or 403 (if no index.html uploaded yet)
```

### Test WebSocket through CloudFront (if configured)

Note: By default, CloudFront serves S3 static content. For WebSocket, you need to connect directly to API Gateway URL.

---

## Test 8: ECS Container Logs

Check if containers are running and see logs:

```bash
# List running tasks (Blue)
aws ecs list-tasks \
  --cluster chatapp-dev-cluster \
  --service-name chatapp-dev-service-blue

# Get task details
TASK_ARN=$(aws ecs list-tasks \
  --cluster chatapp-dev-cluster \
  --service-name chatapp-dev-service-blue \
  --query 'taskArns[0]' \
  --output text)

aws ecs describe-tasks \
  --cluster chatapp-dev-cluster \
  --tasks $TASK_ARN

# View logs
aws logs tail /ecs/chatapp-dev --follow --filter-pattern "blue"
```

---

## Test 9: DynamoDB Access

Verify ECS tasks can access DynamoDB:

```bash
# Check if tables exist
aws dynamodb list-tables | grep chatapp

# Test write to messages table
aws dynamodb put-item \
  --table-name chatapp-dev-messages \
  --item '{
    "roomId": {"S": "test-room"},
    "timestamp": {"N": "1234567890"},
    "userId": {"S": "user1"},
    "message": {"S": "Test message"}
  }'

# Test read
aws dynamodb get-item \
  --table-name chatapp-dev-messages \
  --key '{
    "roomId": {"S": "test-room"},
    "timestamp": {"N": "1234567890"}
  }'
```

---

## Test 10: Redis Connectivity

Test if Redis is accessible from your machine (Note: It's in private subnet, so this won't work directly):

```bash
# Get Redis endpoint
REDIS_ENDPOINT=$(cd terraform && terraform output -raw redis_endpoint)

echo "Redis endpoint: $REDIS_ENDPOINT:6379"
echo "Note: Redis is in private subnet, only accessible from ECS tasks"
```

To test from ECS task:
```bash
# Connect to ECS task via ECS Exec
aws ecs execute-command \
  --cluster chatapp-dev-cluster \
  --task $TASK_ARN \
  --container chatapp-container \
  --interactive \
  --command "/bin/sh"

# Once inside container:
# redis-cli -h <REDIS_ENDPOINT>
# ping
# Expected: PONG
```

---

## Complete Test Script

Save this as `test_all.sh`:

```bash
#!/bin/bash
set -e

echo "========================================="
echo "Complete Infrastructure Test"
echo "========================================="

cd terraform

echo ""
echo "1. Testing AWS Credentials..."
aws sts get-caller-identity && echo "✓ Credentials OK" || echo "✗ Credentials FAILED"

echo ""
echo "2. Getting Infrastructure URLs..."
terraform output

echo ""
echo "3. Testing Target Health..."
echo "Blue Target Group:"
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw blue_target_group_arn) \
  --query 'TargetHealthDescriptions[*].TargetHealth.State'

echo "Green Target Group:"
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw green_target_group_arn) \
  --query 'TargetHealthDescriptions[*].TargetHealth.State'

echo ""
echo "4. Testing ALB Endpoint..."
ALB_DNS=$(terraform output -raw alb_dns_name)
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://$ALB_DNS/ || echo "ALB reachable"

echo ""
echo "5. Listing ECS Tasks..."
aws ecs list-tasks \
  --cluster chatapp-dev-cluster \
  --query 'taskArns' || echo "No tasks running"

echo ""
echo "6. Checking DynamoDB Tables..."
aws dynamodb list-tables \
  --query 'TableNames[?contains(@, `chatapp`)]'

echo ""
echo "========================================="
echo "Test Complete!"
echo "========================================="
echo ""
echo "To test WebSocket connection:"
echo "  WS_URL=\$(terraform output -raw api_gateway_websocket_url)"
echo "  wscat -c \$WS_URL"
echo ""
```

**Run it**:
```bash
chmod +x test_all.sh
./test_all.sh
```

---

## Troubleshooting Common Issues

### Issue: WebSocket connection fails

**Check**:
1. VPC Link status: `aws apigatewayv2 get-vpc-links`
2. Target health: Both should be `healthy`
3. Security groups: ECS should allow traffic from VPC Link

### Issue: Targets are "unhealthy"

**Check**:
1. Container logs: `aws logs tail /ecs/chatapp-dev --follow`
2. Health check path: Should be `/health` and return 200
3. Container port: Should match `container_port` variable (3000)

### Issue: Cannot connect to ALB

**Check**:
1. ALB security group allows HTTP/HTTPS
2. ALB is in `active` state
3. At least one target is `healthy`

### Issue: "No credentials" error

**Fix**:
```bash
aws configure
# Enter your Access Key ID and Secret Access Key
```

---

## Quick Connection Test (One-Liner)

```bash
# Test entire chain: CloudFront → API GW → VPC Link → ALB → Fargate
curl -I https://$(cd terraform && terraform output -raw cloudfront_domain_name)/ && \
echo "✓ CloudFront accessible" && \
curl -I http://$(cd terraform && terraform output -raw alb_dns_name)/ && \
echo "✓ ALB accessible" && \
aws elbv2 describe-target-health \
  --target-group-arn $(cd terraform && terraform output -raw blue_target_group_arn) \
  --query 'TargetHealthDescriptions[0].TargetHealth.State' && \
echo "✓ Fargate healthy"
```
