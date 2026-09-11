# pi-orchestra

Maliyet-optimize, çok katmanlı kodlama sistemi. **Claude Code** orchestrator olarak çalışır, rutin kodu ucuz modellere delege eder, sonucu kendisi doğrulayıp entegre eder.

Fikir basit: **yargı pahalı, kod yazımı ucuz.** Opus'un asıl değeri planlamak, sınıflandırmak, doğrulamak ve entegre etmek. Mekanik kod yazımı bu kotayı hak etmiyor — o iş lokal modele veya DeepSeek'e ait.

```
                  ORCHESTRATOR
              Claude Code / Opus 5
              (abonelik, $0 marjinal)
                       │
                görev zorluğunu belirle
                       │
      ┌────────────────┼─────────────────┐
      ▼                ▼                 ▼
    BASİT             ORTA               ZOR
      │                │                 │
      ▼                ▼                 ▼
 orchestra basit  orchestra orta   orchestra zor
 Qwen2.5-Coder    DeepSeek         DeepSeek V4.1
 7B (lokal, $0)   V4.1 Flash       Flash, thinking:high
      │                │                 │
 typo / küçük     feature /         mimari /
 bug / test       refactor          karmaşık bug
      │                │                 │
      └────────────────┼─────────────────┘
                       ▼
                 INTEGRATION
              Claude Code / Opus 5
                       │
           git diff → typecheck → lint → test
                       │
                  ┌────┴────┐
                  ▼         ▼
                PASS       FAIL
                  │         │
                 DONE   düzelt / yeniden delege
                            (en fazla 2 tur)
```

## Neden bu kombinasyon

| Katman | Nerede çalışır | Maliyet |
|---|---|---|
| Orchestrator + planner | Claude Code, Opus 5 | **$0 marjinal** (abonelik) |
| BASİT | Ollama, Qwen2.5-Coder 7B | **$0** |
| ORTA / ZOR | DeepSeek V4.1 Flash (`deepseek-flash`) | ~$0.15 / $0.60 per M |
| Integration + review + fix | Claude Code, Opus 5 | **$0 marjinal** (abonelik) |

Tek gerçek para harcaması DeepSeek. Tipik bir feature (≈200K in / 20K out) **~$0.04**.

### Neden pi'ye Anthropic ile giriş yapmıyoruz

pi'nin `/login` ile Claude Pro/Max girişi, kullanımı plan limitlerinden değil **"extra usage"dan** düşer ve token başına faturalanır. Bu yüzden Opus katmanı pi'nin içinde değil, **Claude Code'un kendisinde** duruyor. pi yalnızca ucuz modelleri koşturan bir yürütücü.

### Gerçek kısıt: kota

Opus katmanının para maliyeti yok ama **plan kotası** tüketiyor. Skill bunu bilerek yazıldı: rutin kod yazımı delege edilir, yargı ve entegrasyon Opus'ta kalır. `claude` içinde `/usage` ile kotanı izle.

## Kurulum

```bash
git clone https://github.com/endigitals/pi-orchestra ~/pi-orchestra
cd ~/pi-orchestra && ./install.sh
```

Sonra DeepSeek anahtarını bağla:

```bash
pi          # → /login → DeepSeek → anahtarı yapıştır
```

`install.sh` idempotenttir ve mevcut ayarlarını ezmez:

