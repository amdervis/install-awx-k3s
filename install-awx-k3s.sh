#!/bin/bash

install_k3s() {
  # Install k3s (this will also install kubectl)
  curl -sfL https://get.k3s.io | sh -

  # Create the .kube directory
  mkdir -p ~/.kube

  # Copy the k3s config
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

  # Set proper ownership
  sudo chown "$(id -u)":"$(id -g)" ~/.kube/config

  # Add to your ~/.bashrc or ~/.zshrc
  echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc

  # Reload your shell configuration
  source ~/.bashrc
}

install_awx-operator() {
  # Fetch the latest AWX Operator version from GitHub releases API
  local latest_awx_version
  latest_awx_version=$(curl -s https://api.github.com/repos/ansible/awx-operator/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

  # Clone the AWX Operator repository
  git clone https://github.com/ansible/awx-operator.git -y

  # Change directory to the cloned repo and checkout the latest version tag
  cd ~/awx-operator && git checkout tags/"$latest_awx_version"

  #  Export the version as an environment variable
  export VERSION=$latest_awx_version

  # Change service type to ClusterIP
  sed -i 's/service_type: nodeport/service_type: clusterip/g' ~/awx-operator/awx-demo.yml
    
  # Create a kustomization.yaml file
  cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # Find the latest tag here: https://github.com/ansible/awx-operator/releases
  - github.com/ansible/awx-operator/config/default?ref=$latest_awx_version
  - awx-demo.yml
# Set the image tags to match the git version from above
images:
  - name: quay.io/ansible/awx-operator
    newTag: $latest_awx_version

# Specify a custom namespace in which to install AWX
namespace: awx
EOF

  cat > awx-ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: awx-ingress
  namespace: awx
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: ansible-awx.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: awx-demo-service
            port:
              number: 80
EOF

  # Finally, apply the changes to create the AWX instance in your cluster
  kubectl apply -k .

  # Set the current namespace for kubectl so you don't have to keep repeating `-n awx`
  kubectl config set-context --current --namespace=awx
}

install_k3s
install_awx-operator
