# AWX on K3s Installation Script

This script automates the installation of AWX (Ansible Web UI) on a K3s Kubernetes cluster. It handles the complete setup process from installing K3s to deploying AWX with proper networking configuration.

## What This Script Does

### K3s Installation (`install_k3s`)
- Installs K3s lightweight Kubernetes distribution
- Sets up kubectl configuration in `~/.kube/config`
- Configures proper file permissions
- Adds KUBECONFIG environment variable to your shell

### AWX Operator Installation (`install_awx-operator`)
- Fetches the latest AWX Operator version from GitHub
- Clones and configures the AWX Operator repository
- Creates necessary Kubernetes manifests:
  - **kustomization.yaml**: Main configuration file
  - **awx-ingress.yaml**: Ingress configuration for web access
- Configures AWX to use ClusterIP service type
- Sets up ingress for accessing AWX at `ansible-awx.local`
- Deploys AWX in the `awx` namespace

## Prerequisites

- Ubuntu/Debian-based Linux system (or compatible)
- Root/sudo access
- Internet connection
- Git installed
- Curl installed

### ⚠️ Important Security Note (TODO)

**For the current version of this script to work properly, you may need to:**

1. **Disable firewalld** (if running on RHEL/CentOS/Fedora):
   ```bash
   sudo systemctl stop firewalld
   sudo systemctl disable firewalld
   ```

2. **Disable SELinux** (if running on RHEL/CentOS/Fedora):
   ```bash
   sudo setenforce 0
   sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
   ```

> **⚠️ WARNING**: Disabling firewalld and SELinux reduces system security. This is a temporary workaround while proper firewall rules and SELinux policies are being developed.
>
> **TODO**: Future versions of this script will include:
> - Proper firewall configuration for K3s and AWX ports
> - SELinux policy configuration for container operations
> - Network security best practices

### Alternative: Manual Firewall Configuration

If you prefer to keep firewalld enabled, you can manually open the required ports:

```bash
# K3s required ports
sudo firewall-cmd --permanent --add-port=6443/tcp  # Kubernetes API server
sudo firewall-cmd --permanent --add-port=10250/tcp # Kubelet API
sudo firewall-cmd --permanent --add-port=8472/udp  # Flannel VXLAN
sudo firewall-cmd --permanent --add-port=51820/udp # Flannel Wireguard IPv4
sudo firewall-cmd --permanent --add-port=51821/udp # Flannel Wireguard IPv6

# HTTP/HTTPS for AWX access
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp

# Reload firewall rules
sudo firewall-cmd --reload
```

## Usage

1. Make the script executable:
   ```bash
   chmod +x install-awx-k3s.sh
   ```

2. Run the script:
   ```bash
   ./install-awx-k3s.sh
   ```

3. Wait for the installation to complete (this may take several minutes)

## Post-Installation Steps

### 1. Verify K3s Installation
```bash
kubectl get nodes
kubectl get pods -A
```

### 2. Monitor AWX Deployment
```bash
# Watch AWX pods starting up
kubectl get pods -n awx -w

# Check AWX deployment status
kubectl get awx -n awx
```

### 3. Access AWX Web Interface

#### Option A: Using Ingress (Recommended)
1. Add the following to your `/etc/hosts` file:
   ```
   <your-server-ip> ansible-awx.local
   ```

2. Access AWX at: `http://ansible-awx.local`

#### Option B: Port Forwarding
```bash
kubectl port-forward -n awx service/awx-demo-service 8080:80
```
Then access AWX at: `http://localhost:8080`

### 4. Get AWX Admin Password
```bash
kubectl get secret awx-demo-admin-password -o jsonpath="{.data.password}" -n awx | base64 --decode
```

Default username: `admin`

## Configuration Details

### Service Configuration
- **Service Type**: ClusterIP (internal cluster access)
- **Namespace**: awx
- **Ingress Host**: ansible-awx.local

### File Locations
- **K3s Config**: `~/.kube/config`
- **AWX Operator**: `~/awx-operator/`
- **Manifests**: Created in the current working directory

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Ensure proper kubectl permissions
   sudo chown $(id -u):$(id -g) ~/.kube/config
   ```

2. **AWX Pods Not Starting**
   ```bash
   # Check pod logs
   kubectl logs -n awx -l app.kubernetes.io/name=awx-operator
   
   # Check events
   kubectl get events -n awx --sort-by=.metadata.creationTimestamp
   ```

3. **Ingress Not Working**
   ```bash
   # Install nginx ingress controller if needed
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
   ```

4. **Can't Access AWX Web Interface**
   ```bash
   # Check if AWX is ready
   kubectl get awx -n awx
   
   # Verify service is running
   kubectl get svc -n awx
   ```

### Useful Commands

```bash
# Check cluster status
kubectl cluster-info

# List all AWX resources
kubectl get all -n awx

# View AWX operator logs
kubectl logs -f -n awx deployment/awx-operator-controller-manager

# Restart AWX deployment
kubectl rollout restart deployment/awx-demo -n awx

# Uninstall AWX (if needed)
kubectl delete -k ~/awx-operator/

# Uninstall K3s (if needed)
/usr/local/bin/k3s-uninstall.sh
```

## Resource Requirements

### Minimum Requirements
- **CPU**: 2 cores
- **RAM**: 4GB
- **Storage**: 10GB available space

### Recommended for Production
- **CPU**: 4+ cores
- **RAM**: 8GB+
- **Storage**: 20GB+ with SSD

## Security Considerations

- Change the default admin password immediately after first login
- Configure proper RBAC policies for production use
- Use TLS certificates for production deployments
- Regularly update AWX and K3s versions

## Next Steps

After successful installation:

1. **Configure AWX**: Set up organizations, users, and projects
2. **Import Playbooks**: Add your Ansible playbooks and inventories
3. **Set up Credentials**: Configure SSH keys and vault passwords
4. **Create Job Templates**: Define reusable job configurations
5. **Configure Notifications**: Set up email/Slack notifications for job results

## Support

- [AWX Documentation](https://docs.ansible.com/ansible-tower/)
- [K3s Documentation](https://docs.k3s.io/)
- [AWX Operator GitHub](https://github.com/ansible/awx-operator)

## License

This script is provided as-is under the MIT License. Use at your own risk.
