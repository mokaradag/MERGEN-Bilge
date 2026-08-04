# ==============================================================================
# Dosya Yolu: R/helpers_pk_export_xlsx.R
# Açıklama: Proje ve Kaynak Analizi dışa aktarımının G/Ç katmanı (§5.9).
#
#           Taban çizgi `writexl`tir: yerel tipler korunur, çok sayfa desteklenir
#           ve `renv.lock` VM'de üretildiği için bulut oturumunda YENİ PAKET
#           EKLENMEZ. Biçimleme iyileştirmeleri (sayı biçimi, yüzde stili,
#           donmuş bölme, otomatik filtre, sütun genişliği) yalnızca
#           `requireNamespace("openxlsx")` doğruysa devreye girer.
#
#           Doğrulama ZORUNLUDUR: yazılan her parça `readxl` ile geri okunur ve
#           satır/sütun sayısı ile çoklu-küme anahtarı karşılaştırılır. Meşru
#           MÜKERRER SATIRLAR korunur; doğrulamayı geçirmek için asla
#           tekilleştirme yapılmaz. Doğrulama başarısızsa dosya SUNULMAZ;
#           UTF-8 **BOM**lu CSV yedeğine düşülür (Excel UTF-8'i BOM ile
#           algılar — Bilge Yolaç `.txt` sözleşmesiyle aynı kural).
#
#           GÜVENLİK: bu dosyalar kullanıcıya özel RLS filtreli veridir ve
#           `bilge_yolac_downloads/` altına ASLA yazılmaz; orası
#           `addResourcePath` ile global olarak sunulur ve tahmin edilebilir bir
#           URL bir kullanıcının satırlarını bir başkasına açardı. Sunum
#           `session$registerDataObj` ile oturum kapsamlıdır ve oturum bitince
#           dosya silinir.
# ==============================================================================

