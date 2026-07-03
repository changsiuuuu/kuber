
### aws cli를 이용해 접속정보 가져오기
```bash
aws eks update-kubeconfig --region ap-northeast-2 --name hello-eks

### context 목록 
kubectl config get-contexts

kubectl config current-context

# pod, svc 확인
kubectl get pod,svc -o wide

# 지우면 aws에 신호가 간다
kubectl delete deploy nginx-hello

# local k8s 클러스터로 context 변경
kubectl config use-context kubernetes-admin@kubernetes
```