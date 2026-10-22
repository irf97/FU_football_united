#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

if [[ "${FU_BROWSER_QA:-}" != "1" || "${DATABASE_URL:-}" != "postgres://postgres:postgres@localhost:5432/fu_pilot_qa" ]]; then
  echo "Release QA only supports the disposable local fu_pilot_qa database" >&2
  exit 1
fi

export COMPOSE_PROJECT_NAME=fu-acceptance-qa
export FU_QA_APP_CONTAINER=fu-pilot-qa
export FU_SMS_API_KEY=fu-sim-local-rehearsal-only
export SECRET_KEY_BASE
SECRET_KEY_BASE=$(node -e 'process.stdout.write(require("node:crypto").randomBytes(64).toString("base64"))')
compose=(docker compose -f compose.rehearsal.yml)
if [[ -n "$("${compose[@]}" ps --all --quiet)" ]]; then
  echo "The acceptance project already exists; choose an empty local QA environment" >&2
  exit 1
fi
for qa_name in fu-pilot-qa fu-restored-qa fu-bad-config-qa; do
  if docker container inspect "$qa_name" >/dev/null 2>&1; then
    echo "A reserved QA container already exists: $qa_name" >&2
    exit 1
  fi
done
node -e 'const fs=require("node:fs"); fs.rmSync("qa/results",{recursive:true,force:true}); fs.mkdirSync("qa/results",{recursive:true})'
cleanup() {
  local qa_exit=$?
  trap - EXIT
  if [[ "$qa_exit" != 0 ]]; then "${compose[@]}" logs --no-color --tail 100 > qa/results/release-failure.log 2>&1 || true; fi
  FU_QA_EXIT="$qa_exit" node qa/report.cjs || qa_exit=1
  docker rm -f fu-restored-qa fu-bad-config-qa >/dev/null 2>&1 || true
  "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -f /tmp/fu-rehearsal-browser-state.json
  exit "$qa_exit"
}
trap cleanup EXIT

node --test qa/sms-server.test.cjs qa/live-preflight.test.cjs
"${compose[@]}" build app sms
"${compose[@]}" up --detach app
export FU_QA_POSTGRES_CONTAINER
FU_QA_POSTGRES_CONTAINER=$("${compose[@]}" ps --quiet db)
node -e 'require("./qa/runtime.cjs").waitReady().catch(e=>{console.error(e);process.exitCode=1})'

# Check the actual production runtime in the same image, without networking.
image_id=$(docker inspect --format '{{.Image}}' "$FU_QA_APP_CONTAINER")
prod_env=(-e DATABASE_URL=postgres://unused/unused -e "SECRET_KEY_BASE=$SECRET_KEY_BASE" -e PHX_HOST=example.invalid -e FU_MODE=production)
docker run --rm --network none "${prod_env[@]}" "$image_id" /app/bin/fu eval '
  if Application.get_env(:fu, :environment) != :production, do: raise("production label missing")
  if Application.get_env(:fu, :show_otp_codes), do: raise("production exposes OTPs")
  if Fu.Admin.admin_login_enabled?(), do: raise("production has an admin fallback")
  unless Fu.SMS.deliver("+31680000099", "synthetic QA") == {:error, :not_configured}, do: raise("unconfigured SMS must fail closed")
'
if docker run --rm --network none "${prod_env[@]}" -e FU_SMS_ENDPOINT=http://sms:9166/messages "$image_id" /app/bin/fu eval ':ok' > qa/results/rejected-profile.log 2>&1; then
  echo "Production accepted a simulation endpoint" >&2
  exit 1
fi
node -e 'if(!require("node:fs").readFileSync("qa/results/rejected-profile.log","utf8").includes("production does not accept a simulator endpoint")) process.exit(1)'
node -e 'const q=require("./qa/runtime.cjs"); q.save("boundary.json",{status:"passed",same_release_image:true,production_simulator_rejected:true,unconfigured_sms:"fail_closed",demo_codes:false,admin_fallback:false}); q.save("manifest.json",{source_revision:require("node:child_process").execFileSync("git",["rev-parse","HEAD"],{encoding:"utf8"}).trim(),image_id:JSON.parse(q.docker("inspect",q.appContainer))[0].Image,started_at:new Date().toISOString(),node:process.version})'

npm --prefix qa test
node qa/operations.cjs
node qa/recovery.cjs
