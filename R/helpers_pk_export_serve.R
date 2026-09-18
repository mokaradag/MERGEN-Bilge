# ==============================================================================
# Dosya Yolu: R/helpers_pk_export_serve.R
# Açıklama: PK dışa aktarım artefaktının OTURUMA SUNULMASI (session-scoped
#           indirme URL'i) ve oturum sonu dosya temizliği.
#
# `R/helpers_pk_export_xlsx.R` içinden BÖLÜNMÜŞTÜR: orası XLSX/CSV ÜRETİMİ ve
# doğrulamasıdır ve 24-fonksiyon bakım tavanına dayanmıştı. Sunma/temizleme
# Shiny oturumuna dokunur; üretim katmanı dokunmaz.
#
# Manifest sırası ZORUNLUDUR: bu dosya `helpers_pk_export_xlsx.R`'den SONRA
# yüklenir.
# ==============================================================================

#' Artefaktı OTURUM KAPSAMLI sun ve oturum bitiminde sil
#'
#' `bilge_yolac_downloads/` KULLANILMAZ: orası global bir kaynak yoludur ve
#' RLS filtreli veriyi tahmin edilebilir bir URL üzerinden başka kullanıcılara
#' açardı.
.PK_EXPORT_SERVE_FAILURE_TR <- paste0(
  "Analiz eki hazırlandı ancak indirme bağlantısı oluşturulamadı; ",
  "dosya sunulamadığı için ek gönderilmedi."
)

# Sunulamayan artefaktın dosyaları diskte BIRAKILMAZ (temizlik kaydı yoktur).
.pk_export_discard_files <- function(dosyalar) {
  for (dosya in dosyalar) {
    yol <- suppressWarnings(as.character(dosya$path %||% "")[1])
    if (length(yol) == 1L && !is.na(yol) && nzchar(yol)) {
      try(unlink(yol, force = TRUE), silent = TRUE)
    }
  }
  invisible(NULL)
}

pk_export_serve <- function(session, artifact) {
  if (!is.list(artifact) || !length(artifact$files %||% list())) return(artifact)
  # SUNULAMAYAN EK "BAŞARILI" SAYILMAZ: bu erken dönüş aşağıdaki
  # `kayit_basarisiz` kapısını ATLIYOR, `status = "ok"` + `url = NULL` ile
  # indirilemeyen bir ek kartı gösteriliyor ve dosya temizlik kaydı olmadan
  # diskte KALIYORDU.
  if (is.null(session) || is.null(session$registerDataObj)) {
    .pk_export_discard_files(artifact$files %||% list())
    artifact$files <- list()
    artifact$status <- "failed"
    artifact$message <- .PK_EXPORT_SERVE_FAILURE_TR
    return(artifact)
  }

  temizlenecek <- character(0)
  kayit_basarisiz <- FALSE
  artifact$files <- lapply(artifact$files, function(dosya) {
    yol <- normalizePath(dosya$path, winslash = "/", mustWork = FALSE)
    dosya$path <- yol
    tur <- if (identical(dosya$format, "csv")) {
      "text/csv; charset=UTF-8"
    } else {
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    }

    # KAYIT ADI ARTEFAKT BAŞINA BENZERSİZDİR (PR #703 incelemesi).
    #
    # `registerDataObj()` işleyiciyi ADA göre saklar; AYNI ad yeniden
    # kaydedildiğinde eski yuva DEĞİŞTİRİLİR. Dosya adı yalnızca SANİYE
    # çözünürlüklü bir zaman damgası taşıdığı için aynı sorgunun aynı saniyedeki
    # iki dışa aktarımı (veya aynı biçime sanitize olan iki ad) aynı adı üretir;
    # dosya YOLLARI farklı olsa da ESKİ sohbet mesajındaki URL yeni dışa
    # aktarımın baytlarını indirirdi. Bu yüzden ada süreç-yerel bir nonce eklenir.
    kayit_adi <- paste0("pk_export_", gsub("[^A-Za-z0-9]", "_", dosya$name),
                        "_", .pk_export_object_nonce())
    url <- tryCatch(
      session$registerDataObj(
        name = kayit_adi,
        data = list(path = yol, ctype = tur, fname = dosya$name),
        filterFunc = function(data, req) {
          if (!file.exists(data$path)) {
            return(shiny::httpResponse(
              status = 404L, content_type = "text/plain; charset=UTF-8",
              content = "Analiz eki bulunamadi"
            ))
          }
          # Dosya BELLEĞE ALINMADAN akıtılır: izin verilen tavanda tek bir
          # indirme yüzlerce MB'ı paylaşılan Shiny sürecinde tutardı.
          #
          # DOĞRULANMIŞ ZİNCİR (varsayım DEĞİL): Shiny'nin HTTP sarmalayıcısı
          # (`handlerManager$.httpServer`) GET yanıtını `list(status, body =
          # response$content, headers)` olarak httpuv'e verir; httpuv
          # `rookCall()` içindeki `prepare_response()` ise `body` adlandırılmış
          # listesinde `file` alanı görürse bunu `bodyFile`/`bodyFileOwned`
          # alanlarına ÇEVİRİR ve dosyayı diskten akıtır. Yani `content =
          # list(file = ..., owned = ...)` gerçekten akıtılır. Bu çeviri
          # `tests/testthat/test-pk-export-serve-behavior.R` ile kilitlenmiştir;
          # httpuv çevirisi kalkarsa test KIRILIR (sessizce bozuk gövde dönmez).
          shiny::httpResponse(
            status = 200L, content_type = data$ctype,
            content = list(file = data$path, owned = FALSE),
            headers = list(
              "Content-Disposition" = sprintf("attachment; filename=\"%s\"", data$fname)
            )
          )
        }
      ),
      error = function(e) {
        cat(sprintf("[PK_ANALIZ] Ek sunulamadi: %s\n", conditionMessage(e)))
        NULL
      }
    )

    temizlenecek <<- c(temizlenecek, yol)
    # `NA` URL DE BAŞARISIZDIR: `nzchar(NA)` TRUE döner.
    url_metni <- suppressWarnings(as.character(url)[1])
    if (length(url_metni) != 1L || is.na(url_metni) || !nzchar(url_metni)) {
      kayit_basarisiz <<- TRUE; url <- NULL
    }
    dosya$url <- url
    dosya
  })

  .pk_export_register_cleanup(session, temizlenecek)

  # URL ÜRETİLEMEDİYSE EK BAŞARILI SAYILMAZ.
  #
  # `registerDataObj()` hata verdiğinde `url` `NULL` kalıyor ama artefakt
  # `status = "ok"` dönüyordu. Senkron sonuç kurucusu, asenkron yaşam
  # döngüsündeki URL doğrulamasını YAPMAZ; kullanıcıya indirilebilir bağlantısı
  # OLMAYAN, yalnızca dosya adı taşıyan "başarılı" bir ek kartı gösteriliyordu.
  # Tipli başarısızlık, mevcut dışa aktarım-hatası yanıtını devreye sokar.
  if (isTRUE(kayit_basarisiz)) {
    # BAŞARISIZ EK DOSYA TAŞIMAZ (oturumsuz dal ile AYNI sözleşme): `artifact$files` dolu bırakıldığında bağlantısız dosya girdileri aşağı akışa geçiyor ve dosyalar oturum sonuna kadar diskte kalıyordu.
    .pk_export_discard_files(artifact$files %||% list())
    artifact$files <- list()
    artifact$status <- "failed"
    artifact$message <- .PK_EXPORT_SERVE_FAILURE_TR
  }

  artifact
}

