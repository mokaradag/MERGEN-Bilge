# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_commit.R
# Açıklama: Faz 3b metadata üreticisi -- KATMAN BİRLEŞTİRME, KİLİT ve KATALOG
#           TEŞHİSİ.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# Giriş betiği (tools/pk/generate_query_meta.R) yalnızca AKIŞI yürütür; burada
# ise o akışın karar veren, saf ve tek tek test edilebilen parçaları vardır.
# ==============================================================================

#' Önceki üretilen katman ile bu koşunun sonucunu BİRLEŞTİR
#'
#' KISMİ BİR ENVANTER ÖNCEKİ GEÇERLİ METADATA'YI SİLMEZ.
#'
#' Bu koşuda başarısız olan (örneğin geçici bir sürücü hatası alan) bir sorgu
#' için üretilen katman girdisi YOKTUR. Sonucu OLDUĞU GİBİ yazmak, o sorguları
#' hiçbir şey bozulmamışken Tier-0'a DÜŞÜRÜRDÜ. Bu yüzden:
#'
#'   * `ok`       -> bu koşunun girdisi ÖNCEKİNİN YERİNE geçer,
#'   * `withheld` -> önceki girdi KALDIRILIR (bloklayıcı bulgusu olan bir
#'                   sorgunun eski şemasını tutmak, başlangıç doğrulamasını
#'                   düşürebilecek bayat bir sözleşme bırakmak demektir),
#'   * `failed`/`skipped` -> önceki girdi KORUNUR (bu koşu o sorgu hakkında
#'                   hiçbir şey öğrenmedi; "bilmiyorum" "yok" demek değildir),
#'   * kütüphaneden kalkmış kimlikler -> DÜŞÜRÜLÜR.
#'
#' @return list(meta, replaced, kept, dropped, withheld_removed)
pkgc_merge_local_layers <- function(previous, generated, records) {
  onceki <- if (is.list(previous)) previous else list()
  uretilen <- if (is.list(generated)) generated else list()

  durumlar <- list()
  for (r in (records %||% list())) {
    id <- as.character(r$query_id %||% NA_character_)[1]
    if (is.na(id) || !nzchar(id)) next
    durumlar[[id]] <- as.character(r$status %||% "")[1]
  }

  sonuc <- list()
  degistirilen <- character(0)
  korunan <- character(0)
  geri_cekilip_silinen <- character(0)

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
    if (!is.null(onceki[[id]])) {
      sonuc[[id]] <- onceki[[id]]
      korunan <- c(korunan, id)
    }
  }

  # Kütüphanede ARTIK OLMAYAN kimlikler düşürülür: başlangıç kapısı, sorgu
  # kütüphanesinde karşılığı olmayan bir metadata kimliğini HATA sayar.
  dusurulen <- setdiff(names(onceki), names(durumlar))

  list(
    meta = sonuc,
    replaced = degistirilen,
    kept = korunan,
    dropped = dusurulen,
    withheld_removed = geri_cekilip_silinen
  )
}

# --- KOŞU KİLİDİ --------------------------------------------------------------
#
# Çıktı dosyası ve devam durumu SÜREÇ GENELİ yollardır. İki operatör koşusu
# (örneğin `describe` ve `sample`) kendi anlık görüntülerini doğrulayıp
# `R/library_query_meta_local.R` dosyasını SON YAZAN KAZANIR biçimde ezebilir;
# geç biten ESKİ koşu, yeni metadata'nın üzerine yazar. Artefakt dizinlerini
# benzersiz yapmak bu paylaşılan çıktı yarışını ÇÖZMEZ.
#
# Kilit `dir.create()` üzerine kurulur: dizin oluşturma dosya sisteminde
# ATOMİKTİR ve aynı depoda index kilidi için de kullanılan kalıptır.

.pkgc_lock_owner_text <- function() {
  paste0(
    "pid=", Sys.getpid(), "\n",
    "time=", format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), "\n"
  )
}

#' Üretici koşu kilidini al
#'
#' @param stale_sec Bu yaştan eski bir kilit ÇÖKMÜŞ bir koşudan kalmış sayılır
#'   ve kırılır.
#' @return list(ok, path, detail)
pkgc_acquire_run_lock <- function(lock_path, stale_sec = 3600) {
  dizin <- dirname(lock_path)
  if (!dir.exists(dizin)) dir.create(dizin, recursive = TRUE, showWarnings = FALSE)

  alindi <- isTRUE(suppressWarnings(dir.create(lock_path, showWarnings = FALSE)))

  if (!alindi && dir.exists(lock_path)) {
    yas <- suppressWarnings(as.numeric(
      difftime(Sys.time(), file.info(lock_path)$mtime, units = "secs")
    ))
    if (length(yas) == 1L && !is.na(yas) && yas > stale_sec) {
      unlink(lock_path, recursive = TRUE, force = TRUE)
      alindi <- isTRUE(suppressWarnings(dir.create(lock_path, showWarnings = FALSE)))
    }
  }

  if (!alindi) {
    return(list(ok = FALSE, path = lock_path, detail = paste0(
      "Baska bir uretici kosusu devam ediyor gorunuyor (kilit: ", lock_path, "). ",
      "Iki kosu ayni cikti dosyasini SON YAZAN KAZANIR bicimde ezebilecegi icin ",
      "bu kosu BASLATILMADI. Kosunun bittiginden eminseniz kilit dizinini silin."
    )))
  }

  tryCatch(
    writeLines(.pkgc_lock_owner_text(), file.path(lock_path, "owner.txt")),
    error = function(e) NULL
  )
  list(ok = TRUE, path = lock_path, detail = NA_character_)
}

pkgc_release_run_lock <- function(lock) {
  if (is.null(lock) || !isTRUE(lock$ok)) return(invisible(NULL))
  tryCatch(unlink(lock$path, recursive = TRUE, force = TRUE), error = function(e) NULL)
  invisible(NULL)
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
    if ((is.na(sql_beyani) || !nzchar(trimws(sql_beyani))) &&
        (is.na(dosya_beyani) || !nzchar(trimws(dosya_beyani)))) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "missing_sql", "blocking",
        "Sorgu ne inline SQL ne de sql_file beyani tasiyor."
      )))
    }

    if (length(bulgular)) {
      kayitlar[[length(kayitlar) + 1L]] <- pkgh_query_record(
        q, "failed", "catalog", findings = bulgular
      )
    }
  }

  kayitlar
}
