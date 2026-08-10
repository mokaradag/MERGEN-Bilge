# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_bootstrap.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ BOOTSTRAP sözleşmesi, oturum vekili ve işçiye
#           taşınacak globals paketi.
#
# Bu dosya `R/helpers_pk_async_request.R` içinden BÖLÜNMÜŞTÜR: tek dosya bakım
# ratchet'inin 25-fonksiyon tavanını tüketiyordu. Ayrım aynı zamanda daha iyi
# bir sınır: "işçiyi nasıl ayağa kaldırırım" ile "işçiye ne veri gider" farklı
# sorumluluklardır.
#
# SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ. Yalnızca dosya sistemi (bootstrap
# kaynak yükleme) ve düz veri işler.
# ==============================================================================


# İşçinin çalıştırmak için ihtiyaç duyduğu manifest BÖLÜMLERİ. Dosya listesi
# değil BÖLÜM listesi donmuştur: böylece bir bölüme yeni yardımcı eklendiğinde
# işçi otomatik olarak onu da alır (sürüklenme yok), ama işçinin GÖREBİLECEĞİ
# yüzey açıkça gözden geçirilebilir kalır.
#
# UI/modül/gözlemci bölümleri BİLİNÇLİ OLARAK DIŞARIDADIR: işçide Shiny yoktur.
# Tek istisna, aşağıdaki dosya-listesi kurucusunda açıkça eklenen gerçek PK giriş
# dosyasıdır (`module_proje_kaynak_analizi.R`). Böylece bütün module_analysis
# bölümünü worker yüzeyine açmadan `pk_analiz_process_request()` yüklenir.
pk_async_worker_manifest_sections <- function() {
  c(
    "foundation",
    "post_future_utils",
    "config_app_core",
    "config_api_model_keys",
    "database",
    "pk_query_metadata",
    "sql_library",
    "language_messaging",
    "analysis_helpers",
    "llm_pipeline"
  )
}

#' İşçi bootstrap dosya listesi (ana süreçte, manifestten türetilir)
#'
#' @param sections Bölüm adları (varsayılan: donmuş liste).
#' @param manifest `source_manifest_sections` (test için enjekte edilebilir).
#' @return Repo köküne göreli dosya yolları; sıra manifest sırasıdır
#'   (BAĞIMLILIK SIRASI KORUNUR).
pk_async_worker_bootstrap_files <- function(sections = NULL, manifest = NULL) {
  varsayilan <- is.null(sections)
  bolumler <- if (varsayilan) pk_async_worker_manifest_sections() else as.character(sections)

  if (is.null(manifest)) {
    if (!exists("source_manifest_sections", inherits = TRUE)) return(character(0))
    manifest <- get("source_manifest_sections", inherits = TRUE)
  }
  if (!is.list(manifest)) return(character(0))

  yollar <- character(0)
  for (bolum in bolumler) {
    dosyalar <- manifest[[bolum]]
    if (is.null(dosyalar)) next
    yollar <- c(yollar, as.character(dosyalar))
  }

  # Worker'ın gerçek giriş noktası runtime manifestinde module_analysis içinde
  # yaşar. Bölümün tamamını izinli bölüm listesine katmak yerine yalnızca bu
  # sahip dosya, varsayılan worker yüzeyinde explicit olarak eklenir.
  if (isTRUE(varsayilan)) {
    giris <- as.character(manifest[["module_analysis"]] %||% character(0))
    giris <- giris[basename(giris) == "module_proje_kaynak_analizi.R"]
    yollar <- c(yollar, giris)
    # Ana süreçte `server_*` katmanının kurduğu PK gözlemci sarmalayıcıları
    # işçide de gereklidir; aksi hâlde asenkron istekler yalnızca bayrak açık
    # diye doğrudan-çıkış telemetrisini ve v2 derin gözlemci kapsamını kaybeder.
    # Shiny wiring İŞÇİYE GİRMEZ: sarmalayıcılar bu tek amaçlı dosyadadır.
    yollar <- c(yollar, "R/helpers_pk_worker_observers.R")
  }

  # Manifest sırası korunur; yalnızca yinelenenler (bölümler arası) tekilleşir.
  unique(yollar)
}

# İşçide BULUNMASI ZORUNLU dosyalar. Diğer manifest girdilerinin yokluğu
# (ör. VM'e özel opsiyonel metadata) NORMALDİR; ama bu dosyalar eksikken
# bootstrap "başarılı" raporlarsa, derin bir istek sessizce standart boru
# hattına düşer ve kullanıcı hiç istemediği bir analizi alır.
pk_async_worker_required_files <- function() {
  c(
    "R/module_proje_kaynak_analizi.R",
    "R/helpers_deep_analysis.R",
    "R/helpers_pk_sql_execute.R",
    "R/helpers_pk_analysis_security_summary.R"
  )
}

