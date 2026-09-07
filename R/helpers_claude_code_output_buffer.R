# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_output_buffer.R
# Açıklama: Bilge Yolaç alt süreç çıktısı (stdout/stderr) için bayt bütçeli
#           birikim tamponu. R/config_claude_code.R içindeki üst sınır
#           sabitlerini kullanır; R/helpers_claude_code.R (run_claude_code) ve
#           R/helpers_claude_code_streaming.R (run_claude_code_streaming)
#           paylaşır, bu yüzden ikisinden de ÖNCE yüklenir.
#
# NEDEN: Boru her turda boşaltılmaya devam etmelidir (çocuk süreç yazmada
#        bloke olmasın), ancak SAKLANAN metin sınırsız büyürse gürültülü ya da
#        değiştirilmiş bir CLI worker belleğini/CPU'sunu tüketebilir. Ayrıca
#        her turda `c()` ile büyütmek O(n^2) kopyalama üretiyordu; parçalar
#        listede toplanır ve yalnızca sonda birleştirilir.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# Metni UTF-8 sınırına geri çekilerek BAYT bütçesine kırpar. `substr()` KARAKTER
# sayar; çok baytlı Türkçe metinde saklanan veri bütçeyi katlarca aşabiliyordu.
cc_output_truncate_bytes <- function(text, max_bytes) {
  metin <- as.character(text %||% "")[1]
  if (is.na(metin)) return("")
  sinir <- suppressWarnings(as.numeric(max_bytes)[1])
  if (length(sinir) != 1L || is.na(sinir)) sinir <- 0
  if (!is.finite(sinir)) return(metin)
  if (sinir <= 0) return("")
  if (nchar(metin, type = "bytes") <= sinir) return(metin)

  ham <- charToRaw(metin)
  kes <- as.integer(min(length(ham), floor(sinir)))
  # Kesme noktasından SONRAKİ bayt devam baytıysa (0x80-0xBF) karakterin
  # ortasındayız; sınır geriye çekilir.
  while (kes > 0L && kes < length(ham) &&
         bitwAnd(as.integer(ham[kes + 1L]), 0xC0L) == 0x80L) {
    kes <- kes - 1L
  }
  if (kes <= 0L) return("")
  kirpik <- rawToChar(ham[seq_len(kes)])
  Encoding(kirpik) <- "UTF-8"
  kirpik
}

# Dosya adı bileşenini bayt bütçesine sığdırır (varsayılan 255: yaygın dosya
# sistemi sınırı). Uzantı KORUNUR; kırpma gerekirse benzersizliği sürdürmek
# için kısa bir özet eklenir. Benzersizlik jetonu eklendikten sonra daha önce
# sığan uzun bir ad sınırı aşıp `file.copy()` başarısız olabiliyor ve kullanıcı
# hiçbir indirme kaydı alamıyordu.
cc_fit_name_to_byte_budget <- function(onek, ad, max_bytes = 255L) {
  onek <- as.character(onek %||% "")[1]
  ad <- as.character(ad %||% "")[1]
  if (is.na(onek)) onek <- ""
  if (is.na(ad)) ad <- ""

  sinir <- suppressWarnings(as.integer(max_bytes)[1])
  if (length(sinir) != 1L || is.na(sinir) || sinir <= 0L) sinir <- 255L

  tam <- paste0(onek, ad)
  if (nchar(tam, type = "bytes") <= sinir) return(tam)

  uzanti <- sub("^.*(\\.[A-Za-z0-9]{1,10})$", "\\1", ad)
  if (identical(uzanti, ad)) uzanti <- ""
  govde <- substr(ad, 1L, nchar(ad) - nchar(uzanti))

  # ÖZET TÜM addan türetilir. Eski biçim adın hex gösteriminin ilk 8 hanesini,
  # yani İLK 4 BAYTINI alıyordu; bu baytlar zaten korunan önekin parçası olduğu
  # için yalnızca sonunda ayrışan iki uzun ad aynı kırpılmış adı üretiyor ve
  # ikinci indirme birincisinin üzerine yazıyordu. Toplam `double` üzerinde
  # hesaplanır: tamsayı çarpımı uzun adlarda taşıp NA/uyarı üretiyordu.
  ham_baytlar <- as.numeric(charToRaw(ad))
  ozet <- sprintf(
    "%08x",
    as.integer(sum(ham_baytlar * seq_along(ham_baytlar)) %% 2147483647)
  )
  kalan <- sinir - nchar(paste0(onek, "_", ozet, uzanti), type = "bytes")
  kirpik <- if (kalan > 0L) cc_output_truncate_bytes(govde, kalan) else ""

  paste0(onek, kirpik, "_", ozet, uzanti)
}

