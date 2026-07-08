# 01_infra/main.tf 

# terraform을 이용해서 argocd helm 설치, nginx-ingress-controller helm 설치

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# nginx-ingress-controller helm 설치
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.0"
  namespace        = "ingress-nginx"
  create_namespace = true
}

# 테스트로 local 폴더에있는 ingressruleyaml 파일을 직접배포해보자
resource "kubernetes_manifest" "ingress_from_file" {
  # yaml 파일엔 한종류의 deploy, svc등이 있어야한다
  # --- 로 구분해서 여러종류 배포는 안된다
  # namespace도 명시해야한다
  depends_on = [ helm_release.ingress_nginx ]
  manifest = yamldecode(file("${path.module}/ingress-rule/rule.yaml"))
}

# argocd helm 설치
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "3.35.4"
  namespace        = "argocd"
  create_namespace = true
  # my-values.yaml 파일 설치
  values = [ file("${path.module}/argocd/my-values.yaml")]
}