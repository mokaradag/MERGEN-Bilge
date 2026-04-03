# Bilge Yolaç çevrimdışı varlık kontrol listesi

Bu liste **air-gapped / internet erişimsiz** kurulum için hazırlanmıştır.  
Buradaki tüm varlıklar **çalışma anında yerel dosyadan** yüklenmelidir.

## Lisans kuralı

İzin verilen lisanslar:

- **CC0**
- **Public Domain**
- **CC-BY** *(atıf kaydı tutulmalı)*
- **ticari kullanıma izin veren ücretsiz piksel-art paketleri**

Kaçınılması gerekenler:

- oyundan sökülmüş telifli varlıklar
- fan rip / sprite rip içerikleri
- lisansı belirsiz paketler
- piksel-art görünümünü bozan yüksek çözünürlüklü/soft boyalı setler

## Teknik filtre

Manuel indirirken şu filtreleri uygulayın:

- **stil:** pixel art / retro / 16x16 / 32x32 / tileset / sprite sheet
- **arka planlar:** PNG, tercihen şeffaf katmanlı
- **sprite sheet:** PNG, sabit kare boyutlu
- **yükleme:** çalışma anında dış bağlantı kullanmayın
- **önerilen çözünürlük:** 16x16, 24x24, 32x32, 48x48
- **önerilen format:** PNG
- **animasyon sheet düzeni:** yatay strip veya eş kareli sheet

## Standart adlandırma kuralı

Aşağıdaki şablonu kullanın:

- dünya varlıkları: `<tema>_<tur>_<nn>.png`
- düşman stripleri: `<tip>_strip.png`
- dünya özel düşman stripleri: `<dunya>_<tip>_strip.png`
- boss stripleri: `<dunya>_boss_strip.png`
- mermi stripleri: `<tema>_<tip>_strip.png`
- VFX stripleri: `<etki>_strip.png`

Örnekler:

- `plateau_far_01.png`
- `temple_frontier_01.png`
- `mergen_boss_strip.png`
- `precision_arrow_strip.png`
- `glitch_bloom_strip.png`

---

## 1) Dünya arka planları

