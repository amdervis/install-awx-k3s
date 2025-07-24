#!/bin/bash

install_k3s() {
  echo "========================================="
  echo "Starting K3s installation..."
  echo "========================================="
  
  echo "📦 Downloading and installing K3s..."
  # Install k3s (this will also install kubectl)
  curl -sfL https://get.k3s.io | sh -
  
  if [ $? -eq 0 ]; then
    echo "✅ K3s installation completed successfully"
  else
    echo "❌ K3s installation failed"
    exit 1
  fi

  echo "📁 Creating .kube directory..."
  # Create the .kube directory
  mkdir -p ~/.kube

  echo "📋 Copying K3s configuration..."
  # Copy the k3s config
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

  echo "🔒 Setting proper ownership for kubectl config..."
  # Set proper ownership
  sudo chown "$(id -u)":"$(id -g)" ~/.kube/config

  echo "🔧 Adding KUBECONFIG to ~/.bashrc for future sessions..."
  # Add to your ~/.bashrc for future shell sessions
  KUBECONFIG_LINE='export KUBECONFIG=~/.kube/config'
  if ! grep -Fq "$KUBECONFIG_LINE" ~/.bashrc; then
    echo "$KUBECONFIG_LINE" >> ~/.bashrc
    echo "✅ KUBECONFIG added to ~/.bashrc"
  else
    echo "✅ KUBECONFIG already exists in ~/.bashrc"
  fi

  echo "🔧 Setting KUBECONFIG for current script session..."
  # Use absolute path to avoid tilde expansion issues
  KUBECONFIG_PATH="/home/$(whoami)/.kube/config"
  export KUBECONFIG="$KUBECONFIG_PATH"
  echo "✅ KUBECONFIG set to: $KUBECONFIG"
  
  # Verify kubectl can connect
  echo "🔍 Testing kubectl connectivity..."
  if kubectl cluster-info &> /dev/null; then
    echo "✅ kubectl is working correctly"
  else
    echo "❌ kubectl cannot connect to cluster"
    echo "📋 Debugging info:"
    echo "   KUBECONFIG: $KUBECONFIG"
    echo "   Config file exists: $([ -f "$KUBECONFIG" ] && echo "Yes" || echo "No")"
    echo "   Config file readable: $([ -r "$KUBECONFIG" ] && echo "Yes" || echo "No")"
    exit 1
  fi
  
  echo "✅ K3s setup completed!"
  echo ""
}

check_and_install_git() {
  echo "🔍 Checking if git is installed..."
  
  if command -v git &> /dev/null; then
    echo "✅ Git is already installed ($(git --version))"
    return 0
  else
    echo "❌ Git is not installed. Installing git..."
    
    # Install git using appropriate RHEL package manager
    if command -v dnf &> /dev/null; then
      echo "📦 Using dnf to install git..."
      sudo dnf install -y git
    elif command -v yum &> /dev/null; then
      echo "📦 Using yum to install git..."
      sudo yum install -y git
    else
      echo "❌ Neither dnf nor yum found. Please install git manually."
      exit 1
    fi
    
    # Verify git installation
    if command -v git &> /dev/null; then
      echo "✅ Git installed successfully ($(git --version))"
    else
      echo "❌ Git installation failed"
      exit 1
    fi
  fi
  echo ""
}

install_awx-operator() {
  echo "========================================="
  echo "Starting AWX Operator installation..."
  echo "========================================="
  
  # Check and install git if needed
  check_and_install_git
  
  echo "🔍 Fetching latest AWX Operator version from GitHub..."
  # Fetch the latest AWX Operator version from GitHub releases API
  local latest_awx_version
  latest_awx_version=$(curl -s https://api.github.com/repos/ansible/awx-operator/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  
  if [ -z "$latest_awx_version" ]; then
    echo "❌ Failed to fetch latest AWX Operator version"
    exit 1
  fi
  
  echo "📌 Latest AWX Operator version: $latest_awx_version"

  echo "📥 Checking if AWX Operator repository exists..."
  # Check if the awx-operator directory already exists
  if [ -d "~/awx-operator" ]; then
    echo "✅ AWX Operator repository already exists, skipping clone"
    echo "📂 Using existing directory: ~/awx-operator"
  else
    echo "📥 Cloning AWX Operator repository..."
    # Clone the AWX Operator repository
    git clone https://github.com/ansible/awx-operator.git
    
    if [ $? -eq 0 ]; then
      echo "✅ Repository cloned successfully"
    else
      echo "❌ Failed to clone repository"
      exit 1
    fi
  fi

  echo "📂 Changing to AWX Operator directory and checking out version $latest_awx_version..."
  # Change directory to the cloned repo and checkout the latest version tag
  cd ~/awx-operator && git checkout tags/"$latest_awx_version"
  
  if [ $? -eq 0 ]; then
    echo "✅ Successfully checked out version $latest_awx_version"
  else
    echo "❌ Failed to checkout version $latest_awx_version"
    exit 1
  fi

  echo "🔧 Exporting VERSION environment variable..."
  #  Export the version as an environment variable
  export VERSION=$latest_awx_version
  echo "VERSION set to: $VERSION"

  echo "⚙️  Modifying service type from nodeport to clusterip..."
  # Change service type to ClusterIP
  sed -i 's/service_type: nodeport/service_type: clusterip/g' ~/awx-operator/awx-demo.yml
  echo "✅ Service type updated in awx-demo.yml"
    
  echo "📝 Creating kustomization.yaml file..."
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
  echo "✅ kustomization.yaml created successfully"

  echo "🌐 Creating AWX Ingress configuration..."
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
  echo "✅ awx-ingress.yaml created successfully"

  echo "🚀 Applying AWX configuration to Kubernetes cluster..."
  # Apply the kustomization which includes both operator and AWX instance
  kubectl apply -k .
  
  if [ $? -eq 0 ]; then
    echo "✅ AWX configuration applied successfully"
  else
    echo "❌ Failed to apply AWX configuration"
    echo "📋 Current directory contents:"
    ls -la
    echo "📋 Checking if files exist:"
    [ -f "kustomization.yaml" ] && echo "✅ kustomization.yaml exists" || echo "❌ kustomization.yaml missing"
    [ -f "awx-demo.yml" ] && echo "✅ awx-demo.yml exists" || echo "❌ awx-demo.yml missing"
    exit 1
  fi

  echo "🎯 Setting current namespace to 'awx' for kubectl..."
  # Set the current namespace for kubectl so you don't have to keep repeating `-n awx`
  kubectl config set-context --current --namespace=awx
  
  if [ $? -eq 0 ]; then
    echo "✅ Namespace context set to 'awx'"
  else
    echo "⚠️  Warning: Failed to set namespace context"
  fi
  
  echo "========================================="
  echo "🎉 AWX Operator installation completed!"
  echo "========================================="
  echo ""
  echo "📋 Next steps:"
  echo "1. Wait for AWX pods to be ready: kubectl get pods -n awx"
  echo "2. Get admin password: kubectl get secret awx-demo-admin-password -o jsonpath='{.data.password}' | base64 --decode"
  echo "3. Access AWX at: http://ansible-awx.local (add to /etc/hosts if needed)"
  echo ""
}

echo "🚀 Starting K3s and AWX Operator installation script..."
echo "⏰ $(date)"
echo ""

install_k3s
install_awx-operator

echo "🏁 Script execution completed!"
echo "⏰ $(date)"