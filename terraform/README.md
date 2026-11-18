# terraform — GCP foundation of the Wazuh SIEM

Small reusable **modules** in `modules/` and one **workspace per service** in `environments/staging/`,
each with its own state to keep the blast radius small. Workspaces reference each other **by name**
(data sources), not through `terraform_remote_state`. Everything is created in a single project; no
resource, sink or IAM binding reaches a folder, the organization or another project.

```text
terraform/
├── .terraform-version          # 1.15.4 (tfenv)
├── Makefile                    # init / validate / plan / apply / apply-all / teardown / collector-key / check-leaks
├── scripts/                    # converge.sh (wait for Argo CD), teardown.sh (ordered deletion, then destroy)
├── modules/
│   ├── services/  kms/  vpc/  cloud-nat/  firewall/  artifact-registry/  cloud-storage/  secret-manager/
│   ├── kubernetes-engine/      # GKE Standard, private nodes, Dataplane V2, Workload Identity, CMEK, Spot pools
│   ├── service-accounts/       # Google service accounts, roles granted on the resources they use
│   ├── pubsub/                 # topics, pull subscriptions, dead-letter topics
│   ├── logging-sink/           # project log sinks to Pub/Sub or Cloud Storage, writer identity grants
│   ├── audit-config/           # Data Access audit logs per service
│   └── argocd-bootstrap/       # helm_release argo-cd (with the in-cluster cluster secret) + argocd-apps (root Application)
└── environments/staging/
    ├── services/               #  1. enable Google APIs
    ├── kms/                    #  2. key ring staging-siem: gke-secrets, gke-disks (never destroyed)
    ├── vpc/                    #  3. staging-vpc-siem + subnet 10.130.0.0/20
    ├── cloud-nat/              #  4. Cloud NAT (auto-allocated IPs) — private nodes need egress
    ├── firewall/               #  5. SSH through IAP only
    ├── kubernetes-engine/      #  6. staging-siem (zonal): Spot pools general and siem
    ├── artifact-registry/      #  7. staging-siem (Docker, immutable tags) for images built in this repository
    ├── cloud-storage/          #  8. <project>-staging-siem-log-archive (raw copy of the security logs)
    ├── service-accounts/       #  9. staging-siem-gcp-collector
    ├── pubsub/                 # 10. staging-siem-gcp-logs → subscription staging-siem-wazuh (+ dead letter)
    ├── log-router/             # 11. sinks staging-siem-wazuh (Pub/Sub) and staging-siem-archive (Cloud Storage)
    ├── audit-logs/             # 12. Data Access audit logs for IAM (incl. service account credentials), Secret Manager, Cloud KMS
    ├── secret-manager/         # 13. staging-siem-slack-webhook, staging-siem-gcp-collector-key (read by External Secrets)
    └── argocd-bootstrap/       # 14. Argo CD + bootstrap/root.yaml → everything else is GitOps
```

Providers: `hashicorp/google ~> 7.35.0`, `hashicorp/helm ~> 3.1.0`.

## Log flow

```text
Cloud Audit Logs, firewall logs ──► sink staging-siem-wazuh ──► topic staging-siem-gcp-logs ──► subscription staging-siem-wazuh ──► Wazuh GCP collector
                                └─► sink staging-siem-archive ──► bucket <project>-staging-siem-log-archive (365 days)
```

- Both sinks use the same filter (`security_log_filter` in
  [`log-router/staging.tfvars`](environments/staging/log-router/staging.tfvars)): Admin Activity,
  Data Access, System Event, Policy Denied and Access Transparency audit logs, and firewall rule logs.
- Admin Activity, System Event and Policy Denied logs are always on. The `audit-logs` workspace turns on
  Data Access logs for `iam`, `secretmanager` and `cloudkms`; the `DATA_READ` setting of `iam` also covers
  service account token and signing calls (`iamcredentials.googleapis.com`), which have no setting of their
  own. It refuses `pubsub.googleapis.com`: every pull of the collector would produce a log that flows back
  into the topic.
- Messages are stored only in `asia-southeast2` (topic message storage policy) and kept 7 days in the
  subscription. After 10 failed deliveries a message moves to `staging-siem-wazuh-dead-letter`.
- The collector service account has `roles/pubsub.subscriber` on the subscription only. Its JSON key is
  created by `make collector-key`, which writes it straight to the Secret Manager secret
  `staging-siem-gcp-collector-key` through a 0600 temporary file; the key is never in Terraform state or Git.
  The subscription also accepts Kubernetes ServiceAccounts through Workload Identity (`workload_identity`
  in [`pubsub/staging.tfvars`](environments/staging/pubsub/staging.tfvars)).

## Encryption (Cloud KMS)

| Data | Key | Granted to |
|---|---|---|
| Kubernetes Secrets in etcd (application-layer secrets encryption) | `staging-siem/gke-secrets` | GKE service agent `service-<number>@container-engine-robot` |
| Node boot disks (`pd-standard` in `general`, `pd-ssd` in `siem`) | `staging-siem/gke-disks` | Compute Engine service agent `service-<number>@compute-system` |
| Persistent volumes (PD CSI StorageClass `disk-encryption-kms-key`) | `staging-siem/gke-disks` | Compute Engine service agent |