### Zorunlu
| Kategori | Ne indirilecek | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|---|
| Mergen uzak arka plan | plato / steppe silüeti | `CC0 pixel art plateau background 32x32` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/mergen/backgrounds/` | `plateau_far_01.png` |
| Mergen ikinci silüet | kaya sırtı / sınır hattı | `CC0 pixel art rocky ridge background` | CC0 / PD / CC-BY | PNG | aynı | `ridge_far_01.png` |
| Ülgen gök silüeti | ışıklı kuleler / semavi kale | `CC0 pixel art celestial tower skyline` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/ulgen/backgrounds/` | `celestial_spires_01.png` |
| Ülgen ikinci arka katman | yüksek düzen / fortress skyline | `CC0 pixel art fantasy fortress skyline` | CC0 / PD / CC-BY | PNG | aynı | `fortress_skyline_01.png` |
| Kayra orman tepesi | canopy / orman silüeti | `CC0 pixel art forest canopy background` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/kayra/backgrounds/` | `forest_canopy_01.png` |
| Kayra ikinci arka katman | runik tepeler | `CC0 pixel art mystic hills background` | CC0 / PD / CC-BY | PNG | aynı | `runic_hills_01.png` |
| Erlik arka plan | abyss / underworld spires | `CC0 pixel art underworld background` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/erlik/backgrounds/` | `abyss_spires_01.png` |
| Erlik ikinci arka katman | corrupted depth / dark ridge | `CC0 pixel art corrupted cave skyline` | CC0 / PD / CC-BY | PNG | aynı | `corrupted_depth_01.png` |
| Umay arka plan | halo / sanctuary ışık silüeti | `CC0 pixel art sanctuary background` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/umay/backgrounds/` | `sanctuary_halo_01.png` |
| Umay ikinci arka katman | healing garden silhouette | `CC0 pixel art healing garden background` | CC0 / PD / CC-BY | PNG | aynı | `healing_garden_01.png` |

### İsteğe bağlı
- Gece gökyüzü ek overlay
- Bulut / sis katmanı
- Dağ / bina / kule ekstra varyantları

---

## 2) Dünya orta katman / set parçaları

### Zorunlu
| Dünya | Ne indirilecek | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|---|
| Mergen | tapınak cephesi / ruins | `CC0 pixel art temple ruins png` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/mergen/midground/` | `temple_frontier_01.png` |
| Mergen | radar karakolu / dish tower | `CC0 pixel art radar tower` | CC0 / PD / CC-BY | PNG | aynı | `radar_outpost_01.png` |
| Ülgen | ışıklı kule | `CC0 pixel art luminous tower` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/ulgen/midground/` | `luminous_tower_01.png` |
| Ülgen | enerji kapısı / kalekapı | `CC0 pixel art fantasy energy gate` | CC0 / PD / CC-BY | PNG | aynı | `energy_fort_01.png` |
| Kayra | kutsal ağaç | `CC0 pixel art sacred tree` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/kayra/midground/` | `sacred_tree_01.png` |
| Kayra | runik harabe | `CC0 pixel art runic ruin` | CC0 / PD / CC-BY | PNG | aynı | `runic_ruin_01.png` |
| Erlik | glitch tapınağı / kırık karanlık yapı | `CC0 pixel art dark temple ruin` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/erlik/midground/` | `glitch_temple_01.png` |
| Erlik | yarık / portal | `CC0 pixel art portal sprite sheet` veya `CC0 pixel art dark portal` | CC0 / PD / CC-BY | PNG | aynı | `portal_rift_01.png` |
| Umay | şifa kapısı / kutsal kemer | `CC0 pixel art sanctuary gate` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/umay/midground/` | `sanctuary_gate_01.png` |
| Umay | yaşam havuzu / kutsal su | `CC0 pixel art magic pool` | CC0 / PD / CC-BY | PNG | aynı | `life_pool_01.png` |

### İsteğe bağlı
- Mergen için taş sütun / sınır gözetleme direği
- Ülgen için ikinci kule / hover platform
- Kayra için bilgi kemeri / eski tablet
- Erlik için kırık sütun / glitch sütunu
- Umay için ward tower / küçük mabet sütunu

---

## 3) Ön plan prop’ları

