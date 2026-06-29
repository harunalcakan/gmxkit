#!/usr/bin/env bash
# Create a distributable gmxkit release zip (tracked files only; no FF, no sim outputs).
#
#   bash mdprep/make_release.sh [VERSION]
#   → dist/gmxkit-VERSION.zip
#
set -o errexit -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${MDPREP_DIR}/.." && pwd)"
VERSION="${1:-dev}"
DIST="${ROOT}/dist"
PREFIX="gmxkit-${VERSION}"
ZIP="${DIST}/${PREFIX}.zip"
STAGING="${DIST}/${PREFIX}"

cd "${ROOT}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[!] Not a git repository — use git clone for releases." >&2
    exit 1
fi

mkdir -p "${DIST}"
rm -rf "${STAGING}" "${ZIP}"

echo "=== GmxKit release ${VERSION} ==="
echo "Root: ${ROOT}"

# Clean export of tracked files only (.gitignore already excludes FF, trajectories, .venv)
git archive --format=tar HEAD --prefix="${PREFIX}/" \
    | tar -x -C "${DIST}"

# Ensure launcher is executable in the archive metadata
chmod +x "${STAGING}/md" "${STAGING}/mdprep/md.sh" 2>/dev/null || true
find "${STAGING}/mdprep" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

# Bundle quick-start at zip root
cp -f "${MDPREP_DIR}/docs/en/FIRST_RUN_CHECKLIST.md" "${STAGING}/QUICKSTART_CHECKLIST.md"
cp -f "${MDPREP_DIR}/docs/en/INSTALL.md" "${STAGING}/INSTALL.md"

cat > "${STAGING}/README_RELEASE.txt" <<EOF
GmxKit ${VERSION} — release package
==================================

1. Read INSTALL.md (full steps)
2. Use QUICKSTART_CHECKLIST.md while setting up
3. Install GROMACS (gmx) — not included
4. Force field charmm36-*.ff/ is included in this package
5. Run:  chmod +x gmxkit md && ./gmxkit install && gmxkit

GitHub: https://github.com/harunalcakan/gmxkit
EOF

(
    cd "${DIST}"
    if command -v zip >/dev/null 2>&1; then
        zip -rq "${PREFIX}.zip" "${PREFIX}"
    else
        tar -czf "${PREFIX}.tar.gz" "${PREFIX}"
        echo "[i] zip not found — created ${PREFIX}.tar.gz instead"
        ls -lh "${DIST}/${PREFIX}.tar.gz"
        exit 0
    fi
)

BYTES="$(wc -c < "${ZIP}" | tr -d ' ')"
echo ""
echo "[OK] ${ZIP}  (${BYTES} bytes)"
echo ""
echo "Upload:"
echo "  gh release create v${VERSION} '${ZIP}' --title 'GmxKit ${VERSION}' --notes-file mdprep/docs/en/RELEASE_NOTES.md"
echo ""
echo "User install:"
echo "  unzip ${PREFIX}.zip && cd ${PREFIX} && ./md install && ./md"