- `pi` + `pi-lens` kurar (npm'in `minimumReleaseAge` kapısını aşarak)
- Ollama'yı kurar, `qwen2.5-coder:7b` indirir, 32K context'li `qwen-coder-local` alias'ını oluşturur
- `~/.pi/agent/models.json`'a `ollama` provider'ını ve `deepseek-flash` modelini ekler
- `bin/orchestra`'yı `~/.local/bin/` altına, skill'i `~/.claude/skills/orchestra`'ya linkler

### Gereksinimler

- **Claude Code** — kurulu ve login olmuş (orchestrator bu)
- Node **≥ 22.19** (pi şartı)
- `jq`, Homebrew
- ~5 GB disk, ≥16 GB RAM (lokal model için)

## Kullanım

Herhangi bir proje klasöründe `claude` çalıştır ve normal konuş:

```
auth middleware'e rate limiting ekle
```

`orchestra` skill'i devreye girer, Claude seviyeyi belirler, delege eder, doğrular, entegre eder ve ne yaptığını raporlar.

Seviyeyi kendin de dayatabilirsin: *"bunu lokalde yap"*, *"bu zor bir iş"*.

### CLI'ı elle kullanmak

```bash
orchestra basit "src/utils/date.ts içindeki formatDate'de tipo var, düzelt"
orchestra orta  "POST /api/invoices endpoint'i ekle, app/Http/Controllers/OrderController.php desenine uy"
orchestra zor   "Sipariş listesi N+1 sorgu üretiyor, kök nedeni bul ve çöz"

orchestra basit --dry-run "..."     # hangi model seçilecek, çalıştırmadan gör
orchestra orta --cwd ~/proje "..."  # başka dizinde çalıştır
```

## Sınıflandırma rubriği

Tam kurallar `claude-skill/SKILL.md` içinde. Özet:

**BASİT** — hepsi doğruysa: tek dosya, ~20 satır altı, doğru çözüm tartışmasız belli, mimari/API/şema/auth/ödeme etkilenmiyor, yeni bağımlılık yok.

**ORTA** — 2–10 dosya, sınırları belli feature veya refactor, mevcut desenlerin içinde.

**ZOR** — herhangi biri doğruysa: mimari karar, kök nedeni belirsiz bug, performans/concurrency/güvenlik, geri alması pahalı (migration, auth, ödeme, public API), 10+ dosya.

Kural: **tereddütte bir üst seviyeye çık.**

Orchestrator'da kalması gerekenler — bunlar delege edilmez: mimari kararın kendisi, gereksinim netleştirme, doğrulama, review, entegrasyon, brief yazımı.

## Proje bazlı bağlam

Projenin köküne `AGENTS.md` koy; hem Claude Code hem pi okur. Şablon: `examples/AGENTS.example.md`. Doğrulama komutlarını, örnek alınacak desen dosyalarını ve "buraya dokunulursa ZOR seviyedir" alanlarını yazmak sınıflandırma kalitesini belirgin artırır.

## Yapı

```
claude-skill/SKILL.md   Claude Code orchestrator skill'i (rubrik + protokol)
bin/orchestra           delegasyon CLI'ı — seviye → model + sistem promptu
agents/
  local-coder.md        BASİT  → ollama/qwen-coder-local, bash YOK, ESCALATE protokolü
  ds-worker.md          ORTA   → deepseek/deepseek-flash, thinking off
  ds-architect.md       ZOR    → deepseek/deepseek-flash, thinking high
config/models.json      ollama provider + deepseek-flash tanımı
examples/               AGENTS.md ve proje ayarı şablonları
install.sh
```

## Tasarım kararları

**Lokal modelin `bash`'i yok.** 7B model + kabuk erişimi istenmeyen bir kombinasyon. `local-coder` kapsamı aşan iş geldiğinde kod yazmak yerine `ESCALATE: <neden>` döndürür; orchestrator bunu görünce seviyeyi yükseltir.

**Doğrulamayı her zaman orchestrator yapar.** "Testler geçti" raporuna güvenmek bu mimarideki en kolay kırılma noktası. Komutu Opus çalıştırır ve çıktıyı kendisi görür.

**Düzeltme döngüsü 2 turla sınırlı.** Sonrasında sistem durur ve durumu raporlar — sonsuz döngüde kota ve para yakmaz.

**Küçük düzeltmeler delege edilmez.** Birkaç satırlık tip/import/lint düzeltmesi için yeniden delegasyonun gecikmesi tasarrufa değmez; orchestrator kendisi yapar.

## Sık karşılaşılan sorun

```
Failed to load extension ... Cannot find module '.../pi-ai/dist/index.js/compat'
```

npm'de `minimumReleaseAge` ayarlıysa `npm install -g @earendil-works/pi-coding-agent` pi'yi eski bir sürüme düşürür. Çözüm:

```bash
npm install -g --min-release-age=0 @earendil-works/pi-coding-agent pi-lens
```

`install.sh` bunu zaten yapar ve uyumsuzlukta açık hatayla durur.

nvm kullanıyorsan: `pi` hangi node sürümü aktifse onun global paketlerini arar. Sürüm değiştirdikten sonra paketleri yeniden kur.

## Lisans

MIT
