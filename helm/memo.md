### vscode에 helmchart를 편하게 작성하기 위한 플러그인 설치하기

- Helm Intellisense 설치
- YAML by Red Hat 설치

# 1. 헬름 공식 GitHub에서 최신 압축 파일 다운로드 
curl -LO https://get.helm.sh/helm-v3.14.2-linux-amd64.tar.gz

# 2. 압축 해제
tar -zxvf helm-v3.14.2-linux-amd64.tar.gz

# 3. 압축 푼 폴더 안에서 'helm' 실행 파일만 골라서 시스템 실행 경로로 이동
sudo mv linux-amd64/helm /usr/local/bin/helm

# 4. 다운로드했던 임시 파일 삭제
rm -rf id linux-amd64 helm-v3.14.2-linux-amd64.tar.gz