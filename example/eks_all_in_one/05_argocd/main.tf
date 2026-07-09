
# terraform 을 이용해서 argocd helm 설치, nginx-ingress-controller helm 설치

# main.tf 파일
terraform {
  required_providers {
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
# 클러스터 접속정보 (local k8s 를 바라 보도록 context 가 변경되어 있어야 한다)
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
resource "helm_release" "argocd" {
  name             = "argocd"
  # helm 저장소의 위치
  repository       = "https://argoproj.github.io/argo-helm"
  # chart 의 이름
  chart            = "argo-cd"
  # chart 버전
  version          = "10.1.2"
  # namespace 설정 
  namespace        = "argocd"
  create_namespace = true
  # my-values.yaml 파일을 읽어서 설치 하도록 한다 
  values = [ file("${path.module}/my-values.yaml") ]
  set {
    name  = "configs.secret.argocdServerAdminPassword"
    # htpasswd (bcrypt) 형태로 변환하여 주입
    value = bcrypt("@abcd1234") 
  }
  # ArgoCD 핵심 서버 서비스 타입을 여기서 변경할수도있다. ClusterIP or LoadBalancer
  #set {
  #  name  = "server.service.type"
  #  value = "ClusterIP"
  #}
}