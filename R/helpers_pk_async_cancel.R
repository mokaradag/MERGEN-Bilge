# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_cancel.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ TARAFINDAN GÖRÜLEBİLEN iptal jetonu ve
#           duvar-saati son tarih aritmetiği.
#
# Neden dosya tabanlı jeton: senkron yol aşamalar arasında `stop_check`
# çağırıyordu; o bir REAKTİF KAPANIŞTIR ve explicit-mode bir future'a
# serileştirilemez. Geri çağrıyı atmak işçiyi ÇALIŞMAYA DEVAM ETTİRİR — DB
# bağlantısını ve işçi yuvasını tutmaya devam eder. Bir tutam durdurulmuş veya
# yavaş analiz havuzu tüketip her kullanıcıyı bekletir. Bu yüzden gerçek
# akış hattındaki `stop_file` deseni (streaming_should_stop()) yeniden
# kullanılır: dosya varlığı süreçler arasında görülebilir tek sinyaldir.
#
# Bu dosya SAFTIR ve İŞÇİ-GÜVENLİDİR: Shiny, reaktif değer, DB bağlantısı veya
# ağ bağımlılığı YOKTUR. Yalnızca dosya sistemi ve saat okur.
# ==============================================================================

# İptal jetonlarının kök dizini. Bilge Yolaç indirme kökünden AYRIDIR: bu
# dosyalar geçicidir ve tarayıcıya asla servis edilmez.
pk_cancel_token_root <- function(base_dir = NULL) {
  kok <- if (!is.null(base_dir) && nzchar(as.character(base_dir)[1])) {
    as.character(base_dir)[1]
  } else {
    file.path(tempdir(), "mergen_pk_cancel")
  }

  if (!dir.exists(kok)) {
    tryCatch(dir.create(kok, recursive = TRUE, showWarnings = FALSE), error = function(e) NULL)
  }

  kok
}

# İstek kimliğinden dosya adı üretir. Kimlik kullanıcı girdisi DEĞİLDİR ama
# yine de yol ayırıcı/traversal taşıyamaması için ASCII-güvenli hâle getirilir.
.pk_cancel_token_slug <- function(request_id) {
  ham <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.null(ham) || length(ham) == 0L || is.na(ham) || !nzchar(ham)) {
    ham <- paste0("anon_", as.integer(Sys.time()))
  }

  # NOKTA da BİLİNÇLİ olarak dışlanır: `.` izin verilseydi "../../x" girdisi
  # ".._.._x" üretirdi. Yol ayırıcı olmadığı için bu bir traversal değildi, ama
  # dosya adında `..` bulunmaması daha güvenli ve denetlenmesi daha kolaydır.
  # Uzantı (`.flag`) çağıran tarafından eklenir.
  temiz <- gsub("[^A-Za-z0-9_-]", "_", ham)
  temiz <- substr(temiz, 1L, 120L)
  if (!nzchar(temiz)) temiz <- "anon"
  temiz
}

#' İstek için iptal jetonu yolunu üret (dosyayı OLUŞTURMAZ)
#'
#' Jeton yalnızca DURDURMA anında oluşturulur; yokluğu "iptal edilmedi"
#' anlamına gelir. Bu, gerçek akış hattındaki `stop_file` semantiğinin aynısıdır.
pk_cancel_token_path <- function(request_id, base_dir = NULL) {
  file.path(
    pk_cancel_token_root(base_dir),
    paste0("pk_stop_", .pk_cancel_token_slug(request_id), ".flag")
  )
}

#' İptali işaretle (durdurma butonu / oturum sonu / bayat istek)
#'
#' @return `TRUE` dosya yazıldıysa; hata durumunda `FALSE` (asla `stop()`).
pk_cancel_token_signal <- function(token_path) {
  if (is.null(token_path)) return(invisible(FALSE))
  yol <- tryCatch(as.character(token_path)[1], error = function(e) NA_character_)
  if (is.na(yol) || !nzchar(yol)) return(invisible(FALSE))

  ebeveyn <- dirname(yol)
  if (nzchar(ebeveyn) && !dir.exists(ebeveyn)) {
    tryCatch(dir.create(ebeveyn, recursive = TRUE, showWarnings = FALSE), error = function(e) NULL)
  }

  ok <- tryCatch({
    con <- file(yol, open = "wb")
    on.exit(close(con), add = TRUE)
    writeBin(charToRaw("1"), con)
    TRUE
  }, error = function(e) FALSE)

  invisible(isTRUE(ok))
}

