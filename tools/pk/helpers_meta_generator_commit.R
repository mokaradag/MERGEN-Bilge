# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_commit.R
# Açıklama: Faz 3b metadata üreticisi -- KATMAN BİRLEŞTİRME ve KATALOG TEŞHİSİ.
#
#           KOŞU KİLİDİ AYRI DOSYADADIR: helpers_meta_generator_lock.R.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# Giriş betiği (tools/pk/generate_query_meta.R) yalnızca AKIŞI yürütür; burada
# ise o akışın karar veren, saf ve tek tek test edilebilen parçaları vardır.
# ==============================================================================

# GEÇİCİ (transient) ile KESİN (deterministic) başarısızlık AYRIMI.
#
# `failed`/`skipped` durumları TEK BİR ŞEY demek değildir:
#
#   * GEÇİCİ  : sürücü/ağ/checkout hatası, zaman aşımı, tanımlayıcı sondası
#               düştü... Bu koşu o sorgu hakkında HİÇBİR ŞEY öğrenmedi;
#               "bilmiyorum" "yok" demek değildir, önceki girdi KORUNUR.
#   * KESİN   : katalog/yapılandırma kusuru (`missing_query_id`, `missing_sql`,
#               `invalid_db_target`, `malformed_library_entry`) ya da
#               salt-okunur kapısının reddi (`sql_not_readonly`). Bunlar tekrar
#               denemekle DEĞİŞMEZ ve `pk_query_meta_attach()` tarafından da
#               yakalanmaz (kapı `db_target` doğrulamaz). Eski şemayı canlı
#               bırakmak, bloklanmış/Tier-0 raporlanan bir sorgunun sessizce
#               eski sözleşmeyle çalışması demek olurdu.
PKG_META_DETERMINISTIC_BLOCK_CODES <- c(
  "missing_query_id", "missing_sql", "invalid_db_target",
  "malformed_library_entry", "sql_not_readonly"
)

.pkgc_record_codes <- function(record) {
  bulgular <- record$findings %||% list()
  if (!length(bulgular)) return(character(0))
  vapply(bulgular, function(f) as.character(f$code %||% "")[1], character(1))
}

.pkgc_is_deterministic_block <- function(record) {
  any(.pkgc_record_codes(record) %in% PKG_META_DETERMINISTIC_BLOCK_CODES)
}

