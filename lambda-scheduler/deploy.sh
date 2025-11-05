#!/bin/bash
# Lambda 함수 배포 스크립트

set -e

echo "🚀 Lambda 함수 배포 시작..."

# ZIP 파일 생성
echo "📦 ZIP 파일 생성 중..."
zip -j stop_infrastructure.zip stop_infrastructure.py
zip -j start_infrastructure.zip start_infrastructure.py

echo "✅ ZIP 파일 생성 완료"
echo ""
echo "다음 단계:"
echo "1. Terraform으로 Lambda 함수 생성"
echo "   cd ../terraform"
echo "   terraform apply"
echo ""
echo "2. 수동 배포 (선택사항)"
echo "   aws lambda update-function-code --function-name stop-infrastructure --zip-file fileb://stop_infrastructure.zip --region ap-northeast-2"
echo "   aws lambda update-function-code --function-name start-infrastructure --zip-file fileb://start_infrastructure.zip --region ap-northeast-2"
