# step02_local_cloudflared2/main.tf

terraform {
  required_version = ">= 1.0.0"
}

# --- Variables ----------------------------------------------------------------
variable "existing_tunnel_token" {
  description = "이미 만들어진 cloudflared 터널 토큰"
  type        = string
  sensitive   = true
}

# --- 1. VMware 클러스터에 Cloudflared Pod 배포  -----------------------
resource "null_resource" "install_cloudflared_pod_vmware" {
    
    # 1. 코드를 실행할 때마다 항상 앤서블이 상태를 체크하도록 설정
    triggers = {
        always_run = "${timestamp()}"
    }

    # 2. 앤서블 플레이북 실행
    provisioner "local-exec" {
        # 주의: EKS용 플레이북과 겹치지 않도록 이름을 분리하거나, 
        # 실행 전에 로컬 ~/.kube/config 컨텍스트가 VMware를 바라보게 해야 합니다.
        command = "ansible-playbook -i localhost, -c local playbook-kubectl.yml --extra-vars 'tunnel_token=${var.existing_tunnel_token}'"
    }

    # terraform destroy 했을때 deploy와 secret 도 같이 삭제되도록 한다
    provisioner "local-exec" {
      when = destroy
      command = <<-EOF
        kubectl delete -f deploy-cloudflared.yaml
        kubectl delete secret tunnel-credentials --ignore-not-found=true
      EOF
    }
}
