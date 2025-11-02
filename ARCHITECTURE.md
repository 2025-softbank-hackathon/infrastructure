# Architecture Overview

## System Architecture

This project builds a scalable and secure real-time chat application infrastructure on AWS.

### Key Components

#### 1. Frontend (Static Web Hosting)
- **CloudFront**: Fast content delivery via CDN
- **S3**: Static web hosting (HTML, CSS, JavaScript)

#### 2. API Layer
- **API Gateway WebSocket**: Real-time bidirectional communication
- **VPC Link**: Connects API Gateway to VPC internal resources

#### 3. Compute Layer
- **ECS Fargate**: Serverless container execution environment
  - Blue Target Group (90% traffic) - Stable production version
  - Green Target Group (10% traffic) - New version for testing
- **Application Load Balancer**: Traffic distribution and Blue/Green deployment

#### 4. Data Layer
- **DynamoDB**: NoSQL Database
  - `messages` table: Chat message storage
  - `connections` table: WebSocket connection information
  - `user-counter` table: Auto-increment user ID management
- **ElastiCache Redis**: In-memory caching and session management

#### 5. Networking
- **VPC**: Isolated network environment
  - Public Subnets: ALB, NAT Gateway
  - Private Subnets: ECS Tasks, ElastiCache
- **VPC Endpoint**: Private access to DynamoDB

#### 6. Observability (Future Implementation)
- **CloudWatch**: Log and metrics collection
- **X-Ray**: Distributed tracing

### Traffic Flow

1. **Static Content**:
   ```
   User → CloudFront → S3 → User
   ```

2. **WebSocket Connection**:
   ```
   User → API Gateway WebSocket → VPC Link → ALB → ECS Fargate
   ```

3. **Data Access**:
   ```
   ECS Fargate → VPC Endpoint → DynamoDB
   ECS Fargate → ElastiCache Redis
   ```

### Blue/Green Deployment

- **Blue Environment (90%)**: Stable production version
- **Green Environment (10%)**: New version testing

You can gradually deploy new versions by adjusting traffic ratios.

### Security

- All resources deployed within VPC
- Network access control via Security Groups
- Least privilege principle via IAM Roles
- DynamoDB and S3 encryption enabled
- HTTPS enforcement via CloudFront

### Scalability

- ECS Fargate Auto Scaling (Future Implementation)
- DynamoDB On-Demand mode (auto-scales with traffic)
- ElastiCache Redis cluster mode (if needed)
- High availability via Multi-AZ deployment

### Cost Optimization for Hackathon

- **Single NAT Gateway**: Only 1 NAT instead of 2 (saves ~$32/month)
- **Minimal ECS Tasks**: Blue=1, Green=1 (minimum for demo)
- **Single Redis Node**: No replication (saves ~$15/month)
- **Disabled Backups**: ElastiCache snapshot disabled
- **On-Demand DynamoDB**: Pay only for what you use
- **No Auto Scaling**: Manual scaling for hackathon

**Estimated Cost**: ~$50-70/month (hackathon/dev environment)

## Architecture Diagram

See the image file in the project root for the complete architecture diagram.

## Future Improvements

- [ ] Add Auto Scaling policies
- [ ] Custom domain setup via Route53
- [ ] HTTPS setup via ACM certificates
- [ ] Security enhancement via WAF
- [ ] Multi-region deployment via CloudFormation StackSets
- [ ] CI/CD automation via CodePipeline

## Hackathon Demo Scenario

### Objective
Demonstrate zero-downtime Blue/Green deployment in 4 minutes

### Pre-Demo
1. Both Blue (1 task) and Green (1 task) running
2. Traffic: Blue 90%, Green 10%
3. Share CloudFront URL with audience

### During Demo (4 minutes)
1. **Minute 0-1**: Show current state (Blue 90%, Green 10%)
2. **Minute 1-2**: Shift to 50/50 split
3. **Minute 2-3**: Shift to Green 90%, Blue 10%
4. **Minute 3-4**: Verify no disconnections, show monitoring

### Key Points
- No user disconnections during deployment
- Gradual traffic shift ensures safety
- Instant rollback capability if issues occur
- Real-time monitoring via CloudWatch
