# pi-orchestra

Maliyet-optimize, çok katmanlı kodlama agent sistemi. [pi](https://pi.dev) üzerinde çalışır.

Fikir basit: **her işi en pahalı modele yaptırmak israf.** Orchestrator önce görevin zorluğunu belirler, sonra o zorluğa uygun en ucuz modele delege eder. Sonuç, marjinal maliyeti sıfır olan bir review katmanından geçer.

```
                    ORCHESTRATOR
                  (DeepSeek V4.1 Flash)
                         │
                  görev zorluğunu belirle
                         │
        ┌────────────────┼─────────────────┐
        ▼                ▼                 ▼
      BASİT             ORTA               ZOR
        │                │                 │
        ▼                ▼                 ▼
   local-coder       ds-worker        ds-architect
   Qwen2.5-Coder     DeepSeek         DeepSeek V4.1
   7B (lokal)        V4.1 Flash       Flash + thinking:high
        │                │                 │
   typo / küçük      feature /         mimari /
   bug / test        refactor          karmaşık bug
        │                │                 │
        └────────────────┼─────────────────┘
                         ▼
                  test + lint + typecheck
                    (orchestrator koşturur)
                         │
                         ▼
                  claude-code review
                   (Opus, abonelik)
                         │
                    ┌────┴────┐
                    ▼         ▼
                  PASS       FAIL
                    │         │
                   DONE   claude-code-writer
                              │
                          (en fazla 2 tur)
```

## Neden bu kombinasyon

| Katman | Model | Maliyet | Neden |
|---|---|---|---|
| Orchestrator | DeepSeek V4.1 Flash | ~$0.15 / $0.60 per M | Sadece sınıflandırma ve delegasyon yapar; kod yazmaz. 1M context. |
| BASİT | Qwen2.5-Coder 7B (Ollama) | **$0** | HumanEval %88. Typo/rename/küçük test için fazlasıyla yeterli, internete çıkmaz. |
| ORTA / ZOR | DeepSeek V4.1 Flash | ~$0.15 / $0.60 per M | Fiyat/performans dengesi. ZOR'da `thinking: high` açılır. |
| Review + fix | Claude Code CLI (Opus) | **$0 marjinal** | Mevcut Claude aboneliğinden çalışır. |

**Önemli:** review katmanı `pi`'nin Anthropic OAuth'unu **kullanmaz**. pi'nin kendi Claude Pro/Max girişi "extra usage" olarak token başına faturalanır. Bunun yerine `pi-subagents`'ın `claude-code` / `claude-code-writer` adapter'ları kullanılır; bunlar senin kurulu ve login olmuş `claude` CLI'ını çağırır, yani gerçekten abonelikten çalışır.

Tipik bir feature (≈200K in / 20K out) toplam **~$0.07**. Aynı işin tamamı Opus'ta yapılsaydı iki mertebe daha pahalı olurdu.

## Kurulum

```bash
git clone https://github.com/endigitals/pi-orchestra ~/pi-orchestra
cd ~/pi-orchestra && ./install.sh
export DEEPSEEK_API_KEY=sk-...   # veya: pi → /login → DeepSeek
```

`install.sh` idempotenttir ve mevcut `~/.pi/agent/settings.json` değerlerini ezmez. Şunları yapar:

- `pi` + `pi-subagents` + `pi-lens` kurar
- Ollama'yı kurar, `qwen2.5-coder:7b` indirir, 32K context'li `qwen-coder-local` alias'ını oluşturur
- `models.json`'a `ollama` provider'ını ve `deepseek-flash` modelini ekler
- `settings.json`'a agent/skill/prompt yollarını ve model yönlendirmesini ekler

### Gereksinimler

- Node **≥ 22.19** (`pi-subagents` şartı)
- `jq`, Homebrew
- Claude Code CLI — kurulu ve login olmuş (review katmanı için)
- ~5 GB disk, ≥16 GB RAM (lokal model için)

## Kullanım

Herhangi bir proje klasöründe:

```bash
pi
```

Sonra:

| Komut | Ne yapar |
|---|---|
| `/orchestrate <görev>` | Tam akış: sınıflandır → delege et → test et → review et → düzelt |
| `/route <görev>` | Sadece sınıflandırır ve tahmini maliyeti söyler, kod yazmaz |

Slash komutu kullanmadan normal konuşsan da olur — `task-routing` skill'i devrededir ve orchestrator kendi kendine yönlendirir.

Seviyeyi kendin de dayatabilirsin: *"bunu lokalde yap"*, *"bu zor bir iş, architect'e ver"*.

## Sınıflandırma rubriği

Tam kurallar `skills/task-routing/SKILL.md` içinde. Özet:

**BASİT** — hepsi doğruysa: tek dosya, ~20 satır altı, doğru çözüm tartışmasız belli, mimari/API/şema/auth/ödeme etkilenmiyor, yeni bağımlılık yok.

**ORTA** — 2–10 dosya, sınırları belli feature veya refactor, mevcut desenlerin içinde.

**ZOR** — herhangi biri doğruysa: mimari karar, kök nedeni belirsiz bug, performans/concurrency/güvenlik, geri alması pahalı (migration, auth, ödeme, public API), 10+ dosya.

Kural: **tereddütte bir üst seviyeye çık.** Yanlış BASİT seçmenin maliyeti, gereksiz ORTA seçmenin maliyetinden yüksektir.

## Proje bazlı ayar

Projenin kendi doğrulama komutlarını `.pi/settings.json` içine koy:

```json
{
  "orchestra": {
    "verify": {
      "typecheck": "npm run typecheck",
      "lint": "npm run lint",
      "test": "npm test -- --run"
    }
  }
}
```

Yoksa orchestrator `package.json` / `composer.json` / `Makefile` / `pyproject.toml` içinden komutu kendisi bulmaya çalışır.

## Yapı

```
agents/
  local-coder.md      BASİT  → ollama/qwen-coder-local
  ds-worker.md        ORTA   → deepseek/deepseek-flash
  ds-architect.md     ZOR    → deepseek/deepseek-flash, thinking: high
skills/
  task-routing/       sınıflandırma rubriği + döngü protokolü
prompts/
  orchestrate.md      /orchestrate
  route.md            /route
config/
  models.json         ollama provider + deepseek-flash tanımı
install.sh
```

Review katmanı için ayrı agent dosyası yok; `pi-subagents`'ın gömülü `claude-code` (salt-okunur) ve `claude-code-writer` (Read/Write/Edit/Glob/Grep) adapter'ları doğrudan kullanılıyor.

## Bilinen sınırlar

- `claude-code-writer`'ın **`bash`'i yok** — test koşturamaz. Doğrulamayı her zaman orchestrator yapar. Bu bilinçli bir tasarım: tek bir yerden gerçek çıktı görülür.
- Claude Pro plan limitleri review katmanı tarafından tüketilir. Önemsiz BASİT değişikliklerde review atlanır.
- Lokal modelin `bash`'i yok. Küçük model + kabuk erişimi istenmeyen bir kombinasyon.
- Düzeltme döngüsü **2 turla** sınırlı. Sonrasında sistem durur ve durumu raporlar — sonsuz döngüde para yakmaz.

## Lisans

MIT
