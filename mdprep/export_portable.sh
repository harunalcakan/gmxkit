#!/usr/bin/env bash
# mdprep klasörünü Windows'ta kopyalanabilir paket olarak dışa aktar
# (.venv / logs / .state / backups hariç — WSL symlink ve kilit sorunları)
set -o errexit -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-${MDPREP_DIR}/../mdprep_portable}"

EXCLUDE=( ".venv" "logs" ".state" "backups" "__pycache__" )

mkdir -p "${DEST}"

if command -v rsync >/dev/null 2>&1; then
    args=(-a --delete)
    for x in "${EXCLUDE[@]}"; do args+=(--exclude "${x}/"); done
    rsync "${args[@]}" "${MDPREP_DIR}/" "${DEST}/"
else
    shopt -s dotglob nullglob
    for item in "${MDPREP_DIR}"/*; do
        base="$(basename "${item}")"
        skip=0
        for x in "${EXCLUDE[@]}"; do [[ "${base}" == "${x}" ]] && skip=1 && break; done
        [[ "${skip}" -eq 1 ]] && continue
        cp -a "${item}" "${DEST}/"
    done
    for dot in .gitignore; do
        [[ -f "${MDPREP_DIR}/${dot}" ]] && cp -a "${MDPREP_DIR}/${dot}" "${DEST}/"
    done
fi

cat > "${DEST}/KURULUM_YENI_KLASOR.txt" <<'EOF'
Taşınabilir mdprep paketi (.venv hariç).

Yeni bilgisayarda (WSL/Linux), proje kökünde:

  1) mdprep/ + protein.pdb + ligand.mol2 + *.mdp + FF klasörünü birlikte kopyalayın
  2) bash mdprep/md.sh install --with-apt
  3) ./md

Detay: mdprep/KURULUM_YENI_PC.md
EOF

# md launcher şablonu (proje köküne kopyalanacak)
cat > "${DEST}/md.launcher.example" <<'EOF'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/mdprep/md.sh" "$@"
EOF
chmod +x "${DEST}/md.launcher.example" 2>/dev/null || true

[[ -f "${MDPREP_DIR}/KURULUM_YENI_PC.md" ]] && cp -f "${MDPREP_DIR}/KURULUM_YENI_PC.md" "${DEST}/"

echo "OK: ${DEST}"
echo "Hariç tutulan: ${EXCLUDE[*]}"