# Yeni bayt bütçeli tampon oluşturur.
cc_output_buffer_new <- function(max_bytes = NULL) {
  if (is.null(max_bytes)) {
    max_bytes <- if (exists("CC_STREAM_MAX_STDOUT_BYTES", inherits = TRUE)) {
      CC_STREAM_MAX_STDOUT_BYTES
    } else {
      8388608L
    }
  }
  buf <- new.env(parent = emptyenv())
  buf$parcalar <- list()
  buf$bayt <- 0
  cozulen_max <- suppressWarnings(as.numeric(max_bytes)[1])
  # NA/boş yapılandırma değeri `max()` üzerinden NA üretiyor ve sonraki `if`
  # koşulu "missing value where TRUE/FALSE needed" ile düşüyordu.
  if (length(cozulen_max) != 1L || is.na(cozulen_max)) cozulen_max <- 0
  buf$max_bytes <- max(0, cozulen_max)
  if (!is.finite(buf$max_bytes)) buf$max_bytes <- Inf
  buf$asildi <- FALSE
  buf
}

# Parçayı bütçe içinde saklar. Bütçe aşıldıysa FALSE döner (çağıran süreci
# sonlandırabilir); metin her hâlükârda kırpılarak eklenir.
cc_output_buffer_add <- function(buf, text) {
  parca <- as.character(text %||% "")
  if (!length(parca)) return(!isTRUE(buf$asildi))
  parca <- parca[1]
  if (is.na(parca) || !nzchar(parca)) return(!isTRUE(buf$asildi))

  kalan <- buf$max_bytes - buf$bayt
  if (kalan <= 0) {
    buf$asildi <- TRUE
    return(FALSE)
  }

  parca_bayt <- nchar(parca, type = "bytes")
  if (parca_bayt > kalan) {
    parca <- cc_output_truncate_bytes(parca, kalan)
    buf$asildi <- TRUE
    if (!nzchar(parca)) return(FALSE)
  }

  buf$parcalar[[length(buf$parcalar) + 1L]] <- parca
  buf$bayt <- buf$bayt + nchar(parca, type = "bytes")
  !isTRUE(buf$asildi)
}

# Biriken metni tek dizeye toplar; bütçe aşıldıysa açık bir not eklenir.
cc_output_buffer_text <- function(buf, note = "\n[çıktı sınırı aşıldı; metin kısaltıldı]") {
  metin <- paste0(as.character(unlist(buf$parcalar, use.names = FALSE)), collapse = "")
  if (isTRUE(buf$asildi)) metin <- paste0(metin, note)
  metin
}

# Bayt bütçesi aşıldığında dönen ortak başarısızlık sonucu. Hem bekleme
# döngüsü hem de son okuma aynı sözleşmeyi kullanır; kırpılmış çıktı asla
# "başarılı" olarak raporlanmaz.
cc_output_limit_result <- function(duration_sec) {
  list(
    success = FALSE, output = "",
    error = "İşlem çıktısı güvenli sınırı aştı; çalıştırma durduruldu.",
    duration = round(as.numeric(duration_sec)[1], 1),
    tool_uses = list(), session_id = NULL
  )
}

# Alt sürecin stdout/stderr borularını zaman aşımı boyunca bayt bütçesi içinde
# boşaltır. Bütçe aşılırsa süreç sonlandırılır ve `limit_exceeded = TRUE` döner.
# `proc$wait()` boruları boşaltmadığı için doğrudan beklemek 64KB'lık OS boru
# tamponu dolduğunda sahte "zaman aşımı" üretiyordu.
cc_drain_process_streams <- function(proc, timeout_sec, poll_ms = 200L,
                                     stdout_max_bytes = NULL,
                                     stderr_max_bytes = NULL) {
  if (is.null(stderr_max_bytes)) {
    stderr_max_bytes <- if (exists("CC_STREAM_MAX_STDERR_BYTES", inherits = TRUE)) {
      CC_STREAM_MAX_STDERR_BYTES
    } else {
      262144L
    }
  }

  stdout_tampon <- cc_output_buffer_new(stdout_max_bytes)
  stderr_tampon <- cc_output_buffer_new(stderr_max_bytes)
  limit_exceeded <- FALSE

  # Sonlu olmayan/çözülemeyen bütçe `gecen_ms >= bitis_ms` koşulunu NA yapıyor,
  # `if` hata veriyor ve alt süreç öldürülmeden izlenmeden kalıyordu.
  bitis_ms <- suppressWarnings(as.numeric(timeout_sec)[1]) * 1000
  if (length(bitis_ms) != 1L || is.na(bitis_ms) || !is.finite(bitis_ms) ||
      bitis_ms < 0) {
    bitis_ms <- 0
  }
  baslangic <- Sys.time()

  while (proc$is_alive()) {
    gecen_ms <- as.numeric(difftime(Sys.time(), baslangic, units = "secs")) * 1000
    if (!is.finite(gecen_ms) || gecen_ms >= bitis_ms) break

    tryCatch(proc$poll_io(poll_ms), error = function(e) NULL)
    stdout_ok <- cc_output_buffer_add(
      stdout_tampon, tryCatch(proc$read_output(), error = function(e) "")
    )
    # stderr bütçesi de kill koşuluna dahildir: yalnızca stderr'e yazan bir alt
    # süreç aksi hâlde zaman aşımına kadar çalışmaya devam ederdi.
    stderr_ok <- cc_output_buffer_add(
      stderr_tampon, tryCatch(proc$read_error(), error = function(e) "")
    )

    if (!isTRUE(stdout_ok) || !isTRUE(stderr_ok)) {
      # Bütçe aşıldı: okumaya devam etmek CPU/bellek tüketmeye devam ederdi.
      limit_exceeded <- TRUE
      tryCatch(proc$kill(), error = function(e) NULL)
      break
    }
  }

  list(
    stdout_buffer = stdout_tampon,
    stderr_buffer = stderr_tampon,
    limit_exceeded = limit_exceeded
  )
}

