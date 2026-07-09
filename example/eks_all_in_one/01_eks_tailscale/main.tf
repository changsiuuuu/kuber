# step03_eks_tailscale/main.tf 

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
    # terraform 으로 k8s 자원들을 provision 할수 있도록 provider 추가 
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

  name = "eks-vpc"
  # eks 전체가 속하는 대역 
  cidr = "10.0.0.0/16"

  azs             = ["ap-northeast-2a", "ap-northeast-2c"]
  # k8s node 들이 배치되는 subnet 대역
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  # LB 또는 NAT 들이 배치되는 subnet 대역
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

# ---------------------------------------------------------
# 2. 인프라 계층 (EKS v20 최신 규격)
# ---------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "hello-eks"
  cluster_version = "1.31" 

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

 
  enable_cluster_creator_admin_permissions = true

  
  enable_irsa = true

 
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

  # 노드 그룹 설정 (고가용성을 위해 최소 2대 권장)
  # 내부적으로 ec2 오토스케일링 그룹이 동작한다 
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 1
      max_size       = 4
      desired_size   = 2
    }
  }
}

# ---------------------------------------------------------
# 3. 애플리케이션 계층 (Nginx)
# ---------------------------------------------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
   
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "ap-northeast-2"]
  }
}


# --- Tailscale Subnet Router 배포용 null_resource ---
resource "null_resource" "install_tailscale_router" {
  
  # EKS 클러스터 생성이 완전히 끝난 후에 실행되도록 의존성 부여!
  depends_on = [ module.eks ]

  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    # 클러스터 생성 직후 내 로컬(mgmt)의 kubeconfig를 먼저 갱신하고 앤서블 실행!
    # eks 접속정보를 ~/.kube/config 파일로 가져오고 kubectl context 가 eks 를 바라보도록 한후에
    # ansible playbook 을 실행해서 tailscale 파드가 동작하도록 한다 
    # playbook 을 실행할때 tail scale auth key 가 전달되어야 한다 
    command = <<-EOT
      aws eks update-kubeconfig --region ap-northeast-2 --name hello-eks
      ansible-playbook -i localhost, -c local playbook-tailscale.yml --extra-vars 'tailscale_auth_key=${var.tailscale_auth_key}'
    EOT
  }
}

# tailscale 인증키
variable "tailscale_auth_key" {
    type        = string
    description = "tailscale 인증키" 
    sensitive   = true
}


# ebs, efs 에서  읽어갈 수 있도록 아래처럼 통로를 열어줍니다.
output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

# 아래는 efs 에서 추가로 필요한 값 
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  value = module.vpc.private_subnets
}