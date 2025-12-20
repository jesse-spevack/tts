# Auto-Deploy on Merge to Main

## Task Checklist

### Phase 1: GCP Setup
- [x] Create Workload Identity Pool and Provider
- [x] Create secrets in GCP Secret Manager
- [x] Grant service account Secret Manager access

### Phase 2: GitHub Setup
- [x] Generate SSH deploy key and add to VM
- [x] Add SSH_PRIVATE_KEY to GitHub Secrets
- [x] Add GCP project config to GitHub Secrets

### Phase 3: Workflow Implementation
- [x] Create `.github/workflows/deploy.yml`

---

## Phase 1: GCP Setup

**Affected files:** None (GCP console/CLI only)

### 1.1 Create Workload Identity Pool and Provider

Run these commands (replace `PROJECT_ID` and `PROJECT_NUMBER`):

```bash
# Get project number
gcloud projects describe PROJECT_ID --format="value(projectNumber)"

# Create Workload Identity Pool
gcloud iam workload-identity-pools create github-actions-pool \
  --project=PROJECT_ID \
  --location=global \
  --display-name="GitHub Actions Pool"

# Create Provider for GitHub
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project=PROJECT_ID \
  --location=global \
  --workload-identity-pool=github-actions-pool \
  --display-name="GitHub Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='OWNER/REPO'"
```

Replace `OWNER/REPO` with your GitHub repository (e.g., `jesse/tts`).

### 1.2 Grant Service Account Access

```bash
# Allow GitHub Actions to impersonate the service account
gcloud iam service-accounts add-iam-policy-binding SERVICE_ACCOUNT_EMAIL \
  --project=PROJECT_ID \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/OWNER/REPO"

# Grant Secret Manager access
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
  --role="roles/secretmanager.secretAccessor"
```

### 1.3 Create Secrets in GCP Secret Manager

```bash
# Hub secrets
echo -n "value" | gcloud secrets create rails-master-key --data-file=-
echo -n "value" | gcloud secrets create resend-api-key --data-file=-
echo -n "value" | gcloud secrets create mailer-host --data-file=-
echo -n "value" | gcloud secrets create mailer-from-address --data-file=-
echo -n "value" | gcloud secrets create generator-callback-secret --data-file=-
echo -n "value" | gcloud secrets create generator-service-url --data-file=-
echo -n "value" | gcloud secrets create kamal-registry-password --data-file=-

# Generator secrets
echo -n "value" | gcloud secrets create api-secret-token --data-file=-
echo -n "value" | gcloud secrets create hub-callback-url --data-file=-
echo -n "value" | gcloud secrets create hub-callback-secret --data-file=-

# Shared secrets
echo -n "value" | gcloud secrets create google-cloud-bucket --data-file=-
echo -n "value" | gcloud secrets create google-cloud-project --data-file=-
echo -n "value" | gcloud secrets create service-account-email --data-file=-
echo -n "value" | gcloud secrets create cloud-tasks-location --data-file=-
echo -n "value" | gcloud secrets create cloud-tasks-queue --data-file=-
echo -n "value" | gcloud secrets create vertex-ai-location --data-file=-
```

---

## Phase 2: GitHub Setup

**Affected files:** None (GitHub UI and VM CLI only)

### 2.1 Generate SSH Deploy Key

```bash
# Generate key pair (on local machine)
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_deploy_key -N ""

# Copy public key to VM
ssh jesse@34.106.61.4 "echo '$(cat ~/.ssh/github_deploy_key.pub)' >> ~/.ssh/authorized_keys"

# Test connection
ssh -i ~/.ssh/github_deploy_key jesse@34.106.61.4 "echo 'SSH works'"
```

### 2.2 Add GitHub Secrets

In GitHub repo Settings → Secrets and variables → Actions, add:

