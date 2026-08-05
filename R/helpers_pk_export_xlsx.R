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
#           Doğrulama ZORUNLUDUR: yazılan her parça `readxl` ile geri okunur;
#           BAŞLIKLAR, sütun tipleri ve hücre değerleri SIRA KORUNARAK
#           karşılaştırılır. `Ozet` ve `Bilgi` sayfaları da yalnızca adlarıyla
#           değil İÇERİKLERİYLE doğrulanır. Meşru MÜKERRER SATIRLAR korunur;
#           doğrulamayı geçirmek için asla tekilleştirme yapılmaz. Doğrulama
#           başarısızsa dosya SUNULMAZ; UTF-8 BOM'lu CSV yedeğine düşülür ve
#           yedeğin kendisi de geri okunup doğrulanır
#           (`R/helpers_pk_export_csv.R`).
#
#           GÜVENLİK: bu dosyalar kullanıcıya özel RLS filtreli veridir ve
#           `bilge_yolac_downloads/` altına ASLA yazılmaz; orası
#           `addResourcePath` ile global olarak sunulur ve tahmin edilebilir bir
#           URL bir kullanıcının satırlarını bir başkasına açardı. Her dışa
#           aktarım kendi TEKİL çalışma dizinine yazar (çakışan yol = başka bir
#           kullanıcının baytlarının üzerine yazmak), sunum
#           `session$registerDataObj` ile oturum kapsamlıdır ve dosya oturum
#           bitince silinir.
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

.pk_export_cell_ceiling <- function(query_meta = NULL) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(2000000L)
  deger <- tryCatch(
    pk_config_resolve("MERGEN_PK_EXPORT_MAX_CELLS", query_meta = query_meta),
    error = function(e) 2000000L
  )
  deger <- suppressWarnings(as.integer(deger))
  if (length(deger) != 1L || is.na(deger) || deger < 1L) 2000000L else deger
}

# Sütun başlıkları: metadata etiketi + BEYAN EDİLEN BİRİM. Birim yalnızca
# başlıkta ya da sayı biçiminde görünürse veri sayfası "saat mi gün mü TL mi"
# sorusunu yanıtlayamaz. Yüzde sütunları başlığını yüzde hazırlığından alır ve
# burada DEĞİŞTİRİLMEZ.
.pk_export_apply_labels <- function(df, headers, meta) {
  sutun_meta <- if (is.list(meta) && is.list(meta$column_meta)) meta$column_meta else list()

  for (i in seq_along(names(df))) {
    if (!identical(headers[i], names(df)[i])) next
    cmeta <- sutun_meta[[names(df)[i]]]
    if (!is.list(cmeta)) next

    etiket <- if (is.character(cmeta$label) && length(cmeta$label) == 1L &&
                  !is.na(cmeta$label) && nzchar(cmeta$label)) {
      cmeta$label
    } else {
      names(df)[i]
    }

    birim <- as.character(cmeta$unit %||% "")[1]
    if (!is.na(birim) && nzchar(birim) && !identical(birim, "%") &&
        !grepl(birim, etiket, fixed = TRUE)) {
      etiket <- sprintf("%s (%s)", etiket, birim)
    }

    headers[i] <- etiket
  }

  headers
}

