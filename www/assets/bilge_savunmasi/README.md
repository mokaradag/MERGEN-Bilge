# Bilge Savunması yerel varlıkları

Bu klasör oyunun İSTEĞE BAĞLI türetilmiş/yerel varlıklarını tutar; CDN veya
dış indirme KULLANILMAZ. Depoya konmayan her varlık için oyun zarif bir
prosedürel yedeğe düşer ve tam işlevli çalışmaya devam eder (kırık görsel
veya sessizce donma OLMAZ).

## Klasörler

- `heroes/` — isteğe bağlı optimize kahraman görselleri (`<persona_id>.png`).
  Oyun önce kanonik `characters/resim|avatar/<id>/` yollarını kullanır;
  görsel yüklenemezse aksan renkli baş harf diskine düşer. Orijinal persona
  dosyalarının ÜZERİNE YAZILMAZ.

- `gorseller/` — 2.5D sahne görselleri (SVG). Repoda örnek/prosedürel yedekle
  uyumlu SVG'ler bulunur; operatör daha zengin sanat eklemek isterse aynı
  adlarla değiştirebilir.
  - `gorseller/kuleler/<tip>_<kademe>.svg` — kule silüetleri. Tipler:
    `gozetleme`, `veri_topu`, `kripto_isik`; kademe 1..3
    (ör. `gozetleme_1.svg`, `veri_topu_2.svg`, `kripto_isik_3.svg`).
    Gövde hücre tabanından yukarı uzanır (128×192 önerilir). Dosya yoksa
    tipe özgü prosedürel silüet çizilir.
  - `gorseller/dekor/<ad>.svg` — sahne süsleri (`kristal`, `anten`, `sunucu`,
    `kaya`, `veri_agaci`, `bayrak`). İnşa edilemez hücrelerde dekoratif
    olarak yerleşir; hücreyi işgal etmez.
  - `gorseller/dusmanlar/<id>.svg` — isteğe bağlı düşman gövde sprite'ları
    (denge kimliğiyle, ör. `celiski.svg`). Eklenirse prosedürel gövde yerine
    kullanılır; eklenmezse mevcut prosedürel çizim devam eder.

- `muzik/` — oyun müzik grupları. Her klasöre BİRDEN ÇOK parça konabilir;
  istemci gruptan rastgele parça seçer ve parça bitince aynı gruptan yenisine
  geçer (ardışık tekrar azaltılır). Desteklenen uzantılar: `.mp3`, `.ogg`,
  `.m4a`. Otomatik yüksek sesli çalma YOKTUR; müzik ilk kullanıcı
  etkileşiminden sonra başlar ve MERGEN Bilge uygulama müziği oyun sayfasında
  tamamen susturulur.
  - `muzik/menu/` — ana menü teması.
  - `muzik/bolum_1/` — 1-3. haritalar (Bağlam Kapısı, Çelişki Kavşağı,
    Bilgi Çekirdeği).
  - `muzik/bolum_2/` — 4-6. haritalar (Veri Labirenti, Sinyal Vadisi,
    Karar Zirvesi).

- `ses/` — isteğe bağlı yerel efekt sesleri (`efekt_vurus.mp3`,
  `efekt_dalga.mp3`, `efekt_yetenek.mp3`, `efekt_yerlestir.mp3`,
  `efekt_yukselt.mp3`, `efekt_patron.mp3`, `efekt_sizinti.mp3`,
  `efekt_zafer.mp3`, `efekt_yenilgi.mp3`). Eski tekil `muzik_dongu.mp3` yalnızca
  `muzik/` grupları boşken geriye uyumluluk için kullanılır. Dosya yoksa oyun
  sessiz ve tam işlevli çalışır.

## Lisans notu

Bu klasöre yalnızca kullanım hakkına sahip olduğunuz varlıklar konmalıdır
(CC0/kamu malı müzik veya kurumun lisansladığı içerik). Repodaki SVG
görselleri MERGEN Bilge için özgün olarak üretilmiştir.
