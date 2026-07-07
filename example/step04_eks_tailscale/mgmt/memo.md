### 윈도우에서 mgmt를 거쳐서 grafana, argocd로 접속하게하기
```bash
# 접속주소 찾기
k get svc -n argocd | grep argocd-server

k get svc -n monitoring | grep kube-prometheus-stack-grafana
k get svc -n argocd | grep argocd-server
argocd-server                      ClusterIP   172.20.139.217   <none>        80/TCP,443/TCP      50m
[user1@mgmt grafana]$ 
[user1@mgmt grafana]$ k get svc -n monitoring | grep kube-prometheus-stack-grafana
kube-prometheus-stack-grafana                    ClusterIP   172.20.230.94    <none>        80/TCP                          15m

```

### window 메모장으로 system32\driver\etc\hosts 파일 맨 밑에

172.16.8.200 argocd.internal.com
172.16.8.200 grafana.internal.com
추가

### mgmt nginx 설정
```bash
# nginx가 실행중인지 확인
systemctl status nginx
# 실행중이 아니라면
sudo systemctl start nginx
sudo systemctl status nginx

# 설정파일 수정
# vi 편집기로 아래의 정보를 편집한다
sudo vi /etc/nginx/conf.d/internal-tools.conf

server {
    listen 80;
    server_name argocd.internal.com;
    location / {
        proxy_pass http://172.20.139.217:80; 
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffers 32 4k;
        proxy_buffer_size 4k;
    }
}

server {
    listen 80;
    server_name grafana.internal.com;
    location / {
        proxy_pass http://172.20.230.94:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
# 문법 체크 후 반영
sudo nginx -t
sudo systemctl reload nginx
```

# 이제 인터넷 열어서
grafana.internal.com
argocd.internal.com