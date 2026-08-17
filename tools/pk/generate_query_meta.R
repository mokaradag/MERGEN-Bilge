# ==============================================================================
# Dosya Yolu: tools/pk/generate_query_meta.R
# Aciklama: Faz 3b -- SORGU METADATA URETICISI ve KUTUPHANE SAGLIK RAPORU.
#
# YALNIZCA OPERATOR CALISTIRIR. Windows VM'de, RStudio'da, DEPO KOKUNDEN:
#
#   Sys.setenv(MERGEN_PK_META_MODE = "describe")
#   source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
#
#   Sys.setenv(MERGEN_PK_META_MODE = "sample")
#   source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
#
# NE YAPAR:
#   1) Uygulama bootstrap'ini test kipinde yukler (Shiny BASLATILMAZ) ve gercek
#      `query_library` ile yuklenmis SQL'i alir.
#   2) Her sorgunun SONUC SEMASINI cikarir:
#        describe -> sys.dm_exec_describe_first_result_set (SORGU CALISMAZ)
#        sample   -> imleçten yalnizca N satir (SQL SARMALANMAZ)
#   3) YAPISAL metadata uretir ve gitignore'lu R/library_query_meta_local.R
#      dosyasina ATOMIK yazar.
#   4) artifacts/pk-meta/<zaman>/ altina SAGLIK RAPORU yazar.
#
# NE YAPMAZ:
#   * Uretim verisini DEGISTIRMEZ (salt-okunur; kapi uretimle ayni).
#   * Izlenen metadata dosyalarina ve OPERATOR ALIAS dosyasina YAZMAZ.
#   * ANLAMSAL yetenek (capability/grain/additive/unit) URETMEZ.
#   * SQL'i ONARMAZ, RLS beyanini KALDIRMAZ, fail-closed kapilari ZAYIFLATMAZ.
#   * `quit()` CAGIRMAZ; `source(...)` ile guvenle calisir.
# ==============================================================================

