
# argocd 에 접속해서 prometheus stack 배포, microservice app 배포 하는 작업
# main.tf 파일
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
  }
}
# 클러스터 접속정보 (local k8s 를 바라 보도록 context 가 변경되어 있어야 한다)
provider "kubernetes" {
  config_path = "~/.kube/config"
}


# 1. K8s 안에서 ArgoCD Service 리소스를 검색해서 가져옴
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server" # 헬름이 생성한 서비스 이름이 일치해야 한다
    namespace = "argocd" # namespace 도 일치해야 한다 
  }
}

provider "argocd" {
  # cluster_ip (vpn 연결된 eks 에서 사용할 예정)
  server_addr = "${data.kubernetes_service.argocd_server.spec[0].cluster_ip}:80" 
  # external_ip
  # server_addr = "${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip}:80"

  # 초기 로그인 계정 정보
  username    = "admin"
  # 설정한 argocd 의 비밀번호 
  password    = "@abcd1234" 

  # 우리가 --insecure 로 HTTPS를 껐기 때문에 아래 옵션이 반드시 필요합니다!
  plain_text = true
  insecure   = true 
}

# # 배포할 app 구성하기
# resource "argocd_application" "microservice_app"{
#     # 배포할 app 의 이름과 namespace 를 명시 한다 
#     metadata {
#       name = "microservice-app"
#       namespace = "argocd"
#     }
#     spec {
#         project = "default"
#         source {
#             # helm repository 주소 또는 github 주소도 가능
#             repo_url = "https://oli999.github.io/helm-microservice/"
#             # 설치할 chart 의 이름
#             chart = "msa-platform"
#             # 버전 
#             target_revision = "0.1.0"
#         }
#         destination {
#             # 정해진 이름 
#             server = "https://kubernetes.default.svc"
#             namespace = "default" # 배포할 namespace 지정 
#         }
#         # 동기화 정책
#         sync_policy {
#             automated {
#                 prune       = true
#                 self_heal   = true
#             }
#             # namespace 가 없는경우 자동으로 만들어 지도록   
#             sync_options = ["CreateNamespace=true"]
#         }
#     }  
# }

# prometheus stack 을 "argocd_application" 으로 배포할 준비를 해 보세요.
resource "argocd_application" "promethues_stack"{
    # 배포할 app 의 이름과 namespace 를 명시 한다 
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
            # 최신 버전 
            target_revision = "87.10.1"
            # chart 를 설치할때 custom 변수 전달하기
            helm {
              values = file("${path.module}/prometheus/my-values.yaml")
            }
        }
        destination {
            # 정해진 이름 
            server = "https://kubernetes.default.svc"
            namespace = "prometheus" # 배포할 namespace 지정 
        }
        # 동기화 정책
        sync_policy {
            automated {
                prune       = true
                self_heal   = true
            }
            # 크기가 크고 무거운 chart 는 ServerSideApply=true 옵션을 같이 전달한다
            # argocd 는 용량 제한이 있기때문에 k8s 에 직접 던져서 실행이 되도록 
            sync_options = ["CreateNamespace=true", "ServerSideApply=true"]
        }
        # 쿠버네티스가 자동으로 주입하는 인증서 값 무시하기 (무한 핑퐁 방지)
        ignore_difference {
          group         = "admissionregistration.k8s.io"
          kind          = "ValidatingWebhookConfiguration"
          name          = "prometheus-stack-kube-prom-admission"
          json_pointers = ["/webhooks/0/clientConfig/caBundle"]
        }

        ignore_difference {
          group         = "admissionregistration.k8s.io"
          kind          = "MutatingWebhookConfiguration"
          name          = "prometheus-stack-kube-prom-admission"
          json_pointers = ["/webhooks/0/clientConfig/caBundle"]
        }
    }  
}

# external_ip 가 잘 얻어내지는지 확인
output "argocd_server_ip" {
  description = "argocd ip"
  value = "${data.kubernetes_service.argocd_server.spec[0].cluster_ip}"
}
