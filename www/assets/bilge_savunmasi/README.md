# Bilge Savunması yerel varlıkları

Bu klasör oyunun İSTEĞE BAĞLI türetilmiş/yerel varlıklarını tutar; CDN veya
dış indirme KULLANILMAZ.

- `heroes/` — isteğe bağlı optimize kahraman görselleri (`<persona_id>.png`).
  Oyun önce kanonik `characters/resim|avatar/<id>/` yollarını kullanır;
  görsel yüklenemezse aksan renkli baş harf diskine düşer. Orijinal persona
  dosyalarının ÜZERİNE YAZILMAZ.
- `ses/` — isteğe bağlı yerel ses dosyaları (`muzik_dongu.mp3`,
  `efekt_vurus.mp3`, `efekt_dalga.mp3`, `efekt_yetenek.mp3`,
  `efekt_yerlestir.mp3`, `efekt_yukselt.mp3`, `efekt_patron.mp3`,
  `efekt_sizinti.mp3`, `efekt_zafer.mp3`, `efekt_yenilgi.mp3`). Dosya yoksa
  oyun SESSİZ ve tam işlevli çalışır; otomatik yüksek sesli çalma yoktur.