local({

  # --- 0) Depo koku kontrolu ---------------------------------------------------
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

  # --- 1) Yardimcilari yukle ---------------------------------------------------
  for (dosya in c(
    "helpers_meta_generator_config.R",
    "helpers_meta_generator_schema.R",
    "helpers_meta_generator_render.R",
    "helpers_meta_generator_health.R",
    "helpers_meta_generator_run.R"
  )) {
    source(file.path(kok, "tools", "pk", dosya), encoding = "UTF-8", local = FALSE)
  }

  yapilandirma <- pkg_meta_resolve_config(repo_root = kok)

  if (isTRUE(yapilandirma$mode_defaulted)) {
    cat(sprintf(paste0(
      "[PK_META_GEN] UYARI: MERGEN_PK_META_MODE ayarlanmamis; belgelenen ",
      "varsayilan '%s' kullaniliyor.\n"
    ), yapilandirma$mode))
    cat("[PK_META_GEN] ONERI: ILK kosuyu 'describe' ile yapin (sorgu CALISMAZ):\n")
    cat("[PK_META_GEN]   Sys.setenv(MERGEN_PK_META_MODE = \"describe\")\n")
  }

  cat(sprintf("[PK_META_GEN] Kip: %s\n", yapilandirma$mode))
  if (identical(yapilandirma$mode, "sample")) {
    cat(sprintf(
      "[PK_META_GEN] Ornek satir siniri: %d (yontem: prefix -- TEMSILI DEGILDIR)\n",
      yapilandirma$sample_rows
    ))
  }

  # --- 2) Uygulama bootstrap'i (Shiny BASLATILMAZ) -----------------------------
  onceki_run <- Sys.getenv("MERGEN_RUN_APP", unset = NA_character_)
  onceki_fut <- Sys.getenv("MERGEN_DISABLE_FUTURES", unset = NA_character_)
  Sys.setenv(MERGEN_RUN_APP = "false", MERGEN_DISABLE_FUTURES = "true")
  on.exit({
    if (is.na(onceki_run)) Sys.unsetenv("MERGEN_RUN_APP") else Sys.setenv(MERGEN_RUN_APP = onceki_run)
    if (is.na(onceki_fut)) {
      Sys.unsetenv("MERGEN_DISABLE_FUTURES")
    } else {
      Sys.setenv(MERGEN_DISABLE_FUTURES = onceki_fut)
    }
  }, add = TRUE)

  cat("[PK_META_GEN] Uygulama bootstrap'i yukleniyor (Shiny BASLATILMAZ)...\n")
  boot <- tryCatch({
    source(file.path(kok, "app.R"), encoding = "UTF-8", local = FALSE)
    TRUE
  }, error = function(e) conditionMessage(e))

  if (!isTRUE(boot)) {
    stop(paste0(
      "[PK_META_GEN] Uygulama bootstrap'i basarisiz; uretici calistirilamadi.\n",
      "  Hata: ", as.character(boot)[1], "\n\n",
      "  SIK KARSILASILAN NEDEN: onceki bir uretici kosusundan kalan\n",
      "  R/library_query_meta_local.R dosyasi, o zamandan beri DEGISEN bir SQL\n",
      "  ile artik uyusmuyor olabilir (ornegin kuresyonun atif ettigi bir sutun\n",
      "  artik donmuyor). BU DURUMDA:\n",
      "    1) R/library_query_meta_local.R dosyasini yeniden adlandirin/silin,\n",
      "    2) bu betigi TEKRAR calistirin,\n",
      "    3) saglik raporundaki bulgulari duzeltin.\n",
      "  (Bu dosya gitignore'ludur; silmek Git gecmisini etkilemez.)"
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

  # --- 3) Katmanlar ------------------------------------------------------------
  auto_katman <- if (exists("pk_query_meta_auto", inherits = TRUE)) pk_query_meta_auto else list()
  kure_katman <- if (exists("pk_query_meta", inherits = TRUE)) pk_query_meta else list()
  kayit <- if (exists("pk_capability_registry", inherits = TRUE)) pk_capability_registry else list()

  # --- 4) Devam (resume) onbellegi --------------------------------------------
  onbellek <- if (isTRUE(yapilandirma$resume)) {
    pkgh_read_state(yapilandirma$state_path, yapilandirma$mode)
  } else {
    list()
  }

  if (length(onbellek)) {
    cat(sprintf("[PK_META_GEN] Devam onbellegi: %d sorgu yeniden sorgulanmayacak.\n",
                length(onbellek)))
  }

  # --- 5) Envanter kosusu ------------------------------------------------------
  cat("[PK_META_GEN] Envanter cikariliyor...\n")
  ilerleme <- function(i, n, id) {
    if (i %% 10L == 0L || i == n) {
      cat(sprintf("[PK_META_GEN]   %d/%d (%s)\n", i, n, id))
    }
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
    progress_fn = ilerleme
  )

  # --- 6) BUTUN KUTUPHANE DOGRULAMASI -----------------------------------------
  # Uretilen katman gercekten yazilmadan ONCE, uygulamanin acilista calistiracagi
  # AYNI kapidan gecirilir. Boylece bir uretici kosusu uygulamayi ASLA kiramaz.
  cat("[PK_META_GEN] Uretilen katman baslangic kapisinda dogrulaniyor...\n")
  dogrulama <- tryCatch({
    pk_query_meta_attach(
      query_library,
      auto = auto_katman,
      local = kosu$local_meta,
      curated = kure_katman,
      aliases = if (exists("pk_query_aliases_local", inherits = TRUE)) {
        pk_query_aliases_local
      } else {
        list()
      },
      registry = kayit
    )
    TRUE
  }, error = function(e) conditionMessage(e))

  # ONCEKI KOSUNUN ICERIGI: app.R bootstrap'i mevcut yerel katmani ZATEN
  # yukledigi icin onceki girdi sayisi elimizde.
  onceki_sayi <- if (exists("pk_query_meta_local", inherits = TRUE) &&
                     is.list(pk_query_meta_local)) {
    length(pk_query_meta_local)
  } else {
    0L
  }
  yeni_sayi <- length(kosu$local_meta)

  yazildi <- FALSE
  if (!isTRUE(dogrulama)) {
    cat("[PK_META_GEN] !!! Uretilen katman baslangic dogrulamasini GECEMEDI.\n")
    cat("[PK_META_GEN] !!! Dosya YAZILMADI; onceki durum korundu.\n")
    cat(sprintf("[PK_META_GEN] !!! Gerekce: %s\n", as.character(dogrulama)[1]))
  } else if (yeni_sayi == 0L && onceki_sayi > 0L) {
    # FELAKET SINYALI: bu kosu HICBIR sema ogrenemedi ama onceki kosuda
    # gecerli metadata VARDI (DB erisilemez, DSN degismis, yetki kalkmis...).
    # Bos bir katman yazmak o metadata'yi YOK ETMEK olurdu.
    cat(sprintf(paste0(
      "[PK_META_GEN] !!! Bu kosu HICBIR sorgu semasi cikaramadi, ancak onceki\n",
      "[PK_META_GEN] !!! uretilen katmanda %d sorgu vardi. Dosya YAZILMADI;\n",
      "[PK_META_GEN] !!! onceki GECERLI metadata korundu.\n",
      "[PK_META_GEN] !!! Once DB erisimini/DSN'i kontrol edin, sonra tekrar deneyin.\n"
    ), onceki_sayi))
  } else {
    metin <- pkgr_render_local_meta_file(kosu$local_meta, list(
      mode = yapilandirma$mode,
      timestamp = yapilandirma$timestamp,
      artifact_rel = yapilandirma$artifact_rel
    ))
    pkgr_write_local_meta_file(metin, yapilandirma$output_path)
    yazildi <- TRUE
    cat(sprintf("[PK_META_GEN] YAZILDI: %s (%d sorgu)\n",
                yapilandirma$output_rel, yeni_sayi))

    if (onceki_sayi > yeni_sayi) {
      # Azalma MESRU olabilir (sorgu kaldirildi/duzeltildi) ama SESSIZ
      # GECMEMELIDIR: kismi bir DB kesintisi de ayni sekilde gorunur.
      cat(sprintf(paste0(
        "[PK_META_GEN] DIKKAT: uretilen sorgu sayisi AZALDI (%d -> %d).\n",
        "[PK_META_GEN]   Bu mesru olabilir (sorgu kaldirildi/duzeltildi) ya da\n",
        "[PK_META_GEN]   kismi bir erisim sorunu olabilir. Saglik raporundaki\n",
        "[PK_META_GEN]   'failed'/'skipped' sorgulari kontrol edin.\n"
      ), onceki_sayi, yeni_sayi))
    }
  }

  # --- 7) Saglik raporu artefaktlari ------------------------------------------
  dir.create(yapilandirma$artifact_dir, recursive = TRUE, showWarnings = FALSE)

  ozet_yapilandirma <- pkg_meta_config_summary(yapilandirma)
  rapor <- list(
    generator = "tools/pk/generate_query_meta.R",
    phase = "3b",
    timestamp = yapilandirma$timestamp,
    config = ozet_yapilandirma,
    local_layer_written = yazildi,
    startup_validation = if (isTRUE(dogrulama)) "passed" else "failed",
    startup_validation_error = if (isTRUE(dogrulama)) NA_character_ else as.character(dogrulama)[1],
    proof_boundary_notes = paste(
      "Bu artefakt YALNIZCA calistirilan adimlarin kanitidir.",
      "SQL Server disindaki hicbir sey (tarayici, SSO, LLM secim dogrulugu,",
      "uctan uca UX) bu rapor tarafindan KANITLANMAZ.",
      "Ornekleme yontemi 'prefix' oldugunda kardinalite/null/benzersizlik",
      "iddialari YALNIZCA tek yonlu gozlemlerle sinirlidir."
    ),
    summary = kosu$summary,
    queries = kosu$records
  )

  pkgh_write_artifacts(
    report = rapor,
    artifact_dir = yapilandirma$artifact_dir,
    records = kosu$records,
    summary = kosu$summary,
    config_summary = ozet_yapilandirma
  )

  pkgh_write_state(kosu$cache, yapilandirma$state_path,
                   yapilandirma$mode, yapilandirma$timestamp)

  # --- 8) Konsol ozeti ve sonraki adim ----------------------------------------
  cat(pkgh_render_console(kosu$summary, kosu$records))
  cat(sprintf("[PK_META_GEN] Saglik raporu: %s/health.txt\n", yapilandirma$artifact_rel))
  cat(sprintf("[PK_META_GEN] Makine okunur : %s/health.json\n", yapilandirma$artifact_rel))
  cat("[PK_META_GEN]\n")

  if (kosu$summary$rls_mismatches > 0L) {
    cat("[PK_META_GEN] DURDURUCU: RLS beyani ile gercek sonuc uyusmuyor.\n")
    cat("[PK_META_GEN]   Once SQL'i ya da rls_columns beyanini duzeltin,\n")
    cat("[PK_META_GEN]   sonra ureticiyi TEKRAR calistirin.\n")
  }
  if (kosu$summary$withheld > 0L) {
    cat(sprintf(paste0(
      "[PK_META_GEN] %d sorgu uretilen katmandan GERI CEKILDI (bloklayici bulgu).\n",
      "[PK_META_GEN]   Bu sorgular BUGUNKU davranislarinda kalir (Tier-0);\n",
      "[PK_META_GEN]   guvenlik ZAYIFLAMAZ, istek zamani RLS kapisi degismedi.\n"
    ), kosu$summary$withheld))
  }
  if (yazildi && kosu$summary$included > 0L) {
    cat("[PK_META_GEN] SONRAKI ADIM: MERGEN Bilge'yi YENIDEN BASLATIN\n")
    cat("[PK_META_GEN]   (tarayici yenilemesi YETMEZ; R sureci yeniden baslamalidir).\n")
  }
  cat("[PK_META_GEN] ==============================================================\n")

  invisible(rapor)
})