#' Önceki üretilen katman ile bu koşunun sonucunu BİRLEŞTİR
#'
#' KISMİ BİR ENVANTER ÖNCEKİ GEÇERLİ METADATA'YI SİLMEZ -- ama BAYAT bir
#' SÖZLEŞMEYİ de canlı bırakmaz.
#'
#'   * `ok`       -> bu koşunun girdisi ÖNCEKİNİN YERİNE geçer,
#'   * `withheld` -> önceki girdi KALDIRILIR (bloklayıcı bulgusu olan bir
#'                   sorgunun eski şemasını tutmak, başlangıç doğrulamasını
#'                   düşürebilecek bayat bir sözleşme bırakmak demektir),
#'   * KESİN başarısızlık -> önceki girdi KALDIRILIR (yukarıdaki ayrıma bakın),
#'   * GEÇİCİ başarısızlık -> önceki girdi KORUNUR, ANCAK yalnızca PARMAK İZİ
#'                   hâlâ eşleşiyorsa,
#'   * kütüphaneden kalkmış kimlikler -> DÜŞÜRÜLÜR.
#'
#' PARMAK İZİ KAPISI ZORUNLUDUR. Devam önbelleği SQL değişiminde geçersiz kılınır;
#' ama bu birleştirme AYRI bir yoldur ve kapıyı paylaşmazsa eski sözleşmeyi geri
#' getirebilir: `Amount` sütunu `numeric` iken `CAST(... AS nvarchar)` yapılır,
#' ardından geçici bir sürücü hatası alınır -> eski `numeric` `result_schema`
#' korunur ve bütün-kütüphane kapısı bunu YAKALAYAMAZ, çünkü o kapı SQL'i
#' ÇALIŞTIRMAZ. Bu yüzden üretilen her girdi kendi kaynak parmak izini TAŞIR ve
#' yalnızca parmak izi eşleşen girdiler korunur.
#'
#' @param fingerprints `pkgh_state_fingerprints()` çıktısı (id -> parmak izi).
#'   `NULL` verildiğinde parmak izi karşılaştırması YAPILMAZ; bu yalnızca izole
#'   test/teşhis içindir.
#' @return list(meta, replaced, kept, dropped, withheld_removed, stale_removed)
pkgc_merge_local_layers <- function(previous, generated, records,
                                    fingerprints = NULL) {
  onceki <- if (is.list(previous)) previous else list()
  uretilen <- if (is.list(generated)) generated else list()

  durumlar <- list()
  kayit_haritasi <- list()
  for (r in (records %||% list())) {
    id <- as.character(r$query_id %||% NA_character_)[1]
    if (is.na(id) || !nzchar(id)) next
    durumlar[[id]] <- as.character(r$status %||% "")[1]
    kayit_haritasi[[id]] <- r
  }

  sonuc <- list()
  degistirilen <- character(0)
  korunan <- character(0)
  geri_cekilip_silinen <- character(0)
  bayat_silinen <- character(0)

  # Korunan girdinin parmak izi GÜNCEL sorguyla eşleşiyor mu?
  parmak_uyuyor <- function(id, girdi) {
    if (is.null(fingerprints)) return(TRUE)
    beklenen <- fingerprints[[id]]
    if (is.null(beklenen)) return(FALSE)
    kayitli <- as.character(girdi$source_fingerprint %||% NA_character_)[1]
    !is.na(kayitli) && identical(kayitli, beklenen)
  }

  for (id in names(durumlar)) {
    durum <- durumlar[[id]]

    if (identical(durum, "ok") && !is.null(uretilen[[id]])) {
      sonuc[[id]] <- uretilen[[id]]
      degistirilen <- c(degistirilen, id)
      next
    }

    if (identical(durum, "withheld")) {
      if (!is.null(onceki[[id]])) geri_cekilip_silinen <- c(geri_cekilip_silinen, id)
      next
    }

    if (is.null(onceki[[id]])) next

    if (.pkgc_is_deterministic_block(kayit_haritasi[[id]])) {
      geri_cekilip_silinen <- c(geri_cekilip_silinen, id)
      next
    }

    if (!parmak_uyuyor(id, onceki[[id]])) {
      bayat_silinen <- c(bayat_silinen, id)
      next
    }

    sonuc[[id]] <- onceki[[id]]
    korunan <- c(korunan, id)
  }

  # Kütüphanede ARTIK OLMAYAN kimlikler düşürülür: başlangıç kapısı, sorgu
  # kütüphanesinde karşılığı olmayan bir metadata kimliğini HATA sayar.
  dusurulen <- setdiff(names(onceki), names(durumlar))

  list(
    meta = sonuc,
    replaced = degistirilen,
    kept = korunan,
    dropped = dusurulen,
    withheld_removed = geri_cekilip_silinen,
    stale_removed = bayat_silinen
  )
}

# --- KATALOG TEŞHİSİ ----------------------------------------------------------
#
# Uygulama bootstrap'i `pk_query_meta_attach()` kapısını çalıştırır ve
# MÜKERRER/EKSİK sorgu kimliği gibi KATALOG kusurlarında DURUR. Sağlık raporu
# tam da bu kusurları listelemeyi vaat ettiği için, bootstrap düşerse ham sorgu
# kütüphanesi TEK BAŞINA (metadata sözleşmesi UYGULANMADAN) okunur ve kusurlar
# raporlanır. `R/library_queries.R` saf VERİDİR: yan etkisi yoktur.