#' Jeton işaretlenmiş mi?
#'
#' `streaming_should_stop()` ile AYNI katı semantik: yalnızca GERÇEK bir dosya
#' durdurma bayrağıdır. Dizin, boş metin, `NULL` veya `NA` durdurma DEĞİLDİR —
#' aksi hâlde yanlışlıkla oluşturulmuş bir dizin her analizi iptal ederdi.
pk_cancel_token_is_signalled <- function(token_path) {
  if (is.null(token_path)) return(FALSE)

  aday <- tryCatch(as.character(token_path)[1], error = function(e) "")
  if (is.null(aday) || length(aday) == 0L || is.na(aday) || !nzchar(aday)) return(FALSE)
  if (!isTRUE(file.exists(aday))) return(FALSE)

  bilgi <- suppressWarnings(file.info(aday))
  dosya_mi <- is.data.frame(bilgi) && nrow(bilgi) >= 1L && isTRUE(!isTRUE(bilgi$isdir[1]))
  isTRUE(dosya_mi)
}

#' Jetonu temizle (istek bittiğinde; en iyi çaba)
pk_cancel_token_clear <- function(token_path) {
  if (is.null(token_path)) return(invisible(FALSE))
  yol <- tryCatch(as.character(token_path)[1], error = function(e) NA_character_)
  if (is.na(yol) || !nzchar(yol)) return(invisible(FALSE))
  if (!isTRUE(file.exists(yol))) return(invisible(FALSE))

  bilgi <- suppressWarnings(file.info(yol))
  if (is.data.frame(bilgi) && nrow(bilgi) >= 1L && isTRUE(bilgi$isdir[1])) {
    return(invisible(FALSE))
  }

  invisible(isTRUE(suppressWarnings(file.remove(yol))))
}

#' Bayat jetonları yaşa göre temizle (sızıntı önleme; en iyi çaba)
#'
#' Süreç çöktüğünde jeton dosyası kalır. Yaş tabanlı temizlik, AKTİF bir isteğin
#' jetonuna asla dokunmaz çünkü aktif jeton yalnızca durdurma anında yazılır ve
#' istek sonunda silinir.
pk_cancel_token_cleanup_stale <- function(base_dir = NULL, max_age_sec = 3600) {
  kok <- pk_cancel_token_root(base_dir)
  if (!dir.exists(kok)) return(invisible(0L))

  yas <- suppressWarnings(as.numeric(max_age_sec)[1])
  if (length(yas) != 1L || is.na(yas) || !is.finite(yas) || yas < 0) {
    return(invisible(0L))
  }

  dosyalar <- tryCatch(
    list.files(kok, pattern = "^pk_stop_.*\\.flag$", full.names = TRUE),
    error = function(e) character(0)
  )
  if (!length(dosyalar)) return(invisible(0L))

  simdi <- Sys.time()
  silinen <- 0L
  for (dosya in dosyalar) {
    bilgi <- suppressWarnings(file.info(dosya))
    if (!is.data.frame(bilgi) || nrow(bilgi) < 1L) next
    if (isTRUE(bilgi$isdir[1])) next

    gecen <- suppressWarnings(as.numeric(difftime(simdi, bilgi$mtime[1], units = "secs")))
    if (is.na(gecen) || gecen < yas) next
    if (isTRUE(suppressWarnings(file.remove(dosya)))) silinen <- silinen + 1L
  }

  invisible(silinen)
}

# ------------------------------------------------------------------------------
# DUVAR-SAATİ SON TARİH ARİTMETİĞİ
# ------------------------------------------------------------------------------

#' Analiz başlangıcından mutlak son tarih üret
#'
#' @param started_at Analizin başladığı zaman (POSIXct).
#' @param deadline_sec Toplam duvar-saati bütçesi (saniye).
#' @return POSIXct mutlak son tarih; geçersiz girdide `NA` (bütçe yok).
pk_deadline_at <- function(started_at, deadline_sec) {
  baslangic <- tryCatch(as.POSIXct(started_at), error = function(e) NA)
  if (length(baslangic) != 1L || is.na(baslangic)) return(as.POSIXct(NA))

  butce <- suppressWarnings(as.numeric(deadline_sec)[1])
  if (length(butce) != 1L || is.na(butce) || !is.finite(butce) || butce <= 0) {
    return(as.POSIXct(NA))
  }

  baslangic + butce
}

#' Son tarihe kalan saniye
#'
#' @return Kalan saniye (negatif olabilir). Son tarih yoksa `Inf` — sınırsız
#'   DEĞİL, "bu katmanda bütçe tanımlı değil" anlamındadır; çağıran yine kendi
#'   yapılandırılmış zaman aşımını uygular.
pk_deadline_remaining_sec <- function(deadline_at, now = Sys.time()) {
  if (length(deadline_at) != 1L || is.na(deadline_at)) return(Inf)

  simdi <- tryCatch(as.POSIXct(now), error = function(e) Sys.time())
  kalan <- suppressWarnings(as.numeric(difftime(deadline_at, simdi, units = "secs")))
  if (length(kalan) != 1L || is.na(kalan)) return(Inf)
  kalan
}