| Secret Name | Value |
|-------------|-------|
| `SSH_PRIVATE_KEY` | Contents of `~/.ssh/github_deploy_key` |
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_PROJECT_NUMBER` | Your GCP project number |
| `GCP_SERVICE_ACCOUNT` | Your service account email |

---

## Phase 3: Workflow Implementation

**Affected files:**
- `.github/workflows/deploy.yml` (new file)

### 3.1 Create Deploy Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      hub: ${{ steps.changes.outputs.hub }}
      generator: ${{ steps.changes.outputs.generator }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Detect changes
        id: changes
        run: |
          if git diff --name-only HEAD^ HEAD | grep -q "^hub/"; then
            echo "hub=true" >> $GITHUB_OUTPUT
          else
            echo "hub=false" >> $GITHUB_OUTPUT
          fi

          if git diff --name-only HEAD^ HEAD | grep -qv "^hub/" | grep -qv "^docs/" | grep -qv "^\.github/"; then
            echo "generator=true" >> $GITHUB_OUTPUT
          else
            echo "generator=false" >> $GITHUB_OUTPUT
          fi

  deploy-hub:
    needs: [detect-changes, scan_ruby, scan_js, lint, test, system-test]
    if: needs.detect-changes.outputs.hub == 'true'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/${{ secrets.GCP_PROJECT_NUMBER }}/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Setup gcloud
        uses: google-github-actions/setup-gcloud@v2

      - name: Fetch secrets from Secret Manager
        id: secrets
        run: |
          echo "RAILS_MASTER_KEY=$(gcloud secrets versions access latest --secret=rails-master-key)" >> $GITHUB_ENV
          echo "RESEND_API_KEY=$(gcloud secrets versions access latest --secret=resend-api-key)" >> $GITHUB_ENV
          echo "MAILER_HOST=$(gcloud secrets versions access latest --secret=mailer-host)" >> $GITHUB_ENV
          echo "MAILER_FROM_ADDRESS=$(gcloud secrets versions access latest --secret=mailer-from-address)" >> $GITHUB_ENV
          echo "CLOUD_TASKS_LOCATION=$(gcloud secrets versions access latest --secret=cloud-tasks-location)" >> $GITHUB_ENV
          echo "CLOUD_TASKS_QUEUE=$(gcloud secrets versions access latest --secret=cloud-tasks-queue)" >> $GITHUB_ENV
          echo "GENERATOR_CALLBACK_SECRET=$(gcloud secrets versions access latest --secret=generator-callback-secret)" >> $GITHUB_ENV
          echo "GENERATOR_SERVICE_URL=$(gcloud secrets versions access latest --secret=generator-service-url)" >> $GITHUB_ENV
          echo "GOOGLE_CLOUD_BUCKET=$(gcloud secrets versions access latest --secret=google-cloud-bucket)" >> $GITHUB_ENV
          echo "GOOGLE_CLOUD_PROJECT=$(gcloud secrets versions access latest --secret=google-cloud-project)" >> $GITHUB_ENV
          echo "SERVICE_ACCOUNT_EMAIL=$(gcloud secrets versions access latest --secret=service-account-email)" >> $GITHUB_ENV
          echo "VERTEX_AI_LOCATION=$(gcloud secrets versions access latest --secret=vertex-ai-location)" >> $GITHUB_ENV
          echo "KAMAL_REGISTRY_PASSWORD=$(gcloud secrets versions access latest --secret=kamal-registry-password)" >> $GITHUB_ENV

      - name: Setup SSH
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

      - name: Add VM to known_hosts
        run: ssh-keyscan -H 34.106.61.4 >> ~/.ssh/known_hosts

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          working-directory: hub
          bundler-cache: true

      - name: Write Kamal secrets
        working-directory: hub
        run: |
          cat > .kamal/secrets << EOF
          RAILS_MASTER_KEY=$RAILS_MASTER_KEY
          RESEND_API_KEY=$RESEND_API_KEY
          MAILER_HOST=$MAILER_HOST
          MAILER_FROM_ADDRESS=$MAILER_FROM_ADDRESS
          CLOUD_TASKS_LOCATION=$CLOUD_TASKS_LOCATION
          CLOUD_TASKS_QUEUE=$CLOUD_TASKS_QUEUE
          GENERATOR_CALLBACK_SECRET=$GENERATOR_CALLBACK_SECRET
          GENERATOR_SERVICE_URL=$GENERATOR_SERVICE_URL
          GOOGLE_CLOUD_BUCKET=$GOOGLE_CLOUD_BUCKET
          GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT
          SERVICE_ACCOUNT_EMAIL=$SERVICE_ACCOUNT_EMAIL
          VERTEX_AI_LOCATION=$VERTEX_AI_LOCATION
          KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
          EOF

      - name: Deploy with Kamal
        working-directory: hub
        run: bin/kamal deploy

  deploy-generator:
    needs: [detect-changes, scan_ruby, scan_js, lint, test, system-test]
    if: needs.detect-changes.outputs.generator == 'true'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/${{ secrets.GCP_PROJECT_NUMBER }}/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Setup gcloud
        uses: google-github-actions/setup-gcloud@v2

      - name: Fetch secrets from Secret Manager
        run: |
          echo "GOOGLE_CLOUD_PROJECT=$(gcloud secrets versions access latest --secret=google-cloud-project)" >> $GITHUB_ENV
          echo "GOOGLE_CLOUD_BUCKET=$(gcloud secrets versions access latest --secret=google-cloud-bucket)" >> $GITHUB_ENV
          echo "API_SECRET_TOKEN=$(gcloud secrets versions access latest --secret=api-secret-token)" >> $GITHUB_ENV
          echo "SERVICE_ACCOUNT_EMAIL=$(gcloud secrets versions access latest --secret=service-account-email)" >> $GITHUB_ENV
          echo "CLOUD_TASKS_LOCATION=$(gcloud secrets versions access latest --secret=cloud-tasks-location)" >> $GITHUB_ENV
          echo "CLOUD_TASKS_QUEUE=$(gcloud secrets versions access latest --secret=cloud-tasks-queue)" >> $GITHUB_ENV
          echo "HUB_CALLBACK_URL=$(gcloud secrets versions access latest --secret=hub-callback-url)" >> $GITHUB_ENV
          echo "HUB_CALLBACK_SECRET=$(gcloud secrets versions access latest --secret=hub-callback-secret)" >> $GITHUB_ENV

      - name: Build container image
        run: |
          gcloud builds submit \
            --tag gcr.io/$GOOGLE_CLOUD_PROJECT/podcast-api \
            --timeout=20m \
            --project $GOOGLE_CLOUD_PROJECT

      - name: Deploy to Cloud Run
        run: |
          gcloud run deploy podcast-api \
            --image gcr.io/$GOOGLE_CLOUD_PROJECT/podcast-api \
            --project $GOOGLE_CLOUD_PROJECT \
            --region $CLOUD_TASKS_LOCATION \
            --platform managed \
            --allow-unauthenticated \
            --memory 2Gi \
            --timeout 600s \
            --max-instances 1 \
            --min-instances 0 \
            --cpu 4 \
            --set-env-vars "RACK_ENV=production" \
            --set-env-vars "GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" \
            --set-env-vars "GOOGLE_CLOUD_BUCKET=$GOOGLE_CLOUD_BUCKET" \
            --set-env-vars "API_SECRET_TOKEN=$API_SECRET_TOKEN" \
            --set-env-vars "CLOUD_TASKS_LOCATION=$CLOUD_TASKS_LOCATION" \
            --set-env-vars "CLOUD_TASKS_QUEUE=$CLOUD_TASKS_QUEUE" \
            --set-env-vars "SERVICE_ACCOUNT_EMAIL=$SERVICE_ACCOUNT_EMAIL" \
            --set-env-vars "HUB_CALLBACK_URL=$HUB_CALLBACK_URL" \
            --set-env-vars "HUB_CALLBACK_SECRET=$HUB_CALLBACK_SECRET"

      - name: Update with SERVICE_URL
        run: |
          SERVICE_URL=$(gcloud run services describe podcast-api \
            --region $CLOUD_TASKS_LOCATION \
            --project $GOOGLE_CLOUD_PROJECT \
            --format 'value(status.url)')

          gcloud run services update podcast-api \
            --region $CLOUD_TASKS_LOCATION \
            --project $GOOGLE_CLOUD_PROJECT \
            --set-env-vars "RACK_ENV=production,GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT,GOOGLE_CLOUD_BUCKET=$GOOGLE_CLOUD_BUCKET,API_SECRET_TOKEN=$API_SECRET_TOKEN,CLOUD_TASKS_LOCATION=$CLOUD_TASKS_LOCATION,CLOUD_TASKS_QUEUE=$CLOUD_TASKS_QUEUE,SERVICE_ACCOUNT_EMAIL=$SERVICE_ACCOUNT_EMAIL,SERVICE_URL=$SERVICE_URL,HUB_CALLBACK_URL=$HUB_CALLBACK_URL,HUB_CALLBACK_SECRET=$HUB_CALLBACK_SECRET"
```

---

## Implementation Notes

- Used `workflow_run` trigger instead of `workflow_call` - the deploy workflow triggers automatically after CI completes on main, so no changes to `ci.yml` were needed.
- All application secrets are stored in GCP Secret Manager (16 secrets total).
- GitHub only stores: `SSH_PRIVATE_KEY`, `GCP_PROJECT_ID`, `GCP_PROJECT_NUMBER`, `GCP_SERVICE_ACCOUNT`.
- SSH deploy key generated at `~/.ssh/github_deploy_key`.
