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

  # MÜKERRER BAŞLIK TÜM DIŞA AKTARIMI DÜŞÜRÜR: iki sütunun metadata etiketi
  # (ya da bir etiket ile başka bir sütunun ham adı) aynıysa hem
  # `pk_export_verify_multiset()` hem `pk_export_csv_verify()` `anyDuplicated()`
  # kapısında REDDEDER; XLSX silinir, CSV yedeği de geri alınır ve kullanıcı
  # HİÇ dosya alamaz. Çakışan etiketler KAYNAK SÜTUN ADINA döner; hâlâ
  # çakışıyorsa sıra numarası eklenir.
  cakisan <- duplicated(headers) | duplicated(headers, fromLast = TRUE)
  if (any(cakisan)) headers[cakisan] <- names(df)[cakisan]
  hala <- duplicated(headers)
  if (any(hala)) headers[hala] <- sprintf("%s_%d", headers[hala], which(hala))

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
                            format = NA_character_, stop_check = NULL) {
  meta <- if (is.list(query) && is.list(query$meta)) query$meta else list()

  # Dışa aktarım yazımı + geri okuma DOĞRULAMASI büyük dosyalarda uzun sürer ve
  # kendi başına iptal/son tarih GÖZLEMEZDİ: Durdur o sırada gelirse işçi tüm
  # I/O bitene kadar meşgul kalır, yani ilan edilen sert analiz son tarihi
  # aşılırdı. Kapı aşamalar ARASINDA yoklanır; jeton/son tarih yoksa
  # `pk_active_stage_halt()` `FALSE` döner ve davranış DEĞİŞMEZ.
  # DURDURMA NEDENİ TİPLİDİR: kullanıcı Stop'u ile mutlak son tarih AYRI
  # sonuçlardır.
  #
  # `pk_active_stage_halt()` ikisini tek bir mantıksal değere indirger ve
  # `iptal_sonucu()` eskiden her yolu `status = "cancelled"` olarak sabitleyip
  # kullanıcıya "siz durdurdunuz" diyordu. Yalnızca analiz son tarihine ulaşan
  # büyük bir dışa aktarım böylece kullanıcı iptali gibi raporlanıyor, terminal
  # telemetrisi bozuluyor ve bir kapasite/son tarih sorunu gizleniyordu.
  #
  # Durdurma yoksa `NULL` döner; böylece `%||%` zinciri doğal çalışır.
  halt_durumu <- function() tryCatch({
    if (is.function(stop_check) && isTRUE(stop_check())) return("cancelled")
    if (!exists("pk_async_stage_gate", mode = "function", inherits = TRUE)) return(NULL)
    jeton <- getOption("mergen.pk.async.cancel_token", NULL)
    son_tarih <- getOption("mergen.pk.async.deadline_at", NULL)
    if (is.null(jeton) && is.null(son_tarih)) return(NULL)
    kapi <- pk_async_stage_gate(jeton, son_tarih)
    if (!is.list(kapi) || !isTRUE(kapi$halt)) return(NULL)
    as.character(kapi$status %||% "cancelled")[1]
  }, error = function(e) NULL)
  durduruldu <- function() !is.null(halt_durumu())
  iptal_sonucu <- function(rows = 0L, cols = 0L, status = NULL) {
    durum <- as.character(status %||% halt_durumu() %||% "cancelled")[1]
    if (is.na(durum) || !nzchar(durum)) durum <- "cancelled"
    mesaj <- if (exists("pk_async_halt_message", mode = "function", inherits = TRUE)) {
      pk_async_halt_message(durum)
    } else if (identical(durum, "deadline")) {
      "Dışa aktarım ayrılan süre içinde tamamlanamadı."
    } else {
      "Dışa aktarım kullanıcı isteğiyle durduruldu."
    }
    list(status = durum, files = list(), message = mesaj,
         total_rows = rows, cols = cols, format = NA_character_, notes = character(0))
  }

  # YAZIM VE DOĞRULAMA AŞAMALARININ KENDİSİ SINIRLIDIR (PR #703 incelemesi).
  #
  # Yalnızca yazımdan ÖNCE/SONRA kapı yoklamak, büyük ama izinli bir dışa
  # aktarımda Durdur'un ve mutlak son tarihin dosya TAMAMEN üretilene kadar
  # GÖRÜLMEMESİ demekti; işçi o süre boyunca meşgul kalıyordu. Bu aşamalar
  # R/Rcpp hesabıdır, dolayısıyla `setTimeLimit()` onları gerçekten kesebilir.
  #
  # Bütçe yoksa (geri alma kipi / son tarih yayınlanmamış) davranış DEĞİŞMEZ.
  sinirli_asama <- function(fn) {
    if (!exists("pk_async_bounded_fs", mode = "function", inherits = TRUE)) {
      return(list(ok = TRUE, value = fn()))
    }
    pk_async_bounded_fs(fn, getOption("mergen.pk.async.deadline_at", NULL))
  }

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
  # İzole dizin YOKSA dışa aktarım yapılmaz: paylaşılan köke yazmak, aynı
  # saniyede aynı sorguyu aktaran başka bir oturumun dosyasını ezebilir.
  if (is.null(dizin) || !nzchar(as.character(dizin)[1])) {
    return(list(status = "failed", files = list(),
                message = "Dışa aktarım için yalıtılmış çalışma dizini oluşturulamadı.",
                total_rows = plan$total_rows, cols = ncol(data),
                format = NA_character_, notes = character(0)))
  }

  ozet_sayfasi <- pk_export_summary_sheet(packet)
  bilgi_sayfasi <- pk_export_info_sheet(context, plan)

  # writexl tüm sayfaları AYNI ANDA ister; izin verilen tavanda (20 x 100.000)
  # bu, kaynak çerçevenin yanında bir kopya daha demektir. Hücre tavanı aşılırsa
  # XLSX hiç denenmez ve parçaları teker teker yazan akışlı CSV yoluna geçilir.
  hucre_tavani <- .pk_export_cell_ceiling(meta)
  toplam_hucre <- as.numeric(plan$total_rows) * max(1L, ncol(data))

  # BAYT TAVANI HÜCRE TAVANINDAN AYRIDIR.
  #
  # Hücre sayısı hücre GENİŞLİĞİNİ ölçmez: tek bir çok-KB metin sütununun
  # 100.000 satırı 2M hücre varsayılanının çok altındadır ama kabul edilen
  # sonuç yüzlerce MB olabilir. XLSX dalı çerçeveyi normalleştirip kopyalar ve
  # çalışma kitabını onun YANINDA kurar; bu yüzden bayt tahmini de kapıya
  # girer ve aşıldığında akışlı CSV yoluna geçilir.
  bayt_tavani <- .pk_export_byte_ceiling(meta)
  tahmini_bayt <- tryCatch(
    as.numeric(utils::object.size(data)), error = function(e) NA_real_
  )
  bayt_reddi <- is.finite(tahmini_bayt) && tahmini_bayt > bayt_tavani

  bellek_reddi <- (toplam_hucre > hucre_tavani) || bayt_reddi
  # Kullanıcı AÇIKÇA "CSV olarak indir" dediyse XLSX denenmez.
  csv_istendi <- identical(as.character(format %||% NA_character_)[1], "csv")

  yazildi <- FALSE
  yol <- NA_character_
  hazir_notlar <- character(0)
  dogrulama <- list(ok = FALSE, reason = if (csv_istendi) {
    "Kullanici acikca CSV istedi; XLSX uretilmedi."
  } else {
    if (isTRUE(bayt_reddi)) {
      sprintf("Sonuc ~%s MB; XLSX bayt tavani (%s MB) asildi, dogrudan CSV yazildi.",
              format(round(tahmini_bayt / 1024 / 1024, 1L), scientific = FALSE),
              format(round(bayt_tavani / 1024 / 1024), scientific = FALSE))
    } else {
      sprintf("Sonuc %s hucre; XLSX bellek tavani (%s) asildi, dogrudan CSV yazildi.",
              format(toplam_hucre, scientific = FALSE),
              format(hucre_tavani, scientific = FALSE))
    }
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
    if (durduruldu()) return(iptal_sonucu(plan$total_rows, ncol(govde)))

    yazim <- sinirli_asama(function() {
      tryCatch({
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
    })
    # Bütçe içinde bitmediyse YARIM dosya diskte kalmamalıdır. Sınırlı aşamanın
    # bütçesi dolduysa neden SON TARİHtir, kullanıcı iptali değil.
    if (!isTRUE(yazim$ok)) {
      if (!is.na(yol)) try(safe_unlink_if_exists(yol), silent = TRUE)
      return(iptal_sonucu(plan$total_rows, ncol(govde),
                          status = halt_durumu() %||% "deadline"))
    }
    yazildi <- isTRUE(yazim$value)

    # Yazım BİTTİ: dosya artık diskte. Bundan sonraki her başarısız/iptal
    # yolunda temizlenebilmesi için ANINDA kaydedilir.
    if (isTRUE(yazildi)) {
      .pk_export_track_artifact(yol)
    } else if (!is.na(yol)) {
      # BAŞARISIZ YAZIM KISMİ DOSYA BIRAKMAZ: `write_xlsx()`/`saveWorkbook()`
      # hedefi OLUŞTURDUKTAN sonra da düşebilir. Dosya izlenmediği için hiçbir
      # temizlik yolu ona ulaşmaz ve RLS filtreli veri çalışma dizininde KALIR.
      try(safe_unlink_if_exists(yol), silent = TRUE)
    }

    if (durduruldu()) {
      if (!is.na(yol)) try(safe_unlink_if_exists(yol), silent = TRUE)
      return(iptal_sonucu(plan$total_rows, ncol(govde)))
    }

    dogrulama <- if (yazildi) {
      # Geri okuma/doğrulama da SINIRLIDIR: aynı gerekçe (bkz. `sinirli_asama`).
      dogrulama_sonucu <- sinirli_asama(function() pk_export_verify_file(yol, plan, sayfalar))
      if (!isTRUE(dogrulama_sonucu$ok)) {
        if (!is.na(yol)) try(safe_unlink_if_exists(yol), silent = TRUE)
        return(iptal_sonucu(plan$total_rows, ncol(govde),
                            status = halt_durumu() %||% "deadline"))
      }
      dogrulama_sonucu$value
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
    if (!is.na(yol)) try(safe_unlink_if_exists(yol), silent = TRUE)
  }

  # CSV yedeği: yüzde sözleşmesi CSV'ye göre YENİDEN kurulur, parçalar akışlı
  # yazılır ve her biri geri okunup doğrulanır. Bir parça bile doğrulanamazsa
  # yarım küme SUNULMAZ.
  if (durduruldu()) return(iptal_sonucu(plan$total_rows, ncol(data)))

  # TAM BOYUTLU İKİNCİ KOPYA OLUŞTURULMAZ.
  #
  # `.pk_export_csv_body(data, meta)` tüm sonucu dönüştürülmüş İKİNCİ bir
  # çerçeveye kopyalıyordu; kaynak hâlâ canlıyken bu, tam da XLSX bellek
  # baskısından kaçınmak için seçilen yolda canlı ayak izini yaklaşık iki
  # katına çıkarıyordu. Yüzde/etiket hazırlığı YALNIZCA metadata'ya bağlı
  # olduğundan (veriye değil), dönüşümü parça başına uygulamak tüm çerçeveyi
  # dönüştürüp bölmekle AYNI sonucu verir.
  csv_sonda <- tryCatch(
    .pk_export_csv_body(data[0L, , drop = FALSE], meta),
    error = function(e) NULL
  )
  csv_notlari <- if (is.list(csv_sonda)) csv_sonda$notes else character(0)
  csv_sutun <- if (is.list(csv_sonda)) ncol(csv_sonda$body) else ncol(data)
  csv <- list(body = NULL, notes = csv_notlari)

  # Hazırlık/yazım/doğrulama aşamaları da SINIRLIDIR ve iptal parçalar arasında
  # yoklanır: büyük ama izinli bir dışa aktarım Durdur'a ya da mutlak son
  # tarihe rağmen sonuna kadar çalışmaz.
  paket_sonucu <- sinirli_asama(function() {
    pk_export_csv_bundle(
      dizin, base_name, plan, data,
      summary_sheet = ozet_sayfasi, info_sheet = bilgi_sayfasi,
      transform = function(dilim) .pk_export_csv_body(dilim, meta)$body,
      stop_check = durduruldu
    )
  })
  if (!isTRUE(paket_sonucu$ok)) {
    # BÜTÇE TÜKENMESİ İLE GERÇEK HATA AYRILIR.
    #
    # `pk_async_bounded_fs()` `fn` içindeki HER istisnayı `ok = FALSE` yapar;
    # `pk_export_csv_bundle()` gövde dilimleme/`transform` çağrısını sarmadığı
    # için oradaki bir hata "son tarih" olarak raporlanıyordu ("ayrılan süre
    # içinde tamamlanamadı"). XLSX dalında bu boşluk yok: iç `tryCatch` yazım
    # hatasını `yazim$value = FALSE`a çevirir.
    hata_metni <- as.character(paket_sonucu$error %||% "")[1]
    if (is.na(hata_metni)) hata_metni <- ""
    butce_bitti <- identical(hata_metni, "budget_exhausted") ||
      grepl("elapsed time limit|reached elapsed", hata_metni, ignore.case = TRUE)
    durdurma <- halt_durumu()

    if (!is.null(durdurma) || isTRUE(butce_bitti)) {
      return(iptal_sonucu(plan$total_rows, csv_sutun,
                          status = durdurma %||% "deadline"))
    }
    cat(sprintf("[PK_ANALIZ] CSV paketi olusturulamadi: %s\n", hata_metni))
    # HATA YOLUNDA YARIM PAKET DİSKTE BIRAKILMAZ: `pk_export_csv_bundle()`
    # kendi temizliğini yapar, ancak bu isteğe ait daha önce izlenen artefaktlar
    # da (ör. XLSX denemesinden kalanlar) burada bırakılır.
    if (exists("pk_artifact_discard_tracked", mode = "function", inherits = TRUE)) {
      try(pk_artifact_discard_tracked(), silent = TRUE)
    }
    return(list(status = "failed", files = list(),
                message = "Dışa aktarım hazırlanırken beklenmeyen bir hata oluştu.",
                total_rows = plan$total_rows, cols = csv_sutun,
                format = NA_character_, notes = character(0)))
  }
  paket <- paket_sonucu$value
  .pk_export_track_artifact(vapply(
    paket$files %||% list(), function(f) as.character(f$path %||% "")[1], character(1)
  ))

  if (durduruldu()) {
    for (dosya in paket$files %||% list()) {
      try(safe_unlink_if_exists(as.character(dosya$path %||% "")[1]), silent = TRUE)
    }
    return(iptal_sonucu(plan$total_rows, csv_sutun))
  }

  if (!isTRUE(paket$ok)) {
    return(list(status = "failed", files = list(),
                message = "Dışa aktarım dosyası üretilemedi.",
                total_rows = plan$total_rows, cols = csv_sutun,
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
    total_rows = plan$total_rows, cols = csv_sutun, format = "csv",
    parts = length(plan$parts),
    notes = c(hazir_notlar, csv$notes, as.character(dogrulama$reason %||% ""))
  )
}

# Artifact kaydı işçi ortamı yardımcısındadır (`helpers_pk_async_worker_env.R`);
# burada GUARDED çağrılır, böylece dışa aktarım o katman olmadan da çalışır.
.pk_export_track_artifact <- function(paths) {
  if (!exists("pk_artifact_track", mode = "function", inherits = TRUE)) return(invisible(FALSE))
  try(pk_artifact_track(paths), silent = TRUE)
  invisible(TRUE)
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