# Canlı akış stdout SATIR tamponu için ORTAK bütçe uygulaması. Hem
# `run_claude_code_streaming()` hem Shiny yoklama gözlemcisi bu TEK uygulamayı
# kullanır; iki ayrı kopya aynı üç bütçeyi farklı biçimde uyguluyordu.
# `env` bir liste değil ORTAM olmalıdır (yerinde güncellenir).
# En eski satırları düşürürken bayt sayacını da tutarlı tutar.
# Kırpmada KORUNAN kayıt türleri. Ham tampon TANI amaçlı ve sınırlıdır; ancak
# düşen kayıtlar yalnızca metin deltası değildir: `tool_use` / `tool_result`
# olayları AKIŞIN BAŞINDA gelir ve kırpma onları düşürdüğünde son ayrıştırma
# ARAÇ KULLANIMLARI listesini eksik üretiyordu (araç sonucu eşleşmesi de
# kayboluyordu). Araç olayları pratikte azdır ve küçüktür; yine de KENDİ üst
# sınırıyla saklanır, aksi hâlde patolojik bir akış bu tamponu sınırsız
# büyütebilirdi.
CC_STREAM_TOOL_KEEP_MAX <- 2000L

.cc_stream_trim_oldest <- function(env, dusurulecek) {
  dusurulecek <- min(as.integer(dusurulecek), length(env$satir_tamponu))
  if (dusurulecek <= 0L) return(invisible(NULL))
  dusen <- env$satir_tamponu[seq_len(dusurulecek)]
  env$satir_tamponu <- env$satir_tamponu[-seq_len(dusurulecek)]

  # Düşen kayıtlar arasındaki araç/sonuç olayları AYRI tamponda korunur.
  # Sınıflandırma UCUZ bir alt dize denetimidir (her satırda JSON ayrıştırmak
  # canlı akış döngüsünü yavaşlatırdı); yanlış pozitif yalnızca fazladan bir
  # satırın korunmasına yol açar, veri kaybına yol açmaz.
  if (is.null(env$arac_tamponu)) env$arac_tamponu <- list()
  if (length(env$arac_tamponu) < CC_STREAM_TOOL_KEEP_MAX) {
    for (kayit in dusen) {
      metin <- as.character(kayit)[1]
      if (is.na(metin) || !nzchar(metin)) next
      if (!grepl("tool_use", metin, fixed = TRUE) &&
          !grepl("tool_result", metin, fixed = TRUE)) next
      env$arac_tamponu[[length(env$arac_tamponu) + 1L]] <- metin
      if (length(env$arac_tamponu) >= CC_STREAM_TOOL_KEEP_MAX) break
    }
  }

  dusen_bayt <- sum(vapply(
    dusen, function(x) nchar(as.character(x)[1], type = "bytes"), numeric(1)
  ))
  env$stdout_bayt <- max(0, (env$stdout_bayt %||% 0) - dusen_bayt)
  invisible(NULL)
}

# Ayrıştırma girdisi: KORUNAN araç olayları + bütçe içindeki ham tampon.
#
# Kronolojik sıra korunur (araç olayları akışın başındandır), böylece
# `tool_result` kayıtları ilgili `tool_use` girdisine eşleşmeye devam eder.
# Her iki akış yolu (canlı poll gözlemcisi ve bağımsız streaming yardımcısı) bu
# tek yardımcıyı kullanır; aksi hâlde biri korunan araç olaylarını görmezdi.
cc_stream_all_lines <- function(env) {
  arac <- as.character(unlist(env$arac_tamponu %||% list(), use.names = FALSE))
  ham <- as.character(unlist(env$satir_tamponu %||% list(), use.names = FALSE))
  c(arac, ham)
}

