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
- `emre_boss_strip.png`
- `cozum_dalgasi_strip.png`
- `glitch_bloom_strip.png`

---

## 1) Dünya arka planları

### Zorunlu
| Kategori | Ne indirilecek | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|---|
| Emre (Çözüm Vadisi) uzak arka plan | sakin ova / plato silüeti | `CC0 pixel art plateau background 32x32` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/emre/backgrounds/` | `plateau_far_01.png` |
| Emre ikinci silüet | düşük tepe sırtı | `CC0 pixel art rocky ridge background` | CC0 / PD / CC-BY | PNG | aynı | `ridge_far_01.png` |
| Selin (Sinyal Sahası) gök silüeti | sinyal kuleleri / aydınlık hat | `CC0 pixel art sci-fi tower skyline` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/selin/backgrounds/` | `celestial_spires_01.png` |
| Selin ikinci arka katman | düzenli yapı silüeti | `CC0 pixel art tech skyline background` | CC0 / PD / CC-BY | PNG | aynı | `fortress_skyline_01.png` |
| Deniz (Strateji Platosu) tepe silüeti | geniş plato / katmanlı arazi | `CC0 pixel art plateau layers background` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/deniz/backgrounds/` | `forest_canopy_01.png` |
| Deniz ikinci arka katman | tepe katmanları | `CC0 pixel art layered hills background` | CC0 / PD / CC-BY | PNG | aynı | `runic_hills_01.png` |
| Can (Doğrulama Hattı) arka plan | denetim istasyonu silüeti | `CC0 pixel art industrial background` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/can/backgrounds/` | `abyss_spires_01.png` |
| Can ikinci arka katman | kontrol kuleleri sırtı | `CC0 pixel art factory skyline background` | CC0 / PD / CC-BY | PNG | aynı | `corrupted_depth_01.png` |
| İpek (Rehberlik Atölyesi) arka plan | aydınlık öğrenme alanı silüeti | `CC0 pixel art bright studio background` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/ipek/backgrounds/` | `sanctuary_halo_01.png` |
| İpek ikinci arka katman | sakin bahçe silüeti | `CC0 pixel art calm garden background` | CC0 / PD / CC-BY | PNG | aynı | `healing_garden_01.png` |

### İsteğe bağlı
- Gece gökyüzü ek overlay
- Bulut / sis katmanı
- Dağ / bina / kule ekstra varyantları

---

## 2) Dünya orta katman / set parçaları

### Zorunlu
| Dünya | Ne indirilecek | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|---|
| Emre | analiz yapısı / modern bina | `CC0 pixel art modern building png` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/emre/midground/` | `temple_frontier_01.png` |
| Emre | radar karakolu / dish tower | `CC0 pixel art radar tower` | CC0 / PD / CC-BY | PNG | aynı | `radar_outpost_01.png` |
| Selin | sinyal kulesi | `CC0 pixel art signal tower` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/selin/midground/` | `luminous_tower_01.png` |
| Selin | enerji geçidi / veri kapısı | `CC0 pixel art sci-fi gate` | CC0 / PD / CC-BY | PNG | aynı | `energy_fort_01.png` |
| Deniz | plan panosu / büyük yapı | `CC0 pixel art large structure` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/deniz/midground/` | `sacred_tree_01.png` |
| Deniz | katmanlı yapı / kademeli plato | `CC0 pixel art layered structure` | CC0 / PD / CC-BY | PNG | aynı | `runic_ruin_01.png` |
| Can | denetim istasyonu / kontrol yapısı | `CC0 pixel art control station` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/can/midground/` | `glitch_temple_01.png` |
| Can | tarama geçidi | `CC0 pixel art scanner gate sprite sheet` | CC0 / PD / CC-BY | PNG | aynı | `portal_rift_01.png` |
| İpek | rehber panosu / öğrenme yapısı | `CC0 pixel art studio structure` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/ipek/midground/` | `sanctuary_gate_01.png` |
| İpek | bilgi havuzu / örnek panosu | `CC0 pixel art info panel` | CC0 / PD / CC-BY | PNG | aynı | `life_pool_01.png` |

### İsteğe bağlı
- Emre için sınır gözetleme direği
- Selin için ikinci sinyal kulesi / röle platformu
- Deniz için plan kemeri / kademe panosu
- Can için kontrol sütunu / tarama panosu
- İpek için rehber kulesi / küçük örnek sütunu

---

## 3) Ön plan prop’ları

