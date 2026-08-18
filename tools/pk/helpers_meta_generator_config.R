# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_config.R
# Açıklama: Faz 3b metadata üreticisi -- yapılandırma çözümleme (SAF).
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR. Kaynak manifestine EKLENMEZ; yalnızca
# operatörün VM'de elle çalıştırdığı `tools/pk/generate_query_meta.R` tarafından
# source edilir.
#
# SAFTIR: DB'ye bağlanmaz, SQL çalıştırmaz, dosya yazmaz, Shiny/reaktif okumaz.
# Yalnızca ortam değişkenlerini okur ve doğrulanmış bir yapılandırma listesi
# döndürür; bu sayede tamamı çevrimdışı test edilebilir.
# ==============================================================================

# `%||%` çalışma zamanında R/utils_common.R içinde tanımlıdır. Bu dosya izole
# testlerde ve operatör oturumunda tek başına source edilebildiği için yalnızca
# YOKSA tanımlanır; mevcut tanım ASLA ezilmez.
if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# Yerelden BAĞIMSIZ ASCII küçük harf. Kip adı bir PROTOKOL BELİRTECİDİR:
# Türkçe yerelde `tolower("DESCRIBE")` sorunsuzdur ama `tolower("SAMPLE_I")`
# gibi girdilerde noktasız i üretebilir. Depo kuralı gereği protokol
# belirteçleri asla yerele bağlı katlanmaz.
.pkg_ascii_lower <- function(x) {
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) return(pk_ascii_lower(x))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

# Master plan §9: geçerli kipler ve BELGELENMİŞ varsayılan.
PKG_META_MODES <- c("describe", "sample")

# VARSAYILAN `describe`'DIR.
#
# Operatör kılavuzu İLK geçişin her zaman `describe` olmasını söyler: o kip
# üretim sorgularını ÇALIŞTIRMAZ. Varsayılan `sample` olduğunda, ortam
# değişkenini ayarlamayı UNUTAN bir `source(...)` çağrısı tüm üretim sorgu
# kütüphanesini çalıştırırdı. Belgelenen güvenli ilk geçiş ile çalışma
# zamanındaki varsayılan AYNI olmalıdır.
PKG_META_DEFAULT_MODE <- "describe"

# Üretici YALNIZCA bu dosyaya yazar. İzlenen hiçbir dosyaya ve operatörün
# alias dosyasına ASLA dokunmaz.
PKG_META_OUTPUT_FILE <- "R/library_query_meta_local.R"

# Üretici tarafından ASLA yazılmayacak dosyalar. Bu liste bir yorum değil,
# çalışma zamanında uygulanan bir kapıdır (bkz. helpers_meta_generator_render.R).
PKG_META_FORBIDDEN_TARGETS <- c(
  "R/library_query_aliases_local.R",
  "R/library_query_meta.R",
  "R/library_query_meta_auto.R",
  "R/library_queries.R"
)

PKG_META_ARTIFACT_DIR <- "artifacts/pk-meta"

# DESTEKLENEN VERİTABANI HEDEFLERİ.
#
# `get_connection()` BİLİNMEYEN bir hedefi sessizce `DB_DSN`'e düşürür; bu
# yüzden hedef, bağlantı AÇILMADAN önce bu listeye karşı doğrulanır. Aksi hâlde
# `secondaryy` gibi bir yazım hatası sorguyu BİRİNCİL veritabanında çalıştırır
# ve sağlık kaydı yine de yanlış hedefi etiketler.
PKG_META_DB_TARGETS <- c("primary", "secondary", "tertiary")

# Hedef -> zorunlu DSN ortam değişkeni. Üretici, uygulamanın geliştirme
# yedeğini (`TestConnection`) DEVRALMAZ: birincil DSN tanımsızken üretim
# metadata'sı üretmek YANLIŞ veritabanını belgelemek demektir.
PKG_META_DB_TARGET_ENV <- c(
  primary   = "DB_DSN",
  secondary = "DB_DSN_2",
  tertiary  = "DB_DSN_3"
)

# Devam (resume) durum dosyası biçim sürümü. Üretici mantığı değiştiğinde eski
# önbellek YOK SAYILIR; böylece eski bir koşunun kanıt alanları yeni sürümün
# sözleşmesine sessizce taşınmaz.
PKG_META_STATE_VERSION <- 3L

.pkg_env_text <- function(name, default = "") {
  ham <- Sys.getenv(name, unset = "")
  if (!nzchar(trimws(ham))) return(default)
  trimws(ham)
}

.pkg_env_whole <- function(name, default, min = 1L, max = .Machine$integer.max) {
  ham <- .pkg_env_text(name, "")
  if (!nzchar(ham)) return(as.integer(default))

  sayi <- suppressWarnings(as.numeric(ham))
  if (length(sayi) != 1L || is.na(sayi) || !is.finite(sayi) || sayi != trunc(sayi)) {
    stop(sprintf(
      "[PK_META_GEN] %s tam sayi olmalidir (alinan: '%s').", name, ham
    ), call. = FALSE)
  }
  if (sayi < min || sayi > max) {
    stop(sprintf(
      "[PK_META_GEN] %s %s..%s araliginda olmalidir (alinan: %s).",
      name, format(min), format(max), format(sayi)
    ), call. = FALSE)
  }
  as.integer(sayi)
}