#' Ham sorgu kütüphanesini metadata kapısı OLMADAN oku
pkgc_load_raw_query_library <- function(repo_root) {
  yol <- file.path(repo_root, "R", "library_queries.R")
  if (!file.exists(yol)) return(NULL)

  ortam <- new.env(parent = globalenv())
  ok <- tryCatch({
    sys.source(yol, envir = ortam, toplevel.env = globalenv())
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(ok)) return(NULL)
  if (!exists("query_library", envir = ortam, inherits = FALSE)) return(NULL)

  kutuphane <- get("query_library", envir = ortam, inherits = FALSE)
  if (!is.list(kutuphane)) return(NULL)
  kutuphane
}

# BEYAN EDİLEN `sql_file` GERÇEKTEN OKUNABİLİYOR MU?
#
# `config_sql_loader.R` eksik/boş/okunamayan bir `sql_file` yüzünden bootstrap'i
# DURDURUR. Katalog teşhisi tam da bu bootstrap düşmesini açıklamak içindir;
# beyanın yalnızca "boş değil" olduğuna bakmak, o düşmenin gerçek nedenini
# raporun DIŞINDA bırakır ve operatöre yalnızca genel bootstrap hatası kalır.
#
# `.resolve_sql_file_path()` ile AYNI çözümleme kullanılır (verildiğinde);
# üretici kendi ikinci bir yol mantığı yazmaz.
.pkgc_sql_file_finding <- function(declared) {
  yol <- trimws(as.character(declared)[1])

  cozulmus <- if (exists(".resolve_sql_file_path", mode = "function", inherits = TRUE)) {
    tryCatch(.resolve_sql_file_path(yol), error = function(e) NULL)
  } else if (file.exists(yol)) {
    yol
  } else {
    NULL
  }

  if (is.null(cozulmus) || !nzchar(cozulmus)) {
    return(pkgh_finding(
      "sql_file_unresolvable", "blocking",
      sprintf(paste0(
        "Beyan edilen sql_file COZULEMEDI: '%s'. config_sql_loader.R bu durumda ",
        "bootstrap'i DURDURUR (strict kip) ya da placeholder SQL ile devam eder; ",
        "her iki durumda da bu sorgu icin gercek SQL YOKTUR."
      ), yol)
    ))
  }

  boyut <- suppressWarnings(file.info(cozulmus)$size[1])
  if (is.na(boyut) || boyut <= 0) {
    return(pkgh_finding(
      "sql_file_empty", "blocking",
      sprintf("Beyan edilen sql_file BOS: '%s'.", yol)
    ))
  }

  okunabilir <- isTRUE(tryCatch(file.access(cozulmus, mode = 4L)[[1]] == 0L,
                                error = function(e) FALSE))
  if (!okunabilir) {
    return(pkgh_finding(
      "sql_file_unreadable", "blocking",
      sprintf("Beyan edilen sql_file OKUNAMIYOR (izin): '%s'.", yol)
    ))
  }

  NULL
}

#' Katalog (kimlik/SQL beyanı) kusurlarını bulgu kayıtlarına çevir
#'
#' Bunlar ŞEMA gerektirmez; bu yüzden bootstrap düşmüş olsa bile üretilebilirler.
pkgc_catalog_findings <- function(query_library) {
  kayitlar <- list()
  if (!is.list(query_library)) return(kayitlar)

  kimlikler <- character(0)
  for (i in seq_along(query_library)) {
    q <- query_library[[i]]
    if (!is.list(q)) {
      kayitlar[[length(kayitlar) + 1L]] <- pkgh_query_record(
        list(id = sprintf("index_%d", i)), "failed", "catalog",
        findings = list(pkgh_finding(
          "malformed_library_entry", "blocking",
          sprintf("query_library[[%d]] bir liste degil.", i)
        ))
      )
      next
    }

    ham_id <- as.character(q$id %||% NA_character_)[1]
    if (is.na(ham_id) || !nzchar(trimws(ham_id))) {
      kayitlar[[length(kayitlar) + 1L]] <- pkgh_query_record(
        list(id = sprintf("index_%d", i), name = q$name), "failed", "catalog",
        findings = list(pkgh_finding(
          "missing_query_id", "blocking",
          sprintf("query_library[[%d]] kararli bir id tasimiyor.", i)
        ))
      )
      next
    }

    kimlik <- trimws(ham_id)
    bulgular <- list()
    if (kimlik %in% kimlikler) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "duplicate_query_id", "blocking",
        sprintf("Kutuphanede tekrar eden sorgu id: %s", kimlik)
      )))
    }
    kimlikler <- c(kimlikler, kimlik)

    sql_beyani <- as.character(q$sql %||% "")[1]
    dosya_beyani <- as.character(q$sql_file %||% "")[1]
    inline_var <- !is.na(sql_beyani) && nzchar(trimws(sql_beyani))
    dosya_var <- !is.na(dosya_beyani) && nzchar(trimws(dosya_beyani))

    if (!inline_var && !dosya_var) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "missing_sql", "blocking",
        "Sorgu ne inline SQL ne de sql_file beyani tasiyor."
      )))
    } else if (dosya_var) {
      dosya_bulgusu <- .pkgc_sql_file_finding(dosya_beyani)
      if (!is.null(dosya_bulgusu)) bulgular <- c(bulgular, list(dosya_bulgusu))
    }

    if (length(bulgular)) {
      kayitlar[[length(kayitlar) + 1L]] <- pkgh_query_record(
        q, "failed", "catalog", findings = bulgular
      )
    }
  }

  kayitlar
}