# openxlsx yolunda sayı biçimleri metadata'dan gelir (§5.9 madde 2).
#
# `percent = TRUE` YALNIZCA `pk_export_prepare_percent()` ölçeği BEYAN EDİLMİŞ
# bulup değeri kesre çevirdiğinde verilir. Beyansız bir "%" sütununa `0.0%`
# uygulamak 61,3'ü %6130,0 yapardı — bu PR'ın önlediğini iddia ettiği hatanın
# ta kendisi. Ondalık basamak da metadata'dan gelir; sabit 1/2/6 basamak
# beyan edilen kesinliği görünüşte yuvarlar.
.pk_export_number_format <- function(cmeta, percent = FALSE) {
  if (!is.list(cmeta)) return(NULL)

  birim <- as.character(cmeta$unit %||% "")[1]
  if (is.na(birim)) birim <- ""
  ondalik <- suppressWarnings(as.integer(cmeta$decimals %||% NA_integer_))
  if (!is.na(ondalik)) ondalik <- max(0L, min(ondalik, 9L))

  kesirli <- function(basamak, onek) {
    if (basamak > 0L) paste0(onek, ".", strrep("0", basamak)) else onek
  }

  if (isTRUE(percent)) {
    basamak <- if (is.na(ondalik)) 1L else ondalik
    return(paste0(kesirli(basamak, "0"), "%"))
  }
  if (identical(birim, "TL") || identical(birim, "TRY")) {
    return(kesirli(if (is.na(ondalik)) 2L else ondalik, "#,##0"))
  }
  if (is.na(ondalik)) return(NULL)

  kesirli(ondalik, "#,##0")
}

.pk_export_write_openxlsx <- function(path, sheets, meta, percent_columns = character(0)) {
  wb <- openxlsx::createWorkbook()
  sutun_meta <- if (is.list(meta) && is.list(meta$column_meta)) meta$column_meta else list()
  yuzdeler <- as.character(percent_columns %||% character(0))

  for (ad in names(sheets)) {
    df <- sheets[[ad]]
    openxlsx::addWorksheet(wb, ad)
    openxlsx::writeData(wb, ad, df, headerStyle = openxlsx::createStyle(textDecoration = "bold"))
    openxlsx::freezePane(wb, ad, firstRow = TRUE)
    if (ncol(df) > 0L && nrow(df) > 0L) {
      openxlsx::setColWidths(wb, ad, cols = seq_len(ncol(df)), widths = "auto")
    }

    # `Ozet`/`Bilgi` sayfaları kaynak sütun metadatası TAŞIMAZ; öznitelik NULL
    # olduğunda `attr(df, ...)[i]` uzunluk-0 döner ve `if (is.na(...))` HATA
    # fırlatırdı. Bu hata dıştaki tryCatch'e düşüp openxlsx kurulu HER kurulumu
    # sessizce CSV yedeğine indiriyordu.
    kaynaklar <- attr(df, "pk_source_columns")
    if (!is.character(kaynaklar) || length(kaynaklar) != ncol(df)) next
    if (!nrow(df)) next

    for (i in seq_len(ncol(df))) {
      kaynak <- kaynaklar[i]
      if (is.na(kaynak) || !nzchar(kaynak)) next
      bicim <- .pk_export_number_format(sutun_meta[[kaynak]], percent = kaynak %in% yuzdeler)
      if (is.null(bicim)) next
      openxlsx::addStyle(
        wb, ad, openxlsx::createStyle(numFmt = bicim),
        rows = seq_len(nrow(df)) + 1L, cols = i, gridExpand = TRUE, stack = TRUE
      )
    }
  }

  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}

# CSV yedeği için gövdeyi YENİDEN hazırlar. `formatted = TRUE` yolunda yüzde
# puanları Excel stiline güvenilerek kesre bölünür (61,3 -> 0,613); aynı yükü
# stilsiz CSV'ye yazmak kullanıcıya %61,3 yerine 0,613 gösterirdi.
.pk_export_csv_body <- function(data, meta) {
  hazir <- pk_export_prepare_percent(.pk_export_norm(data), meta, formatted = FALSE)
  govde <- hazir$data
  names(govde) <- .pk_export_apply_labels(hazir$data, hazir$headers, meta)
  list(body = govde, notes = hazir$notes)
}

