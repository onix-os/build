#!/usr/bin/env bash
# vm/phase1/publish-dry-run.sh — preview ONIX repo publication without upload.
#
# Runs on the host only. It does not SSH, does not upload, and does not touch DNS.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ONIX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

EXPORT_ROOT="${ONIX_PUBLISH_EXPORT_DIR:-$ONIX_ROOT/artifacts/onix-publish}"
PUBLIC_BASE_URL="${ONIX_REPO_PUBLIC_BASE_URL:-https://repo.onix-os.com}"
UPLOAD_TARGET="${ONIX_REPO_UPLOAD_TARGET:-}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_cmd find
need_cmd sed
need_cmd sort

echo "==> verify no-upload plan and exported artifact"
"$SCRIPT_DIR/prepare-publish-plan.sh" >/dev/null

echo "==> dry-run publication preview"
echo "local root : ${EXPORT_ROOT#$ONIX_ROOT/}"
echo "public root: $PUBLIC_BASE_URL"
if [[ -n "$UPLOAD_TARGET" ]]; then
  echo "upload root: $UPLOAD_TARGET"
else
  echo "upload root: not configured (set ONIX_REPO_UPLOAD_TARGET later)"
fi

echo
echo "==> files that would be published"
while IFS= read -r file; do
  rel="${file#$EXPORT_ROOT/}"
  printf '  %s\n' "$rel"
done < <(find "$EXPORT_ROOT" -type f | sort)

echo
echo "==> public URL mapping"
while IFS= read -r file; do
  rel="${file#$EXPORT_ROOT/}"
  printf '  %-70s -> %s/%s\n' "$rel" "${PUBLIC_BASE_URL%/}" "$rel"
done < <(find "$EXPORT_ROOT" -type f | sort)

echo
echo "==> critical URLs to verify after a real upload"
cat <<EOF
${PUBLIC_BASE_URL%/}/unstable/x86_64/stone.index
${PUBLIC_BASE_URL%/}/unstable/x86_64/SHA256SUMS
EOF

echo
echo "==> commands this dry-run refuses to execute"
if [[ -n "$UPLOAD_TARGET" ]]; then
  cat <<EOF
rsync -av --delete '${EXPORT_ROOT%/}/' '$UPLOAD_TARGET/'
EOF
else
  cat <<'EOF'
rsync -av --delete 'artifacts/onix-publish/' '<upload-target>/'
EOF
fi

cat <<EOF
curl -fsSL '${PUBLIC_BASE_URL%/}/unstable/x86_64/stone.index' -o /tmp/onix-public-stone.index
curl -fsSL '${PUBLIC_BASE_URL%/}/unstable/x86_64/SHA256SUMS' -o /tmp/onix-public-SHA256SUMS
EOF

echo
echo "==> future user-facing repo command after public verification"
cat <<EOF
moss repo add onix-unstable ${PUBLIC_BASE_URL%/}/unstable/x86_64/stone.index -c "ONIX unstable"
moss repo update
EOF

echo
echo "==> safety result"
echo "DRY RUN ONLY: no upload performed, no DNS changed, no network contacted"