# Kaynak parmak izi: kalıcı bir PSOCK işçisi ilk yüklediği uygulamayı işçi
# ömrü boyunca saklar. `global.R` yeniden source edildiğinde ana süreç YENİ
# kodu çalıştırırken bootstrap edilmiş her işçi ESKİ kodu çalıştırmaya devam
# ederdi. Parmak izi (dosya listesi + mtime + boyut) değiştiğinde önbellek
# geçersizleşir ve işçi yeniden yüklenir.
.pk_async_bootstrap_fingerprint <- function(repo_root, files) {
  tam <- file.path(repo_root, files)
  bilgi <- suppressWarnings(file.info(tam))
  parcalar <- paste(
    files,
    if (is.data.frame(bilgi)) as.numeric(bilgi$mtime) else NA_real_,
    if (is.data.frame(bilgi)) bilgi$size else NA_real_,
    sep = ":"
  )
  ham <- paste(parcalar, collapse = "|")
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(ham, algo = "sha256"))
  }
  paste0(length(files), ":", nchar(ham), ":", sum(utf8ToInt(ham)) %% .Machine$integer.max)
}

# İşçi bootstrap'ının SÜREÇ BAŞINA bir kez çalıştığını işaretleyen yuva adı.
# İşçinin global ortamında tutulur; ana süreçte de aynı ad kullanılır ama ana
# süreç zaten yüklü olduğu için bootstrap NO-OP'tur.
.PK_ASYNC_BOOTSTRAP_FLAG <- ".mergen_pk_async_bootstrapped"

#' İşçi tarafında gerekli yardımcıları SÜREÇ BAŞINA BİR KEZ yükle
#'
#' PSOCK işçilerinde uygulama kaynak yüklü DEĞİLDİR; explicit-mode future
#' yalnızca verilen globals'ı taşır. Yüzlerce fonksiyonu tek tek saymak
#' sürüklenmeye açıktır; bunun yerine işçi, DONMUŞ bölüm listesindeki dosyaları
#' kendi global ortamına yükler. `R/helpers_mcp_bootstrap.R` ile aynı desen.
#'
#' @param repo_root Repo kökü (ana süreçten taşınır; `getwd()` VARSAYILMAZ).
#' @param files Repo köküne göreli dosya yolları.
#' @return `list(ok = TRUE/FALSE, loaded = <int>, failed = <chr>, cached = TRUE/FALSE)`.
pk_async_worker_bootstrap <- function(repo_root, files,
                                      required_files = pk_async_worker_required_files()) {
  hedef <- globalenv()

  kok <- tryCatch(as.character(repo_root)[1], error = function(e) NA_character_)
  if (is.na(kok) || !nzchar(kok) || !dir.exists(kok)) {
    return(list(ok = FALSE, loaded = 0L, failed = "repo_root", cached = FALSE))
  }

  dosyalar <- as.character(files %||% character(0))
  if (!length(dosyalar)) {
    return(list(ok = FALSE, loaded = 0L, failed = "empty_file_list", cached = FALSE))
  }

  parmak <- tryCatch(.pk_async_bootstrap_fingerprint(kok, dosyalar),
                     error = function(e) NA_character_)
  onceki <- get0(.PK_ASYNC_BOOTSTRAP_FLAG, envir = hedef, ifnotfound = NULL)
  if (!is.null(onceki) && !is.na(parmak) && identical(as.character(onceki)[1], parmak)) {
    return(list(ok = TRUE, loaded = 0L, failed = character(0), cached = TRUE))
  }

  # `config_sql_loader.R` göreli `sql_file` yollarını `getwd()` üzerinden
  # çözer. Ana süreç `MERGEN_REPO_ROOT` verdiğinde işçinin çalışma dizini
  # BAŞKA BİR YER olabilir; o zaman dosyalar yüklenir ama SQL kütüphanesi
  # bulunamaz. Bootstrap süresince çalışma dizini repo köküne alınır.
  eski_wd <- tryCatch(getwd(), error = function(e) NULL)
  wd_degisti <- FALSE
  if (!is.null(eski_wd) && !identical(normalizePath(eski_wd, winslash = "/", mustWork = FALSE),
                                      normalizePath(kok, winslash = "/", mustWork = FALSE))) {
    wd_degisti <- isTRUE(tryCatch({ setwd(kok); TRUE }, error = function(e) FALSE))
  }
  if (isTRUE(wd_degisti)) on.exit(try(setwd(eski_wd), silent = TRUE), add = TRUE)

  # Kaynak-zamanı yan etkileri (tüm uygulama paket setinin attach edilmesi,
  # günlük log dosyası + sahte "uygulama başladı" başlığı) İŞÇİDE İSTENMEZ.
  eski_mod <- Sys.getenv("MERGEN_PK_WORKER_BOOTSTRAP", unset = NA_character_)
  Sys.setenv(MERGEN_PK_WORKER_BOOTSTRAP = "true")
  on.exit({
    if (is.na(eski_mod)) Sys.unsetenv("MERGEN_PK_WORKER_BOOTSTRAP")
    else Sys.setenv(MERGEN_PK_WORKER_BOOTSTRAP = eski_mod)
  }, add = TRUE)

  zorunlu <- as.character(required_files %||% character(0))
  yuklenen <- 0L
  basarisiz <- character(0)

  for (goreli in dosyalar) {
    tam <- file.path(kok, goreli)
    if (!file.exists(tam)) {
      # Opsiyonel katmanlar (ör. VM'e özel metadata dosyaları) yokluğu NORMALDİR;
      # ama ZORUNLU giriş dosyalarının yokluğu bootstrap başarısızlığıdır.
      if (basename(goreli) %in% basename(zorunlu)) {
        basarisiz <- c(basarisiz, paste0(goreli, " (eksik)"))
      }
      next
    }

    ok <- tryCatch({
      suppressWarnings(suppressMessages(
        sys.source(tam, envir = hedef, keep.source = FALSE)
      ))
      TRUE
    }, error = function(e) FALSE)

    if (isTRUE(ok)) yuklenen <- yuklenen + 1L else basarisiz <- c(basarisiz, goreli)
  }

  eksik_zorunlu <- setdiff(basename(zorunlu), basename(dosyalar))
  if (length(eksik_zorunlu) > 0L) {
    basarisiz <- c(basarisiz, paste0(eksik_zorunlu, " (listede yok)"))
  }

  if (length(basarisiz) > 0L) {
    return(list(ok = FALSE, loaded = yuklenen, failed = basarisiz, cached = FALSE))
  }

  assign(.PK_ASYNC_BOOTSTRAP_FLAG, parmak %||% TRUE, envir = hedef)
  list(ok = TRUE, loaded = yuklenen, failed = character(0), cached = FALSE)
}

