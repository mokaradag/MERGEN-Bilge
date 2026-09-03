# ==============================================================================
# Dosya Yolu: tests/testthat/test-maintainability-ratchet.R
# Açıklama: Maintainability skorunun ve büyük dosya sayaçlarının mevcut
#           üretim taban çizgisinin altına düşmesini engeller.
# ==============================================================================

.find_repo_root_maint_ratchet <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.as_int_env <- function(name, default) {
  raw <- Sys.getenv(name, as.character(default))
  value <- suppressWarnings(as.integer(raw))

  if (is.na(value)) {
    stop(sprintf("%s geçersiz: %s", name, raw), call. = FALSE)
  }

  value
}

test_that("maintainability skoru mevcut taban çizgisinin altına düşmez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  score <- attr(report, "maintainability_score", exact = TRUE)

  expect_true(
    is.numeric(score) || is.integer(score),
    info = "maintainability_report.R attr(..., 'maintainability_score') üretmelidir."
  )

  min_score <- .as_int_env("MERGEN_TEST_MIN_MAINTAINABILITY_SCORE", 100L)

  expect_true(
    score >= min_score,
    info = sprintf(
      "Maintainability skoru geriledi: %s/100 < minimum %s/100.",
      score,
      min_score
    )
  )
})

test_that("büyük dosya ve fonksiyon sayaçları mevcut taban çizgisinden kötüye gitmez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  score_report <- attr(report, "score_report", exact = TRUE)

  expect_true(
    is.data.frame(score_report),
    info = "maintainability_report.R attr(..., 'score_report') üretmelidir."
  )

  max_large_files <- .as_int_env("MERGEN_TEST_MAX_800_LINE_FILES", 0L)
  max_function_heavy_files <- .as_int_env("MERGEN_TEST_MAX_25_FUNCTION_FILES", 0L)
  max_very_large_files <- .as_int_env("MERGEN_TEST_MAX_1500_LINE_FILES", 0L)
  # 678L -> 761L bilinçli güncelleme (Ortak Oturumlar tamamlama seti): iki
  # bütünleşik özellik modülü ölçülen tabanı yükseltti — R/module_ortak_calismalar.R
  # (761; hub: liste + bildirim + yeni oturum + geçmiş kopyalama onayı + oda geri
  # yükleme) ve R/module_ortak_oturum_bilge_yolac.R (705; ortak çalışma alanı
  # köprüsü). 800+ satır dosya sayısı 0, 25+ fonksiyon dosya sayısı 0 ve en
  # yüksek fonksiyon sayısı 24 KORUNUR; yalnızca en büyük dosya satır tavanı
  # yükseldi. DB katmanı bilinçli olarak bölündü (db_mesajlar 768 -> 518;
  # ayrılan Bilge Yolaç DB katmanı R/helpers_ortak_oturum_db_bilge_yolac.R) ve
  # sunum-karar yardımcıları R/helpers_ortak_oturum_sunum.R'ye taşındı
  # (permissions 27 -> 24) — böylece fonksiyon tavanı gevşetilmedi.
  # 761L -> 778L bilinçli güncelleme (Bilge Savunması codex P2 düzeltmeleri):
  # R/helpers_db_bilge_savunmasi_topluluk.R (778; haftalık koşulardan plan
  # yayınının reddi + sezon ConfigJson'undan değiştirici okuma) yeni tabanı
  # oluşturdu. 800+ satır dosya sayısı 0, 25+ fonksiyon dosya sayısı 0 (bu
  # dosya 20 fonksiyon) ve en yüksek fonksiyon sayısı 24 KORUNUR; yalnızca
  # en büyük dosya satır tavanı yükseldi.
  # 778L -> 795L bilinçli güncelleme (Bilge Yolaç çalıştırma hattı codex
  # düzeltmeleri): R/helpers_claude_code_run_completion.R (795; kesilmiş
  # çıktı taramasında staging/sync'i atlayan erken dönüş + arka plan çıktı
  # işleme için hazırlık aşamasındakiyle aynı bağımsız deadline) yeni tabanı
  # oluşturdu. 800+ satır dosya sayısı 0, 25+ fonksiyon dosya sayısı 0 (bu
  # dosya 24 fonksiyon, artmadı) ve en yüksek fonksiyon sayısı 24 KORUNUR;
  # yalnızca en büyük dosya satır tavanı yükseldi.
  # PR #705 incelemesi: manifest DIŞI dinamik `source()` çağrıları kaldırıldı ve
  # dört çalışma zamanı dosyası (PK çekirdek gövdesi, P1 guard'ları, işçi-PID
  # sondası, tüketmeyen köken okuması) `R/config_source_manifest.R` içinde
  # AÇIKÇA sıralandı. En büyük dosya artık SAF VERİ olan manifestin kendisidir
  # (796 satır, 0 fonksiyon). 795 -> 796; "800+ dosya sayısı = 0" kuralı
  # DEĞİŞMEDİ, yani manifeste yeni giriş eklemek artık bölüm bölmesi gerektirir.
  max_file_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_LINES", 796L)
  max_file_functions <- .as_int_env("MERGEN_TEST_MAX_FILE_FUNCTIONS", 24L)

  actual_large_files <- sum(score_report$lines >= 800)
  actual_function_heavy_files <- sum(score_report$functions >= 25)
  actual_very_large_files <- sum(score_report$lines >= 1500)
  actual_max_lines <- max(score_report$lines, na.rm = TRUE)
  actual_max_functions <- max(score_report$functions, na.rm = TRUE)

  expect_true(
    actual_large_files <= max_large_files,
    info = sprintf(
      "800+ satır dosya sayısı arttı: %d > %d.",
      actual_large_files,
      max_large_files
    )
  )

  expect_true(
    actual_function_heavy_files <= max_function_heavy_files,
    info = sprintf(
      "25+ fonksiyon dosya sayısı arttı: %d > %d.",
      actual_function_heavy_files,
      max_function_heavy_files
    )
  )

  expect_true(
    actual_very_large_files <= max_very_large_files,
    info = sprintf(
      "1500+ satır dosya sayısı arttı: %d > %d.",
      actual_very_large_files,
      max_very_large_files
    )
  )

  expect_true(
    actual_max_lines <= max_file_lines,
    info = sprintf(
      "En büyük dosya satırı arttı: %d > %d.",
      actual_max_lines,
      max_file_lines
    )
  )

  expect_true(
    actual_max_functions <= max_file_functions,
    info = sprintf(
      "En yüksek fonksiyon sayısı arttı: %d > %d.",
      actual_max_functions,
      max_file_functions
    )
  )
})

