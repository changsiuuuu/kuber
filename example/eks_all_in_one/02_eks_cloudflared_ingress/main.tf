
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    # terraform 으로 k8s 자원들을 provision 할수 있도록 provider 추가 
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30" 
    }
    # terraform 으로 helm chart 를 직접 배포 가능하도록 하는 provider 추가
    helm = {
      source = "hashicorp/helm"
      version = "~> 2.14"
    }    
  }
}

# 클러스터 접속정보 (eks k8s 를 바라 보도록 context 가 변경되어 있어야 한다)
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# helm provider 가 동작하려면 config 파일 정보를 전달해야 한다. 
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# helm provider 가 동작할 준비가 되어 있으면 "helm_release" 를 사용할수 있다.
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  # helm 저장소의 위치
  repository       = "https://kubernetes.github.io/ingress-nginx"
  # chart 의 이름
  chart            = "ingress-nginx"
  # chart 버전
  version          = "4.11.0"
  # namespace 설정 
  namespace        = "ingress-nginx"
  create_namespace = true
  set {
    name  = "controller.service.type"
    value = "ClusterIP"
  }
}


# --- Variables ----------------------------------------------------------------
variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID (도메인의 고유 ID)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "domain_name" {
  description = "연결할 외부 도메인 (예: yourdomain.com)"
  type        = string
}

# --- Provider -----------------------------------------------------------------
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# --- 1. Tunnel Secret 생성 (터널 인증용 무작위 암호) ------------------------
resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

# --- 2. Cloudflare Tunnel 본체 생성 -------------------------------------------
resource "cloudflare_tunnel" "eks_tunnel" {
  account_id = var.cloudflare_account_id
  name       = "eks-local-tunnel"
  secret     = base64encode(random_password.tunnel_secret.result)
}

# --- 3. DNS CNAME 레코드 생성 (내 도메인 -> 터널 도메인 연결) -----------------

# # --- 3. DNS CNAME 레코드 생성 (내 도메인 -> 클라우드플레어 터널 연결) ---
# resource "cloudflare_record" "eks_dns" {
#   # 1. Zone ID: 어떤 도메인(예: cloud-learning.site)에 레코드를 추가할지 지정합니다. (변수에서 가져옴)
#   zone_id = var.cloudflare_zone_id

#   # 2. 레코드 이름(Name): "@"는 서브도메인(www 등) 없이 '루트 도메인' 자체로 접속함을 의미합니다.
#   name    = "@"

#   # 3. 목적지(Content): 도메인으로 들어온 트래픽을 보낼 도착지입니다. 
#   # 클라우드플레어가 발급한 "터널의 고유 ID.cfargotunnel.com" 주소로 동적 라우팅합니다.
#   content = "${cloudflare_tunnel.eks_tunnel.id}.cfargotunnel.com"

#   # 4. 레코드 타입(Type): IP 주소가 아닌 도메인 이름(cfargotunnel.com)으로 연결하므로 'CNAME'을 사용합니다.
#   type    = "CNAME"

#   # 5. 프록시 활성화 (proxied = true): 클라우드플레어의 핵심 기능입니다. (주황색 구름 아이콘 ON)
#   # 이 옵션이 true여야 무료 SSL(HTTPS) 인증서, DDoS 공격 방어, CDN 캐싱 기능이 터널에 적용됩니다.
#   proxied = true
# }

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
  for_each = toset(local.my_domains)

  zone_id  = var.cloudflare_zone_id
  name     = each.value # 리스트의 값이 하나씩 들어갑니다 (@, argocd, grafana...)

  # 모든 레코드가 단 하나의 EKS 터널 구멍을 가리키게 만듭니다!
  content  = "${cloudflare_tunnel.eks_tunnel.id}.cfargotunnel.com"
  type     = "CNAME"
  proxied  = true
}

# --- 4. Tunnel 라우팅 규칙 (리버스 프록시 설정) -------------------------------
# 터널로 들어온 트래픽을 사설망 어디로 보낼지 결정합니다.
resource "cloudflare_tunnel_config" "eks_config" {
  account_id = cloudflare_tunnel.eks_tunnel.account_id
  tunnel_id  = cloudflare_tunnel.eks_tunnel.id

  config {
    # 🌟 [추가] 서브도메인(argocd, grafana 등)을 모두 Nginx로 통과시킴
    ingress_rule {
      hostname = "*.${var.domain_name}" 
      service  = "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80"
    }

    # 첫 번째 규칙: 지정한 도메인으로 들어오면 eks 내부 서비스로 전달
    ingress_rule {
      hostname = var.domain_name
      # nginx ingress controller 로 전달하기
      service  = "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80"
    }
    
    # 마지막 규칙: 매칭되는 도메인이 없으면 404 에러 반환 (필수 설정)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

output "tunnel_real_token" {
  description = "Cloudflare Tunnel Token"
  value       = cloudflare_tunnel.eks_tunnel.tunnel_token
  sensitive   = true  # 보안상 화면에 바로 노출되지 않게 가림처리
}

resource "null_resource" "install_cloudflared_pod" {
    # 1. 터널 라우팅 규칙과 DNS 세팅이 "완벽히 끝난 후"에 앤서블을 실행해라!
    depends_on = [
        cloudflare_tunnel_config.eks_config,
        cloudflare_record.eks_dns
    ]

    # 2. 터널 토큰이 바뀌면 무조건 앤서블을 다시 실행해라! (항상 실행하려면 timestamp 적용)
    triggers = {
        always_run = "${timestamp()}"
    }

    provisioner "local-exec" {
        command = "ansible-playbook -i localhost, -c local playbook-kubectl.yml --extra-vars 'tunnel_token=${cloudflare_tunnel.eks_tunnel.tunnel_token}'"
    }
}
