---
description: Bir görevi zorluk seviyesine göre sınıflandırıp doğru modele delege eder, test eder, Claude Code ile review ettirir
argument-hint: "<görev>"
---

Görev: $@

`task-routing` skill'indeki orchestrator protokolünü uygula. Kodu sen yazma.

Akış deterministik olsun; aşağıdaki `subagent` workflow'unu tek bir top-level çağrı olarak, `async: true` ile çalıştır. `IMPLEMENTER` değerini sınıflandırma sonucuna göre `"local-coder"`, `"ds-worker"` veya `"ds-architect"` olarak, `TASK` değerini de Adım 2'deki brief formatına göre doldur:

```js
subagent({
  async: true,
  workflowScript: `
    const scan = await runs.run("scan", {
      label: "Kod keşfi",
      agent: "scout",
      task: "Şu görev için ilgili dosyaları, giriş noktalarını, mevcut desenleri ve riskleri çıkar: TASK"
    });

    const impl = await runs.run("impl", {
      label: "Implementasyon",
      agent: "IMPLEMENTER",
      task: "TASK\\n\\nKeşif çıktısı:\\n" + scan.output
    });

    const review = await runs.run("review", {
      label: "Claude Code review",
      agent: "claude-code",
      task: "Şu değişikliği gözden geçir. Sadece bulgu döndür, dosya düzenleme.\\n\\nGörev: TASK\\n\\nImplementasyon raporu:\\n" + impl.output
    });

    return { implementation: impl.output, review: review.output };
  `,
  timeoutMs: 1800000
});
```

Workflow döndükten sonra:

1. Testleri/lint'i/typecheck'i **sen** `bash` ile çalıştır ve gerçek çıktıyı göster. Subagent raporuna güvenme.
2. Review bulgusu veya test hatası varsa `claude-code-writer` agent'ına düzelttir (bulguları ve dosya yollarını ver; onun `bash`'i olmadığını unutma), sonra testleri tekrar sen çalıştır.
3. Bu döngü **en fazla 2 tur**. Hâlâ FAIL varsa dur ve ne denendiğini, neyin çürütüldüğünü raporla.
4. Adım 5 formatında kapanış özeti ver: seviye, agent, değişen dosyalar, doğrulama çıktısı, review bulguları, kalan risk.
