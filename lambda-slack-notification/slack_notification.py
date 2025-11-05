import json
import os
import urllib.request
import urllib.error
from datetime import datetime
import boto3
from typing import Dict, Any, Optional

ssm = boto3.client('ssm')

def get_slack_webhook_url() -> str:
    """
    Parameter Store에서 Slack Webhook URL을 가져옵니다.
    """
    parameter_name = os.environ.get('SLACK_WEBHOOK_PARAMETER', '/chatapp/slack/webhook-url')

    try:
        response = ssm.get_parameter(
            Name=parameter_name,
            WithDecryption=True
        )
        return response['Parameter']['Value']
    except Exception as e:
        print(f"Error getting Slack webhook URL from Parameter Store: {str(e)}")
        raise


def format_timestamp(timestamp_str: str) -> str:
    """
    ISO 8601 타임스탬프를 읽기 쉬운 형식으로 변환합니다.
    """
    try:
        dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        return dt.strftime('%Y-%m-%d %H:%M:%S UTC')
    except Exception:
        return timestamp_str


def get_color_for_status(status: str) -> str:
    """
    상태에 따른 Slack 메시지 색상을 반환합니다.
    """
    status_colors = {
        'RUNNING': 'good',  # 녹색
        'STOPPED': 'danger',  # 빨간색
        'PENDING': 'warning',  # 주황색
        'DEPROVISIONING': 'warning',
        'STOPPING': 'warning',
        'COMPLETED': 'good',
        'FAILED': 'danger',
        'PRIMARY': 'good',
        'ACTIVE': 'good',
        'DRAINING': 'warning',
        'INACTIVE': 'danger'
    }
    return status_colors.get(status.upper(), '#439FE0')  # 기본값: 파란색