# Süreç-yerel, monoton kayıt nonce'u (aynı ada iki kez kayıt YAPILMAZ).
.pk_export_nonce_state <- new.env(parent = emptyenv())
.pk_export_nonce_state$n <- 0L

.pk_export_object_nonce <- function() {
  .pk_export_nonce_state$n <- .pk_export_nonce_state$n + 1L
  paste0(as.integer(Sys.time()), "_", .pk_export_nonce_state$n)
}

# Oturum kapsamlı temizlik DEFTERİ
#
# `register_session_cleanup_on_end()` oturum başına YALNIZCA BİR KEZ kayıt
# kabul eder ve sonraki `extra_cleanup` listelerini eklemez; ilk kaydı çoğu
# oturumda başka bir bileşen yaptığı için dışa aktarım temizliği hiç
# çalışmayabiliyordu. Bu yüzden yollar oturuma ait bir deftere yazılır ve
# defteri boşaltan TEK bir geri çağrı kaydedilir.
.pk_export_register_cleanup <- function(session, paths) {
  yollar <- as.character(paths %||% character(0))
  yollar <- yollar[!is.na(yollar) & nzchar(yollar)]
  if (!length(yollar)) return(invisible(FALSE))
  if (is.null(session) || is.null(session$userData) || !is.environment(session$userData)) {
    return(invisible(FALSE))
  }

  ud <- session$userData
  mevcut <- tryCatch(ud$pk_export_cleanup_paths, error = function(e) NULL)
  ud$pk_export_cleanup_paths <- unique(c(as.character(mevcut %||% character(0)), yollar))

  if (isTRUE(tryCatch(ud$pk_export_cleanup_registered, error = function(e) FALSE))) {
    return(invisible(TRUE))
  }
  if (!is.function(session$onSessionEnded)) return(invisible(FALSE))

  # İŞARET YALNIZCA KAYIT BAŞARILI OLDUKTAN SONRA KONUR (PR #703 incelemesi).
  #
  # Eskiden bayrak kancadan ÖNCE yazılıyor ve kayıt çağrısı sonucu
  # denetlenmeyen bir `try()` içindeydi: kurulum başarısız olsa da (ör. oturum
  # yıkılırken) bayrak `TRUE` kalıyor, sonraki HER dışa aktarım kaydı atlıyor ve
  # biriken tüm dosyalar oturum-sonu temizliğini KAYBEDİYORDU.
  kuruldu <- try({
    session$onSessionEnded(function() {
      hedefler <- tryCatch(ud$pk_export_cleanup_paths, error = function(e) character(0))
      hedefler <- as.character(hedefler %||% character(0))
      for (h in hedefler) try(unlink(h, force = TRUE), silent = TRUE)

      # Tekil çalışma dizinleri boşalınca kaldırılır; yalnızca bu dışa aktarım
      # için üretilmiş "run_" dizinlerine dokunulur.
      for (d in unique(dirname(hedefler))) {
        if (grepl("(^|/)run_[^/]*$", d) && dir.exists(d) && !length(list.files(d))) {
          try(unlink(d, recursive = TRUE, force = TRUE), silent = TRUE)
        }
      }
      tryCatch(ud$pk_export_cleanup_paths <- character(0), error = function(e) NULL)
    })
    TRUE
  }, silent = TRUE)

  if (!identical(kuruldu, TRUE)) {
    # Kanca kurulamadı: bayrak KONMAZ ki bir sonraki dışa aktarım tekrar
    # denesin. Yollar deftere yazıldığı için kayıt başarılı olduğunda hepsi
    # tek seferde temizlenir.
    return(invisible(FALSE))
  }
  ud$pk_export_cleanup_registered <- TRUE
  invisible(TRUE)
}