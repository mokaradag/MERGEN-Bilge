#!/usr/bin/env bash

# ==============================================================================
# Dosya Yolu: tools/install_ai_git_hooks.sh
# Açıklama:
#   Codex/Claude gibi AI çalışma ortamlarında final çalışma ağacını korumak için
#   yerel pre-commit bakım ratchet kancasını idempotent biçimde kurar.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Git worktree unavailable; skipping AI pre-commit hook installation."
  exit 0
fi

HOOK_PATH="$(git rev-parse --git-path hooks/pre-commit)"
HOOK_MARKER="# MERGEN_AI_MAINTAINABILITY_HOOK"
mkdir -p "$(dirname "${HOOK_PATH}")"

if [[ -f "${HOOK_PATH}" ]] && ! grep -Fq "${HOOK_MARKER}" "${HOOK_PATH}"; then
  echo "WARNING: Existing pre-commit hook is not managed by MERGEN; leaving it unchanged." >&2
  echo "Run 'bash tools/maintainability_ratchet_gate.sh' manually before committing." >&2
  exit 0
fi

cat > "${HOOK_PATH}" <<'EOF'
#!/usr/bin/env bash
# MERGEN_AI_MAINTAINABILITY_HOOK
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

bash tools/maintainability_ratchet_gate.sh
EOF

chmod +x "${HOOK_PATH}"
echo "Installed MERGEN AI pre-commit maintainability gate: ${HOOK_PATH}"