### Zorunlu
| Dünya | Ne indirilecek | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|---|
| Mergen | steppe otu / taş / direk | `CC0 pixel art grass tuft` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/mergen/foreground/` | `steppe_grass_01.png` |
| Mergen | sinyal direği | `CC0 pixel art utility pole` | CC0 / PD / CC-BY | PNG | aynı | `signal_pole_01.png` |
| Ülgen | ışık kristali | `CC0 pixel art crystal` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/ulgen/foreground/` | `light_crystal_01.png` |
| Ülgen | röle / küçük kule | `CC0 pixel art sci fi relay` | CC0 / PD / CC-BY | PNG | aynı | `hover_relay_01.png` |
| Kayra | eğrelti / bitki | `CC0 pixel art fern` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/kayra/foreground/` | `fern_01.png` |
| Kayra | runik taş | `CC0 pixel art standing stone` | CC0 / PD / CC-BY | PNG | aynı | `rune_stone_01.png` |
| Erlik | diken / karanlık flora | `CC0 pixel art dark thorn` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/erlik/foreground/` | `shadow_thorn_01.png` |
| Erlik | glitch kristali | `CC0 pixel art corrupted crystal` | CC0 / PD / CC-BY | PNG | aynı | `glitch_crystal_01.png` |
| Umay | ışıklı flora | `CC0 pixel art glowing flower` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/umay/foreground/` | `luminous_flora_01.png` |
| Umay | şifa çiçeği | `CC0 pixel art healing bloom` | CC0 / PD / CC-BY | PNG | aynı | `healing_bloom_01.png` |

---

## 4) Tiles / yapılar / dekoratif set

### Zorunlu değil ama güçlü öneri
Bunlar uzun vadede platform çizimini de zenginleştirir.

| Dünya | Arama terimi | Yerel klasör | Dosya adı önerisi |
|---|---|---|---|
| Mergen | `CC0 pixel art ruins tileset` | `www/assets/bilge_yolac/worlds/mergen/tiles/` | `ruin_tileset_01.png` |
| Ülgen | `CC0 pixel art sci fi temple tileset` | `www/assets/bilge_yolac/worlds/ulgen/tiles/` | `celestial_tileset_01.png` |
| Kayra | `CC0 pixel art forest temple tileset` | `www/assets/bilge_yolac/worlds/kayra/tiles/` | `forest_runic_tileset_01.png` |
| Erlik | `CC0 pixel art underworld tileset` | `www/assets/bilge_yolac/worlds/erlik/tiles/` | `corruption_tileset_01.png` |
| Umay | `CC0 pixel art shrine tileset` | `www/assets/bilge_yolac/worlds/umay/tiles/` | `sanctuary_tileset_01.png` |

---

## 5) Düşman sprite sheet’leri

### Zorunlu
| Tip | Ne indirilecek | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|---|
| Drone | uçan küçük mekanik düşman | `CC0 pixel art drone enemy sprite sheet` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/enemies/drone/` | `drone_strip.png` |
| Jammer | alan bozucu totem / cihaz | `CC0 pixel art turret sprite sheet` veya `CC0 pixel art jammer sprite` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/enemies/jammer/` | `jammer_strip.png` |
| Sentinel | ağır nöbetçi / zırhlı düşman | `CC0 pixel art sentinel enemy` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/enemies/sentinel/` | `sentinel_strip.png` |
| Glitch Entity | bozulmuş varlık / distortion enemy | `CC0 pixel art glitch enemy sprite` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/enemies/glitch/` | `glitch_strip.png` |

### Dünya özel varyantları (isteğe bağlı ama çok önerilir)
| Dosya adı | Anlamı |
|---|---|
| `mergen_drone_strip.png` | sınır / radar temalı drone |
| `ulgen_drone_strip.png` | ışıklı / semavi drone |
| `kayra_drone_strip.png` | runik / doğal drone |
| `erlik_drone_strip.png` | bozulmuş drone |
| `umay_drone_strip.png` | kutsal alan bozulmuş gözcü varyantı |

---

## 6) Boss sprite sheet’leri

### Zorunlu
Her dünya için ayrı bir boss strip’i indirin.

| Dünya | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|
| Mergen | `CC0 pixel art guardian boss sprite sheet` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/enemies/bosses/` | `mergen_boss_strip.png` |
| Ülgen | `CC0 pixel art celestial boss sprite sheet` | CC0 / PD / CC-BY | PNG | aynı | `ulgen_boss_strip.png` |
| Kayra | `CC0 pixel art forest guardian boss sprite` | CC0 / PD / CC-BY | PNG | aynı | `kayra_boss_strip.png` |
| Erlik | `CC0 pixel art demon glitch boss sprite` | CC0 / PD / CC-BY | PNG | aynı | `erlik_boss_strip.png` |
| Umay | `CC0 pixel art shrine guardian boss sprite` | CC0 / PD / CC-BY | PNG | aynı | `umay_boss_strip.png` |

---

## 7) Oyuncu mermi sprite sheet’leri

