
# AWS CLI를 이용해 접속 정보 가져오기
aws eks update-kubeconfig --region ap-northeast-2 --name hello-eks
# context 목록 얻어오기 
kubectl config get-contexts

# 현재 선택된 context 조회
kubectl config current-context

# local k8s 클러스터로 context 변경 
k config use-context kubernetes-admin@kubernetes

# 특정 context 삭제
k config delete-context <context 이름>

# 상태 업데이트: (인프라는 건드리지 않고 출력값만 장부에 갱신합니다)
terraform apply -refresh-only -auto-approve

# 토큰 뽑아내기: (sensitive = true로 가려져 있으므로 -raw 옵션을 줘서 날것 그대로 뽑아냅니다)
terraform output -raw tunnel_real_token

############  terraform  참고

# 1. 🌟 사용할 모든 도메인/서브도메인 이름을 리스트로 선언합니다.
locals {
  # "@" = cloud-learning.site (루트 도메인)
  # 나머지 = argocd.cloud-learning.site 등등
  my_domains = [
    "@", 
    "argocd", 
    "grafana", 
    "prometheus",
    "www"
  ]
}

# 2. 반복문(for_each)을 돌려 한 번에 CNAME 레코드를 쫙 찍어냅니다.
resource "cloudflare_record" "eks_dns" {
  for_each = toset(locals.my_domains)

  zone_id  = var.cloudflare_zone_id
  name     = each.value # 리스트의 값이 하나씩 들어갑니다 (@, argocd, grafana...)

  # 모든 레코드가 단 하나의 EKS 터널 구멍을 가리키게 만듭니다!
  content  = "${cloudflare_tunnel.eks_tunnel.id}.cfargotunnel.com"
  type     = "CNAME"
  proxied  = true
}