#' Dışa aktarım artefaktını üret (yaz + doğrula + gerekirse CSV'ye düş)
#'
#' @param data Yetkili VE filtreli tam veri çerçevesi.
#' @param packet Analiz paketi (`Özet` sayfası için).
#' @param context `Bilgi` sayfası bağlamı (RLS öncesi sayı İÇERMEZ).
#' @return `list(status=, files=, message=, total_rows=, cols=, format=, notes=)`
pk_export_build <- function(data, packet = list(), context = list(),
                            base_name = "analiz", dir = NULL, query = NULL,
                            format = NA_character_) {
  meta <- if (is.list(query) && is.list(query$meta)) query$meta else list()
  plan <- pk_export_plan(data, base_name = "Veri", query_meta = meta)

  if (identical(plan$status, "empty")) {
    return(list(status = "empty", files = list(), message = plan$message,
                total_rows = 0L, cols = if (is.data.frame(data)) ncol(data) else 0L,
                format = NA_character_, notes = character(0)))
  }
  if (identical(plan$status, "refuse")) {
    return(list(status = "refused", files = list(), message = plan$message,
                total_rows = plan$total_rows, cols = ncol(data),
                format = NA_character_, notes = character(0)))
  }

  # Her dışa aktarım KENDİ dizinine yazar: aynı saniyede aynı sorguyu aktaran
  # iki oturum birbirinin dosyasını ezemez ve birinin temizliği diğerininkini
  # silemez.
  dizin <- pk_export_run_dir(dir)

  ozet_sayfasi <- pk_export_summary_sheet(packet)
  bilgi_sayfasi <- pk_export_info_sheet(context, plan)

  # writexl tüm sayfaları AYNI ANDA ister; izin verilen tavanda (20 x 100.000)
  # bu, kaynak çerçevenin yanında bir kopya daha demektir. Hücre tavanı aşılırsa
  # XLSX hiç denenmez ve parçaları teker teker yazan akışlı CSV yoluna geçilir.
  hucre_tavani <- .pk_export_cell_ceiling(meta)
  toplam_hucre <- as.numeric(plan$total_rows) * max(1L, ncol(data))
  bellek_reddi <- toplam_hucre > hucre_tavani
  # Kullanıcı AÇIKÇA "CSV olarak indir" dediyse XLSX denenmez.
  csv_istendi <- identical(as.character(format %||% NA_character_)[1], "csv")

  yazildi <- FALSE
  yol <- NA_character_
  hazir_notlar <- character(0)
  dogrulama <- list(ok = FALSE, reason = if (csv_istendi) {
    "Kullanici acikca CSV istedi; XLSX uretilmedi."
  } else {
    sprintf("Sonuc %s hucre; XLSX bellek tavani (%s) asildi, dogrudan CSV yazildi.",
            format(toplam_hucre, scientific = FALSE),
            format(hucre_tavani, scientific = FALSE))
  })

  if (!bellek_reddi && !csv_istendi) {
    bicimli <- .pk_export_openxlsx_available()
    hazir <- pk_export_prepare_percent(.pk_export_norm(data), meta, formatted = bicimli)
    hazir_notlar <- hazir$notes
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
    sayfalar[["Ozet"]] <- ozet_sayfasi
    sayfalar[["Bilgi"]] <- bilgi_sayfasi

    yol <- file.path(dizin, .pk_export_filename(base_name, "xlsx"))

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
        files = list(list(path = yol, name = basename(yol), rows = plan$total_rows,
                          cols = ncol(govde), format = "xlsx")),
        message = NULL, total_rows = plan$total_rows, cols = ncol(govde),
        format = if (bicimli) "xlsx_formatted" else "xlsx_baseline",
        parts = length(plan$parts), notes = hazir$notes
      ))
    }

    cat(sprintf("[PK_ANALIZ] XLSX dogrulamasi basarisiz (%s); CSV yedegine dusuluyor.\n",
                as.character(dogrulama$reason %||% "?")[1]))
    if (!is.na(yol)) safe_unlink_if_exists(yol)
  }

  # CSV yedeği: yüzde sözleşmesi CSV'ye göre YENİDEN kurulur, parçalar akışlı
  # yazılır ve her biri geri okunup doğrulanır. Bir parça bile doğrulanamazsa
  # yarım küme SUNULMAZ.
  csv <- .pk_export_csv_body(data, meta)
  paket <- pk_export_csv_bundle(dizin, base_name, plan, csv$body,
                                summary_sheet = ozet_sayfasi, info_sheet = bilgi_sayfasi)

  if (!isTRUE(paket$ok)) {
    return(list(status = "failed", files = list(),
                message = "Dışa aktarım dosyası üretilemedi.",
                total_rows = plan$total_rows, cols = ncol(csv$body),
                format = NA_character_,
                notes = c(hazir_notlar, csv$notes, as.character(paket$reason %||% ""))))
  }

  list(
    status = "csv_fallback", files = paket$files,
    message = if (csv_istendi) {
      "Veriler istediğiniz gibi UTF-8 (BOM) CSV olarak aktarıldı."
    } else if (bellek_reddi) {
      paste0(
        "Sonuç kümesi Excel için güvenli bellek tavanını aştığı için veriler ",
        "UTF-8 (BOM) CSV olarak aktarıldı."
      )
    } else {
      paste0(
        "Excel dosyası doğrulamayı geçemediği için sunulmadı; veriler UTF-8 (BOM) ",
        "CSV olarak aktarıldı."
      )
    },
    total_rows = plan$total_rows, cols = ncol(csv$body), format = "csv",
    parts = length(plan$parts),
    notes = c(hazir_notlar, csv$notes, as.character(dogrulama$reason %||% ""))
  )
}

