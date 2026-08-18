# ==============================================================================
# Dosya Yolu: tools/pk/generate_query_meta.R
# Açıklama: Faz 3b -- SORGU METADATA ÜRETİCİSİ ve KÜTÜPHANE SAĞLIK RAPORU.
#
# YALNIZCA OPERATÖR ÇALIŞTIRIR. Windows VM'de, RStudio'da, DEPO KÖKÜNDEN:
#
#   Sys.setenv(MERGEN_PK_META_MODE = "describe")
#   source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
#
#   Sys.setenv(MERGEN_PK_META_MODE = "sample")
#   source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
#
# NE YAPAR:
#   1) Uygulama bootstrap'ini test kipinde yükler (Shiny BAŞLATILMAZ) ve gerçek
#      `query_library` ile yüklenmiş SQL'i alır.
#   2) Her sorgunun SONUÇ ŞEMASINI çıkarır:
#        describe -> sys.dm_exec_describe_first_result_set (SORGU ÇALIŞMAZ)
#        sample   -> imleçten yalnızca N satır (SQL SARMALANMAZ)
#   3) YAPISAL metadata üretir ve gitignore'lu R/library_query_meta_local.R
#      dosyasına ATOMİK yazar.
#   4) artifacts/pk-meta/<koşu>/ altına SAĞLIK RAPORU yazar.
#
# NE YAPMAZ:
#   * Üretim verisini DEĞİŞTİRMEZ (salt-okunur; kapı üretimle aynı).
#   * İzlenen metadata dosyalarına ve OPERATÖR ALIAS dosyasına YAZMAZ.
#   * ANLAMSAL yetenek (capability/grain/additive/unit) ÜRETMEZ.
#   * SQL'i ONARMAZ, RLS beyanını KALDIRMAZ, fail-closed kapıları ZAYIFLATMAZ.
#   * `quit()` ÇAĞIRMAZ; `source(...)` ile güvenle çalışır.
#
# YAZILAN DOSYALAR: metadata katmanı olarak YALNIZCA R/library_query_meta_local.R;
# ayrıca gitignore'lu denetim artefaktları (health.json / health.txt) ve devam
# durumu (generator-state.json). Bu üçü sırasıyla denetim ve kesinti dayanıklılığı
# için ZORUNLUDUR.
# ==============================================================================

