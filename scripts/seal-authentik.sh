#!/usr/bin/env bash
# Seal the Authentik secrets and write the ciphertext into the casa.yaml env files.
#
# Reads plaintext from scripts/authentik-secrets.env (git-ignored; see the .example).
# Requires: kubeseal, python3, and a KUBECONFIG pointing at the cluster
# (sealed-secrets controller in kube-system).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/scripts/authentik-secrets.env"
PG_FILE="${REPO_ROOT}/apps/data/authentik-postgres/environments/local/casa.yaml"
AK_FILE="${REPO_ROOT}/apps/security/authentik/environments/local/casa.yaml"

: "${KUBECONFIG:=${HOME}/.kube/k3slocal.yaml}"
export KUBECONFIG

PG_NS="data-casa";     PG_SECRET="authentik-postgres-app"
AK_NS="security-casa"; AK_SECRET="authentik-secret"

# Sealed-secrets controller (service in kube-system is named "sealed-secrets")
: "${SEALED_SECRETS_CONTROLLER_NAME:=sealed-secrets}"
: "${SEALED_SECRETS_CONTROLLER_NAMESPACE:=kube-system}"

# --- preconditions -----------------------------------------------------------
command -v kubeseal >/dev/null || { echo "ERROR: kubeseal not found in PATH" >&2; exit 1; }
command -v python3  >/dev/null || { echo "ERROR: python3 not found in PATH"  >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE not found. Copy scripts/authentik-secrets.env.example and fill it." >&2; exit 1; }

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

: "${AUTHENTIK_DB_USERNAME:=authentik}"
[[ -n "${AUTHENTIK_DB_PASSWORD:-}" ]]        || { echo "ERROR: AUTHENTIK_DB_PASSWORD is required" >&2; exit 1; }
[[ -n "${AUTHENTIK_BOOTSTRAP_PASSWORD:-}" ]] || { echo "ERROR: AUTHENTIK_BOOTSTRAP_PASSWORD is required" >&2; exit 1; }
[[ -n "${AUTHENTIK_SECRET_KEY:-}" ]]    || { AUTHENTIK_SECRET_KEY="$(openssl rand -base64 60 | tr -d '\n')"; echo "info: generated AUTHENTIK_SECRET_KEY"; }
[[ -n "${AUTHENTIK_BOOTSTRAP_TOKEN:-}" ]] || { AUTHENTIK_BOOTSTRAP_TOKEN="$(openssl rand -hex 32)";          echo "info: generated AUTHENTIK_BOOTSTRAP_TOKEN"; }

# --- helpers -----------------------------------------------------------------
seal() { # seal <namespace> <secret-name> <plaintext>  -> prints ciphertext, aborts on failure
  local out
  out="$(printf '%s' "$3" | kubeseal --raw --from-file=/dev/stdin \
    --namespace "$1" --name "$2" \
    --controller-name "$SEALED_SECRETS_CONTROLLER_NAME" \
    --controller-namespace "$SEALED_SECRETS_CONTROLLER_NAMESPACE")" \
    || { echo "ERROR: kubeseal failed for ${1}/${2}" >&2; exit 1; }
  [[ -n "$out" ]] || { echo "ERROR: empty ciphertext for ${1}/${2}" >&2; exit 1; }
  printf '%s' "$out"
}

patch() { # patch <file> <key> <sealed-value>
  python3 - "$1" "$2" "$3" <<'PY'
import re, sys
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f: text = f.read()
pat = re.compile(r'^(\s*)' + re.escape(key) + r':.*$', re.M)
if not pat.search(text):
    sys.exit(f"key {key!r} not found in {path}")
text = pat.sub(lambda m: f'{m.group(1)}{key}: "{val}"', text, count=1)
with open(path, "w") as f: f.write(text)
PY
}

echo ">> sealing into ${PG_NS}/${PG_SECRET} and ${AK_NS}/${AK_SECRET} (KUBECONFIG=${KUBECONFIG})"

# Postgres CNPG app secret (data-casa)
patch "$PG_FILE" username "$(seal "$PG_NS" "$PG_SECRET" "$AUTHENTIK_DB_USERNAME")"
patch "$PG_FILE" password "$(seal "$PG_NS" "$PG_SECRET" "$AUTHENTIK_DB_PASSWORD")"

# Authentik runtime secret (security-casa) — DB password is the SAME plaintext
patch "$AK_FILE" AUTHENTIK_SECRET_KEY          "$(seal "$AK_NS" "$AK_SECRET" "$AUTHENTIK_SECRET_KEY")"
patch "$AK_FILE" AUTHENTIK_POSTGRESQL__PASSWORD "$(seal "$AK_NS" "$AK_SECRET" "$AUTHENTIK_DB_PASSWORD")"
patch "$AK_FILE" AUTHENTIK_BOOTSTRAP_PASSWORD  "$(seal "$AK_NS" "$AK_SECRET" "$AUTHENTIK_BOOTSTRAP_PASSWORD")"
patch "$AK_FILE" AUTHENTIK_BOOTSTRAP_TOKEN     "$(seal "$AK_NS" "$AK_SECRET" "$AUTHENTIK_BOOTSTRAP_TOKEN")"

echo ">> done. Updated:"
echo "   $PG_FILE"
echo "   $AK_FILE"
echo ">> review the diff and commit. The plaintext in $ENV_FILE stays git-ignored."
