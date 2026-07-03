# ---------------------------------------------------------
# 0. 버전 관리
# ---------------------------------------------------------
terraform {
 
  required_version = ">= 1.10"


  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # terraform 으로 k8s에 인프라를 프로비저닝 할 수 있다
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}


provider "aws" {
  region = "ap-northeast-2"
}


# ---------------------------------------------------------
# 1. 네트워크 계층 (VPC)
# ---------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  # 클러스터에서 사용할 network 대역 구성
  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  # 가용영역은 반드시 2개 
  azs             = ["ap-northeast-2a", "ap-northeast-2c"]
  # 클러스터가 위치하게될 private subnet 2개
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  # 로드 밸런서가 사용하게될 public subnet 2개
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]


  enable_nat_gateway = true
  single_nat_gateway = true


  public_subnet_tags = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}


# ---------------------------------------------------------
# 2. 인프라 계층
# ---------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  # 클러스터의 이름과 버전 설정
  cluster_name    = "hello-eks"
  cluster_version = "1.31"


  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true


  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true


  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }


  node_security_group_additional_rules = {
    ingress_vpc_all = {
      description = "Allow all traffic from VPC CIDR (Cross-Node Pod Communication)"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = ["10.0.0.0/16"]
    }
  }

  # eks 노드들의 사양 설정하기
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 1 # 최소 node 사이즈
      max_size       = 4 # 최대 node 사이즈
      desired_size   = 2 # default node사이즈
    }
  }
}


# ---------------------------------------------------------
# 3. 애플리케이션 계층
# ---------------------------------------------------------


data "aws_eks_cluster_auth" "cluster" { name = module.eks.cluster_name }


provider "kubernetes" {


  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}


resource "kubernetes_deployment_v1" "nginx" {
  metadata {
    name = "nginx-hello"
    labels = { app = "nginx" }
  }
  spec {
    replicas = 2
    selector { match_labels = { app = "nginx" } }
    template {
      metadata { labels = { app = "nginx" } }
      spec {
        container {
          image = "nginx:latest"
          name  = "nginx"
          port { container_port = 80 }
        }
      }
    }
  }
}


resource "kubernetes_service_v1" "nginx_svc" {
  metadata { name = "nginx-service" }
  spec {
    selector = { app = "nginx" }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

# 로드밸런서의 url 출력
output "lb_url" {
  value = kubernetes_service_v1.nginx_svc.status.0.load_balancer.0.ingress.0.hostname
}
