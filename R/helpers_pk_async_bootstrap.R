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
# UI/gözlemci bölümleri BİLİNÇLİ OLARAK DIŞARIDADIR: işçide Shiny yoktur.
# `module_analysis` ise bir UI modülü değil, PK işçisinin gerçek giriş noktası
# `pk_analiz_process_request()` fonksiyonunu sahiplenen dosyadır; bu yüzden
# açıkça bootstrap yüzeyine dahildir.
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
    "module_analysis",
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
  bolumler <- if (is.null(sections)) pk_async_worker_manifest_sections() else as.character(sections)

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

  # Manifest sırası korunur; yalnızca yinelenenler (bölümler arası) tekilleşir.
  unique(yollar)
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
pk_async_worker_bootstrap <- function(repo_root, files) {
  hedef <- globalenv()

  if (isTRUE(get0(.PK_ASYNC_BOOTSTRAP_FLAG, envir = hedef, ifnotfound = FALSE))) {
    return(list(ok = TRUE, loaded = 0L, failed = character(0), cached = TRUE))
  }

  kok <- tryCatch(as.character(repo_root)[1], error = function(e) NA_character_)
  if (is.na(kok) || !nzchar(kok) || !dir.exists(kok)) {
    return(list(ok = FALSE, loaded = 0L, failed = "repo_root", cached = FALSE))
  }

  dosyalar <- as.character(files %||% character(0))
  if (!length(dosyalar)) {
    return(list(ok = FALSE, loaded = 0L, failed = "empty_file_list", cached = FALSE))
  }

  yuklenen <- 0L
  basarisiz <- character(0)

  for (goreli in dosyalar) {
    tam <- file.path(kok, goreli)
    if (!file.exists(tam)) {
      # Opsiyonel katmanlar (ör. VM'e özel metadata dosyaları) yokluğu NORMALDİR.
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

  if (length(basarisiz) > 0L) {
    return(list(ok = FALSE, loaded = yuklenen, failed = basarisiz, cached = FALSE))
  }

  assign(.PK_ASYNC_BOOTSTRAP_FLAG, TRUE, envir = hedef)
  list(ok = TRUE, loaded = yuklenen, failed = character(0), cached = FALSE)
}

#' İşçinin ihtiyaç duyduğu MİNİMUM giriş noktalarının varlığını doğrula
#'
#' Bootstrap "hata vermedi" ile "boru hattı çalıştırılabilir" AYNI ŞEY DEĞİLDİR.
pk_async_worker_entry_points <- function() {
  c(
    "pk_analiz_process_request",
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
