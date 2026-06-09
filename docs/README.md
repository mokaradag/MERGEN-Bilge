# MERGEN Bilge Dokümantasyon Merkezi

Bu sayfa, MERGEN Bilge dokümantasyonunda doğru belgeye hızlı gitmek için hazırlanmış merkezdir. Ürün özeti için kök [`README.md`](../README.md) okunur; bakımcı/kodlama ajanı kuralları için İngilizce [`CLAUDE.md`](../CLAUDE.md) otoritatiftir.

## Nereden başlamalıyım?

| Ben kimim / ne yapıyorum? | İlk okuyacağım belge | Sonra okuyacağım belge |
|---|---|---|
| İlk kez MERGEN Bilge'yi tanıyorum | [`../README.md`](../README.md) | [`release-notes.md`](release-notes.md), [`../ai_rehber.md`](../ai_rehber.md) |
| İlk kez geliştirme yapacağım | [`architecture-map.md`](architecture-map.md) | [`database-schema.md`](database-schema.md), [`../CLAUDE.md`](../CLAUDE.md), [`technical-reference.md`](technical-reference.md) |
| Kodlama ajanıyım | [`../CLAUDE.md`](../CLAUDE.md) | [`../AGENTS.md`](../AGENTS.md), [`architecture-map.md`](architecture-map.md) |
| Üretim operatörüyüm | [`../RUNBOOK.md`](../RUNBOOK.md) | [`dependency-locking.md`](dependency-locking.md), [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) |
| Windows VM sorunu debug ediyorum | [`../RUNBOOK.md`](../RUNBOOK.md) | [`architecture-map.md`](architecture-map.md), [`../CLAUDE.md`](../CLAUDE.md) |
| Bağımlılık kilitlemeyi anlamak istiyorum | [`dependency-locking.md`](dependency-locking.md) | [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) |
| Asistan davranışını anlamak istiyorum | [`../ai_rehber.md`](../ai_rehber.md) | [`release-notes.md`](release-notes.md) |
| Release geçmişini inceliyorum | [`release-notes.md`](release-notes.md) | [`technical-reference.md`](technical-reference.md) |

## Önemli Belgeler

| Belge | Açıklama |
|---|---|
| [`../README.md`](../README.md) | Kısa, Türkçe, ilk giriş belgesi: ürün, hızlı başlangıç, doğrulama ve belge haritası. |
| [`../CLAUDE.md`](../CLAUDE.md) | İngilizce ve bilinçli olarak korunmuş kodlama ajanı/bakımcı sözleşmesi. Detaylı kurallar burada otoritatiftir. |
| [`../AGENTS.md`](../AGENTS.md) | Ajanlar için kısa repo notu, doğrulama dürüstlüğü ve belge yönlendirmeleri. |
| [`../ai_rehber.md`](../ai_rehber.md) | Yardım Asistanı ve AI Uzman için kullanıcıya dönük davranış rehberi. |
| [`architecture-map.md`](architecture-map.md) | Uygulama katmanları, gerçek dosya/dizin haritası ve korunan mimari sınırlar. |
| [`database-schema.md`](database-schema.md) | Uygulama kaynaklarına göre DB tablo yapısı, ilişkiler ve tablo akış diyagramı. |
| [`../RUNBOOK.md`](../RUNBOOK.md) | Kanonik Windows VM/on-prem operasyon kılavuzu. |
| [`dependency-locking.md`](dependency-locking.md) | `renv`, `renv.lock`, Windows VM kilit üretimi ve CI/AI bootstrap davranışı. |
| [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) | `renv.lock` dosyasının on-prem üretim deposu ile GitHub/Codex görünürlüğü arasındaki fark. |
| [`release-notes.md`](release-notes.md) | Uzun değişiklik notları ve güncel bakım özeti. |
| [`technical-reference.md`](technical-reference.md) | Ayrıntılı teknik referans. |
| [`refactor-log.md`](refactor-log.md) | Davranışı değiştirmeden karmaşıklık/onboarding yükünü azaltan yapısal iyileştirmelerin günlüğü. |

## Kısa Uyarılar

- `CLAUDE.md` İngilizcedir ve bu durum bilinçlidir; kodlama ajanı/bakımcı davranışında otoritatif kaynak odur.
- Windows VM, SSO, DB encoding, dosya lifecycle ve `renv.lock` davranışları README'den değil runbook ve sözleşme belgelerinden yönetilir.
- Türkçe karakter bütünlüğü korunmalıdır; UTF-8 bozulmamalı, mojibake üretilmemelidir.
- Secrets, API key, token, parola, gerçek DSN ve private endpoint bilgileri dokümantasyona eklenmez.
