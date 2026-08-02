# Sürüm Geçmişi

<!--
  Bu dosya MERGEN Bilge sürüm geçmişini tanımlar.
  Her sürüm aşağıdaki YAML benzeri yapıda tanımlanır.
  R tarafında config_version_history.R bu dosyayı okur ve ayrıştırır.

  FORMAT:
  ## v{SÜRÜM} | {TARİH} | {BAŞLIK}
  badge: {rozet metni veya boş}

  ### Öne Çıkanlar
  - Madde 1
  - Madde 2

  ### {Kategori Adı} | {ikon_adı}
  - Madde 1
  - Madde 2

  ---
  (sürümleri ayırmak için)
-->

## v1.2 | 2026-07-22 | Kullanım İyileştirmeleri ve Düzeltmeler
badge: Yeni

### Öne Çıkanlar
- Sesli Giriş daha akıcı: butonlar her zaman anında yanıt verir ve konuşma metni silinmeden birikir
- Uzun kod blokları ve yanıtlar artık kesilmiyor
- Yazı tipi boyutu yalnızca "Ayarları Kaydet" ile uygulanır

### Yeni Özellikler | sparkles
- Sesli Giriş çevirisi arka planda çalışır; "İptal", "Onayla ve Gönder", "Temizle" ve "Durdur/Devam Et" butonları hiç donmadan anında yanıt verir
- Sesli Giriş metni artık ekleyerek büyür: konuşup durup tekrar konuşulduğunda önceki metin korunur
- Kısa/alçak sesli ifadeler (örn. "merhaba") daha iyi yakalanır

### İyileştirmeler | arrow-up-right-dots
- Yapılandırma sayfasındaki her ayar artık üzerine gelindiğinde açıklama balonu gösterir; sayfayı doldurup yer kaplayan açıklama satırları kaldırıldı
- Açık temada açılır menülerin yanında beliren küçük, boş giriş kutusu görüntüsü giderildi
- Açık temada karşılama ekranındaki selamlama, "Hızlı Başlangıç" ve "Son Konuşmalar" başlıkları okunaklı hale getirildi
- Uzun kod blokları sohbet içinde belirli bir satırdan sonra kesilmeden tamamen görüntülenir
- Yeni Söyleşi başlatıldığında model otomatik olarak varsayılana döner (Görsel Uzmanı sonrası "dall-e-3" takılı kalmaz)
- Sohbet yanıtı için bekleme süresi (timeout) belirgin şekilde artırıldı
- Söyleşi Geçmişi tarih aralığı gün/ay/yıl biçiminde gösterilir; koyu temada takvim ikonu artık görünür
- Yönetici Paneli araç ipuçları titremeden, kararlı biçimde gösterilir
- Yapılandırma sayfasındaki "Claude Code Yapılandırma" kartı "Bilge Yolaç Yapılandırma" olarak adlandırıldı
- Uygulama genelinde "versiyon" yerine tutarlı biçimde "sürüm" kullanılır

### Teknik | code
- Ortak Oturum tablolarındaki (MB_OrtakOturum_*, MB_Kullanici_CanliDurum) zaman damgaları Türkiye saatinde (Europe/Istanbul) saklanır; tazelik/yaş hesabı korunur
- Varsayılan çıktı token limiti yükseltildi (uzun kod bloklarının kesilmesini önler); MERGEN_MAX_OUTPUT_TOKENS ile ayarlanabilir
- Mesaj kaydetmedeki 20.000 karakterlik uygulama sınırı kaldırıldı; kolon NVARCHAR(MAX) olduğu için uzun kod içeren yanıtlar artık kaydedilebiliyor (MERGEN_MAX_MESSAGE_CHARS)
- Kod görüntüleyici (CodeMirror) tüm belgeyi render eder; otomatik yükseklikte oluşan görsel kırpma giderildi

---

## v1.1 | 2026-05-21 | Modern Asistan Persona Sistemi

### Öne Çıkanlar
- Karakter sistemi modern kurumsal AI persona'larıyla yenilendi: Emre, Selin, Deniz, Can ve İpek
- Her persona farklı bir çalışma tarzını temsil eder
- Eski kayıtlı karakter tercihleri otomatik olarak yeni persona'lara taşınır

### Yeni Özellikler | sparkles
- Emre Onat — Ana Asistan: dengeli ve pratik yardımcı
- Selin Sezgin — Yapıcı Uzman: sorunu çerçeveler, çözüm önerir
- Deniz Özgün — Stratejist: büyük resim, yol haritası, karar matrisi
- Can Yalın — Eleştirel Eş: varsayım ve risk doğrulayıcı
- İpek Duru — Rehber: sade dil, adım adım öğretici

### İyileştirmeler | arrow-up-right-dots
- Persona kimliği artık tek kaynak `R/config_characters.R` üzerinden yönetiliyor
- Varsayılan persona Emre Onat olarak güncellendi

### Teknik | code
- `normalize_character_id()` ile eski karakter kimlikleri güvenle yeni persona'lara çevrilir

---

## v1.0 | 2026-03-07 | MERGEN Bilge Resmi Lansman

### Öne Çıkanlar
- Bütünleşik mod ile tam özellikli deneyim
- 5 AI persona ve sinematik seçim ekranı
- Proje ve Kaynak Analizi aracı ile akıllı veri sorgulama
- Görsel oluşturma ve galeri yönetimi
- Destek merkezi, geri bildirim ve hata bildirimi
- Sürüm bilgilendirme sistemi

### Yeni Özellikler | sparkles
- Sinematik giriş ekranı ile 3 farklı deneyim modu (Odak, Dinamik, Bütünleşik)
- Bütünleşik modda karakter seçim adımı eklendi
- Sürüm bilgilendirme sistemi: giriş ekranında bildirim ikonu ve özel sayfa
- Karakter bazlı neural network animasyonu (daha canlı renkler)
- Proje sorgulamaları için önceden toplulaştırılmış sütun desteği

### İyileştirmeler | arrow-up-right-dots
- Kayıtlı söyleşi yüklendiğinde araç aktivasyonu düzeltildi
- NPS puanlama daireleri daha kompakt ve doğru konumlandırıldı
- Neural network animasyon renkleri daha belirgin hale getirildi
- Sorgu sonuçlarında önceden hesaplanmış sütunlar istatistik özetinden çıkarıldı

### Teknik | code
- Modüler dosya yapısı ile ayrılmış CSS, JS ve R betikleri
- Karakter verileri istemciye dinamik olarak aktarılıyor
- Yarış koşullarına karşı önlemler alınmıştır

---

## v0.9 | 2026-03-04 | Beta Sürümü

### Öne Çıkanlar
- Temel sohbet altyapısı ve LLM entegrasyonu
- Dosya yükleme ve analiz özellikleri
- Karakter sistemi ve kişiselleştirme sayfası
- Destek sayfaları (Yardım Merkezi, Geri Bildirim, Hakkında)

### Temel Özellikler | layer-group
- Gerçek zamanlı akış (streaming) ile LLM yanıt sistemi
- MCP araç entegrasyonu ve tekrarlı araç çağırma desteği
- Dosya yükleme, önizleme ve sohbete ekleme
- Söyleşi kaydetme, yükleme ve arama
- 5 AI karakter profili ve video tanıtım sistemi
- TTS ve STT entegrasyonu
- Görsel oluşturma (DALL-E entegrasyonu)
- Sinematik giriş ekranı ve deneyim modu seçimi
- Destek: Yardım Merkezi, Geri Bildirim, Hata Bildirimi, Hakkında