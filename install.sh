#!/usr/bin/env bash
# pi-orchestra kurulumu — idempotent, mevcut ayarları korur.
#
#   ./install.sh            normal kurulum
#   ./install.sh --check    hiçbir şey kurmadan mevcut durumu denetle
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DIR="$HOME/.pi/agent"
SETTINGS="$PI_DIR/settings.json"
MODELS="$PI_DIR/models.json"
LOCAL_MODEL="qwen2.5-coder:7b"
LOCAL_ALIAS="qwen-coder-local"
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

log()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mHATA:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- ön koşullar
command -v jq   >/dev/null || die "jq gerekli: brew install jq"
command -v node >/dev/null || die "node gerekli"

# nvm varsa varsayılan sürüme geç: pi, hangi node aktifse onun global paketlerini
# arar. Yanlış sürümde kurulan paketler "bulunamadı" hatası verir.
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  # shellcheck disable=SC1091
  . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 && nvm use default >/dev/null 2>&1 || true
fi

NODE_V="$(node -p 'const v=process.versions.node.split("."); `${v[0]}.${String(v[1]).padStart(3,"0")}`')"
if [[ "$(printf '%s\n22.019\n' "$NODE_V" | sort -V | head -1)" != "22.019" ]]; then
  die "Node $(node -v) çok eski; pi >= 22.19 istiyor. Çözüm: nvm install 22 --lts && nvm alias default 22"
fi

if [[ $CHECK_ONLY -eq 0 ]]; then
  # ------------------------------------------------------------------ pi + pi-lens
  # --min-release-age=0: npm'de minimumReleaseAge ayarlıysa pi eski bir sürüme
  # düşer ve eklentileriyle uyumsuz kalır (pi-ai/compat hatası).
  NPM_AGE_FLAG=()
  npm install -g --min-release-age=0 --help >/dev/null 2>&1 && NPM_AGE_FLAG=(--min-release-age=0)

  log "pi + pi-lens kuruluyor/güncelleniyor"
  npm install -g "${NPM_AGE_FLAG[@]}" @earendil-works/pi-coding-agent pi-lens
  pi list 2>/dev/null | grep -q "npm:pi-lens" || pi install npm:pi-lens >/dev/null

  # ------------------------------------------------------------- ollama + model
  if ! command -v ollama >/dev/null; then
    log "Ollama kuruluyor"
    command -v brew >/dev/null || die "Ollama bulunamadı. https://ollama.com/download adresinden kur."
    brew install --cask ollama-app
  fi

  if ! ollama list >/dev/null 2>&1; then
    log "Ollama başlatılıyor"
    open -a Ollama >/dev/null 2>&1 || (ollama serve >/dev/null 2>&1 &)
    for _ in $(seq 1 30); do ollama list >/dev/null 2>&1 && break; sleep 1; done
    ollama list >/dev/null 2>&1 || die "Ollama başlatılamadı."
  fi

  if ! ollama list | awk 'NR>1{print $1}' | grep -qx "$LOCAL_MODEL"; then
    log "$LOCAL_MODEL indiriliyor (~4.7 GB)"
    # Ağ takılırsa ollama parçalı indirmeyi sürdürür; birkaç kez dene.
    for attempt in 1 2 3; do
      ollama pull "$LOCAL_MODEL" && break
      warn "indirme kesildi, kaldığı yerden tekrar deneniyor ($attempt/3)"
    done
    ollama list | awk 'NR>1{print $1}' | grep -qx "$LOCAL_MODEL" \
      || die "$LOCAL_MODEL indirilemedi. Ağı değiştirip 'ollama pull $LOCAL_MODEL' ile sürdür."
  fi

  # Ollama'nın varsayılan num_ctx'i (4K) kod işleri için çok küçük.
  if ! ollama list | awk 'NR>1{print $1}' | grep -q "^$LOCAL_ALIAS"; then
    log "$LOCAL_ALIAS oluşturuluyor (num_ctx=32768)"
    MF="$(mktemp -t orchestra-modelfile)"
    printf 'FROM %s\nPARAMETER num_ctx 32768\n' "$LOCAL_MODEL" > "$MF"
    ollama create "$LOCAL_ALIAS" -f "$MF"
    rm -f "$MF"
  fi

  # --------------------------------------------------------------- pi ayarları
  mkdir -p "$PI_DIR"
  [[ -f "$MODELS"   ]] || echo '{}' > "$MODELS"
  [[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"

  jq -s '.[0] * .[1]' "$MODELS" "$REPO/config/models.json" > "$MODELS.tmp" && mv "$MODELS.tmp" "$MODELS"

  jq '
      .defaultProvider = (.defaultProvider // "deepseek")
    | .defaultModel    = (.defaultModel    // "deepseek-flash")
    | .packages        = ((.packages     // []) + ["npm:pi-lens"] | unique)
    | .enabledModels   = ((.enabledModels // []) + ["deepseek/*", "ollama/*"] | unique)
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  log "pi ayarları güncellendi"

  # ------------------------------------------------ orchestra CLI + Claude skill
  mkdir -p "$HOME/.local/bin" "$HOME/.claude/skills"
  ln -sfn "$REPO/bin/orchestra"  "$HOME/.local/bin/orchestra"
  ln -sfn "$REPO/claude-skill"   "$HOME/.claude/skills/orchestra"
  log "orchestra CLI ve Claude Code skill'i bağlandı"
fi

# -------------------------------------------------------------------- denetim
echo
log "Durum"

command -v pi >/dev/null && ok "pi $(pi --version)" || warn "pi bulunamadı"
command -v claude >/dev/null \
  && ok "Claude Code $(claude --version 2>/dev/null | head -1) — orchestrator katmanı" \
  || warn "Claude Code CLI yok. Orchestrator katmanı bu; https://claude.com/claude-code"

if ollama list >/dev/null 2>&1; then
  if ollama list | awk 'NR>1{print $1}' | grep -q "^$LOCAL_ALIAS"; then
    ok "lokal model hazır ($LOCAL_ALIAS, 32K context)"
  else
    warn "lokal model yok. './install.sh' ile kur."
  fi
else
  warn "Ollama çalışmıyor. 'open -a Ollama' ya da 'ollama serve'"
fi

if [[ -n "${DEEPSEEK_API_KEY:-}" ]] || jq -e '.deepseek' "$PI_DIR/auth.json" >/dev/null 2>&1; then
  ok "DeepSeek anahtarı bağlı"
else
  warn "DeepSeek anahtarı yok → ORTA/ZOR katmanları çalışmaz. 'pi' içinde /login → DeepSeek"
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok "orchestra PATH'te" ;;
  *) warn "~/.local/bin PATH'te değil. Profiline ekle: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

[[ -e "$HOME/.claude/skills/orchestra/SKILL.md" ]] \
  && ok "Claude Code skill'i kurulu" \
  || warn "skill bağlanmamış: ~/.claude/skills/orchestra"

echo
if [[ $CHECK_ONLY -eq 1 ]]; then
  log "Denetim bitti (hiçbir şey değiştirilmedi)."
else
  log "Kurulum bitti. Bir proje klasöründe 'claude' çalıştır ve normal konuş."
fi
