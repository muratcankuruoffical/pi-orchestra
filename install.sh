#!/usr/bin/env bash
# pi-orchestra installer — idempotent, preserves your existing settings.
#
#   ./install.sh            normal install
#   ./install.sh --check    inspect current state without installing anything
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DIR="$HOME/.pi/agent"
SETTINGS="$PI_DIR/settings.json"
MODELS="$PI_DIR/models.json"
LOCAL_MODEL="qwen3:8b"
LOCAL_ALIAS="qwen3-local"
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

log()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------- prerequisites
command -v jq   >/dev/null || die "jq is required: brew install jq"
command -v node >/dev/null || die "node is required"

# If nvm is present, switch to the default version: pi looks for its global
# packages under whichever node is active. Packages installed under a different
# version produce "module not found" errors.
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # shellcheck disable=SC1091
  . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 && nvm use default >/dev/null 2>&1 || true
fi

NODE_V="$(node -p 'const v=process.versions.node.split("."); `${v[0]}.${String(v[1]).padStart(3,"0")}`')"
if [[ "$(printf '%s\n22.019\n' "$NODE_V" | sort -V | head -1)" != "22.019" ]]; then
  die "Node $(node -v) is too old; pi requires >= 22.19. Fix: nvm install 22 --lts && nvm alias default 22"
fi

