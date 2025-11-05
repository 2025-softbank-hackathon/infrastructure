"""
야간 인프라 중단 Lambda 함수
매일 00:00 KST (15:00 UTC)에 실행
비용이 발생하는 리소스들을 중단합니다.
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


def lambda_handler(event, context):
    """
    야간 시간대 인프라 중단
    - ECS 서비스 desired count를 0으로 설정
    """

    results = {
        'timestamp': datetime.now().isoformat(),
        'action': 'STOP',
        'resources': {}
    }

    try:
        # 1. ECS Blue 서비스 중단
        print(f"Stopping ECS service: {BLUE_SERVICE}")
        blue_response = ecs.update_service(
            cluster=CLUSTER_NAME,
            service=BLUE_SERVICE,
            desiredCount=0
        )
        results['resources']['ecs_blue'] = {
            'status': 'SUCCESS',
            'previous_count': blue_response['service']['runningCount'],
            'new_count': 0,
            'message': f'{BLUE_SERVICE} stopped'
        }
        print(f"✓ Blue service stopped: {BLUE_SERVICE}")

    except Exception as e:
        results['resources']['ecs_blue'] = {
            'status': 'FAILED',
            'error': str(e)
        }
        print(f"✗ Failed to stop Blue service: {e}")

    try:
        # 2. ECS Green 서비스 중단
        print(f"Stopping ECS service: {GREEN_SERVICE}")
        green_response = ecs.update_service(
            cluster=CLUSTER_NAME,
            service=GREEN_SERVICE,
            desiredCount=0
        )
        results['resources']['ecs_green'] = {
            'status': 'SUCCESS',
            'previous_count': green_response['service']['runningCount'],
            'new_count': 0,
            'message': f'{GREEN_SERVICE} stopped'
        }
        print(f"✓ Green service stopped: {GREEN_SERVICE}")

    except Exception as e:
        results['resources']['ecs_green'] = {
            'status': 'FAILED',
            'error': str(e)
        }
        print(f"✗ Failed to stop Green service: {e}")

    # 3. CloudWatch 메트릭 전송 (모니터링용)
    try:
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Scheduler',
            MetricData=[
                {
                    'MetricName': 'InfrastructureStatus',
                    'Value': 0,  # 0 = Stopped
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
    print(f"Infrastructure Stop Summary:")
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
    print("Testing stop_infrastructure locally...")
    result = lambda_handler({}, None)
    print(json.dumps(json.loads(result['body']), indent=2))