local({

  # --- 0) Depo kökü kontrolü ---------------------------------------------------
  kok <- tryCatch(normalizePath(".", winslash = "/", mustWork = TRUE),
                  error = function(e) NA_character_)

  if (is.na(kok) || !file.exists(file.path(kok, "app.R")) ||
      !dir.exists(file.path(kok, "R"))) {
    stop(paste0(
      "[PK_META_GEN] Bu betik DEPO KOKUNDEN calistirilmalidir.\n",
      "  RStudio'da: setwd(\"<MERGEN Bilge klasoru>\") sonra tekrar deneyin."
    ), call. = FALSE)
  }

  cat("[PK_META_GEN] ==============================================================\n")
  cat("[PK_META_GEN] Faz 3b -- Sorgu metadata ureticisi ve saglik raporu\n")
  cat("[PK_META_GEN] ==============================================================\n")

  # --- 1) Yardımcıları yükle ---------------------------------------------------
  for (dosya in c(
    "helpers_meta_generator_config.R",
    "helpers_meta_generator_schema.R",
    "helpers_meta_generator_render.R",
    "helpers_meta_generator_findings.R",
    "helpers_meta_generator_health.R",
    "helpers_meta_generator_state.R",
    "helpers_meta_generator_db.R",
    "helpers_meta_generator_run.R",
    "helpers_meta_generator_commit.R"
  )) {
    source(file.path(kok, "tools", "pk", dosya), encoding = "UTF-8", local = FALSE)
  }

  yapilandirma <- pkg_meta_resolve_config(repo_root = kok)

  if (isTRUE(yapilandirma$mode_defaulted)) {
    cat(sprintf(paste0(
      "[PK_META_GEN] BILGI: MERGEN_PK_META_MODE ayarlanmamis; belgelenen ",
      "GUVENLI varsayilan '%s' kullaniliyor (uretim sorgulari CALISTIRILMAZ).\n"
    ), yapilandirma$mode))
    cat("[PK_META_GEN] Ornekleme istiyorsaniz ACIKCA secin:\n")
    cat("[PK_META_GEN]   Sys.setenv(MERGEN_PK_META_MODE = \"sample\")\n")
  }

  cat(sprintf("[PK_META_GEN] Kip: %s | Kosu: %s\n",
              yapilandirma$mode, yapilandirma$run_id))
  if (identical(yapilandirma$mode, "sample")) {
    cat(sprintf(
      "[PK_META_GEN] Ornek satir siniri: %d (yontem: prefix -- TEMSILI DEGILDIR)\n",
      yapilandirma$sample_rows
    ))
  }

  # --- 2) KOŞU KİLİDİ ----------------------------------------------------------
  # İki eş zamanlı koşu aynı çıktı dosyasını SON YAZAN KAZANIR biçimde ezerdi.
  kilit <- pkgc_acquire_run_lock(yapilandirma$lock_path)
  if (!isTRUE(kilit$ok)) {
    stop(paste0("[PK_META_GEN] ", kilit$detail), call. = FALSE)
  }
  on.exit(pkgc_release_run_lock(kilit), add = TRUE)

  # --- 3) Uygulama bootstrap'i (Shiny BAŞLATILMAZ) -----------------------------
  onceki_run <- Sys.getenv("MERGEN_RUN_APP", unset = NA_character_)
  onceki_fut <- Sys.getenv("MERGEN_DISABLE_FUTURES", unset = NA_character_)
  # `global.R` MERGEN_DISABLE_FUTURES=true iken `future::plan(sequential)`
  # ÇALIŞTIRIR. Yalnızca ortam değişkenini geri almak YETMEZ: operatörün
  # RStudio süreci, betik bittikten sonra da sıralı planda kalır ve aynı süreçte
  # çalışan sonraki işler paralel planlarını SESSİZCE kaybeder.
  onceki_plan <- if (requireNamespace("future", quietly = TRUE)) {
    tryCatch(future::plan(), error = function(e) NULL)
  } else {
    NULL
  }

  Sys.setenv(MERGEN_RUN_APP = "false", MERGEN_DISABLE_FUTURES = "true")
  on.exit({
    if (is.na(onceki_run)) Sys.unsetenv("MERGEN_RUN_APP") else Sys.setenv(MERGEN_RUN_APP = onceki_run)
    if (is.na(onceki_fut)) {
      Sys.unsetenv("MERGEN_DISABLE_FUTURES")
    } else {
      Sys.setenv(MERGEN_DISABLE_FUTURES = onceki_fut)
    }
    if (!is.null(onceki_plan)) {
      tryCatch(future::plan(onceki_plan), error = function(e) NULL)
    }
  }, add = TRUE)

  cat("[PK_META_GEN] Uygulama bootstrap'i yukleniyor (Shiny BASLATILMAZ)...\n")
  boot <- tryCatch({
    source(file.path(kok, "app.R"), encoding = "UTF-8", local = FALSE)
    TRUE
  }, error = function(e) conditionMessage(e))

  if (!isTRUE(boot)) {
    # BOOTSTRAP HATASI MASKELENİR: yapılandırma/bağlantı hataları DSN, sunucu,
    # kullanıcı ve yol ayrıntısı taşıyabilir; bunlar operatör loguna GİRMEZ.
    guvenli_hata <- pkgh_sanitize_validation_error(as.character(boot)[1])

    # BAYAT YEREL KATMANI TEMİZLE: bootstrap düşmeden ÖNCE bu dosyayı
    # `.GlobalEnv` içine YÜKLEMİŞ olabilir. Nesne kaldırılmazsa, dosya silinip
    # betik aynı oturumda tekrar çalıştırıldığında manifest eksik dosyayı
    # yalnızca ATLAR ve `pk_query_meta_attach()` HÂLÂ bayat katmanı görür.
    if (exists("pk_query_meta_local", envir = globalenv(), inherits = FALSE)) {
      tryCatch(rm("pk_query_meta_local", envir = globalenv()), error = function(e) NULL)
      cat("[PK_META_GEN] Bellekteki bayat pk_query_meta_local katmani temizlendi.\n")
    }

    # KATALOG TEŞHİSİ: başlangıç kapısı mükerrer/eksik sorgu kimliği gibi
    # KATALOG kusurlarında durur ve sağlık raporu tam da bunları listelemeyi
    # vaat eder. Bu yüzden ham kütüphane metadata kapısı OLMADAN okunur.
    ham_kutuphane <- pkgc_load_raw_query_library(kok)
    katalog <- pkgc_catalog_findings(ham_kutuphane)

    if (length(katalog)) {
      dir.create(yapilandirma$artifact_dir, recursive = TRUE, showWarnings = FALSE)
      ozet <- pkgh_summarize(katalog)
      tryCatch(pkgh_write_artifacts(
        report = list(
          generator = "tools/pk/generate_query_meta.R", phase = "3b",
          run_id = yapilandirma$run_id, timestamp = yapilandirma$timestamp,
          config = pkg_meta_config_summary(yapilandirma),
          local_layer_written = FALSE,
          startup_validation = "bootstrap_failed",
          startup_validation_error = guvenli_hata,
          summary = ozet, queries = katalog
        ),
        artifact_dir = yapilandirma$artifact_dir,
        records = katalog, summary = ozet,
        config_summary = pkg_meta_config_summary(yapilandirma)
      ), error = function(e) NULL)

      cat(sprintf(
        "[PK_META_GEN] KATALOG TESHISI yazildi (%d kusurlu sorgu): %s/health.txt\n",
        length(katalog), yapilandirma$artifact_rel
      ))
    }

    stop(paste0(
      "[PK_META_GEN] Uygulama bootstrap'i basarisiz; uretici calistirilamadi.\n",
      "  Hata (maskelenmis): ", guvenli_hata, "\n\n",
      "  SIK KARSILASILAN NEDEN: onceki bir uretici kosusundan kalan\n",
      "  R/library_query_meta_local.R dosyasi, o zamandan beri DEGISEN bir SQL\n",
      "  ile artik uyusmuyor olabilir (ornegin kuresyonun atif ettigi bir sutun\n",
      "  artik donmuyor). BU DURUMDA:\n",
      "    1) R/library_query_meta_local.R dosyasini yeniden adlandirin/silin,\n",
      "    2) bu betigi TEKRAR calistirin,\n",
      "    3) saglik raporundaki bulgulari duzeltin.\n",
      "  (Bu dosya gitignore'ludur; silmek Git gecmisini etkilemez. Bellekteki\n",
      "   bayat katman yukarida temizlendi; yine de sorun surerse R surecini\n",
      "   yeniden baslatin.)"
    ), call. = FALSE)
  }

  if (!exists("query_library", inherits = TRUE) || !is.list(query_library)) {
    stop("[PK_META_GEN] query_library yuklenemedi; bootstrap eksik.", call. = FALSE)
  }

  cat(sprintf("[PK_META_GEN] query_library yuklendi: %d sorgu.\n", length(query_library)))

  gerekli <- c("pk_sql_classify_readonly", "pk_meta_merge_layers",
               "pk_meta_validate_query", "pk_meta_validate_schema_dependent",
               "pk_meta_tier0_column_meta", "pk_query_meta_attach")
  eksik <- gerekli[!vapply(gerekli, function(ad) {
    exists(ad, mode = "function", inherits = TRUE)
  }, logical(1))]
  if (length(eksik)) {
    stop(sprintf("[PK_META_GEN] Gerekli calisma zamani yardimcilari eksik: %s",
                 paste(eksik, collapse = ", ")), call. = FALSE)
  }

  # --- 4) Katmanlar ------------------------------------------------------------
  auto_katman <- if (exists("pk_query_meta_auto", inherits = TRUE)) pk_query_meta_auto else list()
  kure_katman <- if (exists("pk_query_meta", inherits = TRUE)) pk_query_meta else list()
  kayit <- if (exists("pk_capability_registry", inherits = TRUE)) pk_capability_registry else list()
  alias_katman <- if (exists("pk_query_aliases_local", inherits = TRUE)) {
    pk_query_aliases_local
  } else {
    list()
  }

  # ÖNCEKİ KOŞUNUN İÇERİĞİ: app.R bootstrap'i mevcut yerel katmanı ZATEN
  # yüklediği için elimizdedir.
  onceki_katman <- if (exists("pk_query_meta_local", inherits = TRUE) &&
                       is.list(pk_query_meta_local)) {
    pk_query_meta_local
  } else {
    list()
  }

  # --- 5) Devam (resume) önbelleği --------------------------------------------
  parmak_izleri <- pkgh_state_fingerprints(query_library)
  onbellek <- if (isTRUE(yapilandirma$resume)) {
    pkgh_read_state(yapilandirma$state_path, yapilandirma$mode,
                    fingerprints = parmak_izleri,
                    state_version = yapilandirma$state_version)
  } else {
    list()
  }

  if (length(onbellek)) {
    cat(sprintf("[PK_META_GEN] Devam onbellegi: %d sorgu yeniden sorgulanmayacak.\n",
                length(onbellek)))
  }

  # --- 6) Artefakt dizini (çarpışmasız) ---------------------------------------
  yapilandirma$artifact_dir <- pkgh_allocate_artifact_dir(yapilandirma$artifact_dir)
  yapilandirma$artifact_rel <- file.path(
    PKG_META_ARTIFACT_DIR, basename(yapilandirma$artifact_dir)
  )

  # --- 7) Envanter koşusu ------------------------------------------------------
  cat("[PK_META_GEN] Envanter cikariliyor...\n")
  ilerleme <- function(i, n, id) {
    if (i %% 10L == 0L || i == n) {
      cat(sprintf("[PK_META_GEN]   %d/%d (%s)\n", i, n, id))
    }
  }

  # ARA KAYIT: koşu ortasında kesilirse, buraya kadarki başarılı sorgular
  # devam önbelleğinde KALIR. Yalnızca koşu sonunda yazmak, ilan edilen
  # "kaldığı yerden devam" davranışını gerçek bir kesinti için İŞLEVSİZ bırakır.
  ara_kayit <- function(cache) {
    pkgh_write_state(cache, yapilandirma$state_path, yapilandirma$mode,
                     yapilandirma$timestamp, yapilandirma$state_version)
  }

  kosu <- pkg_meta_run_inventory(
    query_library = query_library,
    config = yapilandirma,
    connect_fn = pkg_default_connect_fn,
    release_fn = pkg_default_release_fn,
    describe_fn = pkg_default_describe_fn,
    sample_fn = pkg_default_sample_fn,
    auto_layer = auto_katman,
    curated_layer = kure_katman,
    registry = kayit,
    cache = onbellek,
    progress_fn = ilerleme,
    alias_overlay = alias_katman,
    fingerprints = parmak_izleri,
    checkpoint_fn = ara_kayit
  )

  # --- 8) ADAY KATMAN: önceki içerikle BİRLEŞTİR -------------------------------
  birlesme <- pkgc_merge_local_layers(onceki_katman, kosu$local_meta, kosu$records)
  aday_katman <- birlesme$meta

  if (length(birlesme$kept)) {
    cat(sprintf(paste0(
      "[PK_META_GEN] %d sorgu bu kosuda sorgulanamadi; ONCEKI gecerli metadata'lari",
      " KORUNDU.\n"
    ), length(birlesme$kept)))
  }
  if (length(birlesme$withheld_removed)) {
    cat(sprintf(paste0(
      "[PK_META_GEN] %d sorgu bloklayici bulgu nedeniyle geri cekildi; onceki",
      " girdileri KALDIRILDI (bayat sozlesme birakilmaz).\n"
    ), length(birlesme$withheld_removed)))
  }

  # --- 9) BÜTÜN KÜTÜPHANE DOĞRULAMASI -----------------------------------------
  # Üretilen katman gerçekten yazılmadan ÖNCE, uygulamanın açılışta çalıştıracağı
  # AYNI kapıdan geçirilir. Böylece bir üretici koşusu uygulamayı ASLA kıramaz.
  cat("[PK_META_GEN] Aday katman baslangic kapisinda dogrulaniyor...\n")
  dogrulama <- tryCatch({
    pk_query_meta_attach(
      query_library,
      auto = auto_katman,
      local = aday_katman,
      curated = kure_katman,
      aliases = alias_katman,
      registry = kayit
    )
    TRUE
  }, error = function(e) conditionMessage(e))

  onceki_sayi <- length(onceki_katman)
  yeni_sayi <- length(aday_katman)

  # --- 10) Çıktı dosyasını HAZIRLA (henüz YAYIMLAMA) ---------------------------
  # Zorunlu denetim artefaktları YAZILMADAN üretimden türetilmiş metadata
  # devreye ALINMAZ; aksi hâlde operatör, incelemesi gereken sağlık raporu
  # olmadan yeni metadata ile uygulamayı açabilirdi.
  hazirlanan <- NULL
  yazma_engeli <- NA_character_

  if (!isTRUE(dogrulama)) {
    yazma_engeli <- "startup_validation_failed"
    cat("[PK_META_GEN] !!! Aday katman baslangic dogrulamasini GECEMEDI.\n")
    cat("[PK_META_GEN] !!! Dosya YAZILMADI; onceki durum korundu.\n")
    cat(sprintf("[PK_META_GEN] !!! Gerekce: %s\n",
                pkgh_sanitize_validation_error(as.character(dogrulama)[1])))
  } else if (yeni_sayi == 0L && onceki_sayi > 0L) {
    # FELAKET SİNYALİ: bu koşu HİÇBİR şema öğrenemedi ama önceki koşuda
    # geçerli metadata VARDI (DB erişilemez, DSN değişmiş, yetki kalkmış...).
    # Boş bir katman yazmak o metadata'yı YOK ETMEK olurdu.
    yazma_engeli <- "empty_layer_guard"
    cat(sprintf(paste0(
      "[PK_META_GEN] !!! Bu kosu HICBIR sorgu semasi cikaramadi, ancak onceki\n",
      "[PK_META_GEN] !!! uretilen katmanda %d sorgu vardi. Dosya YAZILMADI;\n",
      "[PK_META_GEN] !!! onceki GECERLI metadata korundu.\n",
      "[PK_META_GEN] !!! Once DB erisimini/DSN'i kontrol edin, sonra tekrar deneyin.\n"
    ), onceki_sayi))
  } else {
    metin <- pkgr_render_local_meta_file(aday_katman, list(
      mode = yapilandirma$mode,
      timestamp = yapilandirma$timestamp,
      artifact_rel = yapilandirma$artifact_rel
    ))
    hazirlanan <- tryCatch(
      pkgr_stage_local_meta_file(metin, yapilandirma$output_path, repo_root = kok),
      error = function(e) {
        yazma_engeli <<- "stage_failed"
        cat(sprintf("[PK_META_GEN] !!! Cikti hazirlanamadi: %s\n", conditionMessage(e)))
        NULL
      }
    )
  }

  # --- 11) Sağlık raporu artefaktları (YAYIMDAN ÖNCE) --------------------------
  ozet <- kosu$summary
  # ADAY ile GERÇEKTEN YAZILAN aynı şey DEĞİLDİR: bütün kütüphane kapısı
  # düşerse hiçbir şey yazılmaz, ama sorgu bazında `ok` kayıtları yine vardır.
  ozet$candidate_layer_entries <- yeni_sayi
  ozet$written_entries <- if (is.null(hazirlanan)) 0L else yeni_sayi
  ozet$previous_layer_entries <- onceki_sayi
  ozet$preserved_from_previous <- length(birlesme$kept)
  ozet$removed_withheld <- length(birlesme$withheld_removed)
  ozet$dropped_missing_from_library <- length(birlesme$dropped)

  ozet_yapilandirma <- pkg_meta_config_summary(yapilandirma)
  rapor <- list(
    generator = "tools/pk/generate_query_meta.R",
    phase = "3b",
    run_id = yapilandirma$run_id,
    timestamp = yapilandirma$timestamp,
    config = ozet_yapilandirma,
    local_layer_written = !is.null(hazirlanan),
    local_layer_write_block = yazma_engeli,
    startup_validation = if (isTRUE(dogrulama)) "passed" else "failed",
    # Doğrulama hatası, üretimden türetilmiş alias bindirmesinden gelen KANONİK
    # HEDEF değerleri taşıyabilir; rapora ham hâliyle GİRMEZ.
    startup_validation_error = if (isTRUE(dogrulama)) {
      NA_character_
    } else {
      pkgh_sanitize_validation_error(as.character(dogrulama)[1])
    },
    proof_boundary_notes = paste(
      "Bu artefakt YALNIZCA calistirilan adimlarin kanitidir.",
      "SQL Server disindaki hicbir sey (tarayici, SSO, LLM secim dogrulugu,",
      "uctan uca UX) bu rapor tarafindan KANITLANMAZ.",
      "Ornekleme yontemi 'prefix' oldugunda kardinalite/null/benzersizlik",
      "iddialari YALNIZCA tek yonlu gozlemlerle sinirlidir.",
      "Ornekleme satir siniri bir AKTARIM sinirdir; sunucu is yuku siniri DEGILDIR."
    ),
    summary = ozet,
    queries = kosu$records
  )

  artefakt_ok <- TRUE
  tryCatch(
    pkgh_write_artifacts(
      report = rapor,
      artifact_dir = yapilandirma$artifact_dir,
      records = kosu$records,
      summary = ozet,
      config_summary = ozet_yapilandirma
    ),
    error = function(e) {
      artefakt_ok <<- FALSE
      cat(sprintf("[PK_META_GEN] !!! Saglik raporu YAZILAMADI: %s\n", conditionMessage(e)))
    }
  )

  # --- 12) Çıktı dosyasını YAYIMLA --------------------------------------------
  yazildi <- FALSE
  if (!is.null(hazirlanan)) {
    if (!isTRUE(artefakt_ok)) {
      cat("[PK_META_GEN] !!! Denetim artefaktlari yazilamadigi icin uretilen katman\n")
      cat("[PK_META_GEN] !!! YAYIMLANMADI; onceki metadata korundu.\n")
      tryCatch(unlink(hazirlanan), error = function(e) NULL)
    } else {
      yazildi <- isTRUE(tryCatch({
        pkgr_publish_staged_file(hazirlanan, yapilandirma$output_path)
        TRUE
      }, error = function(e) {
        cat(sprintf("[PK_META_GEN] !!! Cikti yayimlanamadi: %s\n", conditionMessage(e)))
        FALSE
      }))

      if (yazildi) {
        cat(sprintf("[PK_META_GEN] YAZILDI: %s (%d sorgu)\n",
                    yapilandirma$output_rel, yeni_sayi))
        if (onceki_sayi > yeni_sayi) {
          # Azalma MEŞRU olabilir (sorgu kaldırıldı/düzeltildi) ama SESSİZ
          # GEÇMEMELİDİR: kısmi bir DB kesintisi de aynı şekilde görünür.
          cat(sprintf(paste0(
            "[PK_META_GEN] DIKKAT: uretilen sorgu sayisi AZALDI (%d -> %d).\n",
            "[PK_META_GEN]   Bu mesru olabilir (sorgu kaldirildi/duzeltildi) ya da\n",
            "[PK_META_GEN]   kismi bir erisim sorunu olabilir. Saglik raporundaki\n",
            "[PK_META_GEN]   'failed'/'skipped' sorgulari kontrol edin.\n"
          ), onceki_sayi, yeni_sayi))
        }
      }
    }
  }

  # --- 13) Devam durumunu son kez yaz -----------------------------------------
  if (!isTRUE(pkgh_write_state(kosu$cache, yapilandirma$state_path,
                               yapilandirma$mode, yapilandirma$timestamp,
                               yapilandirma$state_version))) {
    cat("[PK_META_GEN] UYARI: devam durumu YAZILAMADI; sonraki kosu bastan baslar.\n")
  }

  # --- 14) Konsol özeti ve sonraki adım ----------------------------------------
  cat(pkgh_render_console(ozet, kosu$records))
  cat(sprintf("[PK_META_GEN] Saglik raporu: %s/health.txt\n", yapilandirma$artifact_rel))
  cat(sprintf("[PK_META_GEN] Makine okunur : %s/health.json\n", yapilandirma$artifact_rel))
  cat(sprintf("[PK_META_GEN] Aday katman   : %d sorgu | YAZILAN: %d sorgu\n",
              yeni_sayi, ozet$written_entries))
  cat("[PK_META_GEN]\n")

  if (ozet$rls_mismatches > 0L) {
    cat("[PK_META_GEN] DURDURUCU: RLS beyani ile gercek sonuc uyusmuyor.\n")
    cat("[PK_META_GEN]   Once SQL'i ya da rls_columns beyanini duzeltin,\n")
    cat("[PK_META_GEN]   sonra ureticiyi TEKRAR calistirin.\n")
  }
  if (ozet$withheld > 0L) {
    cat(sprintf(paste0(
      "[PK_META_GEN] %d sorgu uretilen katmandan GERI CEKILDI (bloklayici bulgu).\n",
      "[PK_META_GEN]   Bu sorgular BUGUNKU davranislarinda kalir (Tier-0);\n",
      "[PK_META_GEN]   guvenlik ZAYIFLAMAZ, istek zamani RLS kapisi degismedi.\n"
    ), ozet$withheld))
  }
  if (yazildi && ozet$written_entries > 0L) {
    cat("[PK_META_GEN] SONRAKI ADIM: MERGEN Bilge'yi YENIDEN BASLATIN\n")
    cat("[PK_META_GEN]   (tarayici yenilemesi YETMEZ; R sureci yeniden baslamalidir).\n")
  }
  cat("[PK_META_GEN] ==============================================================\n")

  invisible(rapor)
})
