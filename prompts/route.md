---
description: Görevi sadece sınıflandırır ve hangi agent'a gideceğini söyler, implementasyon yapmaz
argument-hint: "<görev>"
---

Görev: $@

`task-routing` skill'indeki Adım 1 sınıflandırma rubriğini uygula. Gerekirse ilgili dosyalara bak.

Şunu döndür ve **dur** — hiçbir kod değişikliği yapma, hiçbir subagent başlatma:

- **Seviye:** BASİT / ORTA / ZOR
- **Agent:** local-coder / ds-worker / ds-architect
- **Gerekçe:** rubriğin hangi maddelerine dayandığın, 2-3 cümle.
- **Tahmini maliyet:** $0 (lokal) veya kaba token tahminiyle DeepSeek maliyeti.
- **Brief:** subagent'a verilecek görev metni (okunacak dosya yolları, kabul kriteri, dokunulmayacak yerler dahil).
- **Riskler:** yanlış sınıflandırma ihtimali varsa neden.
