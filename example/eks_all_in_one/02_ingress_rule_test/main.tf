# 02_ingress_rule_test/main.tf 
terraform {
  required_providers {
    # 1.상단에 kubectl 전용 프로바이더를 선언합니다.
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

# 2. 프로바이더 접속 정보 세팅 (로컬 K8s context 사용)
provider "kubectl" {
  config_path = "~/.kube/config"
}

# ---------------------------------------------------------
# 폴더 내 모든 YAML 파일 읽어와서 쪼개기
# ---------------------------------------------------------
data "kubectl_path_documents" "manifests" {
  # 현재 테라폼 경로 하위의 'sub' 폴더 안의 모든 .yaml 파일을 스캔합니다.
  # 이 과정에서 파일 내부의 --- (다중 문서 구분선)까지 전부 개별 문서로 분리해 줍니다!
  pattern = "${path.module}/sub/*.yaml"
}

# ---------------------------------------------------------
# 분리된 매니페스트들을 K8s에 한 방에 꽂아 넣기
# ---------------------------------------------------------
resource "kubectl_manifest" "apply_all" {
  # 위 data 소스에서 파싱된 문서 개수만큼 반복문(for_each)을 돌립니다.
  for_each  = toset(data.kubectl_path_documents.manifests.documents)
  
  # each.value에 순수 YAML 텍스트가 한 조각씩 들어가며 배포됩니다.
  yaml_body = each.value
}