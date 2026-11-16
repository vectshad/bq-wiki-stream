#!/usr/bin/env bash
# Undo scripts/setup_wif.sh. Run from bash:  bash scripts/teardown_wif.sh
set -uo pipefail

PROJECT=bq-stream-514812
REPO=vectshad/bq-wiki-stream
SA="gha-pipeline@$PROJECT.iam.gserviceaccount.com"

gh variable delete GCP_WIF_PROVIDER --repo "$REPO"
gh variable delete GCP_SERVICE_ACCOUNT --repo "$REPO"
gcloud iam workload-identity-pools providers delete gha-provider --project "$PROJECT" --location global --workload-identity-pool gha-pool --quiet
gcloud iam workload-identity-pools delete gha-pool --project "$PROJECT" --location global --quiet
for role in roles/bigquery.jobUser roles/bigquery.dataEditor; do
  gcloud projects remove-iam-policy-binding "$PROJECT" --member "serviceAccount:$SA" --role "$role" --condition=None >/dev/null
done
gcloud iam service-accounts delete "$SA" --project "$PROJECT" --quiet
