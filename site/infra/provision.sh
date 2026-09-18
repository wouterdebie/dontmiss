#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=wouterdebie-personal
ACCOUNT="${GCLOUD_ACCOUNT:?Set GCLOUD_ACCOUNT to an account with access to wouterdebie-personal}"
ZONE=dontmiss-now
BUCKET=dontmiss-now-site
GCLOUD=(gcloud --project="$PROJECT" --account="$ACCOUNT" --quiet)

# List failures stop provisioning; they must never be mistaken for missing resources.
ensure_compute() {
    local collection="$1" name="$2" existing
    shift 2
    existing="$("${GCLOUD[@]}" compute "$collection" list --filter="name=$name" --format='value(name)')"
    if [ -z "$existing" ]; then
        "${GCLOUD[@]}" compute "$collection" create "$name" "$@"
    else
        printf 'Keeping existing %s: %s\n' "$collection" "$name"
    fi
}

ZONE_EXISTS="$("${GCLOUD[@]}" dns managed-zones list --filter="name=$ZONE" --format='value(name)')"
if [ -z "$ZONE_EXISTS" ]; then
    "${GCLOUD[@]}" dns managed-zones create "$ZONE" --dns-name=dontmiss.now. \
        --description="Public DNS for the Don't Miss website" --visibility=public
fi
BUCKET_EXISTS="$("${GCLOUD[@]}" storage buckets list --filter="name=$BUCKET" --format='value(name)')"
if [ -z "$BUCKET_EXISTS" ]; then
    "${GCLOUD[@]}" storage buckets create "gs://$BUCKET" --location=US --uniform-bucket-level-access
fi
"${GCLOUD[@]}" storage buckets update "gs://$BUCKET" --web-main-page-suffix=index.html
"${GCLOUD[@]}" storage buckets add-iam-policy-binding "gs://$BUCKET" \
    --member=allUsers --role=roles/storage.objectViewer

ensure_compute addresses dontmiss-now-ip --global --ip-version=IPV4 --network-tier=PREMIUM
ensure_compute backend-buckets dontmiss-now-bucket-backend --gcs-bucket-name="$BUCKET"
"${GCLOUD[@]}" compute url-maps import dontmiss-now-lb --global --source=infra/https-map.yaml
"${GCLOUD[@]}" compute url-maps import dontmiss-now-lb-redirect --global --source=infra/http-redirect.yaml
ensure_compute ssl-certificates dontmiss-now-cert --global --domains=dontmiss.now,www.dontmiss.now
ensure_compute target-https-proxies dontmiss-now-lb-target-proxy \
    --url-map=dontmiss-now-lb --ssl-certificates=dontmiss-now-cert
ensure_compute target-http-proxies dontmiss-now-lb-http-proxy --url-map=dontmiss-now-lb-redirect
ensure_compute forwarding-rules dontmiss-now-lb-https-forwarding-rule \
    --global --load-balancing-scheme=EXTERNAL --network-tier=PREMIUM \
    --address=dontmiss-now-ip --target-https-proxy=dontmiss-now-lb-target-proxy --ports=443
ensure_compute forwarding-rules dontmiss-now-lb-http-forwarding-rule \
    --global --load-balancing-scheme=EXTERNAL --network-tier=PREMIUM \
    --address=dontmiss-now-ip --target-http-proxy=dontmiss-now-lb-http-proxy --ports=80

IP="$("${GCLOUD[@]}" compute addresses describe dontmiss-now-ip --global --format='value(address)')"
for name in dontmiss.now. www.dontmiss.now.; do
    EXISTING="$("${GCLOUD[@]}" dns record-sets list --zone="$ZONE" --name="$name" --type=A --format='value(rrdatas)')"
    if [ -z "$EXISTING" ]; then
        "${GCLOUD[@]}" dns record-sets create "$name" --zone="$ZONE" --type=A --ttl=300 --rrdatas="$IP"
    elif [ "$EXISTING" != "$IP" ]; then
        echo "Existing A record for $name differs from $IP; refusing to replace it automatically." >&2
        exit 1
    fi
done
"${GCLOUD[@]}" dns record-sets export infra/dontmiss.now.zone --zone="$ZONE" --zone-file-format
printf '\nSet these nameservers at the registrar for dontmiss.now:\n'
"${GCLOUD[@]}" dns managed-zones describe "$ZONE" --format='value(nameServers)'
printf '\nReserved IP: %s\nDeploy with: bash site/deploy.sh\n' "$IP"