#' İşçinin ihtiyaç duyduğu MİNİMUM giriş noktalarının varlığını doğrula
#'
#' Bootstrap "hata vermedi" ile "boru hattı çalıştırılabilir" AYNI ŞEY DEĞİLDİR.
pk_async_worker_entry_points <- function() {
  c(
    "pk_analiz_process_request",
    # Derin istek işçiye geldiğinde bu giriş noktası YOKSA, standart boru
    # hattına sessizce düşmek kullanıcıya istemediği bir analizi vermek olurdu.
    "pk_deep_analysis_process",
    "pk_sql_execute_bounded",
    "get_connection",
    "release_connection",
    "resolve_pk_analysis_username",
    "pk_sql_readonly_guard",
    "apply_rls_to_data"
  )
}

pk_async_worker_ready <- function(entry_points = NULL) {
  noktalar <- entry_points %||% pk_async_worker_entry_points()
  eksik <- noktalar[!vapply(
    noktalar,
    function(fn) exists(fn, mode = "function", inherits = TRUE),
    logical(1)
  )]
  list(ready = length(eksik) == 0L, missing = eksik)
}

# ------------------------------------------------------------------------------
# İŞÇİ TARAFI OTURUM VEKİLİ
# ------------------------------------------------------------------------------

#' İşçi içinde düz anlık görüntüden oturum vekili kur
#'
#' `userData` bir ORTAMDIR (liste değil): boru hattı yardımcıları oraya yazar
#' (seçim durumu, köken alt bilgisi) ve iş bittiğinde ana süreç bu yazımları
#' geri toplar. Liste kullanılsaydı kopya semantiği yüzünden yazımlar sessizce
#' kaybolurdu.
#'
#' Ortak Oturum köprüsü de aynı deseni kullanır (`list(userData = ...)`).
pk_async_worker_session <- function(request) {
  ud <- new.env(parent = emptyenv())

  anlik <- if (is.list(request$user_session)) request$user_session else list()
  for (alan in names(anlik)) ud[[alan]] <- anlik[[alan]]

  kullanici <- as.character(request$username %||% "")[1]
  if (nzchar(kullanici)) ud$system_username <- kullanici

  # SSO hazırlığı ANA SÜREÇTE doğrulandı; işçi bunu yeniden yapamaz (DB kimliği
  # yok). Vekil bu yüzden hazır olarak işaretlenir ve kullanıcı adı ZORUNLUDUR.
  ud$auth_initialized <- TRUE

  # Kişisel anahtar yalnızca gerçekten kişisel çözüldüyse taşınır; sahiplik
  # işareti de birlikte konur ki ownership denetimi birebir aynı kararı versin.
  anahtar <- as.character(request$api_key %||% "")[1]
  if (nzchar(anahtar) && nzchar(kullanici)) {
    ud$ai_api_key <- anahtar
    ud$ai_api_key_owner <- kullanici
  }

  # Seçim durumu (eksiltili takip sorusu kimliği) taşınır.
  if (is.list(request$select_state) && length(request$select_state) > 0L) {
    ud[["pk_select_state"]] <- request$select_state
  }

  # Köken alt bilgisi istek kimliğine bağlıdır; vekilde de aynı kimlik olmalı.
  istek <- as.character(request$request_id %||% "")[1]
  if (nzchar(istek)) ud[["pk_provenance_request_id"]] <- istek

  list(userData = ud, token = istek)
}

