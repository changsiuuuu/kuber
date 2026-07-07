# 1. ArgoCD 공식 레포지토리 등록
helm repo add argo https://argoproj.github.io/argo-helm
# 2. 등록된 저장소에 어떤 내용이 있는지 업데이트 하기
helm repo update
# 3. helm 저장소 목록 확인하기
helm repo ls
# 4. 설치할 namespace 만들기 (이미 만들어 놓았음)
kubectl create namespace argocd

# 5. helm 을 이용해서 설치하기

# helm install <배포의 이름>  <배포할 내용> -n <namespace>  -f <옵션정보를 가지고 있는 yaml>
helm install argocd argo/argo-cd -n argocd -f my-values.yaml

# 비밀번호 
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# 접속 주소 
kubectl get svc -n argocd

# my-values파일 수정해서 업그레이드
helm upgrade argocd argo/argo-cd -n argocd -f my-values.yaml