def create_task_state_change_message(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    ECS 태스크 상태 변경 이벤트에 대한 Slack 메시지를 생성합니다.
    """
    detail = event.get('detail', {})
    last_status = detail.get('lastStatus', 'UNKNOWN')
    desired_status = detail.get('desiredStatus', 'UNKNOWN')
    task_arn = detail.get('taskArn', 'N/A')
    task_id = task_arn.split('/')[-1] if '/' in task_arn else task_arn
    cluster_arn = detail.get('clusterArn', 'N/A')
    cluster_name = cluster_arn.split('/')[-1] if '/' in cluster_arn else cluster_arn

    # 그룹 정보에서 서비스 이름 추출
    group = detail.get('group', '')
    service_name = group.replace('service:', '') if group.startswith('service:') else 'N/A'

    # 컨테이너 정보
    containers = detail.get('containers', [])
    container_info = []
    for container in containers:
        name = container.get('name', 'unknown')
        status = container.get('lastStatus', 'unknown')
        container_info.append(f"{name}: {status}")

    # 정지 이유 (있는 경우)
    stopped_reason = detail.get('stoppedReason', '')
    stop_code = detail.get('stopCode', '')

    # 이모지 선택
    emoji = "🚀" if last_status == "RUNNING" else "🛑" if last_status == "STOPPED" else "⏳"

    # 메시지 생성
    title = f"{emoji} ECS Task {last_status}"

    fields = [
        {
            "title": "Service",
            "value": service_name,
            "short": True
        },
        {
            "title": "Cluster",
            "value": cluster_name,
            "short": True
        },
        {
            "title": "Task ID",
            "value": f"`{task_id[:13]}...`",
            "short": True
        },
        {
            "title": "Status",
            "value": f"{last_status} → {desired_status}",
            "short": True
        }
    ]

    if container_info:
        fields.append({
            "title": "Containers",
            "value": "\n".join(container_info),
            "short": False
        })

    if stopped_reason:
        fields.append({
            "title": "Stop Reason",
            "value": stopped_reason,
            "short": False
        })

    if stop_code:
        fields.append({
            "title": "Stop Code",
            "value": stop_code,
            "short": True
        })

    return {
        "attachments": [{
            "color": get_color_for_status(last_status),
            "title": title,
            "fields": fields,
            "footer": "ECS Deployment Monitor",
            "ts": int(datetime.fromisoformat(event['time'].replace('Z', '+00:00')).timestamp())
        }]
    }


def create_service_deployment_message(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    ECS 서비스 배포 이벤트에 대한 Slack 메시지를 생성합니다.
    """
    detail = event.get('detail', {})
    event_type = detail.get('eventType', 'UNKNOWN')
    event_name = detail.get('eventName', 'UNKNOWN')

    # 리소스 정보
    resources = event.get('resources', [])
    service_arn = resources[0] if resources else 'N/A'
    service_name = service_arn.split('/')[-1] if '/' in service_arn else service_arn

    # 배포 정보
    deployments = detail.get('deployments', [])

    # 이모지 선택
    emoji = "📦" if "DEPLOYMENT" in event_name else "🔄"

    title = f"{emoji} ECS Service Update: {service_name}"

    fields = [
        {
            "title": "Event",
            "value": event_name,
            "short": True
        },
        {
            "title": "Service",
            "value": service_name,
            "short": True
        }
    ]

    # 배포 정보 추가
    if deployments:
        for idx, deployment in enumerate(deployments[:2]):  # 최대 2개만 표시
            deployment_id = deployment.get('id', 'unknown')
            status = deployment.get('status', 'unknown')
            desired_count = deployment.get('desiredCount', 0)
            running_count = deployment.get('runningCount', 0)
            pending_count = deployment.get('pendingCount', 0)

            fields.append({
                "title": f"Deployment {idx + 1}",
                "value": f"Status: {status}\nDesired: {desired_count} | Running: {running_count} | Pending: {pending_count}",
                "short": False
            })

    color = get_color_for_status(event_type)

    return {
        "attachments": [{
            "color": color,
            "title": title,
            "fields": fields,
            "footer": "ECS Deployment Monitor",
            "ts": int(datetime.fromisoformat(event['time'].replace('Z', '+00:00')).timestamp())
        }]
    }


def create_deployment_state_change_message(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    ECS 배포 상태 변경 이벤트에 대한 Slack 메시지를 생성합니다 (한글).
    """
    detail = event.get('detail', {})

    # 서비스 정보 (detail에서 직접 가져오기)
    service_name = detail.get('serviceName', 'N/A')

    # resources에서 서비스 이름 추출 (fallback)
    if service_name == 'N/A':
        resources = event.get('resources', [])
        service_arn = resources[0] if resources else 'N/A'
        service_name = service_arn.split('/')[-1] if '/' in service_arn else service_arn

    # Blue/Green 환경 구분
    env_emoji = "🔵" if "blue" in service_name.lower() else "🟢" if "green" in service_name.lower() else "📦"
    env_name = "Blue" if "blue" in service_name.lower() else "Green" if "green" in service_name.lower() else "Unknown"

    # 배포 상태
    deployment_status = detail.get('deploymentStatus', 'UNKNOWN')
    event_name = detail.get('eventName', '')

    # 배포 상세 정보
    deployment = detail.get('deployment', {})
    deployment_id = deployment.get('id', 'N/A')
    task_definition = deployment.get('taskDefinition', 'N/A')
    task_def_revision = task_definition.split(':')[-1] if ':' in task_definition else 'N/A'
    rollout_state = deployment.get('rolloutState', '')

    desired_count = deployment.get('desiredCount', 0)
    running_count = deployment.get('runningCount', 0)
    pending_count = deployment.get('pendingCount', 0)
    failed_tasks = deployment.get('failedTasks', 0)

    # 색상 및 상태 텍스트 선택
    if deployment_status == 'COMPLETED':
        color = "good"
        status_text = "배포 완료 ✅"
        emoji = "🎉"
    elif deployment_status == 'FAILED':
        color = "danger"
        status_text = "배포 실패 ❌"
        emoji = "🚨"
    elif deployment_status == 'IN_PROGRESS':
        color = "warning"
        status_text = "배포 진행중"
        emoji = "⏳"
    else:
        color = "#439FE0"
        status_text = deployment_status
        emoji = "📦"

    # 타이틀
    title = f"{emoji} {env_emoji} {env_name} 환경 - {status_text}"

    # 배포 시간 (한국 시간으로 변환)
    from datetime import timedelta
    deploy_time = datetime.fromisoformat(event['time'].replace('Z', '+00:00')) + timedelta(hours=9)
    deploy_time_str = deploy_time.strftime('%Y년 %m월 %d일 %H:%M')

    # 필드 정보 구성
    info_lines = [
        f"🕒 {deploy_time_str}",
        f"🎯 서비스: `{service_name}`",
        f"📦 Task 정의: `revision {task_def_revision}`",
        f"🔢 실행중: *{running_count}/{desired_count}개*"
    ]

    if pending_count > 0:
        info_lines.append(f"⏳ 대기중: {pending_count}개")

    if failed_tasks > 0:
        info_lines.append(f"❌ 실패: *{failed_tasks}개*")

    if rollout_state:
        info_lines.append(f"📊 Rollout 상태: {rollout_state}")

    fields = [
        {
            "value": "\n".join(info_lines),
            "short": False
        }
    ]

    # 성공 메시지
    if deployment_status == 'COMPLETED' and failed_tasks == 0:
        fields.append({
            "value": "✨ 모든 태스크가 정상적으로 실행되었습니다.",
            "short": False
        })
    elif deployment_status == 'FAILED':
        fields.append({
            "value": "⚠️ 배포가 실패했습니다. 로그를 확인해주세요.",
            "short": False
        })

    return {
        "attachments": [{
            "color": color,
            "title": title,
            "fields": fields,
            "footer": "🚀 Chatapp 배포 알림",
            "ts": int(datetime.fromisoformat(event['time'].replace('Z', '+00:00')).timestamp())
        }]
    }


def create_target_health_message(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    ALB 타겟 헬스 상태 변경 이벤트에 대한 Slack 메시지를 생성합니다.
    """
    detail = event.get('detail', {})

    target = detail.get('target', {})
    target_id = target.get('id', 'N/A')
    target_port = target.get('port', 'N/A')

    target_health = detail.get('targetHealth', {})
    state = target_health.get('state', 'unknown')
    reason = target_health.get('reason', '')
    description = target_health.get('description', '')

    # 타겟 그룹 정보
    resources = event.get('resources', [])
    target_group_arn = resources[0] if resources else 'N/A'
    tg_name = target_group_arn.split(':')[-1] if ':' in target_group_arn else target_group_arn

    # 이모지 및 색상
    if state == 'healthy':
        emoji = "💚"
        color = "good"
    elif state == 'unhealthy':
        emoji = "💔"
        color = "danger"
    else:
        emoji = "💛"
        color = "warning"

    title = f"{emoji} Target Health: {state.upper()}"

    fields = [
        {
            "title": "Target Group",
            "value": tg_name,
            "short": False
        },
        {
            "title": "Target",
            "value": f"{target_id}:{target_port}",
            "short": True
        },
        {
            "title": "State",
            "value": state,
            "short": True
        }
    ]

    if reason:
        fields.append({
            "title": "Reason",
            "value": reason,
            "short": True
        })

    if description:
        fields.append({
            "title": "Description",
            "value": description,
            "short": False
        })

    return {
        "attachments": [{
            "color": color,
            "title": title,
            "fields": fields,
            "footer": "ECS Deployment Monitor",
            "ts": int(datetime.fromisoformat(event['time'].replace('Z', '+00:00')).timestamp())
        }]
    }


def send_slack_notification(webhook_url: str, message: Dict[str, Any]) -> None:
    """
    Slack Webhook으로 메시지를 전송합니다.
    """
    data = json.dumps(message).encode('utf-8')
    req = urllib.request.Request(
        webhook_url,
        data=data,
        headers={'Content-Type': 'application/json'}
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status != 200:
                print(f"Slack notification failed with status {response.status}")
                print(f"Response: {response.read().decode('utf-8')}")
            else:
                print("Slack notification sent successfully")
    except urllib.error.URLError as e:
        print(f"Error sending Slack notification: {str(e)}")
        raise


def lambda_handler(event, context):
    """
    Lambda 핸들러 함수
    """
    print(f"Received event: {json.dumps(event)}")

    try:
        # Slack Webhook URL 가져오기
        webhook_url = get_slack_webhook_url()

        # 이벤트 소스 확인
        source = event.get('source', '')
        detail_type = event.get('detail-type', '')

        # 이벤트 타입에 따라 메시지 생성
        message = None

        if source == 'aws.ecs':
            if detail_type == 'ECS Deployment State Change':
                # 배포 상태 변경 - COMPLETED 또는 FAILED 상태만 알림
                detail = event.get('detail', {})
                deployment_status = detail.get('deploymentStatus', '')

                # 배포 완료 또는 실패 시에만 알림
                if deployment_status in ['COMPLETED', 'FAILED']:
                    message = create_deployment_state_change_message(event)

        elif source == 'aws.elasticloadbalancing':
            if 'Target Health' in detail_type:
                # ALB 타겟 헬스 변경
                message = create_target_health_message(event)

        # 메시지가 생성되었으면 Slack으로 전송
        if message:
            send_slack_notification(webhook_url, message)
            return {
                'statusCode': 200,
                'body': json.dumps('Notification sent successfully')
            }
        else:
            print(f"No message generated for event type: {detail_type}")
            return {
                'statusCode': 200,
                'body': json.dumps('Event not applicable for notification')
            }

    except Exception as e:
        print(f"Error processing event: {str(e)}")
        import traceback
        traceback.print_exc()

        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
