# MinIO Backend for Terraform State

Terraform state is stored in a MinIO bucket instead of a local file. MinIO runs as a Docker container on the self-hosted GitHub Actions runner and exposes an S3-compatible API on `localhost:9000`.

## Architecture

```
GitHub Actions runner
├── MinIO container (docker compose up -d)
│   ├── S3 API   → localhost:9000
│   └── Console  → localhost:9001
└── Terraform (backend "s3")
    └── stores state in MinIO bucket "tf-state"
```

## Components

| Component | Path |
|---|---|
| Docker Compose | `deploy/preaction/docker-compose.yml` |
| Terraform backend | `providers.tf` (backend `"s3"`) |
| CI – apply | `.github/workflows/terraform-apply.yml` |
| CI – destroy | `.github/workflows/terraform-destroy.yml` |

## Required Repository Secrets

| Secret | Description |
|---|---|
| `MINIO_ROOT_USER` | MinIO root username |
| `MINIO_ROOT_PASSWORD` | MinIO root password |

These are passed as environment variables to the Docker Compose step and as `-backend-config` arguments to `terraform init`.

## Setup

### 1. Add repository secrets

In GitHub go to **Settings → Secrets and variables → Actions** and add:

- `MINIO_ROOT_USER`
- `MINIO_ROOT_PASSWORD`

The `tf-state` bucket is created automatically by the CI workflows on each run (using `mc mb --ignore-existing`). No manual bucket setup is required.

## How It Works

1. Both workflows (`terraform-apply.yml`, `terraform-destroy.yml`) start by checking out the repo.
2. The **"Ensure MinIO is running"** step runs `docker compose up -d` in `deploy/preaction/`, passing the MinIO credentials from repository secrets.
3. The **"Create MinIO bucket"** step installs the MinIO client (`mc`), configures an alias, and creates the `tf-state` bucket if it does not already exist.
4. **Terraform Init** receives `-backend-config` flags that point at `http://localhost:9000`, the `tf-state` bucket, and the MinIO credentials. Additional flags (`skip_credentials_validation`, `force_path_style`, etc.) are required because MinIO is not AWS S3.
5. Terraform reads and writes state directly in the MinIO bucket — no local file backend.

## Manual Local Usage

To run Terraform locally against the same MinIO backend:

```sh
export MINIO_ROOT_USER=<your-user>
export MINIO_ROOT_PASSWORD=<your-password>

docker compose -f deploy/preaction/docker-compose.yml up -d

terraform init -reconfigure \
  -backend-config="endpoint=http://localhost:9000" \
  -backend-config="bucket=tf-state" \
  -backend-config="key=homeserver-infra.tfstate" \
  -backend-config="access_key=$MINIO_ROOT_USER" \
  -backend-config="secret_key=$MINIO_ROOT_PASSWORD" \
  -backend-config="skip_credentials_validation=true" \
  -backend-config="skip_metadata_api_check=true" \
  -backend-config="skip_requesting_account_id=true" \
  -backend-config="force_path_style=true"

terraform plan
```

## Notes

- The MinIO container uses `restart: unless-stopped` so it survives runner reboots.
- Default ports: `9000` (S3 API), `9001` (web console).
- Credentials are configured via `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD` environment variables (no hardcoded defaults).
- The MinIO client (`mc`) is downloaded at runtime in the CI workflows; it is not pre-installed on the runner.
- `mc mb --ignore-existing` is idempotent — the bucket creation step is safe to re-run on every workflow execution.