### Zorunlu
| Dünya | Ne indirilecek | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|---|
| Emre | ot / taş / direk | `CC0 pixel art grass tuft` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/emre/foreground/` | `steppe_grass_01.png` |
| Emre | sinyal direği | `CC0 pixel art utility pole` | CC0 / PD / CC-BY | PNG | aynı | `signal_pole_01.png` |
| Selin | sinyal kristali | `CC0 pixel art crystal` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/selin/foreground/` | `light_crystal_01.png` |
| Selin | röle / küçük kule | `CC0 pixel art sci fi relay` | CC0 / PD / CC-BY | PNG | aynı | `hover_relay_01.png` |
| Deniz | bitki / küçük pano | `CC0 pixel art fern` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/deniz/foreground/` | `fern_01.png` |
| Deniz | plan taşı / işaret | `CC0 pixel art standing stone` | CC0 / PD / CC-BY | PNG | aynı | `rune_stone_01.png` |
| Can | kontrol işareti | `CC0 pixel art warning marker` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/can/foreground/` | `shadow_thorn_01.png` |
| Can | tarama kristali | `CC0 pixel art scanner crystal` | CC0 / PD / CC-BY | PNG | aynı | `glitch_crystal_01.png` |
| İpek | aydınlık bitki | `CC0 pixel art glowing flower` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/worlds/ipek/foreground/` | `luminous_flora_01.png` |
| İpek | örnek panosu çiçeği | `CC0 pixel art bloom` | CC0 / PD / CC-BY | PNG | aynı | `healing_bloom_01.png` |

---

## 4) Tiles / yapılar / dekoratif set

### Zorunlu değil ama güçlü öneri
Bunlar uzun vadede platform çizimini de zenginleştirir.

| Dünya | Arama terimi | Yerel klasör | Dosya adı önerisi |
|---|---|---|---|
| Emre | `CC0 pixel art modern tileset` | `www/assets/bilge_yolac/worlds/emre/tiles/` | `ruin_tileset_01.png` |
| Selin | `CC0 pixel art sci fi tileset` | `www/assets/bilge_yolac/worlds/selin/tiles/` | `celestial_tileset_01.png` |
| Deniz | `CC0 pixel art plateau tileset` | `www/assets/bilge_yolac/worlds/deniz/tiles/` | `forest_runic_tileset_01.png` |
| Can | `CC0 pixel art industrial tileset` | `www/assets/bilge_yolac/worlds/can/tiles/` | `corruption_tileset_01.png` |
| İpek | `CC0 pixel art studio tileset` | `www/assets/bilge_yolac/worlds/ipek/tiles/` | `sanctuary_tileset_01.png` |

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
| `emre_drone_strip.png` | Çözüm Vadisi temalı drone |
| `selin_drone_strip.png` | Sinyal Sahası temalı drone |
| `deniz_drone_strip.png` | Strateji Platosu temalı drone |
| `can_drone_strip.png` | Doğrulama Hattı temalı drone |
| `ipek_drone_strip.png` | Rehberlik Atölyesi temalı drone |

---

## 6) Boss sprite sheet’leri

### Zorunlu
Her dünya için ayrı bir boss strip’i indirin.

| Dünya | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|
| Emre (Karmaşa Çekirdeği) | `CC0 pixel art boss sprite sheet` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/enemies/bosses/` | `emre_boss_strip.png` |
| Selin (Belirsizlik Bloğu) | `CC0 pixel art tech boss sprite sheet` | CC0 / PD / CC-BY | PNG | aynı | `selin_boss_strip.png` |
| Deniz (Dağınık Plan Yığını) | `CC0 pixel art large boss sprite` | CC0 / PD / CC-BY | PNG | aynı | `deniz_boss_strip.png` |
| Can (Gizli Varsayım) | `CC0 pixel art glitch boss sprite` | CC0 / PD / CC-BY | PNG | aynı | `can_boss_strip.png` |
| İpek (Bilgi Kalabalığı) | `CC0 pixel art boss sprite sheet` | CC0 / PD / CC-BY | PNG | aynı | `ipek_boss_strip.png` |

---

## 7) Oyuncu mermi sprite sheet’leri

### Zorunlu
| Persona | Ne indirilecek | Arama terimi | Lisans | Format | Yerel klasör | Dosya adı |
|---|---|---|---|---|---|---|
| Emre | çözüm dalgası / enerji dalgası | `CC0 pixel art wave projectile sprite` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/emre/` | `cozum_dalgasi_strip.png` |
| Selin | sinyal taraması / tarama darbesi | `CC0 pixel art scan pulse projectile` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/selin/` | `sinyal_taramasi_strip.png` |
| Deniz | rota projeksiyonu / yapısal blok | `CC0 pixel art geometric projectile` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/deniz/` | `rota_projesi_strip.png` |
| Can | doğrulama ışını / hedef ışını | `CC0 pixel art beam projectile sprite` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/can/` | `dogrulama_isini_strip.png` |
| İpek | rehber halkası / destek halkası | `CC0 pixel art ring projectile sprite` | CC0 / PD / CC-BY | PNG | `www/assets/bilge_yolac/projectiles/ipek/` | `rehber_halkasi_strip.png` |

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

- `sinyal_taramasi_strip.png` — Sanatçı: ... — Lisans: CC-BY 4.0 — Kaynak: ... — İndirme tarihi: ...

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
