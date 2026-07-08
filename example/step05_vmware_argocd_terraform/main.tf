# main.tf

terraform {
  required_providers {
    # ArgoCD 전용 프로바이더 선언
    argocd = {
      source  = "oboukili/argocd"
      version = "6.1.1" # 최신 안정화 버전
    }
    # terraform 으로 k8s 자원들을 provision 할수 있도록 provider 추가 
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30" 
    }
    helm = {
      source = "hashicorp/helm"
      version = "~> 2.14"
    }
  }

}
# 클러스터 접속정보 (local k8s를 바라보도록 context가 변경되어있어야한다)
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# helm provider가 동작하려면 config 파일 정보를 전달해야한다.
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# helm provider가 동작할 준비가 되어있으면 helm release를 사용할수있다
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  # helm 저장소의 위치
  repository       = "https://kubernetes.github.io/ingress-nginx"
  # chart 이름
  chart            = "ingress-nginx"
  # chart 버전
  version          = "4.11.0"
  # namespace 설정
  namespace        = "ingress-nginx"
  create_namespace = true
}

# 테스트로 local 폴더에있는 ingressruleyaml 파일을 직접배포해보자
resource "kubernetes_manifest" "ingress_from_file" {
  # yaml 파일엔 한종류의 deploy, svc등이 있어야한다
  # --- 로 구분해서 여러종류 배포는 안된다
  # namespace도 명시해야한다
  manifest = yamldecode(file("${path.module}/ingress-rule/rule.yaml"))
}

# 1. K8s 안에서 ArgoCD Service 리소스를 검색해서 가져옴
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server" # 헬름이 생성한 서비스 이름
    namespace = "argocd"
  }
}

provider "argocd" {
  # cluster_ip (vpn연결된 eks 에서 사용)
  # server_addr = "${data.kubernetes_service.argocd_server.spec[0].cluster_ip}:80"
  # 방금 뚫어놓은 도메인을 그대로 사용합니다! externalip
  server_addr = "${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip}:80" 
  
  # 초기 로그인 계정 정보
  username    = "admin"
  password    = "3BcCRVXs1qeXslpA" 

  # 우리가 --insecure 로 HTTPS를 껐기 때문에 아래 옵션이 반드시 필요합니다!
  plain_text = true
  insecure   = true 
}

# 배포할 app 구성하기
resource "argocd_application" "member_app"{
    metadata {
      name = "member-app"
      namespace = "argocd"
    }
    spec {
        project = "default"
        source {
            # helm repository 주소 또는 github 주소도 가능
            repo_url = "https://oli999.github.io/chart_test/"
            # 설치할 chart 의 이름
            chart = "member-app"
            # 버전 
            target_revision = "0.1.1"
            # (선택) values.yaml 값을 덮어쓰고 싶을 때 사용
            # helm {
            #   value_files = ["values.yaml"]
            #   parameter {
            #     name  = "replicaCount"
            #     value = "3"
            #   }
            # }
        }
        destination {
            # 정해진 이름 
            server = "https://kubernetes.default.svc"
            namespace = "default" # 배포할 namespace 지정 
        }
        # 동기화 정책
        sync_policy {
            automated {
                prune       = true
                self_heal   = true
            }
            # namespace 가 없는경우 자동으로 만들어 지도록   
            sync_options = ["CreateNamespace=true"]
        }
    }  

}
# 배포할 app 구성하기
resource "argocd_application" "microservice_app"{
    metadata {
      name = "microservice-app"
      namespace = "argocd"
    }
    spec {
        project = "default"
        source {
            # helm repository 주소 또는 github 주소도 가능
            repo_url = "https://oli999.github.io/helm-microservice/"
            # 설치할 chart 의 이름
            chart = "msa-platform"
            # 버전 
            target_revision = "0.1.0"
            # (선택) values.yaml 값을 덮어쓰고 싶을 때 사용
            # helm {
            #   value_files = ["values.yaml"]
            #   parameter {
            #     name  = "replicaCount"
            #     value = "3"
            #   }
            # }
        }
        destination {
            # 정해진 이름 
            server = "https://kubernetes.default.svc"
            namespace = "default" # 배포할 namespace 지정 
        }
        # 동기화 정책
        sync_policy {
            automated {
                prune       = true
                self_heal   = true
            }
            # namespace 가 없는경우 자동으로 만들어 지도록   
            sync_options = ["CreateNamespace=true"]
        }
    }  
}

# prometheus stack 을 "argocd_application" 으로 배포할 준비를 해보자 
resource "argocd_application" "prometheus_stack"{
    metadata {
      name = "prometheus-stack"
      namespace = "argocd"
    }
    spec {
        project = "default"
        source {
            # helm repository 주소 또는 github 주소도 가능
            repo_url = "https://prometheus-community.github.io/helm-charts"
            # 설치할 chart 의 이름
            chart = "kube-prometheus-stack"
            # 버전 
            target_revision = "87.10.1"
            # (선택) values.yaml 값을 덮어쓰고 싶을 때 사용
            helm {
              values = file("${path.module}/prometheus/my-values.yaml")
            }
        }
        destination {
            # 정해진 이름 
            server = "https://kubernetes.default.svc"
            namespace = "default" # 배포할 namespace 지정 
        }
        # 동기화 정책
        sync_policy {
            automated {
                prune       = true
                self_heal   = true
            }
            # 크기가 크고 무거운 chart는 serversideapply=true 옵션을 같이 전달한다
            # argocd는 용량제한이 있기 때문에 k8s에 직접 던져서 실행이되게한다.
            # namespace 가 없는경우 자동으로 만들어 지도록   
            sync_options = ["CreateNamespace=true", "ServerSideApply=true"]
        }
    }  

} 




# external_ip 가 잘 읽어와지는지 테스트
output "argocd_server_ip" {
    description = "argocd ip"
    value = "${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip}"
  
}