#' Yazılan XLSX'i geri okuyup doğrula
#'
#' Veri parçaları kadar `Ozet` ve `Bilgi` de İÇERİKLE doğrulanır: adı var diye
#' boş/kırpılmış bir denetim sayfası "doğrulanmış çalışma kitabı" sayılamaz.
pk_export_verify_file <- function(path, plan, sheets) {
  if (!file.exists(path)) return(list(ok = FALSE, reason = "Dosya olusmadi."))
  if (!requireNamespace("readxl", quietly = TRUE)) {
    return(list(ok = FALSE, reason = "readxl yok; dogrulama yapilamadi."))
  }

  tryCatch({
    mevcut <- readxl::excel_sheets(path)
    denetlenecek <- c(vapply(plan$parts, function(p) p$sheet, character(1)), "Ozet", "Bilgi")

    for (sayfa in denetlenecek) {
      if (!(sayfa %in% mevcut)) {
        return(list(ok = FALSE, reason = sprintf("Sayfa eksik: %s", sayfa)))
      }

      beklenen <- sheets[[sayfa]]
      if (!is.data.frame(beklenen)) {
        return(list(ok = FALSE, reason = sprintf("Beklenen sayfa yok: %s", sayfa)))
      }
      attr(beklenen, "pk_source_columns") <- NULL

      okunan <- as.data.frame(
        readxl::read_excel(path, sheet = sayfa, .name_repair = "minimal"),
        stringsAsFactors = FALSE
      )

      dogrulama <- pk_export_verify_multiset(beklenen, okunan)
      if (!isTRUE(dogrulama$ok)) {
        return(list(ok = FALSE, reason = sprintf("%s: %s", sayfa, dogrulama$reason)))
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

  temizlenecek <- character(0)

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
          # Dosya BELLEĞE ALINMADAN akıtılır: izin verilen tavanda tek bir
          # indirme yüzlerce MB'ı paylaşılan Shiny sürecinde tutardı.
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
    dosya$url <- url
    dosya
  })

  .pk_export_register_cleanup(session, temizlenecek)
  artifact
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

  ud$pk_export_cleanup_registered <- TRUE
  try(session$onSessionEnded(function() {
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
  }), silent = TRUE)

  invisible(TRUE)
}
