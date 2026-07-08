# 02_argocd_deploy/main.tf 

# argocd에 접속해서 prometheus stack 배포, microservice app 배포

terraform {
  required_providers {
    # ArgoCD 전용 프로바이더 선언
    argocd = {
      source  = "oboukili/argocd"
      version = "6.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30" 
    }
  }
}

# 클러스터 접속 정보
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# 1. K8s 안에서 ArgoCD Service 리소스를 검색해서 가져옴
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }
}

# 2. Secret에서 ArgoCD 초기 비밀번호 로드
data "kubernetes_secret" "argocd_initial_admin_secret" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
}

provider "argocd" {
  # LoadBalancer 서비스의 External IP를 가져옵니다.
  server_addr = "${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip}:80" 
  
  # 로그인 정보 설정
  username    = "admin"
  password    = data.kubernetes_secret.argocd_initial_admin_secret.data["password"]

  # insecure HTTPS 무시 설정
  plain_text = true
  insecure   = true 
}

# microservice app 배포
resource "argocd_application" "microservice_app" {
  metadata {
    name      = "microservice-app"
    namespace = "argocd"
  }
  spec {
    project = "default"
    source {
      repo_url        = "https://oli999.github.io/helm-microservice/"
      chart           = "msa-platform"
      target_revision = "0.1.0"
    }
    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "default"
    }
    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
      sync_options = ["CreateNamespace=true"]
    }
  }
}

# prometheus stack 배포
resource "argocd_application" "prometheus_stack" {
  metadata {
    name      = "prometheus-stack"
    namespace = "argocd"
  }
  spec {
    project = "default"
    source {
      repo_url        = "https://prometheus-community.github.io/helm-charts"
      chart           = "kube-prometheus-stack"
      target_revision = "87.10.1"
      helm {
        values = file("${path.module}/prometheus/my-values.yaml")
      }
    }
    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "default"
    }
    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
      sync_options = ["CreateNamespace=true", "ServerSideApply=true"]
    }
  }
}

output "argocd_server_ip" {
  description = "argocd ip"
  value       = data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip
}

