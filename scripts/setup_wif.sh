#!/usr/bin/env bash
# One-time keyless setup: lets GitHub Actions run the pipeline in Google Cloud without any service account key
# (Workload Identity Federation). Everything here is free and can be undone with scripts/teardown_wif.sh.
#
# Needs: gcloud logged in as an owner of the project, and `gh` logged in with admin rights on the repo.
# Run from bash:  bash scripts/setup_wif.sh
set -euo pipefail

PROJECT=bq-stream-514812
REPO=vectshad/bq-wiki-stream
SA_NAME=gha-pipeline
POOL=gha-pool
PROVIDER=gha-provider
SA="$SA_NAME@$PROJECT.iam.gserviceaccount.com"
NUM=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')

echo "1/6 enable the three free APIs"
gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com --project "$PROJECT"

echo "2/6 service account (no key is ever created)"
gcloud iam service-accounts describe "$SA" --project "$PROJECT" >/dev/null 2>&1 \
  || gcloud iam service-accounts create "$SA_NAME" --project "$PROJECT" --display-name "GitHub Actions pipeline"

echo "3/6 roles: run query/load jobs, edit tables in this sandbox project (nothing else)"
for role in roles/bigquery.jobUser roles/bigquery.dataEditor; do
  gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$SA" --role "$role" --condition=None >/dev/null
done

echo "4/6 workload identity pool"
gcloud iam workload-identity-pools describe "$POOL" --project "$PROJECT" --location global >/dev/null 2>&1 \
  || gcloud iam workload-identity-pools create "$POOL" --project "$PROJECT" --location global --display-name "GitHub Actions"

echo "5/6 OIDC provider, only trusting THIS repository on the main branch"
gcloud iam workload-identity-pools providers describe "$PROVIDER" --project "$PROJECT" --location global \
    --workload-identity-pool "$POOL" >/dev/null 2>&1 \
  || gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" --project "$PROJECT" --location global \
    --workload-identity-pool "$POOL" --issuer-uri "https://token.actions.githubusercontent.com" \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition "assertion.repository=='$REPO' && assertion.ref=='refs/heads/main'"

gcloud iam service-accounts add-iam-policy-binding "$SA" --project "$PROJECT" --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/$NUM/locations/global/workloadIdentityPools/$POOL/attribute.repository/$REPO" >/dev/null

echo "6/6 repository variables (identifiers, not secrets)"
gh variable set GCP_WIF_PROVIDER --repo "$REPO" --body "projects/$NUM/locations/global/workloadIdentityPools/$POOL/providers/$PROVIDER"
gh variable set GCP_SERVICE_ACCOUNT --repo "$REPO" --body "$SA"
echo "done. Trigger a first run: gh workflow run pipeline --repo $REPO"