.pkg_env_flag <- function(name, default = FALSE) {
  ham <- .pkg_ascii_lower(.pkg_env_text(name, ""))
  if (!nzchar(ham)) return(isTRUE(default))
  if (ham %in% c("true", "t", "1", "yes", "on", "evet", "acik")) return(TRUE)
  if (ham %in% c("false", "f", "0", "no", "off", "hayir", "kapali")) return(FALSE)
  stop(sprintf(
    "[PK_META_GEN] %s TRUE/FALSE olmalidir (alinan: '%s').", name, ham
  ), call. = FALSE)
}

#' Üretici kipini çöz
#'
#' Geçersiz bir kip SESSİZCE varsayılana DÜŞMEZ; açıkça hata verir. Yanlış
#' yazılmış bir kip ile beklenmeyen bir kipte çalışmak (örneğin `describe`
#' yazmak isterken `sample` çalıştırmak) üretim veritabanında gereksiz yük
#' demektir.
#'
#' @return list(mode, defaulted)
pkg_meta_resolve_mode <- function(raw = NULL) {
  ham <- if (is.null(raw)) Sys.getenv("MERGEN_PK_META_MODE", unset = "") else raw
  ham_metin <- if (length(ham) == 1L && !is.na(ham)) trimws(as.character(ham)) else ""

  if (!nzchar(ham_metin)) {
    return(list(mode = PKG_META_DEFAULT_MODE, defaulted = TRUE))
  }

  kip <- .pkg_ascii_lower(ham_metin)
  if (!(kip %in% PKG_META_MODES)) {
    stop(sprintf(
      paste0(
        "[PK_META_GEN] Gecersiz MERGEN_PK_META_MODE: '%s'. ",
        "Izinli kipler: %s."
      ),
      ham_metin, paste(PKG_META_MODES, collapse = ", ")
    ), call. = FALSE)
  }

  list(mode = kip, defaulted = FALSE)
}

#' Hedefin desteklenip desteklenmediğini söyle
#'
#' @return list(ok, target, env_var, detail)
pkg_meta_validate_db_target <- function(target) {
  ham <- if (length(target) == 1L && !is.na(target)) trimws(as.character(target)) else ""
  if (!nzchar(ham)) {
    return(list(ok = FALSE, target = NA_character_, env_var = NA_character_,
                detail = "db_target bos; hedef veritabani belirsiz."))
  }

  kucuk <- .pkg_ascii_lower(ham)
  if (!(kucuk %in% PKG_META_DB_TARGETS)) {
    return(list(
      ok = FALSE, target = ham, env_var = NA_character_,
      detail = sprintf(
        paste0(
          "Desteklenmeyen db_target: '%s'. Izinli hedefler: %s. ",
          "Bilinmeyen hedef BIRINCIL veritabanina dusebilecegi icin baglanti ACILMADI."
        ),
        ham, paste(PKG_META_DB_TARGETS, collapse = ", ")
      )
    ))
  }

  list(ok = TRUE, target = kucuk,
       env_var = unname(PKG_META_DB_TARGET_ENV[[kucuk]]), detail = NA_character_)
}

#' Koşuya ÖZGÜ, çarpışma güvenli çalıştırma kimliği
#'
#' Saniye çözünürlüğü YETMEZ: aynı saniyede başlatılan iki üretici süreci aynı
#' `artifacts/pk-meta/<zaman>` yoluna çözülür ve birbirinin sağlık raporunu
#' EZERDİ. Milisaniye + süreç kimliği bu çarpışmayı yapısal olarak kapatır.
pkg_meta_run_id <- function(now = Sys.time(), pid = Sys.getpid()) {
  an <- as.POSIXct(now)
  damga <- format(an, "%Y%m%d-%H%M%S")
  kesir <- suppressWarnings(as.numeric(an) %% 1)
  if (length(kesir) != 1L || is.na(kesir) || !is.finite(kesir)) kesir <- 0
  sprintf("%s-%03d-p%d", damga, as.integer(floor(kesir * 1000)), as.integer(pid))
}