.pk_export_norm <- function(df) {
  if (exists("normalize_pk_dataframe_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_pk_dataframe_utf8(df))
  }
  df
}

.pk_export_openxlsx_available <- function() {
  isTRUE(requireNamespace("openxlsx", quietly = TRUE))
}

# Sütun başlıkları: metadata etiketi varsa o, yoksa sütun adı.
.pk_export_apply_labels <- function(df, headers, meta) {
  sutun_meta <- if (is.list(meta) && is.list(meta$column_meta)) meta$column_meta else list()

  for (i in seq_along(names(df))) {
    if (!identical(headers[i], names(df)[i])) next
    cmeta <- sutun_meta[[names(df)[i]]]
    if (is.list(cmeta) && is.character(cmeta$label) && length(cmeta$label) == 1L &&
        !is.na(cmeta$label) && nzchar(cmeta$label)) {
      headers[i] <- cmeta$label
    }
  }

  headers
}

.pk_export_filename <- function(base, ext, index = NULL, total = 1L) {
  temiz <- gsub("[^A-Za-z0-9_.-]+", "_", as.character(base %||% "analiz")[1])
  temiz <- gsub("^_+|_+$", "", temiz)
  if (!nzchar(temiz)) temiz <- "analiz"

  damga <- format(Sys.time(), "%Y%m%d_%H%M%S")
  parca <- if (!is.null(index) && total > 1L) sprintf("_%03d", as.integer(index)) else ""
  sprintf("%s_%s%s.%s", temiz, damga, parca, ext)
}

# openxlsx yolunda sayı biçimleri metadata'dan gelir (§5.9 madde 2).
.pk_export_number_format <- function(cmeta) {
  if (!is.list(cmeta)) return(NULL)

  birim <- as.character(cmeta$unit %||% "")[1]
  ondalik <- suppressWarnings(as.integer(cmeta$decimals %||% NA_integer_))

  if (identical(birim, "%")) return("0.0%")
  if (identical(birim, "TL") || identical(birim, "TRY")) return("#,##0.00")
  if (!is.na(ondalik) && ondalik > 0L) {
    return(paste0("#,##0.", strrep("0", min(ondalik, 6L))))
  }
  if (!is.na(ondalik) && ondalik == 0L) return("#,##0")

  NULL
}

.pk_export_write_openxlsx <- function(path, sheets, meta, percent_columns) {
  wb <- openxlsx::createWorkbook()

  for (ad in names(sheets)) {
    df <- sheets[[ad]]
    openxlsx::addWorksheet(wb, ad)
    openxlsx::writeData(wb, ad, df, headerStyle = openxlsx::createStyle(textDecoration = "bold"))
    openxlsx::freezePane(wb, ad, firstRow = TRUE)
    if (ncol(df) > 0L && nrow(df) > 0L) {
      openxlsx::setColWidths(wb, ad, cols = seq_len(ncol(df)), widths = "auto")
    }

    sutun_meta <- if (is.list(meta) && is.list(meta$column_meta)) meta$column_meta else list()
    for (i in seq_along(names(df))) {
      kaynak <- attr(df, "pk_source_columns")[i]
      if (is.na(kaynak)) next
      bicim <- .pk_export_number_format(sutun_meta[[kaynak]])
      if (is.null(bicim) || !nrow(df)) next
      openxlsx::addStyle(
        wb, ad, openxlsx::createStyle(numFmt = bicim),
        rows = seq_len(nrow(df)) + 1L, cols = i, gridExpand = TRUE, stack = TRUE
      )
    }
  }

  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}

# UTF-8 BOM'lu CSV. Excel BOM olmadan UTF-8'i ANSI sanar ve Türkçe bozulur.
.pk_export_write_csv_bom <- function(path, df) {
  metin <- utils::capture.output(
    utils::write.csv(df, row.names = FALSE, fileEncoding = "", na = "")
  )
  govde <- paste(paste(metin, collapse = "\n"), "\n", sep = "")

  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  writeBin(charToRaw(enc2utf8(govde)), con)

  invisible(path)
}

#' Dışa aktarım artefaktını üret (yaz + doğrula + gerekirse CSV'ye düş)
#'
#' @param data Yetkili VE filtreli tam veri çerçevesi.
#' @param packet Analiz paketi (`Özet` sayfası için).
#' @param context `Bilgi` sayfası bağlamı (RLS öncesi sayı İÇERMEZ).
#' @return `list(status=, files=, message=, total_rows=, cols=, format=, notes=)`
pk_export_build <- function(data, packet = list(), context = list(),
                            base_name = "analiz", dir = NULL, query = NULL) {
  meta <- if (is.list(query) && is.list(query$meta)) query$meta else list()
  dizin <- dir %||% file.path(tempdir(), "pk_export")
  if (!dir.exists(dizin)) dir.create(dizin, recursive = TRUE, showWarnings = FALSE)

  plan <- pk_export_plan(data, base_name = "Veri", query_meta = meta)

  if (identical(plan$status, "empty")) {
    return(list(status = "empty", files = list(), message = plan$message,
                total_rows = 0L, cols = 0L, format = NA_character_, notes = character(0)))
  }
  if (identical(plan$status, "refuse")) {
    return(list(status = "refused", files = list(), message = plan$message,
                total_rows = plan$total_rows, cols = ncol(data),
                format = NA_character_, notes = character(0)))
  }

  bicimli <- .pk_export_openxlsx_available()
  hazir <- pk_export_prepare_percent(.pk_export_norm(data), meta, formatted = bicimli)
  basliklar <- .pk_export_apply_labels(hazir$data, hazir$headers, meta)

  govde <- hazir$data
  kaynak_sutunlar <- names(govde)
  names(govde) <- basliklar

  sayfalar <- list()
  for (parca in plan$parts) {
    alt <- govde[parca$ordinals, , drop = FALSE]
    rownames(alt) <- NULL
    attr(alt, "pk_source_columns") <- kaynak_sutunlar
    sayfalar[[parca$sheet]] <- alt
  }
  sayfalar[["Ozet"]] <- pk_export_summary_sheet(packet)
  sayfalar[["Bilgi"]] <- pk_export_info_sheet(context, plan)

  dosya_adi <- .pk_export_filename(base_name, "xlsx")
  yol <- file.path(dizin, dosya_adi)

  yazildi <- tryCatch({
    if (bicimli) {
      .pk_export_write_openxlsx(yol, sayfalar, meta, hazir$percent_columns)
    } else {
      writexl::write_xlsx(lapply(sayfalar, function(s) {
        attr(s, "pk_source_columns") <- NULL
        s
      }), path = yol)
    }
    TRUE
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] XLSX yazimi basarisiz: %s\n", conditionMessage(e)))
    FALSE
  })

  dogrulama <- if (yazildi) {
    pk_export_verify_file(yol, plan, sayfalar)
  } else {
    list(ok = FALSE, reason = "XLSX dosyasi yazilamadi.")
  }

  if (isTRUE(dogrulama$ok)) {
    return(list(
      status = "ok",
      files = list(list(path = yol, name = dosya_adi, rows = plan$total_rows,
                        cols = ncol(govde), format = "xlsx")),
      message = NULL, total_rows = plan$total_rows, cols = ncol(govde),
      format = if (bicimli) "xlsx_formatted" else "xlsx_baseline",
      parts = length(plan$parts), notes = hazir$notes
    ))
  }

  # Doğrulama başarısız: dosya SUNULMAZ, BOM'lu CSV yedeğine düşülür.
  cat(sprintf("[PK_ANALIZ] XLSX dogrulamasi basarisiz (%s); CSV yedegine dusuluyor.\n",
              as.character(dogrulama$reason %||% "?")[1]))
  safe_unlink_if_exists(yol)

  csv_dosyalari <- list()
  for (parca in plan$parts) {
    alt <- govde[parca$ordinals, , drop = FALSE]
    attr(alt, "pk_source_columns") <- NULL
    alt <- pk_export_neutralize_csv(alt)
    ad <- .pk_export_filename(base_name, "csv", parca$index, length(plan$parts))
    csv_yol <- file.path(dizin, ad)
    tryCatch({
      .pk_export_write_csv_bom(csv_yol, alt)
      csv_dosyalari[[length(csv_dosyalari) + 1L]] <- list(
        path = csv_yol, name = ad, rows = parca$rows, cols = ncol(alt), format = "csv"
      )
    }, error = function(e) {
      cat(sprintf("[PK_ANALIZ] CSV yedegi yazilamadi: %s\n", conditionMessage(e)))
    })
  }

  if (!length(csv_dosyalari)) {
    return(list(status = "failed", files = list(),
                message = "Dışa aktarım dosyası üretilemedi.",
                total_rows = plan$total_rows, cols = ncol(govde),
                format = NA_character_, notes = hazir$notes))
  }

  list(
    status = "csv_fallback", files = csv_dosyalari,
    message = paste0(
      "Excel dosyası doğrulamayı geçemediği için sunulmadı; veriler UTF-8 (BOM) ",
      "CSV olarak aktarıldı."
    ),
    total_rows = plan$total_rows, cols = ncol(govde), format = "csv",
    parts = length(csv_dosyalari), notes = c(hazir$notes, as.character(dogrulama$reason %||% ""))
  )
}