# Ham tampon kırpıldı mı? Kırpıldıysa delta tabanlı metin EKSİKTİR ve son
# `result` kaydındaki tam metin yetkilidir (bkz. `prefer_result_text`).
cc_stream_buffer_trimmed <- function(env) {
  isTRUE(env$satir_tamponu_kirpildi) ||
    isTRUE(env$stdout_bayt_kirpildi) ||
    isTRUE(env$satir_kaydi_kirpildi)
}

cc_stream_append_line <- function(env, satir) {
  if (is.null(env$satir_tamponu)) env$satir_tamponu <- list()

  # KAYIT BAŞINA bayt sınırı: tek bir devasa satır (ör. base64 gövde) hem
  # tamponu hem cc_stream_collect_lines() kopyasını şişirebiliyordu.
  satir <- as.character(satir)[1]
  if (is.na(satir)) satir <- ""
  # Dönüş değeri: kayıt bütçe İÇİNDE mi? Çağıranlar bütçeyi aşan kaydı
  # `parse_streaming_chunk()` / `send_parca()` yoluna sokmaz; kırpma yalnızca
  # SAKLANAN kopyayı sınırlıyor, ayrıştırma ham kaydı işlemeye devam ediyordu.
  butce_icinde <- TRUE
  if (nchar(satir, type = "bytes") > CC_STREAM_MAX_RECORD_BYTES) {
    butce_icinde <- FALSE
    satir <- cc_output_truncate_bytes(satir, CC_STREAM_MAX_RECORD_BYTES)
    if (!isTRUE(env$satir_kaydi_kirpildi)) {
      env$satir_kaydi_kirpildi <- TRUE
      try(log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Canlı akış kaydı bayt sınırını aştı; kayıt kırpıldı:",
        CC_STREAM_MAX_RECORD_BYTES
      )), silent = TRUE)
    }
  }

  if (length(env$satir_tamponu) >= CC_STREAM_MAX_LINES) {
    if (!isTRUE(env$satir_tamponu_kirpildi)) {
      env$satir_tamponu_kirpildi <- TRUE
      try(log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Canlı akış satır sınırına ulaşıldı; en eski satırlar düşürülüyor:",
        CC_STREAM_MAX_LINES
      )), silent = TRUE)
    }
    # En eski çeyreği düş; JSONL sonuç satırları akışın sonunda gelir.
    .cc_stream_trim_oldest(env, as.integer(CC_STREAM_MAX_LINES / 4L))
  }

  env$satir_tamponu[[length(env$satir_tamponu) + 1L]] <- satir
  env$stdout_bayt <- (env$stdout_bayt %||% 0) + nchar(satir, type = "bytes")

  # TOPLAM stdout bayt sınırı: satır sayısı sınırın altındayken bile çok sayıda
  # büyük kayıt belleği doldurabiliyordu.
  while ((env$stdout_bayt %||% 0) > CC_STREAM_MAX_STDOUT_BYTES &&
         length(env$satir_tamponu) > 1L) {
    if (!isTRUE(env$stdout_bayt_kirpildi)) {
      env$stdout_bayt_kirpildi <- TRUE
      try(log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Canlı akış stdout bayt sınırına ulaşıldı; en eski satırlar düşürülüyor:",
        CC_STREAM_MAX_STDOUT_BYTES
      )), silent = TRUE)
    }
    .cc_stream_trim_oldest(env, max(1L, as.integer(length(env$satir_tamponu) / 4L)))
  }

  invisible(butce_icinde)
}

# Geriye dönük ad: `helpers_claude_code_streaming.R` bu adı kullanır.
cc_stream_line_budget_add <- function(env, satir) {
  cc_stream_append_line(env, satir)
}

# İPTAL/DEADLINE denetimi: geri çağrı verilmemişse ya da hata fırlatırsa
# FAIL-OPEN (iptal edilmedi) sayılır; aksi hâlde tek bir bozuk sonda tüm çıktı
# toplamayı durdururdu. R/helpers_claude_code_downloads.R bu yardımcıyı
# paylaşır (o dosya 24 fonksiyon tavanındadır).
cc_cancel_requested <- function(cancel_fn) {
  if (!is.function(cancel_fn)) return(FALSE)
  isTRUE(tryCatch(cancel_fn(), error = function(e) FALSE))
}