if [[ $CHECK_ONLY -eq 0 ]]; then
  # --------------------------------------------------------------------- pi
  # --min-release-age=0: if npm has minimumReleaseAge configured, pi installs at
  # an older version and becomes incompatible with its extensions (pi-ai/compat).
  NPM_AGE_FLAG=()
  npm install -g --min-release-age=0 --help >/dev/null 2>&1 && NPM_AGE_FLAG=(--min-release-age=0)

  log "Installing/updating pi"
  npm install -g "${NPM_AGE_FLAG[@]}" @earendil-works/pi-coding-agent

  # -------------------------------------------------------- ollama + local model
  if ! command -v ollama >/dev/null; then
    log "Installing Ollama"
    command -v brew >/dev/null || die "Ollama not found. Install it from https://ollama.com/download"
    brew install --cask ollama-app
  fi

  if ! ollama list >/dev/null 2>&1; then
    log "Starting Ollama"
    open -a Ollama >/dev/null 2>&1 || (ollama serve >/dev/null 2>&1 &)
    for _ in $(seq 1 30); do ollama list >/dev/null 2>&1 && break; sleep 1; done
    ollama list >/dev/null 2>&1 || die "Could not start Ollama."
  fi

  if ! ollama list | awk 'NR>1{print $1}' | grep -qx "$LOCAL_MODEL"; then
    log "Downloading $LOCAL_MODEL (~5 GB)"
    # Ollama resumes partial downloads, so a stalled transfer is worth retrying.
    for attempt in 1 2 3; do
      ollama pull "$LOCAL_MODEL" && break
      warn "download interrupted, resuming ($attempt/3)"
    done
    ollama list | awk 'NR>1{print $1}' | grep -qx "$LOCAL_MODEL" \
      || die "Could not download $LOCAL_MODEL. Switch networks and resume with: ollama pull $LOCAL_MODEL"
  fi

  # Ollama's default num_ctx (4K) is far too small for code work.
  if ! ollama list | awk 'NR>1{print $1}' | grep -q "^$LOCAL_ALIAS"; then
    log "Creating $LOCAL_ALIAS (num_ctx=32768)"
    MF="$(mktemp -t orchestra-modelfile)"
    printf 'FROM %s\nPARAMETER num_ctx 32768\n' "$LOCAL_MODEL" > "$MF"
    ollama create "$LOCAL_ALIAS" -f "$MF"
    rm -f "$MF"
  fi

  # ------------------------------------------------------------- pi settings
  mkdir -p "$PI_DIR"
  [[ -f "$MODELS"   ]] || echo '{}' > "$MODELS"
  [[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"

  jq -s '.[0] * .[1]' "$MODELS" "$REPO/config/models.json" > "$MODELS.tmp" && mv "$MODELS.tmp" "$MODELS"

  jq '
      .defaultProvider = (.defaultProvider // "deepseek")
    | .defaultModel    = (.defaultModel    // "deepseek-flash")
    | .enabledModels   = ((.enabledModels // []) + ["deepseek/*", "ollama/*"] | unique)
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  log "pi settings updated"

  # ------------------------------------------- orchestra CLI + Claude Code skill
  mkdir -p "$HOME/.local/bin" "$HOME/.claude/skills"
  ln -sfn "$REPO/bin/orchestra"  "$HOME/.local/bin/orchestra"
  ln -sfn "$REPO/claude-skill"   "$HOME/.claude/skills/orchestra"
  log "Linked orchestra CLI and Claude Code skill"

  # A skill alone does not fire reliably: its description is only a suggestion to
  # the model, which often starts working directly. The directive in CLAUDE.md is
  # always in context, so that is what actually enforces delegation.
  cp "$REPO/ORCHESTRA.md" "$HOME/.claude/ORCHESTRA.md"
  CC_MD="$HOME/.claude/CLAUDE.md"
  touch "$CC_MD"
  grep -q '@ORCHESTRA.md' "$CC_MD" || printf '@ORCHESTRA.md\n' >> "$CC_MD"
  log "Installed ORCHESTRA.md and wired it into ~/.claude/CLAUDE.md"

  # Allowlist only the low-risk commands. 'orchestra simple' runs the local model,
  # which has no bash tool; medium/hard give the remote model shell access and
  # deliberately keep prompting.
  CC_SETTINGS="$HOME/.claude/settings.json"
  [[ -f "$CC_SETTINGS" ]] || echo '{}' > "$CC_SETTINGS"
  TMP="$(mktemp)"
  jq '.permissions = ((.permissions // {}) | .allow = ((.allow // []) +
        ["Bash(orchestra simple *)", "Bash(orchestra init)", "Bash(orchestra init *)"] | unique))' \
     "$CC_SETTINGS" > "$TMP" && mv "$TMP" "$CC_SETTINGS"
  log "Allowlisted orchestra simple / orchestra init"
fi

# ---------------------------------------------------------------------- status
echo
log "Status"

command -v pi >/dev/null && ok "pi $(pi --version)" || warn "pi not found"
command -v claude >/dev/null \
  && ok "Claude Code $(claude --version 2>/dev/null | head -1) — the orchestrator layer" \
  || warn "Claude Code CLI missing. It is the orchestrator; see https://claude.com/claude-code"

if ollama list >/dev/null 2>&1; then
  if ollama list | awk 'NR>1{print $1}' | grep -q "^$LOCAL_ALIAS"; then
    ok "local model ready ($LOCAL_ALIAS, 32K context)"
  else
    warn "local model missing. Run ./install.sh"
  fi
else
  warn "Ollama is not running. Try: open -a Ollama  (or: ollama serve)"
fi

if [[ -n "${DEEPSEEK_API_KEY:-}" ]] || jq -e '.deepseek' "$PI_DIR/auth.json" >/dev/null 2>&1; then
  ok "DeepSeek key configured"
else
  warn "No DeepSeek key → MEDIUM/HARD tiers will not work. Run 'pi', then /login → DeepSeek"
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok "orchestra is on PATH" ;;
  *) warn "~/.local/bin is not on PATH. Add to your profile: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

[[ -e "$HOME/.claude/skills/orchestra/SKILL.md" ]] \
  && ok "Claude Code skill installed" \
  || warn "skill not linked: ~/.claude/skills/orchestra"

if [[ -f "$HOME/.claude/ORCHESTRA.md" ]] && grep -qs '@ORCHESTRA.md' "$HOME/.claude/CLAUDE.md"; then
  ok "delegation directive active in ~/.claude/CLAUDE.md"
else
  warn "directive missing → the skill will not fire reliably. Run ./install.sh"
fi

echo
if [[ $CHECK_ONLY -eq 1 ]]; then
  log "Check complete (nothing was modified)."
else
  log "Done. Run 'claude' in a project directory and talk to it normally."
fi
