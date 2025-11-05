#!/usr/bin/env python3
"""
간단한 테스트 애플리케이션
- DynamoDB 연결 테스트
- Redis 연결 테스트
- NAT Gateway를 통한 외부 API 호출 테스트
"""

import os
import time
import json
from datetime import datetime
from flask import Flask, jsonify
import boto3
import redis
import requests

app = Flask(__name__)

# 환경 변수
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'test-table')
AWS_REGION = os.environ.get('AWS_REGION', 'ap-northeast-1')

# AWS 클라이언트
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)
table = dynamodb.Table(DYNAMODB_TABLE_NAME)

# Redis 클라이언트
redis_client = None
try:
    redis_client = redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        decode_responses=True,
        socket_connect_timeout=5
    )
except Exception as e:
    print(f"Redis 초기화 실패: {e}")


@app.route('/')
def hello():
    """간단한 Hello World"""
    return jsonify({
        "message": "Hello World!",
        "timestamp": datetime.now().isoformat(),
        "environment": {
            "redis_host": REDIS_HOST,
            "redis_port": REDIS_PORT,
            "dynamodb_table": DYNAMODB_TABLE_NAME,
            "aws_region": AWS_REGION
        }
    })


@app.route('/health')
def health():
    """Health check 엔드포인트"""
    return jsonify({"status": "healthy"}), 200


@app.route('/test/all')
def test_all():
    """모든 테스트 실행"""
    results = {
        "timestamp": datetime.now().isoformat(),
        "tests": {}
    }

    # 1. DynamoDB 테스트
    try:
        test_key = f"test-{int(time.time())}"
        test_data = {
            'pk': test_key,
            'timestamp': int(time.time() * 1000),
            'message': 'Test message from Flask app',
            'ttl': int(time.time()) + 3600  # 1시간 후 만료
        }

        # 쓰기 테스트
        table.put_item(Item=test_data)

        # 읽기 테스트
        response = table.get_item(Key={'pk': test_key, 'timestamp': test_data['timestamp']})

        if 'Item' in response:
            results['tests']['dynamodb'] = {
                "status": "✓ SUCCESS",
                "write": "OK",
                "read": "OK",
                "data": response['Item']
            }
        else:
            results['tests']['dynamodb'] = {
                "status": "✗ FAILED",
                "error": "데이터를 읽을 수 없음"
            }
    except Exception as e:
        results['tests']['dynamodb'] = {
            "status": "✗ FAILED",
            "error": str(e)
        }

    # 2. Redis 테스트
    try:
        if redis_client:
            test_key = f"test-{int(time.time())}"
            test_value = f"test-value-{int(time.time())}"

            # 쓰기 테스트
            redis_client.setex(test_key, 60, test_value)  # 60초 만료

            # 읽기 테스트
            retrieved_value = redis_client.get(test_key)

            if retrieved_value == test_value:
                results['tests']['redis'] = {
                    "status": "✓ SUCCESS",
                    "write": "OK",
                    "read": "OK",
                    "value": retrieved_value
                }
            else:
                results['tests']['redis'] = {
                    "status": "✗ FAILED",
                    "error": "값이 일치하지 않음"
                }
        else:
            results['tests']['redis'] = {
                "status": "✗ FAILED",
                "error": "Redis 클라이언트가 초기화되지 않음"
            }
    except Exception as e:
        results['tests']['redis'] = {
            "status": "✗ FAILED",
            "error": str(e)
        }

    # 3. NAT Gateway 테스트 (외부 API 호출)
    try:
        # 공개 API 호출 (httpbin.org)
        response = requests.get('https://httpbin.org/json', timeout=10)

        if response.status_code == 200:
            results['tests']['nat_gateway'] = {
                "status": "✓ SUCCESS",
                "http_status": response.status_code,
                "message": "외부 인터넷 연결 성공 (NAT Gateway 작동)"
            }
        else:
            results['tests']['nat_gateway'] = {
                "status": "✗ FAILED",
                "http_status": response.status_code
            }
    except Exception as e:
        results['tests']['nat_gateway'] = {
            "status": "✗ FAILED",
            "error": str(e)
        }

    # 4. 전체 상태 확인
    all_passed = all(
        test.get('status', '').startswith('✓')
        for test in results['tests'].values()
    )

    results['overall_status'] = "✓ ALL TESTS PASSED" if all_passed else "✗ SOME TESTS FAILED"

    return jsonify(results), 200 if all_passed else 500


@app.route('/test/dynamodb')
def test_dynamodb():
    """DynamoDB만 테스트"""
    try:
        test_key = f"test-{int(time.time())}"
        test_data = {
            'pk': test_key,
            'timestamp': int(time.time() * 1000),
            'message': 'Test message from Flask app',
            'ttl': int(time.time()) + 3600
        }

        table.put_item(Item=test_data)
        response = table.get_item(Key={'pk': test_key, 'timestamp': test_data['timestamp']})

        return jsonify({
            "status": "✓ SUCCESS",
            "write": "OK",
            "read": "OK",
            "data": response.get('Item', {})
        }), 200
    except Exception as e:
        return jsonify({
            "status": "✗ FAILED",
            "error": str(e)
        }), 500


@app.route('/test/redis')
def test_redis():
    """Redis만 테스트"""
    try:
        if not redis_client:
            return jsonify({
                "status": "✗ FAILED",
                "error": "Redis 클라이언트가 초기화되지 않음"
            }), 500

        test_key = f"test-{int(time.time())}"
        test_value = f"test-value-{int(time.time())}"

        redis_client.setex(test_key, 60, test_value)
        retrieved_value = redis_client.get(test_key)

        return jsonify({
            "status": "✓ SUCCESS",
            "write": "OK",
            "read": "OK",
            "value": retrieved_value
        }), 200
    except Exception as e:
        return jsonify({
            "status": "✗ FAILED",
            "error": str(e)
        }), 500


@app.route('/test/nat')
def test_nat():
    """NAT Gateway (외부 인터넷 연결)만 테스트"""
    try:
        response = requests.get('https://httpbin.org/json', timeout=10)

        return jsonify({
            "status": "✓ SUCCESS",
            "http_status": response.status_code,
            "message": "외부 인터넷 연결 성공 (NAT Gateway 작동)",
            "data": response.json()
        }), 200
    except Exception as e:
        return jsonify({
            "status": "✗ FAILED",
            "error": str(e)
        }), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 3000))
    app.run(host='0.0.0.0', port=port, debug=False)
