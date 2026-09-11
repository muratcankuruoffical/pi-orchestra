#!/usr/bin/env bash
# pi-orchestra kurulumu — idempotent, mevcut ayarları korur.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DIR="$HOME/.pi/agent"
SETTINGS="$PI_DIR/settings.json"
MODELS="$PI_DIR/models.json"
LOCAL_MODEL="qwen2.5-coder:7b"
LOCAL_ALIAS="qwen-coder-local"

log() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31mHATA:\033[0m %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null || die "jq gerekli: brew install jq"
command -v node >/dev/null || die "node gerekli"

NODE_MAJOR_MINOR="$(node -p 'const [a,b]=process.versions.node.split("."); `${a}.${String(b).padStart(3,"0")}`')"
if [[ "$(printf '%s\n22.019\n' "$NODE_MAJOR_MINOR" | sort -V | head -1)" != "22.019" ]]; then
  warn "Node $(node -v) kullanıyorsun; pi-subagents >=22.19.0 istiyor. 'nvm install 22 --lts' önerilir."
fi

# --- pi ---
# --min-release-age=0: npm'in minimumReleaseAge ayarı pi'yi eski bir sürüme
# düşürüyor ve pi-subagents ile sürüm uyumsuzluğu (pi-ai/compat) yaratıyor.
NPM_AGE_FLAG=()
npm install -g --min-release-age=0 --help >/dev/null 2>&1 && NPM_AGE_FLAG=(--min-release-age=0)

log "pi kuruluyor/güncelleniyor"
npm install -g "${NPM_AGE_FLAG[@]}" @earendil-works/pi-coding-agent
log "pi $(pi --version)"

# --- pi paketleri ---
log "pi-lens kuruluyor/güncelleniyor"
npm install -g "${NPM_AGE_FLAG[@]}" pi-lens
for pkg in pi-lens; do
  pi list 2>/dev/null | grep -q "npm:$pkg" || pi install "npm:$pkg" >/dev/null
done


# --- ollama + lokal model ---
if ! command -v ollama >/dev/null; then
  log "Ollama kuruluyor"
  if command -v brew >/dev/null; then
    brew install --cask ollama-app
  else
    die "Ollama bulunamadı. https://ollama.com/download adresinden kur, sonra tekrar çalıştır."
  fi
fi

pgrep -x ollama >/dev/null || { log "Ollama başlatılıyor"; open -a Ollama 2>/dev/null || (ollama serve >/dev/null 2>&1 &); sleep 3; }

if ! ollama list 2>/dev/null | grep -q "^${LOCAL_MODEL%%:*}"; then
  log "$LOCAL_MODEL indiriliyor (~4.7 GB)"
  ollama pull "$LOCAL_MODEL"
fi

# 32K context'li alias: Ollama'nın varsayılan num_ctx'i kod işleri için çok küçük
if ! ollama list 2>/dev/null | grep -q "^$LOCAL_ALIAS"; then
  log "$LOCAL_ALIAS oluşturuluyor (num_ctx=32768)"
  MF="$(mktemp -t orchestra-modelfile)"
  printf 'FROM %s\nPARAMETER num_ctx 32768\n' "$LOCAL_MODEL" > "$MF"
  ollama create "$LOCAL_ALIAS" -f "$MF"
  rm -f "$MF"
fi

# --- models.json birleştir ---
mkdir -p "$PI_DIR"
[[ -f "$MODELS" ]] || echo '{}' > "$MODELS"
jq -s '.[0] * .[1]' "$MODELS" "$REPO/config/models.json" > "$MODELS.tmp" && mv "$MODELS.tmp" "$MODELS"
log "models.json güncellendi (ollama + deepseek-flash)"

# --- settings.json birleştir (mevcut değerleri ezmeden) ---
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
jq --arg repo "$REPO" '
  .defaultProvider   = (.defaultProvider   // "deepseek")
  | .defaultModel    = (.defaultModel      // "deepseek-flash")
  | .packages        = ((.packages // []) + ["npm:pi-subagents", "npm:pi-lens"] | unique)
  | .enabledModels   = ((.enabledModels // []) + ["deepseek/*", "ollama/*", "anthropic/*"] | unique)
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
log "settings.json güncellendi"

# --- orchestra CLI ve Claude Code skill'i ---
mkdir -p "$HOME/.local/bin" "$HOME/.claude/skills"
ln -sfn "$REPO/bin/orchestra" "$HOME/.local/bin/orchestra"
ln -sfn "$REPO/claude-skill" "$HOME/.claude/skills/orchestra"
log "orchestra → ~/.local/bin/orchestra, skill → ~/.claude/skills/orchestra"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) warn "~/.local/bin PATH'te değil. Shell profiline ekle: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# --- kontroller ---
echo
if [[ -z "${DEEPSEEK_API_KEY:-}" ]] && ! jq -e '.deepseek' "$PI_DIR/auth.json" >/dev/null 2>&1; then
  warn "DeepSeek anahtarı yok. 'export DEEPSEEK_API_KEY=sk-...' ya da pi içinde '/login' → DeepSeek."
fi
command -v claude >/dev/null || warn "Claude Code CLI bulunamadı — orchestrator katmanı bu. https://claude.com/claude-code"

log "Kurulum bitti. Bir proje klasöründe 'claude' çalıştır ve normal konuş; orchestra skill'i devreye girer."
