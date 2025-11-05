"""
아침 인프라 재가동 Lambda 함수
매일 08:00 KST (23:00 UTC 전날)에 실행
중단된 리소스들을 다시 가동합니다.
"""

import json
import boto3
import os
from datetime import datetime

# AWS 클라이언트
ecs = boto3.client('ecs')
cloudwatch = boto3.client('cloudwatch')

# 환경 변수
# AWS_REGION은 Lambda가 자동으로 제공
CLUSTER_NAME = os.environ.get('CLUSTER_NAME', 'chatapp-dev-cluster')
BLUE_SERVICE = os.environ.get('BLUE_SERVICE', 'chatapp-dev-service-blue')
GREEN_SERVICE = os.environ.get('GREEN_SERVICE', 'chatapp-dev-service-green')
BLUE_DESIRED_COUNT = int(os.environ.get('BLUE_DESIRED_COUNT', '1'))
GREEN_DESIRED_COUNT = int(os.environ.get('GREEN_DESIRED_COUNT', '1'))


def lambda_handler(event, context):
    """
    아침 시간대 인프라 재가동
    - ECS 서비스 desired count를 원래대로 복구
    """

    results = {
        'timestamp': datetime.now().isoformat(),
        'action': 'START',
        'resources': {}
    }

    try:
        # 1. ECS Blue 서비스 재가동
        print(f"Starting ECS service: {BLUE_SERVICE} (count: {BLUE_DESIRED_COUNT})")
        blue_response = ecs.update_service(
            cluster=CLUSTER_NAME,
            service=BLUE_SERVICE,
            desiredCount=BLUE_DESIRED_COUNT
        )
        results['resources']['ecs_blue'] = {
            'status': 'SUCCESS',
            'previous_count': 0,
            'new_count': BLUE_DESIRED_COUNT,
            'message': f'{BLUE_SERVICE} started'
        }
        print(f"✓ Blue service started: {BLUE_SERVICE}")

        # 서비스 안정화 대기 (선택사항)
        print(f"Waiting for {BLUE_SERVICE} to stabilize...")
        waiter = ecs.get_waiter('services_stable')
        waiter.wait(
            cluster=CLUSTER_NAME,
            services=[BLUE_SERVICE],
            WaiterConfig={
                'Delay': 15,
                'MaxAttempts': 40  # 최대 10분 대기
            }
        )
        print(f"✓ Blue service is now stable")

    except ecs.exceptions.ServiceNotFoundException:
        results['resources']['ecs_blue'] = {
            'status': 'FAILED',
            'error': f'Service {BLUE_SERVICE} not found'
        }
        print(f"✗ Blue service not found: {BLUE_SERVICE}")

    except Exception as e:
        results['resources']['ecs_blue'] = {
            'status': 'FAILED',
            'error': str(e)
        }
        print(f"✗ Failed to start Blue service: {e}")

    try:
        # 2. ECS Green 서비스 재가동
        print(f"Starting ECS service: {GREEN_SERVICE} (count: {GREEN_DESIRED_COUNT})")
        green_response = ecs.update_service(
            cluster=CLUSTER_NAME,
            service=GREEN_SERVICE,
            desiredCount=GREEN_DESIRED_COUNT
        )
        results['resources']['ecs_green'] = {
            'status': 'SUCCESS',
            'previous_count': 0,
            'new_count': GREEN_DESIRED_COUNT,
            'message': f'{GREEN_SERVICE} started'
        }
        print(f"✓ Green service started: {GREEN_SERVICE}")

        # 서비스 안정화 대기 (선택사항)
        print(f"Waiting for {GREEN_SERVICE} to stabilize...")
        waiter = ecs.get_waiter('services_stable')
        waiter.wait(
            cluster=CLUSTER_NAME,
            services=[GREEN_SERVICE],
            WaiterConfig={
                'Delay': 15,
                'MaxAttempts': 40  # 최대 10분 대기
            }
        )
        print(f"✓ Green service is now stable")

    except ecs.exceptions.ServiceNotFoundException:
        results['resources']['ecs_green'] = {
            'status': 'FAILED',
            'error': f'Service {GREEN_SERVICE} not found'
        }
        print(f"✗ Green service not found: {GREEN_SERVICE}")

    except Exception as e:
        results['resources']['ecs_green'] = {
            'status': 'FAILED',
            'error': str(e)
        }
        print(f"✗ Failed to start Green service: {e}")

    # 3. Health Check 확인
    try:
        print("Checking service health...")
        services = ecs.describe_services(
            cluster=CLUSTER_NAME,
            services=[BLUE_SERVICE, GREEN_SERVICE]
        )

        for service in services['services']:
            service_name = service['serviceName']
            running_count = service['runningCount']
            desired_count = service['desiredCount']

            print(f"  {service_name}: {running_count}/{desired_count} tasks running")

            if service_name in results['resources']:
                results['resources'][service_name.replace('chatapp-dev-service-', 'ecs_')]['health'] = {
                    'running_count': running_count,
                    'desired_count': desired_count,
                    'healthy': running_count == desired_count
                }

    except Exception as e:
        print(f"Warning: Failed to check service health: {e}")

    # 4. CloudWatch 메트릭 전송 (모니터링용)
    try:
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Scheduler',
            MetricData=[
                {
                    'MetricName': 'InfrastructureStatus',
                    'Value': 1,  # 1 = Running
                    'Unit': 'None',
                    'Timestamp': datetime.now()
                }
            ]
        )
    except Exception as e:
        print(f"Warning: Failed to send CloudWatch metric: {e}")

    # 결과 요약
    total_resources = len(results['resources'])
    successful = sum(1 for r in results['resources'].values() if r['status'] == 'SUCCESS')

    results['summary'] = {
        'total': total_resources,
        'successful': successful,
        'failed': total_resources - successful
    }

    print(f"\n{'='*60}")
    print(f"Infrastructure Start Summary:")
    print(f"  Total resources: {total_resources}")
    print(f"  Successful: {successful}")
    print(f"  Failed: {total_resources - successful}")
    print(f"{'='*60}\n")

    return {
        'statusCode': 200,
        'body': json.dumps(results, indent=2, default=str)
    }


if __name__ == '__main__':
    # 로컬 테스트용
    print("Testing start_infrastructure locally...")
    result = lambda_handler({}, None)
    print(json.dumps(json.loads(result['body']), indent=2))