#' Son tarih doldu mu?
pk_deadline_expired <- function(deadline_at, now = Sys.time()) {
  kalan <- pk_deadline_remaining_sec(deadline_at, now = now)
  is.finite(kalan) && kalan <= 0
}

#' Bir ODBC ifadesi için ETKİN SQL zaman aşımını hesapla
#'
#' §9 sözleşmesi: `effective = min(çözülmüş SQL zaman aşımı, kalan bütçe)`.
#' Sorgu bazlı bir override yapılandırılmış SQL zaman aşımını YÜKSELTEBİLİR ama
#' analiz son tarihini ASLA uzatamaz. Pozitif bütçe kalmadıysa ifade
#' GÖNDERİLMEZ — bu, "ardışık geçerli zaman aşımlarının toplamı bütçeyi aşar"
#' hatasının tek gerçek çaresidir.
#'
#' @return `list(dispatch = TRUE/FALSE, timeout_sec = <int>, reason = <chr>)`.
pk_sql_timeout_plan <- function(configured_sec, remaining_sec) {
  yapilandirilmis <- suppressWarnings(as.numeric(configured_sec)[1])
  if (length(yapilandirilmis) != 1L || is.na(yapilandirilmis) ||
      !is.finite(yapilandirilmis) || yapilandirilmis <= 0) {
    yapilandirilmis <- Inf
  }

  kalan <- suppressWarnings(as.numeric(remaining_sec)[1])
  if (length(kalan) != 1L || is.na(kalan)) kalan <- Inf

  if (is.finite(kalan) && kalan <= 0) {
    return(list(dispatch = FALSE, timeout_sec = 0L, reason = "deadline_exhausted"))
  }

  etkin <- min(yapilandirilmis, kalan)
  if (!is.finite(etkin)) {
    # Ne yapılandırılmış zaman aşımı ne de bütçe var: sürücü varsayılanına
    # bırakmak yerine 0 döner ve çağıran zaman aşımı BELİRTMEZ.
    return(list(dispatch = TRUE, timeout_sec = 0L, reason = "no_limit"))
  }

  # Kesirli saniye ODBC tarafında güvenilir değildir; AŞAĞI yuvarlanır ki
  # etkin zaman aşımı kalan bütçeyi asla aşmasın. Aşağı yuvarlama 0 üretirse
  # bütçe pratikte tükenmiştir.
  saniye <- as.integer(floor(etkin))
  if (is.na(saniye) || saniye <= 0L) {
    return(list(dispatch = FALSE, timeout_sec = 0L, reason = "deadline_exhausted"))
  }

  sebep <- if (is.finite(kalan) && kalan < yapilandirilmis) "bounded_by_deadline" else "configured"
  list(dispatch = TRUE, timeout_sec = saniye, reason = sebep)
}

#' Aşama sınırında birleşik iptal/son tarih kapısı
#'
#' İşçi bunu PAHALI her adımdan ÖNCE çağırır. Tek tip sonuç döndürmesi,
#' "iptal", "zaman aşımı" ve "sıradan hata" ayrımının aşağı akışta
#' KAYBOLMAMASINI sağlar (§5.11: sessizce başarı gibi görünen bozulma yasak).
#'
#' @return `list(halt = TRUE/FALSE, status = "ok"|"cancelled"|"deadline")`.
pk_async_stage_gate <- function(token_path = NULL, deadline_at = NULL,
                                now = Sys.time()) {
  if (pk_cancel_token_is_signalled(token_path)) {
    return(list(halt = TRUE, status = "cancelled"))
  }

  if (!is.null(deadline_at) && pk_deadline_expired(deadline_at, now = now)) {
    return(list(halt = TRUE, status = "deadline"))
  }

  list(halt = FALSE, status = "ok")
}

# Kullanıcıya görünen Türkçe mesajlar. Zaman aşımı ile iptal AYRI mesajlardır:
# ikisini birleştirmek, kullanıcının durdurmadığı bir zaman aşımını "siz iptal
# ettiniz" diye raporlamak olurdu.
PK_ASYNC_CANCELLED_MESSAGE <- paste0(
  "\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi."
)

PK_ASYNC_DEADLINE_MESSAGE <- paste0(
  "\U000023F1\U0000FE0F **Analiz Zaman Aşımı:** Analiz ayrılan süre içinde ",
  "tamamlanamadı. Lütfen sorunuzu daraltıp tekrar deneyin."
)

#' Durum kodundan kullanıcıya görünen Türkçe mesaj
pk_async_halt_message <- function(status) {
  durum <- tryCatch(as.character(status)[1], error = function(e) NA_character_)
  if (identical(durum, "deadline")) return(PK_ASYNC_DEADLINE_MESSAGE)
  PK_ASYNC_CANCELLED_MESSAGE
}