# İş bittiğinde ana sürece geri taşınacak oturum yazımları.
.PK_ASYNC_HARVEST_SLOTS <- c(
  "pk_select_state",
  "pk_provenance_pending"
)

#' İŞÇİ TARAFINDA üretilmiş dışa aktarım artifact'ini yerelde sil
#'
#' Bir çalıştırma, iptal/son tarih GÖZLENMEDEN önce büyük bir XLSX/CSV dosyası
#' üretmiş olabilir. Sonuç düşürüldüğünde ana sürecin temizleyecek bir yol
#' listesi kalmaz; dosya işçinin kalıcı temp dizininde ÖKSÜZ kalır. Bu yüzden
#' halt yolunda dosya İŞÇİDE silinir.
#'
#' Ana süreçteki `mergen_pk_cleanup_worker_artifact()` ile aynı işi yapar ama
#' işçi bootstrap yüzeyindedir (server katmanı işçiye yüklenmez).
pk_async_discard_worker_artifact <- function(result) {
  if (!is.list(result) || !is.list(result$pk_attachment)) return(invisible(FALSE))
  dosyalar <- result$pk_attachment$files
  if (!is.list(dosyalar) || !length(dosyalar)) return(invisible(FALSE))

  yollar <- vapply(dosyalar, function(x) {
    if (!is.list(x)) return("")
    yol <- tryCatch(as.character(x$path)[1], error = function(e) "")
    if (is.na(yol)) "" else yol
  }, character(1))
  yollar <- yollar[nzchar(yollar)]
  if (!length(yollar)) return(invisible(FALSE))

  for (yol in yollar) try(unlink(yol, force = TRUE), silent = TRUE)
  for (dizin in unique(dirname(yollar))) {
    norm <- gsub("\\\\", "/", dizin)
    if (grepl("(^|/)run_[^/]*$", norm) && dir.exists(dizin) && !length(list.files(dizin))) {
      try(unlink(dizin, recursive = TRUE, force = TRUE), silent = TRUE)
    }
  }
  invisible(TRUE)
}

#' İşçi vekilinden ana sürece taşınacak yazımları topla
#'
#' Toplanan değerler ana süreçte YALNIZCA istek-kimliği koruması geçtikten
#' sonra uygulanır. Bayat bir işçi sonucu daha yeni bir isteğin seçim durumunu
#' veya köken alt bilgisini EZEMEZ.
pk_async_harvest_session <- function(worker_session) {
  if (is.null(worker_session)) return(list())
  ud <- tryCatch(worker_session$userData, error = function(e) NULL)
  if (is.null(ud)) return(list())

  cikti <- list()
  for (yuva in .PK_ASYNC_HARVEST_SLOTS) {
    deger <- tryCatch(ud[[yuva]], error = function(e) NULL)
    if (is.null(deger)) next
    cikti[[yuva]] <- deger
  }

  cikti
}

#' Toplanan oturum yazımlarını ana süreçte uygula
#'
#' @return Uygulanan yuva adları.
pk_async_apply_session_writes <- function(session, writes) {
  if (is.null(session) || !is.list(writes) || length(writes) == 0L) {
    return(invisible(character(0)))
  }

  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(character(0)))

  uygulanan <- character(0)
  for (yuva in intersect(names(writes), .PK_ASYNC_HARVEST_SLOTS)) {
    ok <- tryCatch({
      ud[[yuva]] <- writes[[yuva]]
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok)) uygulanan <- c(uygulanan, yuva)
  }

  invisible(uygulanan)
}
