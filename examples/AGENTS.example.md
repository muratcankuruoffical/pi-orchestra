# Proje bağlamı

Bu dosya `pi` tarafından otomatik yüklenir ve her subagent'a aktarılır.
Orchestrator'ın doğru sınıflandırma yapabilmesi için burayı doldur.

## Stack

<!-- örn: Laravel 11 + Inertia + React 18 + TypeScript, MySQL 8, Redis -->

## Doğrulama komutları

<!-- orchestrator bunları çalıştıracak -->
- typecheck: `npm run typecheck`
- lint: `npm run lint`
- test: `npm test`

## Desenler

<!-- Yeni kod yazılırken örnek alınacak dosyalar -->
- Controller örneği: `app/Http/Controllers/...`
- Servis örneği: `app/Services/...`
- Test örneği: `tests/Feature/...`

## Dokunulmaz alanlar

<!-- ZOR seviyeye zorlanacak yerler -->
- `database/migrations/` — migration yazılacaksa her zaman ZOR seviye
- `app/Http/Middleware/Auth*` — auth akışı
- ödeme ile ilgili her şey

## Bilinen tuzaklar

<!-- Modelin bilemeyeceği, tekrar eden hatalar -->