### Zorunlu
| Karakter | Ne indirilecek | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|---|
| Mergen | ok / precision bolt | `CC0 pixel art arrow projectile sprite` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/mergen/` | `precision_arrow_strip.png` |
| Ülgen | semavi patlama / radiant blast | `CC0 pixel art holy projectile sprite` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/ulgen/` | `celestial_blast_strip.png` |
| Kayra | runik küre / bilgi tohumu | `CC0 pixel art magic orb projectile` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/kayra/` | `rune_orb_strip.png` |
| Erlik | glitch shard / shadow bolt | `CC0 pixel art dark projectile sprite` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/erlik/` | `glitch_shard_strip.png` |
| Umay Ana | protective pulse / shield wave | `CC0 pixel art shield projectile sprite` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/umay/` | `protective_pulse_strip.png` |

---

## 8) Düşman mermi sprite sheet’leri

### Zorunlu
| Dosya adı | Arama terimi | Yerel klasör |
|---|---|---|
| `drone_bolt_strip.png` | `CC0 pixel art laser bolt sprite` | `www/assets/bilge_yolac/projectiles/enemies/` |
| `jammer_pulse_strip.png` | `CC0 pixel art pulse ring sprite` | aynı |
| `sentinel_lance_strip.png` | `CC0 pixel art energy lance projectile` | aynı |
| `glitch_chaos_strip.png` | `CC0 pixel art glitch projectile` | aynı |
| `boss_core_burst_strip.png` | `CC0 pixel art boss energy projectile` | aynı |

---

## 9) VFX sprite sheet’leri

### İsteğe bağlı ama önerilir
| Dosya adı | Arama terimi | Yerel klasör |
|---|---|---|
| `hit_spark_strip.png` | `CC0 pixel art hit spark` | `www/assets/bilge_yolac/vfx/` |
| `portal_pulse_strip.png` | `CC0 pixel art portal effect` | aynı |
| `shield_ring_strip.png` | `CC0 pixel art shield ring` | aynı |
| `glitch_bloom_strip.png` | `CC0 pixel art glitch burst` | aynı |
| `dust_strip.png` | `CC0 pixel art dust effect` | aynı |

---

## 10) Retro UI / HUD öğeleri

### İsteğe bağlı
| Dosya adı | Arama terimi | Yerel klasör |
|---|---|---|
| `panel_frame.png` | `CC0 pixel art UI panel frame` | `www/assets/bilge_yolac/ui/` |
| `reticle_01.png` | `CC0 pixel art crosshair` | aynı |
| `mini_badge_01.png` | `CC0 pixel art hud badge` | aynı |

---

## 11) Varlık ararken kullanabileceğiniz güvenli kaynak türleri

Ben canlı web taraması yapamadığım için burada **doğrudan doğrulanmış URL** veremiyorum.  
İnternet bağlı bir makinede şu tür kaynaklarda arayın:

- **OpenGameArt**
- **itch.io** *(free / CC0 / commercial use filtresiyle)*
- lisansı açık kişisel GitHub / asset repo sayfaları

Arama sırasında mutlaka şu ek filtreleri kullanın:

- `license: CC0`
- `license: public domain`
- `license: CC-BY`
- `commercial use allowed`
- `pixel art`
- `sprite sheet`
- `PNG`

---

## 12) Atıf kaydı

CC-BY varlık indirirseniz şu dosyayı proje içinde tutun:

`www/assets/bilge_yolac/manifests/asset_attribution.md`

İçeriği en az şu alanları içersin:

- varlık adı
- indirdiğiniz kaynak sayfa
- sanatçı adı
- lisans adı
- tarih
- yerel dosya adı

Örnek satır:

- `celestial_blast_strip.png` — Sanatçı: ... — Lisans: CC-BY 4.0 — Kaynak: ... — İndirme tarihi: ...

---

## 13) Minimum zorunlu paket

En hızlı kurulum için aşağıdakiler **mutlaka** indirilmeli:

- 10 arka plan dosyası
- 10 orta katman set parçası
- 10 ön plan prop dosyası
- 4 düşman strip’i
- 5 boss strip’i
- 5 oyuncu mermi strip’i
- 5 düşman mermi strip’i

Toplam minimum: **39 dosya**

---

## 14) Performans notu

İlk aşamada şu strateji güvenlidir:

- her dünya için **2 arka plan + 2 orta katman + 2 ön plan**
- düşman başına **1 strip**
- boss başına **1 strip**
- mermi başına **1 strip**

Bu, görsel sıçrama sağlar ama Shiny içindeki ilk yüklemeyi aşırı büyütmez.
