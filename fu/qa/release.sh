#!/usr/bin/env bash
set -euo pipefail

if [[ "${FU_BROWSER_QA:-}" != "1" || "${DATABASE_URL:-}" != "postgres://postgres:postgres@localhost:5432/fu_pilot_qa" ]]; then
  echo "Release QA only supports the disposable local fu_pilot_qa database" >&2
  exit 1
fi

# Values below belong only to this disposable CI container.
qa_env=(
  -e "DATABASE_URL=$DATABASE_URL"
  -e "SECRET_KEY_BASE=fu-qa-only-never-use-in-production-0123456789012345678901234567890123456789"
  -e PHX_HOST=localhost -e PORT=4000 -e "ERL_FLAGS=+S 2:2"
)
cleanup() { docker rm -f fu-pilot-qa >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker build --tag fu-pilot-qa .
docker run --rm --network host "${qa_env[@]}" fu-pilot-qa /app/bin/migrate
docker run --detach --name fu-pilot-qa --network host "${qa_env[@]}" fu-pilot-qa

ready=0
for attempt in {1..30}; do
  if curl --fail --silent --max-time 3 http://localhost:4000/healthz > /dev/null; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" != 1 ]]; then
  docker logs fu-pilot-qa
  exit 1
fi

# These assertions run in the actual production image before test setup.
docker exec fu-pilot-qa /app/bin/fu rpc '
  if Application.get_env(:fu, :show_otp_codes), do: raise("production exposes OTPs")
  if Fu.Admin.admin_login_enabled?(), do: raise("production has an admin fallback")
  unless Fu.SMS.deliver("+31680000099", "synthetic QA") == {:error, :not_configured}, do: raise("SMS must fail closed")
'
npm --prefix qa test
node qa/recovery.cjs
