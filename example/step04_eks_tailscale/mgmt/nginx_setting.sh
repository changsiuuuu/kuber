#!/bin/bash

# mgmt_nginx/nginx_setting.sh

# 1. kubectl을 이용해 실시간 ClusterIP 추출
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
GRAFANA_IP=$(kubectl get svc kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

# IP 획득 검증
if [ -z "$ARGOCD_IP" ] || [ -z "$GRAFANA_IP" ]; then
    echo "Error: Cluster IP를 가져오지 못했습니다. 서비스 상태를 확인하세요."
    exit 1
fi

echo "ArgoCD IP : $ARGOCD_IP"
echo "Grafana IP: $GRAFANA_IP"

# 2. Nginx 설정 파일 경로
TARGET_FILE="/etc/nginx/conf.d/internal-tools.conf"

echo "Nginx 설정 파일을 업데이트합니다: $TARGET_FILE"

# 3. Nginx 설정 파일 생성 및 덮어쓰기 (관리자 권한 필요)
# Nginx 변수가 쉘 변수로 치환되지 않도록 \$ 처리함
sudo tee "$TARGET_FILE" > /dev/null << EOF
server {
    listen 80;
    server_name argocd.internal.com;
    location / {
        proxy_pass http://$ARGOCD_IP:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffers 32 4k;
        proxy_buffer_size 4k;
    }
}

server {
    listen 80;
    server_name grafana.internal.com;
    location / {
        proxy_pass http://$GRAFANA_IP:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

echo "설정 파일이 성공적으로 생성되었습니다."

# 오타가 없는지 문법 체크
sudo nginx -t

# 설정을 시스템에 반영
sudo systemctl reload nginx