#' Yazılan XLSX'i geri okuyup doğrula
pk_export_verify_file <- function(path, plan, sheets) {
  if (!file.exists(path)) return(list(ok = FALSE, reason = "Dosya olusmadi."))
  if (!requireNamespace("readxl", quietly = TRUE)) {
    return(list(ok = FALSE, reason = "readxl yok; dogrulama yapilamadi."))
  }

  tryCatch({
    mevcut <- readxl::excel_sheets(path)

    for (parca in plan$parts) {
      if (!(parca$sheet %in% mevcut)) {
        return(list(ok = FALSE, reason = sprintf("Sayfa eksik: %s", parca$sheet)))
      }

      okunan <- as.data.frame(
        readxl::read_excel(path, sheet = parca$sheet, .name_repair = "minimal"),
        stringsAsFactors = FALSE
      )
      beklenen <- sheets[[parca$sheet]]
      attr(beklenen, "pk_source_columns") <- NULL

      dogrulama <- pk_export_verify_multiset(beklenen, okunan)
      if (!isTRUE(dogrulama$ok)) {
        return(list(ok = FALSE, reason = sprintf("%s: %s", parca$sheet, dogrulama$reason)))
      }
    }

    for (zorunlu in c("Ozet", "Bilgi")) {
      if (!(zorunlu %in% mevcut)) {
        return(list(ok = FALSE, reason = sprintf("Zorunlu sayfa eksik: %s", zorunlu)))
      }
    }

    list(ok = TRUE, reason = NULL)
  }, error = function(e) {
    list(ok = FALSE, reason = sprintf("Geri okuma hatasi: %s", conditionMessage(e)))
  })
}

#' Artefaktı OTURUM KAPSAMLI sun ve oturum bitiminde sil
#'
#' `bilge_yolac_downloads/` KULLANILMAZ: orası global bir kaynak yoludur ve
#' RLS filtreli veriyi tahmin edilebilir bir URL üzerinden başka kullanıcılara
#' açardı.
pk_export_serve <- function(session, artifact) {
  if (!is.list(artifact) || !length(artifact$files %||% list())) return(artifact)
  if (is.null(session) || is.null(session$registerDataObj)) return(artifact)

  temizlik <- list()

  artifact$files <- lapply(artifact$files, function(dosya) {
    yol <- normalizePath(dosya$path, winslash = "/", mustWork = FALSE)
    tur <- if (identical(dosya$format, "csv")) {
      "text/csv; charset=UTF-8"
    } else {
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    }

    url <- tryCatch(
      session$registerDataObj(
        name = paste0("pk_export_", gsub("[^A-Za-z0-9]", "_", dosya$name)),
        data = list(path = yol, ctype = tur, fname = dosya$name),
        filterFunc = function(data, req) {
          if (!file.exists(data$path)) {
            return(shiny::httpResponse(
              status = 404L, content_type = "text/plain; charset=UTF-8",
              content = "Analiz eki bulunamadi"
            ))
          }
          bayt <- readBin(data$path, "raw", file.info(data$path)$size)
          shiny::httpResponse(
            status = 200L, content_type = data$ctype, content = bayt,
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

    temizlik[[length(temizlik) + 1L]] <<- local({
      hedef <- yol
      function() safe_unlink_if_exists(hedef)
    })

    dosya$url <- url
    dosya
  })

  if (length(temizlik) &&
      exists("register_session_cleanup_on_end", mode = "function", inherits = TRUE)) {
    try(register_session_cleanup_on_end(session, extra_cleanup = temizlik), silent = TRUE)
  }

  artifact
}
