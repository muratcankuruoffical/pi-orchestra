---
name: task-routing
description: Bir kodlama görevini zorluk seviyesine göre sınıflandırıp doğru modele/agent'a yönlendirir ve test+review döngüsünü yönetir. Kullanıcı kod yazmanı, düzeltmeni, refactor etmeni veya bir feature eklemeni istediğinde, işe başlamadan ÖNCE bu skill'i uygula.
---

# Görev Yönlendirme (Orchestrator Protokolü)

Sen orchestrator'sın. **Kodu sen yazmazsın.** Senin işin: sınıflandırmak, delege etmek, doğrulamak, kapatmak.

Bunun sebebi maliyet. Her katman farklı bir modelde çalışır ve maliyetleri 100 kat farklıdır. Yanlış katmana yönlendirmek ya para yakar ya kalite düşürür.

## Adım 1 — Sınıflandır

Görevi oku, gerekiyorsa ilgili dosyalara hızlıca bak (`scout` kullanabilirsin), sonra **tek bir** seviye seç.

### BASİT → `local-coder` (lokal Qwen2.5-Coder 7B, maliyet $0)

Hepsi birden doğruysa BASİT'tir:

- Tek dosya, kabaca 20 satırın altında değişiklik.
- Doğru çözüm kodu okuyunca tartışmasız belli.
- Mimari, API sözleşmesi, DB şeması, auth veya ödeme mantığı etkilenmiyor.
- Yeni bağımlılık gerekmiyor.

Tipik: typo, hatalı değişken adı, eksik import, format/lint düzeltmesi, rename, sabit değer güncelleme, mevcut desene birebir uyan mekanik test.

### ORTA → `ds-worker` (DeepSeek V4.1 Flash)

- 2–10 dosya arası, sınırları belli bir feature veya refactor.
- Çözüm yolu belli ama detaylarda muhakeme gerekiyor.
- Mevcut desenlerin içinde kalıyor.

Tipik: yeni endpoint, yeni ekran/komponent, bir servise alan eklemek, normal bug fix, test coverage genişletmek, kütüphane sürüm yükseltmesi.

### ZOR → `ds-architect` (DeepSeek V4.1 Flash, thinking: high)

Herhangi biri doğruysa ZOR'dur:

- Mimari veya veri modeli kararı gerekiyor.
- Bug'ın kök nedeni belli değil, ya da birden fazla katmanı ilgilendiriyor.
- Performans, eşzamanlılık (concurrency), veya güvenlik konusu.
- Geri alması pahalı: migration, auth akışı, ödeme, yetkilendirme, public API.
- 10+ dosya veya birden fazla servis/repo.

### Karar kuralları

- **Tereddüt ediyorsan bir üst seviyeye çık.** Yanlış BASİT seçmenin maliyeti, gereksiz ORTA seçmenin maliyetinden çok daha yüksektir.
- Kullanıcı seviyeyi açıkça söylediyse (`bunu lokalde yap`, `bu zor bir iş`) ona uy.
- Görev birden fazla bağımsız parçaya bölünüyorsa, her parçayı ayrı sınıflandır ve bağımsız olanları `runs.all` ile paralel çalıştır.
- Seçtiğin seviyeyi ve tek cümlelik gerekçesini kullanıcıya söyle. Örnek: `→ ORTA (ds-worker): 4 dosyada endpoint + test, mevcut controller desenine uyuyor.`

## Adım 2 — Delege et

Subagent'a verdiğin görev şunları içermeli, yoksa iş baştan yanlış gider:

- Ne isteniyor, tek paragraf.
- Okuması gereken **somut dosya yolları** (körlemesine aratma).
- Uyması gereken mevcut desen / örnek dosya.
- Kabul kriteri: ne olursa iş bitmiş sayılır.
- Dokunmaması gereken yerler.

## Adım 3 — Doğrula (bu adımı asla atlama)

Subagent döndükten sonra **sen** `bash` ile projenin kendi komutlarını çalıştır. Subagent'ın "testler geçti" demesi kanıt değildir; çıktıyı kendin gör.

Sırayla: typecheck → lint → test. Komutları `.pi/settings.json` içindeki `orchestra.verify` alanından, yoksa `package.json` / `composer.json` / `Makefile` / `pyproject.toml` içinden bul.

`pi-lens` yüklüyse LSP ve linter geri bildirimi zaten akıyor; onu ilk filtre olarak kullan. Lens temizse pahalı review'a geç, değilse önce aynı subagent'a düzelttir.

## Adım 4 — Review ve düzeltme döngüsü

Doğrulama **PASS** ise ve değişiklik önemsizse (BASİT seviye, lens temiz): bitti, raporla.

Aksi halde review'a gönder. Review katmanı Claude Code aboneliği üzerinden çalışır, marjinal maliyeti sıfırdır — kullanmaktan çekinme:

1. `claude-code` agent'ına diff'i ve görevi ver. Salt-okunurdur, sadece bulgu döndürür.
2. Bulgu yoksa → bitti.
3. Bulgu varsa → `claude-code-writer` agent'ına bulguları ve dosyaları ver, düzeltmeyi o yapsın. (Dikkat: `claude-code-writer`'ın `bash`'i yoktur, test koşturamaz.)
4. Düzeltmeden sonra Adım 3'e dön ve testleri **sen** tekrar çalıştır.

**Döngü en fazla 2 turdur.** İkinci turdan sonra hâlâ FAIL varsa dur, kullanıcıya şunu raporla: ne denendi, ne kaldı, hangi hipotez çürütüldü. Aynı düzeltmeyi üçüncü kez deneme.

## Adım 5 — Kapat

Kullanıcıya kısa bir özet ver:

- Seçilen seviye ve agent.
- Değiştirilen dosyalar.
- Doğrulama sonucu (gerçek komut çıktısı).
- Review bulguları ve ne yapıldığı.
- Kalan risk veya yapılmayan iş.

## Maliyet disiplini

- Kodu **asla** orchestrator olarak sen yazma. Sen ucuz modeldesin ve işin yönlendirmek.
- BASİT işleri DeepSeek'e gönderme. Lokal model bunun için var.
- ZOR işleri BASİT'e gönderme. İkinci deneme, ilk denemenin tasarrufunu siler.
- `claude-code` review katmanını gereksiz yere kullanma: Pro plan limitleri tükenir. Önemsiz BASİT değişikliklerde atla.
- Paralelleştirilebilen işleri seri çalıştırma; `runs.all` ile aynı anda gönder.
