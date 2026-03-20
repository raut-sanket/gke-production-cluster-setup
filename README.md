# GKE Production Cluster Setup

End-to-end bootstrap guide for a production-grade Google Kubernetes Engine cluster — from initial provisioning to running workloads. Covers cluster creation, node pool configuration, addon installation (ingress, cert-manager, external-secrets, monitoring), namespace strategy, RBAC, and network policies. Based on a real GKE cluster running 50+ pods for a DeFi platform.

---

## Problem Statement

Setting up a production Kubernetes cluster involves dozens of post-provisioning steps that are often done ad-hoc and undocumented: installing ingress controllers, configuring TLS, setting up secret management, deploying monitoring, applying network policies, and more. Need a reproducible, documented bootstrap process that takes a bare GKE cluster to production-ready in a single workflow.

## Solution

A step-by-step cluster bootstrap that installs and configures:
1. NGINX Ingress Controller with static IP
2. cert-manager with Let's Encrypt ClusterIssuer
3. External Secrets Operator with GCP Secret Manager
4. kube-prometheus-stack (Prometheus + Grafana)
5. Loki + Promtail for log aggregation
6. ArgoCD for GitOps deployment
7. Namespace isolation and resource quotas
8. Network policies for inter-namespace traffic control

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    GKE Production Cluster                     │
│               Region: us-east4 · 3 AZs · 0-3 Nodes          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                    System Addons                       │  │
│  │                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │  │
│  │  │ ingress-nginx│  │ cert-manager │  │ external-   │ │  │
│  │  │ LoadBalancer │  │ Let's Encrypt│  │ secrets     │ │  │
│  │  │ Static IP    │  │ Auto-TLS     │  │ GCP SecMgr  │ │  │
│  │  └──────────────┘  └──────────────┘  └─────────────┘ │  │
│  │                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │  │
│  │  │ ArgoCD       │  │ Prometheus   │  │ Loki +      │ │  │
│  │  │ GitOps       │  │ + Grafana    │  │ Promtail    │ │  │
│  │  │ App-of-Apps  │  │ Monitoring   │  │ Logging     │ │  │
│  │  └──────────────┘  └──────────────┘  └─────────────┘ │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                  Application Workloads                  │  │
│  │                                                        │  │
│  │  ┌─────────┐ ┌──────────┐ ┌────────┐ ┌────────────┐  │  │
│  │  │ API     │ │ Frontend │ │ Worker │ │ Indexer    │  │  │
│  │  │ Backends│ │ SPAs     │ │ Procs  │ │ Services   │  │  │
│  │  └─────────┘ └──────────┘ └────────┘ └────────────┘  │  │
│  │                                                        │  │
│  │  ┌────────────┐ ┌──────────┐                          │  │
│  │  │ PostgreSQL │ │  Redis   │                          │  │
│  │  │ (Stateful) │ │ (Cache)  │                          │  │
│  │  └────────────┘ └──────────┘                          │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Security & Governance                                 │  │
│  │  ☑ Workload Identity  ☑ Network Policies              │  │
│  │  ☑ Resource Quotas    ☑ No Default VPC                │  │
│  │  ☑ Binary AuthZ       ☑ Private Cluster               │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
gke-production-cluster-setup/
├── 00-prerequisites/
│   ├── gcloud-setup.sh                   # GCP project, APIs, service accounts
│   └── terraform/                        # Optional: cluster provisioning via TF
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── 01-cluster-bootstrap/
│   ├── namespaces.yaml                   # Namespace definitions
│   ├── resource-quotas.yaml              # Per-namespace quotas
│   └── priority-classes.yaml             # Pod scheduling priorities
├── 02-ingress/
│   ├── values.yaml                       # NGINX Ingress Helm values
│   └── install.sh
├── 03-cert-manager/
│   ├── values.yaml                       # cert-manager Helm values
│   ├── clusterissuer.yaml                # Let's Encrypt issuer
│   └── install.sh
├── 04-external-secrets/
│   ├── values.yaml                       # ESO Helm values
│   ├── clustersecretstore.yaml           # GCP Secret Manager store
│   └── install.sh
├── 05-monitoring/
│   ├── prometheus-values.yaml            # kube-prometheus-stack values
│   ├── loki-values.yaml                  # Loki + Promtail values
│   ├── dashboards/                       # Grafana dashboard JSONs
│   └── install.sh
├── 06-argocd/
│   ├── values.yaml                       # ArgoCD Helm values
│   ├── ingress.yaml                      # ArgoCD UI ingress
│   └── install.sh
├── 07-network-policies/
│   ├── deny-all-default.yaml             # Default deny ingress
│   ├── allow-ingress-to-apps.yaml        # Allow ingress → app namespaces
│   ├── allow-apps-to-db.yaml             # Allow apps → database namespace
│   └── allow-monitoring.yaml             # Allow Prometheus scraping
├── 08-security-hardening/
│   ├── pod-security-standards.yaml       # PSS baseline enforcement
│   ├── audit-policy.yaml                 # API server audit logging
│   └── image-policy.yaml                 # Allowed registries only
├── docs/
│   ├── bootstrap-runbook.md              # Step-by-step cluster setup
│   ├── day2-operations.md                # Scaling, upgrades, patching
│   └── incident-response.md              # Common issues + resolution
├── Makefile                              # `make bootstrap` runs everything
└── README.md
```

---

## Bootstrap Sequence

```bash
# 1. Prerequisites
./00-prerequisites/gcloud-setup.sh

# 2. Create namespaces and quotas
kubectl apply -f 01-cluster-bootstrap/

# 3. Install addons (order matters: ingress → TLS → secrets → monitoring → gitops)
./02-ingress/install.sh
./03-cert-manager/install.sh
./04-external-secrets/install.sh
./05-monitoring/install.sh
./06-argocd/install.sh

# 4. Apply network policies
kubectl apply -f 07-network-policies/

# 5. Security hardening
kubectl apply -f 08-security-hardening/

# Or run everything at once:
make bootstrap
```

---

## Tech Stack

| Component | Technology | Version |
|---|---|---|
| **Cluster** | GKE (Regular channel) | 1.29+ |
| **Node Pool** | e2-custom-2-8192 | Autoscaling 0–3 |
| **Ingress** | NGINX Ingress Controller | v1.13.3 |
| **TLS** | cert-manager + Let's Encrypt | v1.16.2 |
| **Secrets** | External Secrets Operator + GCP SM | v0.11.0 |
| **Monitoring** | kube-prometheus-stack | v77.12.0 |
| **Logging** | Loki + Promtail | v6.24.0 |
| **GitOps** | ArgoCD | v2.13.1 |
| **IaC** | Terraform (optional) | >= 1.5 |

---

## Security Checklist

- [x] Private cluster (no public node IPs)
- [x] Workload Identity (no static SA keys)
- [x] Default deny network policies
- [x] Resource quotas per namespace
- [x] No default VPC (deleted overly permissive firewall rules)
- [x] Binary Authorization (optional)
- [x] Artifact Registry image lifecycle policies (90-day prune)
- [x] Secret Manager integration (no secrets in Git)
- [x] TLS on all ingress endpoints

---

## Screenshots (Suggested)

- GKE Console: cluster overview with node pool and autoscaler
- ArgoCD UI: all applications synced and healthy
- Grafana: cluster overview dashboard
- kubectl: namespace list with resource quotas applied
- Network policy visualization (Cilium Hubble or similar)

---

## Author

**Sanket Raut** — DevOps Engineer  
[LinkedIn](https://linkedin.com/in/sanket-raut) · [Email](mailto:sanketraut.cloud@gmail.com)