- Keys are symmetric, software protection, in `asia-southeast2` (GKE needs the key in the cluster region),
  rotated every 90 days. The key path for volumes reaches Argo CD as the cluster secret annotation
  `platform/volume-kms-key`.
- Control plane boot disks and etcd disks use Google-managed keys: customer-managed keys for them
  (GKE control plane authority) are not offered in `asia-southeast2`.
- Key rings and keys cannot be deleted in Cloud KMS. The resources carry `prevent_destroy`, and the `kms`
  workspace is not part of `make teardown`. Disabling or destroying a key version makes the cluster and the
  disks encrypted with it unusable.

## Cluster

| Pool | Machine | Nodes | Spot | Taint | Runs |
|---|---|---|---|---|---|
| `staging-general` | e2-standard-4 | 1–3 | yes | — | Argo CD, controllers, Wazuh dashboard, GCP collector |
| `staging-siem` | e2-standard-4 | 3–6 | yes | `workload=siem:NoSchedule` | Wazuh indexer and manager |

- The `staging-siem` pool sets `vm.max_map_count=262144` through the GKE node system config, as the
  indexer (OpenSearch) requires, so no workload needs a privileged container to change it.
- Every pool runs on Spot VMs. The indexer keeps one replica of every shard on another data node and
  three cluster-manager nodes, so it survives the preemption of one node; losing two cluster-manager
  nodes at once stops the cluster until GKE replaces them.
- Zonal cluster in `asia-southeast2-a`: the control plane is covered by the GKE free tier.
- Private nodes; `kubectl` and the Terraform Helm provider use the IAM-gated **DNS-based control plane
  endpoint**, while the IP endpoint is restricted to the VPC.
- Cloud Logging and Cloud Monitoring receive system components only; Managed Prometheus is disabled.
- **No project ID in the repository**: `project_id` comes from `TF_VAR_project_id`, which the Makefile
  reads from the git-ignored `../.env`. Values that contain it are stored as annotations on the Argo CD
  cluster secret: `platform/project-id`, `platform/image-registry`, `platform/gcp-subscription`,
  `platform/volume-kms-key`. The secret also carries the label `env=staging` and one `enable_<component>`
  label per entry of `enabled_components`, which the ApplicationSets select on.
- **Workload Identity without Google service accounts**: Secret Manager grants `secretAccessor` directly
  to the Kubernetes ServiceAccount `external-secrets/external-secrets`
  (`principal://…/subject/ns/external-secrets/sa/external-secrets`).

## Enabled APIs

Defined in [`environments/staging/services/staging.tfvars`](environments/staging/services/staging.tfvars);
`disable_on_destroy = false`, so destroying the workspace never turns APIs off.

| API | Used by |
|---|---|
| `container.googleapis.com`, `containerfilesystem.googleapis.com`, `containersecurity.googleapis.com` | GKE, image streaming, security posture |
| `compute.googleapis.com` | VPC, Cloud NAT, firewall, node VMs, persistent disks |
| `cloudkms.googleapis.com` | Customer-managed encryption keys |
| `artifactregistry.googleapis.com` | Images built in this repository |
| `iam.googleapis.com`, `iamcredentials.googleapis.com` | Service accounts, Workload Identity |
| `logging.googleapis.com`, `monitoring.googleapis.com` | Log sinks, audit logs, system component metrics |
| `pubsub.googleapis.com` | Log transport to the SIEM |
| `storage.googleapis.com` | Log archive |
| `secretmanager.googleapis.com` | Slack webhook, collector key |
| `cloudresourcemanager.googleapis.com`, `serviceusage.googleapis.com` | Terraform project and API management |

## State

Local state per workspace (`terraform.tfstate`, git-ignored). Apart from KMS, nothing has deletion guards,
so the environment can be destroyed at any time.

## Prerequisites

```bash
cp ../.env.example ../.env                # set PROJECT_ID and GITOPS_REPO_URL
gcloud config set project <PROJECT_ID>    # must match PROJECT_ID in .env
gcloud auth application-default login     # credentials for the Terraform providers
tfenv install && tfenv use                # Terraform 1.15.4
```

`make check-project` runs before every plan/apply/teardown and fails if the active `gcloud` project
differs from `PROJECT_ID` or if any tfvars file contains a `project_id`. To run `terraform` directly,
export `TF_VAR_project_id` yourself.

## Usage

```bash
make init                                  # all workspaces
make plan WS=kubernetes-engine
make apply WS=kubernetes-engine            # staging auto-approves
make apply-all                             # every workspace in order, then wait for Argo CD
make collector-key                         # new collector key → Secret Manager (then delete the old key)
gcloud secrets versions add staging-siem-slack-webhook --data-file=-   # paste the Slack webhook URL
make check-leaks                           # fail if the project ID or number is in a file Git tracks
make teardown                              # Argo CD workloads and PVCs first, then terraform destroy
```

`make teardown` keeps `services`, `kms` and `secret-manager`: APIs stay on, keys cannot be deleted, and the
secret values survive a rebuild.