#' Tüm üretici yapılandırmasını çöz
#'
#' Gizli değer OKUNMAZ ve RAPORLANMAZ: burada yalnızca kip, satır sınırları ve
#' zaman aşımı gibi çalışma parametreleri vardır. DSN/kimlik bilgisi
#' `get_connection()` içinde kalır ve bu listeye ASLA girmez.
pkg_meta_resolve_config <- function(repo_root = ".", now = Sys.time()) {
  kip <- pkg_meta_resolve_mode()

  zaman_damgasi <- format(as.POSIXct(now), "%Y%m%d-%H%M%S")
  kosu_kimligi <- pkg_meta_run_id(now)

  # `sample` kipinde sorgu başına getirilecek EN FAZLA satır. Bu bir kanıt
  # sınırı değildir: 500 satır 501 satırlık sonucu 5 milyondan AYIRT EDEMEZ.
  ornek_satir <- .pkg_env_whole("MERGEN_PK_META_SAMPLE_ROWS", 500L, min = 1L)
  # Yüksek kardinalite KANITI için gereken farklı değer sayısı (tek yönlü:
  # bu eşiğin ÜSTÜNE çıkmak TRUE kanıtlar; altında kalmak hiçbir şey kanıtlamaz).
  kardinalite_esigi <- .pkg_env_whole("MERGEN_PK_META_HIGH_CARD_MIN", 50L, min = 2L)

  # ULAŞILAMAZ EŞİK REDDEDİLİR -- YALNIZCA `sample` KİPİNDE.
  #
  # `distinct_observed` en fazla `sample_rows` olabilir; eşik ona eşit ya da
  # ondan büyükse `high_cardinality = TRUE` KANITI hiçbir sütun için
  # üretilemez. Bu, sessizce "kanıt yok" üretmek yerine açıkça reddedilir.
  #
  # KİP KAPISI ZORUNLUDUR: `describe` kipi ne `sample_rows` ne de kardinalite
  # eşiğini KULLANIR. Çapraz kontrol koşulsuz çalıştığında, önceki bir örnekleme
  # koşusundan kalan `MERGEN_PK_META_SAMPLE_ROWS=10` +
  # `MERGEN_PK_META_HIGH_CARD_MIN=50` çifti, üretim sorgularını ÇALIŞTIRMAYAN
  # güvenli describe envanterini de imkânsız kılardı.
  if (identical(kip$mode, "sample") && kardinalite_esigi >= ornek_satir) {
    stop(sprintf(paste0(
      "[PK_META_GEN] MERGEN_PK_META_HIGH_CARD_MIN (%d) ",
      "MERGEN_PK_META_SAMPLE_ROWS (%d) degerinden KUCUK olmalidir; aksi halde ",
      "yuksek kardinalite kaniti hicbir sutun icin uretilemez."
    ), kardinalite_esigi, ornek_satir), call. = FALSE)
  }

  list(
    mode = kip$mode,
    mode_defaulted = kip$defaulted,
    repo_root = repo_root,
    output_path = file.path(repo_root, PKG_META_OUTPUT_FILE),
    output_rel = PKG_META_OUTPUT_FILE,
    state_path = file.path(repo_root, PKG_META_ARTIFACT_DIR, "generator-state.json"),
    lock_path = file.path(repo_root, PKG_META_ARTIFACT_DIR, "generator.lock"),
    artifact_dir = file.path(repo_root, PKG_META_ARTIFACT_DIR, kosu_kimligi),
    artifact_rel = file.path(PKG_META_ARTIFACT_DIR, kosu_kimligi),
    timestamp = zaman_damgasi,
    run_id = kosu_kimligi,
    state_version = PKG_META_STATE_VERSION,
    sample_rows = ornek_satir,
    high_cardinality_threshold = kardinalite_esigi,
    sql_timeout_sec = .pkg_env_whole("MERGEN_PK_META_SQL_TIMEOUT_SEC", 120L, min = 1L),
    max_result_mb = .pkg_env_whole("MERGEN_PK_META_MAX_RESULT_MB", 64L, min = 1L),
    # ÖRNEKLEME UNICODE PARAMETRE YOLU. Doğrudan çalıştırma anında okunsaydı
    # iki sorun doğardı: (1) değer koşu yapılandırma özetine GİRMEZ, dolayısıyla
    # iki örnekleme koşusu FARKLI ODBC yolları kullanırken raporlarda AYIRT
    # EDİLEMEZ olurdu; (2) yalnızca birebir `false` metni kapatırdı, oysa
    # üreticinin diğer bayrakları `0`/`no`/`kapali` biçimlerini de kabul eder.
    sample_unicode = .pkg_env_flag("MERGEN_PK_META_SAMPLE_UNICODE", TRUE),
    # Kesintiye uğrayan bir koşuyu kaldığı yerden sürdürür. Operatör temiz bir
    # koşu istediğinde FALSE yapar.
    resume = .pkg_env_flag("MERGEN_PK_META_RESUME", TRUE)
  )
}

#' Yapılandırmayı gizli-güvenli özetle
#'
#' Çıktıda DSN, kimlik bilgisi, uç nokta veya jeton BULUNMAZ.
pkg_meta_config_summary <- function(config) {
  list(
    mode = config$mode,
    mode_defaulted = isTRUE(config$mode_defaulted),
    sample_rows = config$sample_rows,
    high_cardinality_threshold = config$high_cardinality_threshold,
    sql_timeout_sec = config$sql_timeout_sec,
    max_result_mb = config$max_result_mb,
    sample_unicode = isTRUE(config$sample_unicode),
    resume = isTRUE(config$resume),
    output_rel = config$output_rel,
    artifact_rel = config$artifact_rel,
    run_id = as.character(config$run_id %||% NA_character_)[1]
  )
}
