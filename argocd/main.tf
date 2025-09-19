module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = var.vpc_id
  subnet_ids      = var.subnet_ids

  eks_managed_node_groups = {
    default = {
      desired_size   = var.desired_capacity
      max_size       = var.desired_capacity + 1
      min_size       = 1
      instance_types = var.instance_types
      key_name       = var.key_name
    }
  }
}

# -------------------
# Instalar ArgoCD vía Helm
# -------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  values = [
    file("helm/values-argocd.yaml")
  ]
  depends_on = [module.eks]
}

# -------------------
# Namespaces adicionales
# -------------------
resource "kubernetes_namespace" "demo" {
  metadata {
    name = "demo"
  }
  depends_on = [module.eks]
}

# -------------------
# RoleBindings
# -------------------
resource "kubernetes_role_binding" "argocd_admin" {
  metadata {
    name      = "argocd-admin-binding"
    namespace = helm_release.argocd.namespace
  }

  role_ref {
    kind      = "ClusterRole"
    name      = "cluster-admin"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
  }
}

resource "kubernetes_role_binding" "demo_admin" {
  metadata {
    name      = "demo-admin-binding"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  role_ref {
    kind      = "ClusterRole"
    name      = "admin"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
  }
}

# -------------------
# Secret inicial de ArgoCD
# -------------------
data "kubernetes_secret" "argocd_initial_admin_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = helm_release.argocd.namespace
  }
}

# -------------------
# Outputs
# -------------------
output "cluster_endpoint" {
  description = "EKS Cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "argocd_server_url" {
  description = "ArgoCD server URL (ClusterIP service)"
  value       = "https://${helm_release.argocd.name}-server.argocd.svc.cluster.local"
}

output "argocd_initial_admin_password" {
  description = "Initial password for the ArgoCD admin user"
  value       = data.kubernetes_secret.argocd_initial_admin_password.data["password"]
  sensitive   = true
}