test_that("near-limit runtime files do not silently consume remaining headroom", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  assert_current_budget <- function(path, max_lines, max_functions) {
    row <- report[
      grepl(
        paste0("(^|/)", gsub("([.])", "\\\\\\1", path), "$"),
        report$file,
        perl = TRUE
      ),
      ,
      drop = FALSE
    ]

    expect_equal(
      nrow(row),
      1L,
      info = sprintf("%s maintainability raporunda tek satır olarak görünmelidir.", path)
    )

    expect_true(
      row$lines[1] <= max_lines,
      info = sprintf("%s mevcut satır baş boşluğunu tüketti: %d > %d.", path, row$lines[1], max_lines)
    )

    expect_true(
      row$functions[1] <= max_functions,
      info = sprintf("%s mevcut fonksiyon baş boşluğunu tüketti: %d > %d.", path, row$functions[1], max_functions)
    )
  }

  assert_current_budget("R/module_claude_code.R", 780L, 11L)
  # TTS açık streaming dalı R/server_handler_streaming_tts.R'ye çıkarıldı; gerçek
  # SSE ve non-streaming dalları gibi simetrik handler oldu. send_message
  # 694/14 -> 590/9'a indi. Bütçeler geri birleşmeyi ve büyümeyi kilitler.
  # Bilinçli güncelleme: Süreç/Uygulama Uzmanı için Langflow dispatch dalı
  # eklendi (handle_langflow_chat_mode'a delege eder); 620 -> 634.
  # PR #702 inceleme düzeltmesi: PK asenkron yolunda GÖNDERİM ANI anlık
  # görüntüsü (ayarlar + etkin API anahtarı planı) eklendi; canlı reaktif
  # nesneyi devam kapanışında yeniden okumak, aynı isteği İKİ farklı ayar
  # durumundan derliyordu. Anlık görüntü üretimi ayrı yardımcıdadır
  # (mergen_pk_send_snapshot); burada yalnızca çağrı ve tüketim kaldı.
  # 634 -> 643 (fonksiyon sayısı DÜŞTÜ: 11 -> 9).
    # PR #705 incelemesi (P2): gönderim anı API anahtarı planı DONDURULAMADIĞINDA
  # istek dürüstçe başarısız olur; canlı yeniden çözüm kaldırıldı. Ölçülen
  # taban çizgisi 643 -> 655.
  # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 655 -> 659 satir (OLCULEN).
  # BOS PK anlik goruntusu artik `settings_data`yi EZMEZ; `list()` `NULL`
  # olmadigi icin `%||%` onu koruyor ve gonderim-ani ayarlari sessizce
  # varsayilana dusuyordu. Fonksiyon sayisi AYNI.
  assert_current_budget("R/server_send_message.R", 659L, 11L)
  assert_current_budget("R/server_handler_streaming_tts.R", 200L, 8L)
  assert_current_budget("R/module_admin_hata_analizi.R", 640L, 7L)
  assert_current_budget("R/helpers_admin_hata_detail_runtime.R", 380L, 12L)
  # Görsel UI/HTML render katmanı (ayarlar paneli, sohbet kontrolleri, görsel kartı
  # HTML üreticileri) R/module_image_generation_ui.R'ye çıkarıldı; runtime dosyası
  # 730/22 -> 545/17'ye indi. Bütçeler geri birleşmeyi ve büyümeyi kilitler.
  assert_current_budget("R/module_image_generation.R", 560L, 18L)
  assert_current_budget("R/module_image_generation_ui.R", 220L, 8L)
  assert_current_budget("R/helpers_llm_sse.R", 762L, 20L)
  # At-budget admin modüllerinin inline highcharter/DT renderer'ları *_outputs()
  # dosyalarına çıkarıldı (davranış değişmedi). Modüller veri/sekme orkestrasyonuna
  # odaklı kaldı; renderer'lar ayrı tek-sorumluluk dosyasında. Budgetler geri
  # birleşmeyi yakalar.
  assert_current_budget("R/module_admin_geri_bildirim.R", 90L, 3L)
  assert_current_budget("R/module_admin_geri_bildirim_outputs.R", 670L, 5L)
  assert_current_budget("R/helpers_admin_geri_bildirim_output_tables.R", 145L, 5L)
  assert_current_budget("R/module_admin_yanit_analizi.R", 140L, 4L)
  assert_current_budget("R/module_admin_yanit_analizi_outputs.R", 710L, 5L)
  assert_current_budget("R/server_module_wiring.R", 735L, 14L)
  assert_current_budget("R/server_core_interaction_runtime.R", 360L, 8L)
  assert_current_budget("R/server_core_observer_runtime.R", 320L, 6L)
  # AI Uzman sunucu işleyicileri: saf karar yardımcıları (sayfa adı, sıklık,
  # boşta bağlam) helpers_ai_expert_handlers_support.R'ye ayrıldıktan sonra
  # 726/23 -> 652/22'ye indi. Bütçe geri tırmanışı kilitler.
  assert_current_budget("R/server_ai_expert_handlers.R", 660L, 22L)
  assert_current_budget("R/helpers_ai_expert_handlers_support.R", 180L, 8L)
  assert_current_budget("R/module_file_manager.R", 560L, 10L)
  # 140L/3 -> 175L/7 bilinçli güncelleme: senkron toplu yükleme döngüsü ortak
  # dosya alım hattına taşındı; dosya artık plan gönderimi + ana süreç commit'i
  # + yükleme runtime fabrikası sorumluluğunu taşıyor.
  assert_current_budget("R/helpers_file_manager_upload_runtime.R", 175L, 7L)
  # 686L/22L -> 686L/23L bilinçli güncelleme: TTS parça hattı sınırlı
  # eşzamanlılık/sıralı teslim/başlangıç tamponu ile
  # R/helpers_ai_expert_chunk_pipeline.R'ye ayrıldı; modülde yalnızca ince
  # uyarlayıcı + doğal bitiş kancası kaldı (667 satır, 23 fonksiyon).
  assert_current_budget("R/module_ai_expert.R", 694L, 23L)
  # AI Uzman yardımcı dosyası, worker-safe DB okuyucuları
  # helpers_ai_expert_user_data.R'ye ayrıldıktan sonra 24-fonksiyon küresel
  # tavanından indi (680/24 -> 507/13). Bütçe geri tırmanışı kilitler.
  assert_current_budget("R/helpers_ai_expert.R", 540L, 15L)
  assert_current_budget("R/helpers_ai_expert_user_data.R", 220L, 13L)
  assert_current_budget("R/helpers_mcp_tools.R", 535L, 20L)
  assert_current_budget("R/module_chartlab.R", 532L, 20L)
  # Sohbet okuma SQL'i (önizleme/liste/mesaj/toplu/geçmiş) saf üretici dosyasına
  # ayrıldı: helpers_db_chat_readers.R 680/13 -> 522/13; üreticiler 133/6.
  # SQL byte-birebir korundu (golden). Bütçeler SQL'in reader'a geri sızmasını kilitler.
  assert_current_budget("R/helpers_db_chat_readers.R", 560L, 14L)
  assert_current_budget("R/helpers_db_chat_read_queries.R", 180L, 8L)

  # Derin uzay giriş ekranı UI/sunucu olarak bölündü: createStartupScreenUI()
  # ve saf .startup_*() yapıcıları module_startup_screen_ui.R'ye taşındı; üç
  # deneyim-modu kartı tek veri-odaklı .startup_mode_card() ile üretilir.
  # module_startup_screen.R 740 -> 358 satıra indi. Bütçeler geri birleşmeyi
  # ve büyümeyi yakalar.
  assert_current_budget("R/module_startup_screen.R", 380L, 7L)
  assert_current_budget("R/module_startup_screen_ui.R", 430L, 16L)

  # Yapılandırma UI'sinin medya/görsel/analiz kartları ayrı gelişmiş UI dosyasına
  # çıkarıldı; ana kompozitör ve temel kartlar ayrı kaldı. Bütçeler geri birleşmeyi
  # ve yeni en-büyük-dosya pinini yakalar.
  assert_current_budget("R/module_settings_yapilandirma_ui.R", 430L, 8L)
  # Bilinçli güncelleme: Başlangıç Deneyimi (startup lane) kartı
  # (.syap_startup_lane_card) gelişmiş kart dosyasına eklendi (yeni ürün
  # yüzeyi; ana kompozitör 430 bütçesinde kaldı). 370/6 -> 430/7.
  assert_current_budget("R/module_settings_yapilandirma_advanced_ui.R", 430L, 7L)

  # Gerçek SSE worker-export globals listesi (reasoning delta / stop-file /
  # model request override yardımcıları) saf fabrikaya (helpers_llm_true_streaming_
  # worker.R) çıkarıldı; handler onu delege eder. server_handler_true_streaming.R
  # 681 -> 655 satıra indi (küresel pin 681 -> 678). Bütçeler liste içeriğinin
  # handler'a geri sızmasını ve fabrikanın şişmesini yakalar.
  # PR #705 incelemesi (P1): `block` kipinde doğrulanmamış analiz metni artık
  # akışta yayınlanmaz; tampon kararı ve dal ölçülen taban çizgisini 660 -> 680
  # yükseltti. Yeni fonksiyon EKLENMEDİ; sınır bilinçli olarak güncellendi.
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 680 -> 689 satır (ÖLÇÜLEN).
  # `pk_provenance_decorate()` cagrisi `tryCatch` ile sarildi: dekorasyon
  # hatasi (bozuk olgu kaydi, eksik yardimci) TUM akis sonlandirmasini
  # dusuruyor ve kullanici HAZIR yaniti hic goremiyordu. Fonksiyon sayisi
  # ARTMAMISTIR (17).
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 689 -> 707 satır (ÖLÇÜLEN).
  # `defer_visible_text` TRUE iken bos yanit balonu artik ACILMAZ; kanit
  # dogrulamasi biten metin gelene kadar kullaniciya bos bir kabuk
  # gosteriliyordu. Fonksiyon sayisi ARTMAMISTIR (18).
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 707 -> 717 (ÖLÇÜLEN).
  # `mergen_pk_stream_validated_text()` çağrısı `tryCatch` ile sarıldı. Bu
  # sınırdan kaçan bir istisna `finalize_stream_message()` ve `observe()`
  # gövdesini terk ediyor, `stream_env$finalized` ZATEN TRUE olduğu için
  # yoklama duruyordu: `finalizeStreamingMessage` gönderilmiyor,
  # `cleanup_streaming_state()` ve `ctx$reset_chat_state_fn()` HİÇ çalışmıyor,
  # yazma animasyonu ve `is_sending` KALICI olarak takılı kalıyordu.
  # `defer_visible_text` TRUE iken yedek KAPALI BAŞARISIZDIR (doğrulanmamış
  # tampon metin yayımlanmaz). Fonksiyon sayısı 18 -> 17 (ölçülen).
  # ÖLÇÜLEN DEĞER 17'DİR (PR #705 incelemesi, P3): bütçe 18 bırakılınca dosyaya
  # BİR fonksiyon eklense bile ratchet geçiyordu, yani baş boşluk sessizce
  # tüketilebiliyordu.
  assert_current_budget("R/server_handler_true_streaming.R", 717L, 17L)
  assert_current_budget("R/helpers_llm_true_streaming_worker.R", 80L, 1L)

  # Yönetişim katmanı (seam kayıt defteri + frontend bölge haritası) saf veri
  # dosyalarıdır; bütçeler bölge/seam başına birkaç yeni varlık satırına izin
  # verir ama dosyaların runtime mantığıyla şişmesini erken yakalar.
  # Bilinçli güncelleme: frontend bölge dosyası VERİ + DOĞRULAYICI olarak
  # bölündü (config_source_manifest.R / bootstrap_source_manifest.R deseni).
  # config_ui_asset_zones.R artık SADECE veri (777/10 -> 502/0); doğrulayıcı
  # API (saf fonksiyonlar) config_ui_asset_zone_validators.R'ye taşındı.
  # Veri dosyası 0 fonksiyonda kilitlenir (runtime mantık sızması engellenir);
  # doğrulayıcı dosyası 10 fonksiyonu taşır. Bütçeler geri birleşmeyi yakalar.
  assert_current_budget("R/config_ui_asset_zones.R", 550L, 2L)
  assert_current_budget("R/config_ui_asset_zone_validators.R", 360L, 12L)
  # Bilinçli güncelleme: seam guard test / odaklı doğrulama listeleri AYRI
  # veri dosyasına (R/config_seam_guard_tests.R) çıkarıldı. Kayıt defteri TAM
  # 580/580 tavanındaydı; sahiplik verisi seam SAYISIYLA, guard test listesi
  # ise KOD TABANI büyüdükçe artar. İkisi aynı dosyada tutulduğunda sabit
  # tavan, YENİ BİR TESTİN SEAM'E KAYDEDİLMESİNİ engelliyordu (Faz 4 guard
  # testleri bu yüzden sahipsiz kalmıştı). 580/8 -> 430/8 + 300/1.
  assert_current_budget("R/config_seam_registry.R", 430L, 8L)
  assert_current_budget("R/config_seam_guard_tests.R", 300L, 1L)

  # Faz 4 (§5.4) varlık çözümleme hattı. Her katman TEK sorumluluktadır ve
  # geri birleştirilmemelidir: biçimbirim -> normalleştirme -> anım ->
  # alias -> puanlama formülleri -> kapalı sözlük taraması -> karar
  # politikası -> D11 geçmişi -> filtre hattına bağlama.
  assert_current_budget("R/helpers_pk_entity_morph.R", 320L, 10L)
  # BİLİNÇLİ GÜNCELLEME (inceleme): 460 -> 466 satır (ÖLÇÜLEN); fonksiyon
  # sayısı ARTMAMIŞTIR. Tek nedeni ayırıcı-ek taramasının GERÇEK bir kusurunun
  # düzeltilmesidir: `stri_match_first_regex()` en soldaki eşleşmeyi verdiği
  # için `HAVA-SAVUNMA-da` içindeki `A-SAVUNMA` parçasında duruluyor, sondaki
  # gerçek `-da` eki hiç soyulmuyor ve tam eşleşecek varlık kaçırılıyordu.
  # Eşleşmelerin tamamı taranır ve SON ek zinciri soyulur. KÜRESEL eşikler
  # (796 satır / 24 fonksiyon) DEĞİŞMEDİ.
  # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 466/14 -> 467/12 (OLCULEN).
  # Varlik normallestirmesinde tekil/olcek kapisi bir satir buyudu.
  assert_current_budget("R/helpers_pk_entity_normalize.R", 467L, 12L)
  # ÖLÇÜLEN DARALTMA: 150 -> 148 satır (noktalama sınırı düzeltmesi açıklama
  # yoğunluğunu azalttı; davranış EKLENDİ, satır sayısı düştü).
  # BILINCLI GUNCELLEME (PR #705 inceleme): 148 -> 161 satir (OLCULEN).
  # `/` ve `|` hem liste ayirici hem kanonik adin KENDI parcasi olabilir
  # (`AR/GE`, `A/B`); yalnizca bolunmus parcalar uretilince hicbir anim kanonik
  # katlamaya ULASAMIYOR ve kullanici adi birebir yazsa bile istek
  # netlestirmeye gidiyordu. Bolunmemis bicim ek aday olarak eklenir.
  # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 161/6 -> 162/4 (OLCULEN).
  # Anma cikarimi bir satir buyudu; fonksiyon sayisi DUSTU.
  assert_current_budget("R/helpers_pk_entity_mention.R", 162L, 4L)
  assert_current_budget("R/helpers_pk_entity_alias.R", 170L, 4L)
  assert_current_budget("R/helpers_pk_entity_score.R", 400L, 16L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 400 -> 408 satır (ÖLÇÜLEN).
  # `.pk_entity_merge_mention_matches()` artik `list(records =, truncated =)`
  # dondurur; kirpilmis bir anim taramasi eskiden SESSIZCE tam tarama gibi
  # davraniyordu. Fonksiyon sayisi ARTMAMISTIR (11).
  # Fonksiyon bütçesi ÖLÇÜLEN değere çekildi (11): 13 iki fonksiyonluk sessiz
  # büyüme payı bırakıyordu ve yorumda yazan ölçümle çelişiyordu.
  assert_current_budget("R/helpers_pk_entity_scan.R", 408L, 11L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 680 -> 702 satır (ÖLÇÜLEN).
  # (a) Kirpilmis taramada `allow_all` artik FALSE (eksik kumeyi "tumu" gibi
  # sunmak yanlis toplam uretiyordu); (b) `refinement` rolu icin 7. kural
  # (aciklama ile `unfiltered`) eklendi -- daralticidan ibaret bir anim TUM
  # analizi durduruyordu. Fonksiyon sayisi ARTMAMISTIR (15).
  # Fonksiyon bütçesi ÖLÇÜLEN değere çekildi (15).
  assert_current_budget("R/helpers_pk_entity_resolver.R", 702L, 15L)
  # BILINCLI GUNCELLEME (PR incelemesi): 520 -> 530 satir (OLCULEN). Guncel
  # turun belirtecleri KALICI BAGLAMDAN ONCE denenir; `"ANKA icin"` gibi kisa
  # bir daraltma ifadesinde kullanicinin AZ ONCE yazdigi varlik hic teklif
  # edilmiyor, onay istemi ESKI ozneyi oneriyordu. Fonksiyon sayisi AYNI.
  assert_current_budget("R/helpers_pk_entity_history.R", 530L, 17L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 270 -> 284 satır (ÖLÇÜLEN).
  # Karakter OLMAYAN sutunda varlik filtresi artik SESSIZCE atlanmaz; bir
  # aciklama (`aciklamalar`) kaydi uretilir. Aksi halde kullanici, uygulanmadigi
  # halde uygulanmis sandigi bir filtreyle sonuc goruyordu. Fonksiyon sayisi
  # ARTMAMISTIR (7).
  # BÖLÜNME (inceleme): yaprak düzeyi karar katmanı
  # `R/helpers_pk_entity_apply_leaf.R`ye taşındı. İki KAPALI BAŞARISIZLIK
  # düzeltmesi (özne yaprağında `config_error` reddi ve birincil varlık
  # bilinmezken ikincil daraltmanın analizi durdurmaması) bu dosyayı bütçenin
  # üstüne çıkarıyordu; ratchet gevşetilmedi, sorumluluk ayrıldı.
  assert_current_budget("R/helpers_pk_entity_apply.R", 190L, 5L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 145 -> 180 satır (ÖLÇÜLEN).
  # Boş sözlük SEBEBİNİ ayrıştıran iki SAF yardımcı buraya alındı:
  # `.pk_entity_apply_vocab_reason()` / `.pk_entity_apply_skip_note()`.
  # Dört farklı durum (sütun YOK / metin değil / tümü boş / veri yok) tek bir
  # "alan metin değil" metniyle bildiriliyor, üstelik sayısal-tarih
  # filtrelerinde (çözümleme zaten beklenmez) HER analizde gereksiz uyarı
  # üretiliyordu. `helpers_pk_entity_apply.R` bütçesi GEVŞETİLMEDİ;
  # sorumluluk yaprak dosyasına ayrıldı. Fonksiyon sayısı 2 -> 4.
  assert_current_budget("R/helpers_pk_entity_apply_leaf.R", 180L, 5L)

  # Faz 5 (§5.2) iki geçişli sorgu seçimi. Katmanlar TEK sorumluluktadır ve
  # geri birleştirilmemelidir: sözlüksel getirim (KARAR VERMEZ) -> katı JSON
  # ilkeleri -> kapalı-başarısız yapılandırma -> istem yükü -> mesaj kurulumu ->
  # `requirements` doğrulaması -> ayrıştırma -> karar politikası -> bozulma
  # kipi -> oturum durumu -> LLM orkestrasyonu -> çalışma zamanına bağlama.
  #
  # İnceleme düzeltmeleri katılığı (katı ayrıştırma, geri alınamaz recall
  # kanıtları, anlamsal alanlar, oturum kapsamı) büyüttüğü için üç dosya YEDİYE
  # bölündü. HİÇBİR BÜTÇE GEVŞETİLMEDİ: `prompt` 520 -> 400, `parse` 680 -> 300,
  # `ai` 380 -> 520 (orkestrasyon iptal/teşhis/onay yollarını da üstlendi),
  # `apply` 250 -> 320, `retrieval` 360 -> 400 (not_for olumsuz kanıtı).
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme): 400 -> 411 satır (ÖLÇÜLEN). Tek
  # nedeni `not_for` olumsuz kanitinin BUTUN IFADE eslesmesine cevrilmesidir:
  # tek bir >=3 karakterlik belirtec artik yetmez, bir ifadenin TUM anlamli
  # belirteçleri istemde geçmelidir. Aksi hâlde `not_for = "planlanan bütçe"`,
  # "planlanan iscilik" istegini de reddedip GECERLI bir secimi guven kapisinin
  # altina itiyordu. Fonksiyon sayisi ARTMAMISTIR (17).
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 411 -> 422 satır (ÖLÇÜLEN).
  # `not_for` dislamasi SIFIR PUAN kisayolundan ONCE degerlendirilir ve
  # `excluded_by_not_for` alani HER yolda (TRUE/FALSE) dondurulur; eskiden
  # sifir puanli bir sorgu dislama kanitini tasimadan donuyor, tuketiciler de
  # alanin varligina gore dallandigi icin sessizce yanlis dala giriyordu.
  # Fonksiyon sayisi ARTMAMISTIR.
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 422 -> 424 (ÖLÇÜLEN).
  # `pk_retrieval_agreement()` artık AYRI bir `exclusion_prompt` alır: `not_for`
  # dışlaması YALNIZCA güncel soruya bakar. Konuşma geçmişiyle genişletilmiş
  # metin sözlüksel puanlama için doğruydu, ama aynı metin dışlamaya
  # uygulandığında ÖNCEKİ bir turun jetonları `not_for` ifadesini tamamlayıp
  # GEÇERLİ bir seçimi dışlıyordu.
  # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 424/17 -> 434/10 (OLCULEN).
  # HIC 3-gram yokken `table()` CAGRILMAZ: metinsel metadata tasimayan bir
  # kutuphanede `table(NULL)` bazi R surumlerinde "nothing to tabulate" hatasi
  # verip indeks kurulumunu dusuruyordu. Bos indeks MESRU sonuctur.
  assert_current_budget("R/helpers_pk_query_retrieval.R", 434L, 10L)
  assert_current_budget("R/helpers_pk_query_selection_json.R", 240L, 10L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 300 -> 308 satır (ÖLÇÜLEN).
  # Birlestirilmis yapilandirma `pk_select_normalize_config()` ile YENIDEN
  # dogrulanir; kullanici geciversiz bir esik verdiginde birlestirme sonrasi
  # dogrulama yapilmadigi icin gecersiz deger canli karara sizabiliyordu.
  # Fonksiyon sayisi ARTMAMISTIR.
  assert_current_budget("R/helpers_pk_query_selection_config.R", 308L, 10L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 460 -> 472 satır (ÖLÇÜLEN),
  # 18 -> 16 fonksiyon (ÖLÇÜLEN; SIKILAŞTIRMA).
  # `pk_select_entity_kinds()` sıralaması artık YERELDEN BAĞIMSIZ `order(...,
  # method = "radix")` kullanır; Türkçe `LC_COLLATE` altında `sort()` "İ"/"ı"
  # harflerini farklı sıralayıp AYNI varlık kümesi için FARKLI istem üretiyor
  # ve seçim kararını oynatabiliyordu. Ayrıca `ornek_n` uzunluk koruması
  # eklendi: sıfır uzunlukta bir yapılandırma değeri `> 0L` karşılaştırmasında
  # `logical(0)` üretip `if()` içinde HATA veriyordu.
  # BİLİNÇLİ GÜNCELLEME (PR #705 üretim düzeltmesi): seçim istemleri artık
  # bütçeyi aşınca TÜM isteği reddetmek yerine ayrıntıyı seyreltir; ölçülen
  # yeni değerler aşağıdadır (bkz. R/helpers_pk_query_selection_compact.R).
  # BILINCLI GUNCELLEME (PR #715 inceleme): 542 -> 533 satir, 18 -> 17 fonksiyon
  # (OLCULEN). Yinelenen `pk_select_query_capabilities()` KALDIRILDI; ilan
  # edilen yetenekler artik kapinin okudugu kanonik beyandan gelir.
  assert_current_budget("R/helpers_pk_query_selection_payload.R", 533L, 17L)
  # BILINCLI GUNCELLEME (PR #715 inceleme): 130 -> 140 satir (OLCULEN).
  # Sutun kirpmasi tek tanim sigmadiginda da butceyi asmaz; bos yetenek
  # kesisiminde listenin NEDEN bosaltilmadigi belgelendi. Fonksiyon sayisi AYNI.
  # BILINCLI GUNCELLEME (PR #715 inceleme, 2. tur): 140 -> 151 satir (OLCULEN).
  # Merdiven basamagi artik SADECE daraltir: sabit degeri korlemesine yazmak,
  # operatorun daha dar verdigi alani genisletip sigacak bir yuku reddediyordu.
  assert_current_budget("R/helpers_pk_query_selection_compact.R", 151L, 5L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 400 -> 412 (ÖLÇÜLEN).
  # ZORUNLU Geçiş B örneği artık `entity:null` + BEŞ BOŞ dizi ŞEKLİNDE
  # DEĞİLDİR. O şekil tam olarak `pk_select_requirements_empty()` TRUE dediği
  # nesnedir; doğrulayıcı `not_asserted` dönüp `pk_meta_capability_check()`
  # HİÇ çağrılmıyor ve örneği birebir kopyalayan model anlamsal kapıyı
  # atlıyordu. Örnek artık BU istek için İZİNLİ bir yetenek kimliğini KENDİ
  # rol alanında gösterir.
  # BILINCLI GUNCELLEME (PR #705 inceleme): 412 -> 415 satir (OLCULEN).
  # Gecis B istemi ARTIK alti `requirements` alaninin TAMAMININ zorunlu
  # oldugunu ACIKCA soyler; normallestirici eksik alani zaten reddediyordu ama
  # istem bunu bildirmedigi icin model tek onarim hakkini tuketiyordu.
  # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 415/16 -> 418/16 (OLCULEN).
  # Rol cozumlemesi `role` -> `type` -> `"user"` sirasini BOS OLMAYAN TEKIL
  # deger uzerinden yapar: `%||%` yalnizca `NULL` atladigi icin `role = NA`
  # tasiyan bir asistan turu SESSIZCE "user" rolune dusuyordu.
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 418 -> 425 satır (ÖLÇÜLEN).
  # `tur_sayisi` artık `> 0L` karşılaştırmasından ÖNCE uzunluk denetiminden
  # geçer: sıfır uzunlukta bir değer `logical(0)` üretiyor, `if()` HATA veriyor
  # ve istem oluşturma tümüyle düşüyordu. `utils::tail()` çağrısı da aynı
  # korumanın arkasına alındı. Fonksiyon sayısı ARTMAMIŞTIR.
  # BILINCLI GUNCELLEME (PR #715 inceleme): 434 -> 440 satir (OLCULEN). "En az
  # 2 aday" talimati artik listede en az 2 sorgu varken verilir. Fonksiyon AYNI.
  assert_current_budget("R/helpers_pk_query_selection_prompt.R", 440L, 16L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme): 300 -> 325 satır / 12 -> 13
  # fonksiyon (ÖLÇÜLEN). İki neden: (a) TİPLİ doğrulama sonucuna `canonicalized`
  # alani eklendi ve varolussal->sayim kanoniklestirmesi TEK cagri ile baglandi
  # (kanoniklestiricinin KENDISI ayri dosyada: helpers_..._canonical.R);
  # (b) `unsupported` serbest metin alanini normalize eden
  # `pk_select_unsupported_needs()` BURAYA tasindi ve hem normal karar yolu hem
  # de CIP ONAYI yolu ayni sahibi kullanir (kopya mantik kaldirildi).
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 325 -> 345 satır (ÖLÇÜLEN).
  # Iki neden: (a) BOS bir `requirements` nesnesi artik REDDEDILIR -- eskiden
  # "beyan yok" ile "bos beyan" ayni sayilip guven kapisini bypass ediyordu;
  # (b) `zaten` (already-satisfied) kontrolu YALNIZCA tarih ve boyut alanlarina
  # uygulanir, olcut alanlarina degil. Fonksiyon sayisi ARTMAMISTIR.
  # BİLİNÇLİ GÜNCELLEME (inceleme): 345 -> 358 satır (ÖLÇÜLEN); fonksiyon
  # sayısı ARTMAMIŞTIR. Tek nedeni AÇIK-BAŞARISIZ bir kapının kapatılmasıdır:
  # şekil muhafızı yalnızca `{}`yi reddediyordu; `{"measures":[]}` gibi PARÇALI
  # bir nesne normalleştirmeyi geçiyor ve yetenek kaydı denetimi HİÇ
  # çalışmıyordu. KÜRESEL eşikler DEĞİŞMEDİ.
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 358 -> 361 satır (ÖLÇÜLEN).
  # Boş `requirements` nesnesi için üretilen ONARIM mesajı artık ALTI alan
  # kuralıyla aynı şeyi söyler; eski metin "en az bir alan" diyordu, model
  # onu izliyor ve TEK onarım hakkı boşa gidip istek reddediliyordu.
  # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 361/13 -> 371/12 (OLCULEN).
  # Kanoniklestirici YUKLENMEMISSE tipli `validator_error` uretilir; tanimsiz
  # fonksiyon istisnasi v2 yolunda IC SECIM HATASINA donusuyordu.
  # BILINCLI GUNCELLEME (PR #715 inceleme): 402 -> 405 satir (OLCULEN). Ortam
  # belirteci ASCII katlanir; Turkce yerelde "ACIK" katı kipi kapatiyordu.
  assert_current_budget("R/helpers_pk_query_selection_requirements.R", 405L, 14L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 300 -> 304 satır (ÖLÇÜLEN).
  # Iptal durumu icin ACIK sabit eklendi (`PK_SELECT_STATUS_CANCELLED`); iptal
  # "bos yanit" ile ayni koda dusunce oturum durumu iptalde de temizleniyordu.
  # Fonksiyon sayisi ARTMAMISTIR.
  # BİLİNÇLİ GÜNCELLEME (PR incelemesi): `alternates` ögelerinde `$` kısmi ad
  # eşleşmesi yerine KESİN alan erişimi (`[["id"]]`/`[["confidence"]]`) ve
  # sözleşme dışı anahtar reddi eklendi; ÖLÇÜLEN taban 304 -> 319. KÜRESEL
  # eşikler DEĞİŞMEDİ (fonksiyon sayısı aynı).
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 319 -> 323 satır (ÖLÇÜLEN).
  # NESNE biçimli `alternates` yanıtı artık reddedilir; `is.list()` hem dizi
  # hem nesne için TRUE olduğundan sözleşme dışı şekil geçerli sayılıyor ve
  # marj kapısı yanlış şekle göre ölçülüyordu. Fonksiyon sayısı AYNI.
  # BILINCLI GUNCELLEME (PR incelemesi): Gecis A ayristiricisi artik Gecis B ile
  # AYNI KATI ust duzey anahtar kumesini uyguluyor. Eskiden yalnizca aday takma
  # adlari okunuyor, `{"candidates":[...],"selected_id":"q009"}` gibi sema
  # kaymasi tasiyan yanit onarim yoluna gitmeden geciyordu.
  # BILINCLI GUNCELLEME (PR #715 inceleme): 344 -> 349 satir (OLCULEN). SIFIR
  # aday beklentisi reddedilir; alt sinir 0a dusup bos cevabi gecerli sayiyordu.
  assert_current_budget("R/helpers_pk_query_selection_parse.R", 349L, 8L)
  # PR #705 incelemesi: `not_for` ile dışlanan sorgu güven/marj kapılarından
  # ÖNCE reddedilir ve yetkin alternatifler AZALAN güvene göre sıralanır
  # (marj kapısı en güçlü rakibe karşı ölçülür). Taban çizgisi 400 -> 420.
  # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 420/10 -> 428/9 (OLCULEN).
  # `not_for` dislamasi BUTUN diger kurallardan ONCE gelir (Gecis B tek aday
  # bildirdiginde reddedilen sorgu chip olarak GERI TEKLIF ediliyordu); rakip
  # guveni ve `missing_info` alanlari SKALERE indirgenir.
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 428 -> 450 satır (ÖLÇÜLEN).
  # Marj kapısı artık KAPALI BAŞARISIZ olur: ikinci adayın güveni `NA` iken
  # `ikinci_guven < esik` karşılaştırması `NA` döndürüyor, `if()` dalı hiçbir
  # koşulu seçmiyor ve karar YAKIN MARJ uyarısı ÜRETMEDEN geçiyordu. Artık
  # açık bir `is.na()` dalı `PK_SELECT_STATUS_CLOSE_MARGIN` döndürür.
  # Fonksiyon sayısı ARTMAMIŞTIR.
  # BILINCLI GUNCELLEME (PR #715 inceleme): 499 -> 520 satir (OLCULEN).
  # (a) Uydurma kimlik temizligi kayit defteri YOKKEN kapiyi acmaz; (b) temiz
  # gereksinim saklanan nesneye de yazilir (Derin Dusunme alternatifleri);
  # (c) yetenek uyarisi erken cikislarda da bildirilir; (d) rakip filtresi
  # tavsiye kipinde secilen sorguyla AYNI olcutu kullanir. Fonksiyon AYNI.
  # BILINCLI GUNCELLEME (PR #715 inceleme, 2. tur): 520 -> 522 satir (OLCULEN).
  # Uydurma kimlik temizligi artik KAYIT DEFTERI YUKLU iken uygulanir; bos
  # izinli listede varlik-yalniz bir nesne de kanitsiz `auto` uretebiliyordu.
  assert_current_budget("R/helpers_pk_query_selection_decide.R", 522L, 10L)
  assert_current_budget("R/helpers_pk_query_selection_degraded.R", 190L, 7L)
  assert_current_budget("R/helpers_pk_query_selection_session.R", 220L, 14L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 kararlılık): Geçiş A TOPLAM yük bütçesi
  # aşıldığında kapalı başarısız olan dal eklendi (sessiz kırpma, görünmeyen
  # sorgu = geri alınamaz recall kaybı). Fonksiyon sayısı ARTMAMIŞTIR.
  #
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme): 578 -> 601 satır (ÖLÇÜLEN). Tek
  # nedeni GÜVENLİK kapısıdır: `unsupported_requirement` kapısı ÇİP ONAYI
  # yolunda YENİDEN uygulanır. Önceden `unsupported` SERBEST METİN olduğu için
  # dogrulayici `not_asserted` donuyor ve bir onceki turda REDDEDILMIS istek,
  # kullanici cip sectiginde `AUTO` + guven 100 olarak calisabiliyordu; karar
  # politikasinin 4. kurali BYPASS ediliyordu. Fonksiyon sayisi ARTMAMISTIR.
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 601 -> 611 satır (ÖLÇÜLEN).
  # İki neden: (a) Geçiş B yanıtı Geçiş A'nın DONDURDUĞU `bloklar$ids` kümesine
  # göre doğrulanır -- model küme dışı bir kimlik uydurduğunda eskiden sessizce
  # kabul ediliyordu; (b) iptal `PK_SELECT_STATUS_CANCELLED` dondurur.
  # Fonksiyon sayisi ARTMAMISTIR (22).
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 611 -> 613 satır (ÖLÇÜLEN).
  # Tohum (`seed`) artık KÜTÜPHANE kimlik kümesine göre doğrulanır; kütüphane
  # disi bir tohum eskiden gecerli secim gibi ilerliyordu. Fonksiyon sayisi
  # ARTMAMISTIR (22).
  # ÖLÇÜLEN DARALTMA (inceleme takibi): 613 -> 604 satır, 22 -> 21 fonksiyon.
  # Seçici zaman aşımı kararı `R/helpers_pk_select_timeout.R` ortak
  # yardımcısına taşındı; v1 ve v2 hatları artık AYNI sözleşmeyi kullanır.
  # BILINCLI GUNCELLEME (PR #705 inceleme): 604 -> 617 satir (OLCULEN).
  # Gecis B `malformed` durumunda operator bildirimi ARTIK eklenir; bu metin
  # yalnizca tipli basarisizlik yolunda uretiliyor ve onarim denemeleri
  # tukendiginde operatore HIC ulasmiyordu. Kullaniciya gosterilen Turkce
  # mesajlarin Latinlestirilmis yazimi da duzeltildi. Fonksiyon sayisi AYNI.
  # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 617/21 -> 622/22 (OLCULEN).
  # Onarim kapisi dogrulayiciyi YAKALAYICI ile cagirir: kacan bir istisna
  # istegi tipli `validator_error` reddi yerine `internal_error` yapiyordu.
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 622 -> 651 satır (ÖLÇÜLEN).
  # `pk_select_query_v2()` artık HEM Geçiş A HEM Geçiş B için `CANCELLED`
  # durumunu ERKEN döndürür. Önceden iptal edilen bir geçiş
  # `.pk_select_pass_failure_decision()` / `pk_retrieval_agreement()` yoluna
  # düşüyor, kullanıcı isteği DURDURMUŞ olmasına rağmen "başarısız seçim"
  # gerekçesi üretiliyor ve iptal, hata gibi raporlanıyordu.
  # Fonksiyon sayısı ARTMAMIŞTIR.
  # BILINCLI GUNCELLEME (PR #715 inceleme): 671 -> 678 satir (OLCULEN).
  # (a) Atlanan kimlik denetimi BOS kimlik listesinden ONCE gelir; (b) Gecis A
  # tabani kutuphane boyunu asmaz; (c) kirpma bilgisi bozuk cevapta da tasinir.
  # BILINCLI GUNCELLEME (PR #715 inceleme, 2. tur): 678 -> 682 satir (OLCULEN).
  # `blocks_clipped` artik zaman asimi / LLM erisilemez dallarinda da tasinir.
  assert_current_budget("R/helpers_pk_query_selection_ai.R", 682L, 22L)
  # BILINCLI GUNCELLEME (PR #705 inceleme takibi): 320/14 -> 328/15 (OLCULEN).
  # (a) Bayat teklif HER reddetmede temizlenir (cipsiz ret sonrasi "1" cevabi
  # ALAKASIZ sorguyu onayliyordu). (b) `||` operandlari uzunluk denetiminden
  # gecer. (c) Oturum, secim yoluyla AYNI sekilde cozulur.
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 328 -> 337 satır (ÖLÇÜLEN).
  # İptal metni artık yedekli çözülür: karar mesajı boş/`NA` geldiğinde
  # kullanıcıya sohbette birebir "NA" yazısı gösteriliyordu.
  # Fonksiyon sayısı ARTMAMIŞTIR.
  assert_current_budget("R/helpers_pk_query_selection_apply.R", 337L, 15L)

  # PR #705 dengeleme (inceleme borcu kök neden düzeltmeleri). Bu üç bütçe
  # ÖLÇÜLEN yeni tabanla güncellendi; hiçbir KÜRESEL eşik gevşetilmedi
  # (skor 100/100, 800+ satır 0, 25+ fonksiyon 0, en büyük dosya 795):
  #   * `json` 220 -> 240: ayristirici katiligi (kacis dizisi/kontrol karakteri
  #     dogrulamasi, yinelenen anahtar taramasinin dize-farkindaligi).
  #   * `ai` 520 -> 560 ve 21 -> 22: onaylanmis secim yolunun oturum durumu
  #     okumalari FAIL-SOFT sarmalandi (iki tryCatch isleyicisi).
  #   * `analysis_ai_selector` 140 -> 155: v1 seciciye tipli reddetme durumu.
  # v1 AI seçicisi modülden çıkarıldı (davranış BİREBİR); modül orkestrasyona
  # odaklı kalır ve 800 satır tavanına geri dayanmaz.
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 155 -> 167 satır (ÖLÇÜLEN).
  # Sorgu adi/aciklamasi SKALER'e indirgenir ve model yanitindaki indeks
  # `suppressWarnings(as.integer(...)[1])` ile korunur; cok elemanli bir ad ya
  # da sayisal olmayan bir indeks `if` icinde kosul uzunlugu hatasi firlatiyor
  # ve TUM secimi dusuruyordu. Fonksiyon sayisi AYNI (4).
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 167 -> 173 satır (ÖLÇÜLEN).
  # Liste degerli `match_id` `as.integer()` oncesi REDDEDILIR; aksi halde
  # coklu elemanli bir model yaniti kosul uzunlugu hatasi firlatiyordu.
  # Fonksiyon sayisi AYNI (4).
  # BİLİNÇLİ GÜNCELLEME (PR incelemesi): `confidence` için atomik denetim ve
  # `sprintf()` LİSTE argümanına karşı skaler metin indirgemesi eklendi
  # (sözleşme ihlali artık ISTISNAYA dönüşmüyor). Yerel `skaler_metin`
  # yardımcısı fonksiyon sayısını 4 -> 5 yaptı; ÖLÇÜLEN taban 173 -> 194.
  # KÜRESEL eşikler (24 fonksiyon / 796 satır) DEĞİŞMEDİ.
  # ÖLÇÜLEN DARALTMA (inceleme takibi): 194 -> 184 satır, 5 -> 4 fonksiyon.
  # Zaman aşımı bloğu ortak yardımcıya taşındı (bkz. aşağıdaki bütçe).
  assert_current_budget("R/helpers_pk_analysis_ai_selector.R", 184L, 4L)

  # Seçici HTTP zaman aşımı sözleşmesinin TEK kaynağı. Küçük ve saf kalmalıdır:
  # burada büyüme, kararın yeniden iki hatta dağılmaya başladığının işaretidir.
  assert_current_budget("R/helpers_pk_select_timeout.R", 70L, 5L)

  # Varlık manifesti VERİ/DOĞRULAYICI/RENDER olarak üç dosyaya bölündü
  # (config_ui_asset_zones.R deseni): config_ui_assets.R 690 satırdan VERİ-odaklı
  # dosyaya indi; çözümleyici/doğrulayıcı API'si config_ui_asset_validators.R'ye,
  # htmltools etiket render katmanı config_ui_asset_tags.R'ye taşındı. VERİ dosyası
  # düşük fonksiyon sayısında kilitlenir (fonksiyon mantığı geri sızmasını engeller);
  # bütçeler geri birleşmeyi ve büyümeyi yakalar.
  # 470L -> 485L bilinçli güncelleme: Bilge Savunması kule/2.5D/sahne/müzik
  # genişletmesi 5 yeni oyun JS dosyası (sim_kuleler, varliklar, cizim_zemin,
  # sahne) + ortak piksel çizici (pixel_sprite_render.js) manifeste eklendi.
  # Bu bir DATA-dosyası manifest genişlemesidir; fonksiyon sayısı 2L değişmedi
  # (load-order tek sahibi bu dosyadır, girdiler yardımcıya çıkarılamaz).
  # Bloklamayan dosya alım hattı: her katman tek sorumlulukta ve küçük kalmalı.
  # Saf plan / worker yürütme / kuyruk / ana süreç orkestrasyonu ayrımı geri
  # birleştirilmemelidir.
  assert_current_budget("R/helpers_file_ingestion_task.R", 240L, 10L)
  assert_current_budget("R/helpers_file_ingestion_worker.R", 250L, 13L)
  assert_current_budget("R/helpers_file_ingestion_queue.R", 220L, 20L)
  assert_current_budget("R/helpers_file_ingestion_runtime.R", 265L, 19L)

  assert_current_budget("R/config_ui_assets.R", 485L, 2L)
  assert_current_budget("R/config_ui_asset_validators.R", 300L, 13L)
  assert_current_budget("R/config_ui_asset_tags.R", 110L, 8L)
})

test_that("module_claude_code.R setup extraction kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  cc_row <- report[
    grepl("(^|/)R/module_claude_code\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(cc_row),
    1L,
    info = "R/module_claude_code.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_cc_lines <- .as_int_env("MERGEN_TEST_MAX_CLAUDE_CODE_LINES", 780L)

  expect_true(
    cc_row$lines[1] <= max_cc_lines,
    info = sprintf(
      "module_claude_code.R setup extraction sonrası küçülmüş kalmalıdır: %d > %d.",
      cc_row$lines[1],
      max_cc_lines
    )
  )
})

test_that("mevcut büyük ve fonksiyon yoğun dosya taban çizgileri sessizce büyümez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  assert_file_budget <- function(path, max_lines, max_functions) {
    row <- report[
      grepl(paste0("(^|/)", gsub("([.])", "\\\\\\1", path), "$"), report$file, perl = TRUE),
      ,
      drop = FALSE
    ]

    expect_equal(
      nrow(row),
      1L,
      info = sprintf("%s maintainability raporunda tek satır olarak görünmelidir.", path)
    )

    expect_true(
      row$lines[1] <= max_lines,
      info = sprintf("%s satır bütçesini aştı: %d > %d.", path, row$lines[1], max_lines)
    )

    expect_true(
      row$functions[1] <= max_functions,
      info = sprintf("%s fonksiyon bütçesini aştı: %d > %d.", path, row$functions[1], max_functions)
    )
  }

  # Renderer'lar *_outputs() dosyalarına çıkarıldıktan sonra modül tabanı düştü.
  assert_file_budget("R/module_admin_geri_bildirim.R", 90L, 3L)
  assert_file_budget("R/module_admin_geri_bildirim_outputs.R", 670L, 5L)
  assert_file_budget("R/helpers_admin_geri_bildirim_output_tables.R", 145L, 5L)
  assert_file_budget("R/module_admin_yanit_analizi.R", 140L, 4L)
  assert_file_budget("R/module_admin_yanit_analizi_outputs.R", 710L, 5L)
  assert_file_budget("R/helpers_admin_geri_bildirim_queries.R", 260L, 3L)
  # Sidebar kullanıcı paneli bölünmesi: saf görünüm yardımcıları
  # helpers_sidebar_user_display.R içindedir; modül Shiny orkestrasyonuna
  # odaklı kalır. 24-fonksiyon tavanına geri tırmanmayı engeller.
  assert_file_budget("R/module_sidebar_user_panel.R", 360L, 17L)
  assert_file_budget("R/helpers_sidebar_user_display.R", 320L, 11L)
  # config_api.R bölünmesi sonrası sıkılaştırılmış bütçe: Derin Düşünme yetenek
  # kaydı helpers_deep_thinking_model_capabilities.R, API anahtarı kripto katmanı
  # helpers_api_key_crypto.R içindedir; bu dosyaya geri taşınarak bütçe tüketilemez.
  assert_file_budget("R/config_api.R", 520L, 6L)
  assert_file_budget("R/helpers_deep_thinking_model_capabilities.R", 160L, 4L)
  assert_file_budget("R/helpers_api_key_crypto.R", 220L, 12L)
  assert_file_budget("R/helpers_api_model_config.R", 360L, 18L)
  assert_file_budget("R/helpers_llm_worker.R", 799L, 8L)
  assert_file_budget("R/helpers_llm_worker_tool_results.R", 260L, 2L)
  assert_file_budget("R/helpers_claude_code.R", 450L, 18L)
  # BİLİNÇLİ GÜNCELLEME (PR #705 inceleme takibi): 260 -> 264 satır (ÖLÇÜLEN).
  # `cc_list_dir_relaxed()` artık bloklayan `fs::dir_ls()` yedeğini ana Shiny
  # olay döngüsünde ÇALIŞTIRMAZ: `setTimeLimit()` askıda kalmış YERLİ bir
  # çağrıyı kesemez ve kopmuş bir UNC paylaşımı tüm oturumları dondurur.
  # KARARIN KENDİSİ bilerek bu dosyaya EKLENMEDİ; `dir_listing_async.R`
  # içindeki `cc_dir_listing_fs_fallback_allowed()` yardımcısına taşındı,
  # böylece fonksiyon bütçesi 19'da SABİT kaldı (artış YALNIZCA çağrı yeri).
  assert_file_budget("R/helpers_claude_code_directory_listing.R", 264L, 19L)
  # Bütçe: UNC ağ paylaşımı için runtime workdir yeniden kullanım yolu ve
  # fs::dir_ls fallback'i eklenince satır sayısı 240 -> ~325'e çıktı. Codex
  # P1 düzeltmesi (boyut sınırı nedeniyle atlanan GEREKLİ girdinin artık
  # sessizce yutulmayıp kopyalama hatası gibi raporlanması) 360 -> 365'e
  # çıkardı. İkinci Codex düzeltmesi (senkronizasyon sırasında kaynak/runtime
  # kökü kaybolursa - örn. koparılmış UNC paylaşımı - bunun artık sessiz
  # "başarılı boş sync" yerine açık başarısızlık olarak raporlanması) 365 ->
  # 385'e çıkardı.
  assert_file_budget("R/helpers_claude_code_runtime_workdir.R", 385L, 14L)
  assert_file_budget("R/helpers_claude_code_workdir_scan.R", 423L, 14L)
  assert_file_budget("R/helpers_claude_code_workdir_snapshot.R", 450L, 24L)
  assert_file_budget("R/helpers_db_chat_mutations.R", 420L, 24L)
  assert_file_budget("R/helpers_database.R", 320L, 12L)
  assert_file_budget("R/helpers_server_runtime_contracts.R", 160L, 7L)
  # SSO auth-ready / yenilenebilir modül wiring katmanı
  # R/server_runtime_auth_ready.R'ye ayrıldıktan sonra context dosyası
  # 687/17 -> 503/13'e indi. Bütçeler geri birleşmeyi ve büyümeyi kilitler.
  assert_file_budget("R/server_runtime_context.R", 540L, 15L)
  assert_file_budget("R/server_runtime_auth_ready.R", 290L, 6L)
  assert_file_budget("R/server_core_observer_runtime.R", 320L, 6L)
  assert_file_budget("R/server_core_interaction_runtime.R", 360L, 8L)
  assert_file_budget("R/helpers_chartlab.R", 577L, 24L)
  assert_file_budget("R/helpers_chartlab_spec.R", 220L, 12L)
  assert_file_budget("R/helpers_files_path.R", 220L, 18L)
  assert_file_budget("R/helpers_files.R", 260L, 24L)
})

test_that("module_file_manager.R state runtime extraction sonrası 800 satır altı kalır", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  fm_row <- report[
    grepl("(^|/)R/module_file_manager\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  helper_row <- report[
    grepl("(^|/)R/helpers_file_manager_state_runtime\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  upload_helper_row <- report[
    grepl("(^|/)R/helpers_file_manager_upload_runtime\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  delete_helper_row <- report[
    grepl("(^|/)R/helpers_file_manager_delete_runtime\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(fm_row),
    1L,
    info = "R/module_file_manager.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(helper_row),
    1L,
    info = "R/helpers_file_manager_state_runtime.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(upload_helper_row),
    1L,
    info = "R/helpers_file_manager_upload_runtime.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(delete_helper_row),
    1L,
    info = "R/helpers_file_manager_delete_runtime.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_fm_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_LINES", 560L)
  # 140L/3 -> 175L/7 bilinçli güncelleme: toplu yükleme artık olay döngüsünde
  # senkron for döngüsü çalıştırmıyor. Dosya, ortak alım hattına gönderim +
  # ana süreç commit'i + yükleme runtime fabrikası sorumluluğunu üstlendi;
  # pahalı doğrulama/kopyalama/bütünlük denetimi R/helpers_file_ingestion_*.R
  # dosyalarına taşındı. Bütçe yeni gerçek tabanı kilitler.
  max_upload_helper_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_UPLOAD_RUNTIME_LINES", 175L)
  max_upload_helper_functions <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_UPLOAD_RUNTIME_FUNCTIONS", 7L)
  max_helper_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_STATE_RUNTIME_LINES", 450L)
  max_helper_functions <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_STATE_RUNTIME_FUNCTIONS", 10L)
  max_delete_helper_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_DELETE_RUNTIME_LINES", 90L)
  max_delete_helper_functions <- .as_int_env("MERGEN_TEST_MAX_FILE_MANAGER_DELETE_RUNTIME_FUNCTIONS", 4L)

  expect_true(
    fm_row$lines[1] <= max_fm_lines,
    info = sprintf(
      "module_file_manager.R state runtime extraction sonrası 800 satır altı kalmalıdır: %d > %d.",
      fm_row$lines[1],
      max_fm_lines
    )
  )

  expect_true(
    helper_row$lines[1] <= max_helper_lines,
    info = sprintf(
      "helpers_file_manager_state_runtime.R küçük runtime helper dosyası olarak kalmalıdır: %d > %d.",
      helper_row$lines[1],
      max_helper_lines
    )
  )


  expect_true(
    upload_helper_row$lines[1] <= max_upload_helper_lines,
    info = sprintf(
      "helpers_file_manager_upload_runtime.R küçük toplu yükleme helper dosyası olarak kalmalıdır: %d > %d.",
      upload_helper_row$lines[1],
      max_upload_helper_lines
    )
  )

  expect_true(
    upload_helper_row$functions[1] <= max_upload_helper_functions,
    info = sprintf(
      "helpers_file_manager_upload_runtime.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      upload_helper_row$functions[1],
      max_upload_helper_functions
    )
  )

  expect_true(
    helper_row$functions[1] <= max_helper_functions,
    info = sprintf(
      "helpers_file_manager_state_runtime.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      helper_row$functions[1],
      max_helper_functions
    )
  )

  expect_true(
    delete_helper_row$lines[1] <= max_delete_helper_lines,
    info = sprintf(
      "helpers_file_manager_delete_runtime.R küçük silme helper dosyası olarak kalmalıdır: %d > %d.",
      delete_helper_row$lines[1],
      max_delete_helper_lines
    )
  )

  expect_true(
    delete_helper_row$functions[1] <= max_delete_helper_functions,
    info = sprintf(
      "helpers_file_manager_delete_runtime.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      delete_helper_row$functions[1],
      max_delete_helper_functions
    )
  )
})

test_that("helpers_llm_sse.R akış I/O ayrımı sonrası ince kalır", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  sse_row <- report[
    grepl("(^|/)R/helpers_llm_sse\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(sse_row),
    1L,
    info = "R/helpers_llm_sse.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_sse_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_SSE_LINES", 799L)
  max_sse_functions <- .as_int_env("MERGEN_TEST_MAX_LLM_SSE_FUNCTIONS", 24L)

  expect_true(
    sse_row$lines[1] <= max_sse_lines,
    info = sprintf(
      "helpers_llm_sse.R stream I/O ayrımı sonrası 800 satır altı kalmalıdır: %d > %d.",
      sse_row$lines[1],
      max_sse_lines
    )
  )

  expect_true(
    sse_row$functions[1] <= max_sse_functions,
    info = sprintf(
      "helpers_llm_sse.R fonksiyon sayısı stream I/O ayrımı sonrası 25 altı kalmalıdır: %d > %d.",
      sse_row$functions[1],
      max_sse_functions
    )
  )
})

test_that("helpers_llm_worker.R payload extraction kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  worker_row <- report[
    grepl("(^|/)R/helpers_llm_worker\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  payload_row <- report[
    grepl("(^|/)R/helpers_llm_worker_payload\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  tool_results_row <- report[
    grepl("(^|/)R/helpers_llm_worker_tool_results\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(worker_row),
    1L,
    info = "R/helpers_llm_worker.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(payload_row),
    1L,
    info = "R/helpers_llm_worker_payload.R maintainability raporunda tek satır olarak görünmelidir."
  )
  
  expect_equal(
    nrow(tool_results_row),
    1L,
    info = "R/helpers_llm_worker_tool_results.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_worker_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_LINES", 799L)
  max_payload_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_LINES", 320L)
  max_payload_functions <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_FUNCTIONS", 12L)
  max_tool_results_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_TOOL_RESULTS_LINES", 260L)
  max_tool_results_functions <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_TOOL_RESULTS_FUNCTIONS", 2L)

  expect_true(
    worker_row$lines[1] <= max_worker_lines,
    info = sprintf(
      "helpers_llm_worker.R payload extraction sonrası küçülmüş kalmalıdır: %d > %d.",
      worker_row$lines[1],
      max_worker_lines
    )
  )

  expect_true(
    payload_row$lines[1] <= max_payload_lines,
    info = sprintf(
      "helpers_llm_worker_payload.R küçük saf helper dosyası olarak kalmalıdır: %d > %d.",
      payload_row$lines[1],
      max_payload_lines
    )
  )

  expect_true(
    payload_row$functions[1] <= max_payload_functions,
    info = sprintf(
      "helpers_llm_worker_payload.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      payload_row$functions[1],
      max_payload_functions
    )
  )

  expect_true(
    tool_results_row$lines[1] <= max_tool_results_lines,
    info = sprintf(
      "helpers_llm_worker_tool_results.R küçük araç-sonuç helper dosyası olarak kalmalıdır: %d > %d.",
      tool_results_row$lines[1],
      max_tool_results_lines
    )
  )

  expect_true(
    tool_results_row$functions[1] <= max_tool_results_functions,
    info = sprintf(
      "helpers_llm_worker_tool_results.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      tool_results_row$functions[1],
      max_tool_results_functions
    )
  )
})

test_that("helpers_mcp_tools.R refactor kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  mcp_row <- report[grepl("(^|/)R/helpers_mcp_tools\\.R$", report$file, perl = TRUE), , drop = FALSE]

  expect_equal(
    nrow(mcp_row),
    1L,
    info = "R/helpers_mcp_tools.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_mcp_lines <- .as_int_env("MERGEN_TEST_MAX_MCP_TOOLS_LINES", 700L)
  max_mcp_functions <- .as_int_env("MERGEN_TEST_MAX_MCP_TOOLS_FUNCTIONS", 24L)

  expect_true(
    mcp_row$lines[1] <= max_mcp_lines,
    info = sprintf(
      "helpers_mcp_tools.R satır sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      mcp_row$lines[1],
      max_mcp_lines
    )
  )

  expect_true(
    mcp_row$functions[1] <= max_mcp_functions,
    info = sprintf(
      "helpers_mcp_tools.R fonksiyon sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      mcp_row$functions[1],
      max_mcp_functions
    )
  )
})

test_that("module_admin_geri_bildirim.R refactor kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  gb_row <- report[grepl("(^|/)R/module_admin_geri_bildirim\\.R$", report$file, perl = TRUE), , drop = FALSE]

  expect_equal(
    nrow(gb_row),
    1L,
    info = "R/module_admin_geri_bildirim.R maintainability raporunda tek satır olarak görünmelidir."
  )

  # Inline highcharter/DT renderer'lar R/module_admin_geri_bildirim_outputs.R'ye
  # çıkarıldıktan sonra modül 760 -> 55 satıra indi. Taban 799 -> 90.
  max_gb_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_LINES", 90L)
  max_gb_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_FUNCTIONS", 3L)

  expect_true(
    gb_row$lines[1] <= max_gb_lines,
    info = sprintf(
      "module_admin_geri_bildirim.R satır sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      gb_row$lines[1],
      max_gb_lines
    )
  )

  expect_true(
    gb_row$functions[1] <= max_gb_functions,
    info = sprintf(
      "module_admin_geri_bildirim.R fonksiyon sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      gb_row$functions[1],
      max_gb_functions
    )
  )
})

test_that("module_admin_hata_analizi.R helper extraction kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  hata_row <- report[
    grepl("(^|/)R/module_admin_hata_analizi\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(hata_row),
    1L,
    info = "R/module_admin_hata_analizi.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_hata_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_ANALIZI_LINES", 640L)

  expect_true(
    hata_row$lines[1] <= max_hata_lines,
    info = sprintf(
      "module_admin_hata_analizi.R detail runtime extraction sonrası küçük kalmalıdır: %d > %d.",
      hata_row$lines[1],
      max_hata_lines
    )
  )

  helper_row <- report[
    grepl("(^|/)R/helpers_admin_hata_analizi\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  heatmap_helper_row <- report[
    grepl("(^|/)R/helpers_admin_hata_heatmap_data\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  detail_runtime_row <- report[
    grepl("(^|/)R/helpers_admin_hata_detail_runtime\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(helper_row),
    1L,
    info = "R/helpers_admin_hata_analizi.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(heatmap_helper_row),
    1L,
    info = "R/helpers_admin_hata_heatmap_data.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(detail_runtime_row),
    1L,
    info = "R/helpers_admin_hata_detail_runtime.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_helper_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HELPER_LINES", 799L)
  max_helper_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HELPER_FUNCTIONS", 20L)
  max_heatmap_helper_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HEATMAP_HELPER_LINES", 120L)
  max_heatmap_helper_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HEATMAP_HELPER_FUNCTIONS", 2L)
  max_detail_runtime_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_DETAIL_RUNTIME_LINES", 380L)
  max_detail_runtime_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_DETAIL_RUNTIME_FUNCTIONS", 12L)

  expect_true(
    helper_row$lines[1] <= max_helper_lines,
    info = sprintf(
      "helpers_admin_hata_analizi.R 800 satır altı kalmalıdır: %d > %d.",
      helper_row$lines[1],
      max_helper_lines
    )
  )

  expect_true(
    helper_row$functions[1] <= max_helper_functions,
    info = sprintf(
      "helpers_admin_hata_analizi.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      helper_row$functions[1],
      max_helper_functions
    )
  )

  expect_true(
    heatmap_helper_row$lines[1] <= max_heatmap_helper_lines,
    info = sprintf(
      "helpers_admin_hata_heatmap_data.R küçük saf helper dosyası olarak kalmalıdır: %d > %d.",
      heatmap_helper_row$lines[1],
      max_heatmap_helper_lines
    )
  )

  expect_true(
    heatmap_helper_row$functions[1] <= max_heatmap_helper_functions,
    info = sprintf(
      "helpers_admin_hata_heatmap_data.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      heatmap_helper_row$functions[1],
      max_heatmap_helper_functions
    )
  )

  expect_true(
    detail_runtime_row$lines[1] <= max_detail_runtime_lines,
    info = sprintf(
      "helpers_admin_hata_detail_runtime.R küçük detay runtime helper dosyası olarak kalmalıdır: %d > %d.",
      detail_runtime_row$lines[1],
      max_detail_runtime_lines
    )
  )

  expect_true(
    detail_runtime_row$functions[1] <= max_detail_runtime_functions,
    info = sprintf(
      "helpers_admin_hata_detail_runtime.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      detail_runtime_row$functions[1],
      max_detail_runtime_functions
    )
  )
})

test_that("module_admin_yanit_analizi.R refactor kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  yanit_row <- report[
    grepl("(^|/)R/module_admin_yanit_analizi\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(yanit_row),
    1L,
    info = "R/module_admin_yanit_analizi.R maintainability raporunda tek satır olarak görünmelidir."
  )

  # Inline highcharter/DT renderer'lar R/module_admin_yanit_analizi_outputs.R'ye
  # çıkarıldıktan sonra modül 753 -> 106 satıra indi. Taban 799 -> 140.
  max_yanit_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_YANIT_ANALIZI_LINES", 140L)

  expect_true(
    yanit_row$lines[1] <= max_yanit_lines,
    info = sprintf(
      "module_admin_yanit_analizi.R refactor sonrası taban çizgisini aşmamalıdır: %d > %d.",
      yanit_row$lines[1],
      max_yanit_lines
    )
  )
})