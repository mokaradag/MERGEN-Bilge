# Önceden Üretilmiş Konuşma Varlıkları

Bu dizin, MERGEN Bilge karşılama konuşması ve sayfa rehberliği için kullanılan
ortak konuşma metinlerini ve persona bazlı WAV kayıt konumlarını içerir.

## İçerik modeli

- Karşılama konuşması için **10 ortak metin çeşidi** bulunur.
- Desteklenen her sayfa için **10 ortak metin çeşidi** bulunur.
- Aynı konuşma metni `emre`, `selin`, `deniz`, `can` ve `ipek` sesleriyle
  ayrı ayrı kaydedilir.
- Altyazı metni her zaman ortak `.txt` dosyasından okunur. Ses dosyası,
  metin dosyasıyla aynı temel dosya adını kullanmalıdır.

Örnek:

```text
scripts/pages/files/files_03.txt
audio/emre/pages/files/files_03.wav
audio/selin/pages/files/files_03.wav
audio/deniz/pages/files/files_03.wav
audio/can/pages/files/files_03.wav
audio/ipek/pages/files/files_03.wav
```

## Rehberlik bulunan sayfalar

- `history` — Söyleşi Geçmişi
- `saved_chats` — Kayıtlı Söyleşiler
- `ortak_sohbetler` — Ortak Söyleşiler
- `image_gallery` — Görsel Galerisi
- `claude_code` — Çalışma Alanı
- `claude_code_sessions` — Oturumlar
- `ortak_bilge_yolac` — Ortak Bilge Yolaç Oturumları
- `ortak_calismalar` — Ortak Çalışmalarım
- `files` — Dosya Yönetimi
- `settings_yapilandirma` — Yapılandırma
- `destek_yardim` — Yardım Merkezi
- `destek_geri_bildirim` — Geri Bildirim & Hata
- `destek_surum` — Yenilikler
- `destek_hakkinda` — Hakkında

## Sessiz kalması gereken sayfalar

Aşağıdaki sayfalar için sayfa rehberliği varlığı eklenmemelidir:

- `chat` — Ana Söyleşi; açılıştaki karşılama konuşması bu sayfayı zaten kapsar.
- `settings_kisisel` — Kişiselleştirme; persona tanıtım videoları burada oynatılır.
- `admin_analytics` — Genel Analiz.
- `admin_geri_bildirim` — Geri Bildirim Analizi.
- `admin_hata_analizi` — Hata Analizi.
- `admin_yanit_analizi` — Yanıt Geri Bildirimi.
- `admin_dokumantasyon` — Dokümantasyon.
- `health` — Sistem Durumu.

## Kayıt iş akışı

1. Ortak bir `.txt` konuşma metni seçin.
2. Metni değiştirmeden her persona sesiyle ayrı ayrı kaydedin.
3. Her kaydı, konuşma metniyle aynı temel dosya adını kullanarak PCM WAV biçiminde kaydedin.
4. Altyazı metnini persona klasörlerine kopyalamayın veya yeniden yazmayın.
5. WAV dosyaları eklendikten sonra oynatma bütünleştirmesi,
   `generated/speech_manifest.json` dosyasını otomatik olarak üretmelidir.
   Süre ve sağlama toplamı bilgileri WAV dosyalarından türetilmeli, hiçbir zaman
   elle girilmemelidir.

Yalnızca varlık yapısını hazırlayan bu iskelet, bildirim dosyası üreticisini veya
çalışma zamanı oynatma bağlantılarını henüz içermez.

Önerilen WAV profili: mono, 16 bit PCM, tutarlı ses düzeyi, en az başlangıç
sessizliği ve kısa, doğal bir bitiş sessizliği.