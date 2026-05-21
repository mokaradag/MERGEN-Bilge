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

## v1.1 | 2026-05-21 | Modern Asistan Persona Sistemi
badge: Yeni

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