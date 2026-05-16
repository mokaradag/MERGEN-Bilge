# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_workdir_snapshot.R
# Açıklama: Bilge Yolaç çalışma dizininden tespit edilen yeni/değişmiş dosyaları
#           indirilebilir kayıtlara dönüştürür ve üretilen düz metin dosyalarının
#           Türkçe karakter kodlamasını UTF-8'e normalize eder. Snapshot/diff,
#           yol kanonikleştirme ve dosya kararlılık yardımcıları
#           R/helpers_claude_code_workdir_scan.R içinde tutulur.
#           Tüm akış çevrimdışı çalışır; ek paket veya internet gerektirmez.
# ==============================================================================

# ------------------------------------------------------------------------------
# NİYET, YOL KANONİKLEŞTİRME VE SNAPSHOT/DIFF YARDIMCILARI
# ------------------------------------------------------------------------------
# Bu sorumluluklar R/helpers_claude_code_workdir_scan.R dosyasına taşınmıştır.
# Bu dosya yalnızca metin kodlama normalizasyonu ve indirme toplama/staging
# orkestrasyonuna odaklanır.

# ------------------------------------------------------------------------------
# TÜRKÇE .TXT KODLAMA NORMALİZASYONU
# Claude Code CLI, Windows VM üzerinde Türkçe içerikli .txt dosyalarını
# aşağıdaki kodlamalardan biriyle yazabilir:
#   * UTF-8 (BOM'suz) -> Notepad CP1254 sanar -> mojibake
#   * WINDOWS-1254     -> Windows Türkçe ANSI (GUI araçları)
#   * CP857            -> Windows Türkçe OEM (cmd.exe echo çıktıları)
#   * CP850 / CP437    -> Eski cmd.exe Latin OEM
#   * CP1252           -> Batı Avrupa ANSI
# Bu yardımcı dosyayı güvenli biçimde okur, her aday kodlama için Türkçe
# karakter sayısından mojibake örüntü cezasını çıkararak en iyi adayı seçer,
# ardından UTF-8 (BOM ile) olarak geri yazar.
# ------------------------------------------------------------------------------

#' Aday kodlamaları Türkçe karakter yoğunluğuna göre puanla
#'
#' @param aday Çözülmüş metin
#' @return Puan: Türkçe karakter sayısı - (mojibake örüntü sayısı * 10)
score_turkish_decoding_candidate <- function(aday) {
  if (is.null(aday) || is.na(aday) || !nzchar(aday)) return(-1L)

  # Türkçe ayırt edici karakterler
  tr_deseni <- "[\u00e7\u011f\u0131\u0130\u00f6\u015f\u00fc\u00c7\u011e\u00d6\u015e\u00dc]"

  tr_sayisi <- tryCatch(
    {
      eslesmeler <- gregexpr(tr_deseni, aday, perl = TRUE)[[1]]
      if (length(eslesmeler) == 1 && eslesmeler[1] == -1L) 0L
      else length(eslesmeler)
    },
    error = function(e) 0L
  )

  # UTF-8 baytlarının WINDOWS-1254/1252 olarak yorumlanmasından doğan
  # tipik mojibake sekansları
  mojibake_deseni <- paste(
    c(
      "\u00c3[\u00a7\u0178\u00bc\u00b6\u00b1\u00bd]",  # Ã§, ÃŸ, Ã¼, Ã¶, Ã±, Ã½
      "\u00c5[\u0178\u009e]",                            # ÅŸ, Åž
      "\u00c4\u00b1",                                     # Ä±
      "\u00ef\u00bf\u00bd",                               # U+FFFD replacement
      "\u00c2[\u00a0-\u00bf]"                             # Â followed by control
    ),
    collapse = "|"
  )

  mojibake_sayisi <- tryCatch(
    {
      eslesmeler <- gregexpr(mojibake_deseni, aday, perl = TRUE)[[1]]
      if (length(eslesmeler) == 1 && eslesmeler[1] == -1L) 0L
      else length(eslesmeler)
    },
    error = function(e) 0L
  )

  as.integer(tr_sayisi) - (as.integer(mojibake_sayisi) * 10L)
}

#' Ham baytlardan en iyi Türkçe kodlama adayını seç
#'
#' @param icerik_ham Raw vektör
#' @return En iyi UTF-8 metin (veya NA)
pick_best_turkish_decoding <- function(icerik_ham) {
  if (!length(icerik_ham)) return(NA_character_)

  # Windows kodlamaları ilk sırada — Bilge Yolaç çoğunlukla bu ortamda üretir
  denemeler <- c(
    "WINDOWS-1254",
    "CP857",
    "CP1254",
    "CP1252",
    "CP850",
    "CP437",
    "latin5",
    "latin1"
  )

  en_iyi_metin <- NA_character_
  en_iyi_skor <- -1L

  ham_metin_tabani <- tryCatch(rawToChar(icerik_ham), error = function(e) NA_character_)
  if (is.na(ham_metin_tabani)) return(NA_character_)

  for (kod in denemeler) {
    aday <- tryCatch(
      {
        s <- ham_metin_tabani
        Encoding(s) <- "unknown"
        donusum <- iconv(s, from = kod, to = "UTF-8", sub = NA)
        donusum
      },
      error = function(e) NA_character_
    )

    if (is.na(aday) || !nzchar(aday)) next

    skor <- score_turkish_decoding_candidate(aday)

    if (skor > en_iyi_skor) {
      en_iyi_skor <- skor
      en_iyi_metin <- aday
    }
  }

  en_iyi_metin
}

#' Türkçe metin dosyasını UTF-8 (BOM ile) olarak normalize et
#'
#' @param file_path Hedef dosya yolu
#' @return Normalizasyon yapıldıysa TRUE, aksi halde FALSE
normalize_claude_code_text_file_to_utf8 <- function(file_path) {
  if (is.null(file_path) || !nzchar(file_path)) return(FALSE)
  if (!isTRUE(file.exists(file_path))) return(FALSE)
  if (isTRUE(dir.exists(file_path))) return(FALSE)

  boyut <- tryCatch(
    suppressWarnings(as.numeric(file.info(file_path)$size[1])),
    error = function(e) NA_real_
  )

  if (!is.finite(boyut) || boyut <= 0) return(FALSE)
  # Aşırı büyük dosyaları atla (20 MB üzeri)
  if (boyut > 20L * 1024L * 1024L) return(FALSE)

  ham <- tryCatch(
    readBin(file_path, what = "raw", n = as.integer(boyut)),
    error = function(e) raw(0)
  )

  if (!length(ham)) return(FALSE)

  utf8_bom <- as.raw(c(0xEF, 0xBB, 0xBF))
  bom_mevcut <- length(ham) >= 3 && identical(ham[1:3], utf8_bom)

  icerik_ham <- if (isTRUE(bom_mevcut)) ham[-(1:3)] else ham

  if (!length(icerik_ham)) return(FALSE)

  # NUL baytlarını temizle (rawToChar gömülü NUL'da hata verir)
  icerik_ham <- icerik_ham[icerik_ham != as.raw(0L)]

  if (!length(icerik_ham)) return(FALSE)

  # Önce UTF-8 olarak yorumla
  metin_utf8 <- tryCatch(
    {
      s <- rawToChar(icerik_ham)
      Encoding(s) <- "UTF-8"
      s
    },
    error = function(e) NA_character_
  )

  utf8_gecerli <- FALSE

  if (!is.na(metin_utf8) && nzchar(metin_utf8)) {
    utf8_gecerli <- tryCatch(
      isTRUE(all(validUTF8(metin_utf8))),
      error = function(e) FALSE
    )
  }

  if (!isTRUE(utf8_gecerli)) {
    # Geçersiz UTF-8: aday kodlamaları Türkçe karakter puanına göre dene
    metin_utf8 <- pick_best_turkish_decoding(icerik_ham)

    if (is.na(metin_utf8) || !nzchar(metin_utf8)) {
      return(FALSE)
    }
  } else {
    # UTF-8 geçerli olsa bile, UTF-8 baytlarının WINDOWS-1254 olarak yorumlanmış
    # olma olasılığını kontrol et. Mojibake örüntüsü varsa Türkçe puanına göre
    # daha iyi bir aday kodlama varsa ona geç.
    mevcut_skor <- score_turkish_decoding_candidate(metin_utf8)

    if (mevcut_skor < 0) {
      aday <- pick_best_turkish_decoding(icerik_ham)
      aday_skor <- score_turkish_decoding_candidate(aday)

      if (!is.na(aday) && nzchar(aday) && aday_skor > mevcut_skor) {
        metin_utf8 <- aday
      }
    }
  }

  # Her ihtimale karşı çıktıyı zorla UTF-8'e işaretle
  metin_utf8 <- enc2utf8(metin_utf8)

  # UTF-8 BOM + içerik olarak geri yaz
  cikti_baytlari <- tryCatch(
    c(utf8_bom, charToRaw(metin_utf8)),
    error = function(e) raw(0)
  )

  if (!length(cikti_baytlari)) return(FALSE)

  tryCatch({
    baglanti <- file(file_path, open = "wb")
    on.exit(close(baglanti), add = TRUE)
    writeBin(cikti_baytlari, baglanti)
    TRUE
  }, error = function(e) FALSE)
}

#' Birden çok dosya için Türkçe metin kodlama normalizasyonu uygula
#'
#' @param file_paths Dosya yolları
#' @param extensions Hedef uzantılar (varsayılan: txt, log, csv, md)
#' @return Normalizasyon yapılan dosyaların yolları
normalize_claude_code_text_files <- function(file_paths,
                                              extensions = c("txt", "log", "csv", "md")) {
  file_paths <- unique(Filter(nzchar, as.character(file_paths %||% character(0))))

  if (!length(file_paths)) return(character(0))

  uygulananlar <- character(0)

  for (yol in file_paths) {
    uzanti <- tolower(tools::file_ext(yol))

    if (!(uzanti %in% tolower(extensions))) next

    basarili <- tryCatch(
      normalize_claude_code_text_file_to_utf8(yol),
      error = function(e) FALSE
    )

    if (isTRUE(basarili)) {
      uygulananlar <- c(uygulananlar, yol)
    }
  }

  uygulananlar
}

# ------------------------------------------------------------------------------
# ANA TOPLAYICI
# Çalışma dizini taramasını, araç kullanım yollarını ve .txt kodlama
# düzeltmesini birleştirerek indirme kayıtlarını üretir.
# ------------------------------------------------------------------------------

#' Çalışma dizini değişikliklerinden indirme kayıtlarını topla
#'
#' Bu fonksiyon iki kaynaktan dosya toplar:
#'   1) Çalıştırma öncesi alınan snapshot ile mevcut durum arasındaki fark
#'      (Claude Code'un Bash üzerinden python/officer gibi araçlarla ürettiği
#'       .docx, .xlsx vb. dosyalar bu yolla yakalanır)
#'   2) Claude Code araç kullanımlarındaki dosya yolları (Write/Edit tool)
#'
#' Ardından .txt dosyaları için Türkçe karakter kodlamasını UTF-8 BOM olarak
#' normalize eder ve stage_claude_code_downloads ile indirme kayıtlarını
#' oluşturur.
#'
#' @param before_snapshot Çalıştırma öncesi snapshot (veya list())
#' @param tool_uses Claude Code araç kullanımları
#' @param runtime_workdir Claude Code runtime dizini
#' @param source_workdir Kullanıcının seçtiği kaynak dizin
#' @param user_id Kullanıcı kimliği
#' @param session_token Shiny oturum anahtarı
#' @return İndirme kayıtları listesi
collect_claude_code_workdir_changes_downloads <- function(before_snapshot,
                                                           source_before_snapshot = NULL,
                                                           tool_uses = list(),
                                                           runtime_workdir = "",
                                                           source_workdir = "",
                                                           user_id = 0L,
                                                           session_token = "") {
  runtime_norm <- tryCatch(
    normalizePath(runtime_workdir, winslash = "/", mustWork = FALSE),
    error = function(e) runtime_workdir
  )

  source_norm <- tryCatch(
    normalizePath(source_workdir, winslash = "/", mustWork = FALSE),
    error = function(e) source_workdir
  )

  same_runtime_source <- nzchar(runtime_norm) &&
    nzchar(source_norm) &&
    identical(tolower(runtime_norm), tolower(source_norm))

  allowed_roots <- unique(c(
    cc_policy_allowed_output_roots(
      user_id = user_id,
      workdir = runtime_workdir %||% source_workdir
    ),
    if (nzchar(source_workdir)) {
      cc_policy_allowed_output_roots(user_id = user_id, workdir = source_workdir)
    } else {
      character(0)
    },
    if (nzchar(runtime_workdir)) {
      cc_policy_allowed_output_roots(user_id = user_id, workdir = runtime_workdir)
    } else {
      character(0)
    }
  ))

  # 1) Runtime dizininde yeni/değişmiş dosyaları bul
  yeni_dosyalar <- character(0)

  if (nzchar(runtime_workdir) && dir.exists(runtime_workdir)) {
    yeni_dosyalar <- tryCatch(
      diff_claude_code_workdir_snapshot(
        before_snapshot = before_snapshot,
        workdir = runtime_workdir
      ),
      error = function(e) character(0)
    )
  }

  # 1B) Kaynak/asıl dizinde yeni/değişmiş dosyaları da bul.
  # Bazı durumlarda model dosyayı doğrudan kaynak klasöre yazabilir.
  kaynak_yeni_dosyalar <- character(0)

  if (!isTRUE(same_runtime_source) &&
      nzchar(source_workdir) &&
      dir.exists(source_workdir)) {
    kaynak_yeni_dosyalar <- tryCatch(
      diff_claude_code_workdir_snapshot(
        before_snapshot = source_before_snapshot %||% list(),
        workdir = source_workdir
      ),
      error = function(e) character(0)
    )
  }

  # 2) Araç kullanımlarından gelen yolları da ekle (yedek)
  arac_yollari <- tryCatch(
    list_claude_code_generated_file_paths(
      tool_uses = tool_uses,
      runtime_workdir = runtime_workdir,
      source_workdir = source_workdir,
      allowed_roots = allowed_roots,
      user_id = user_id
    ),
    error = function(e) character(0)
  )

  # Windows 8.3 kısa adlarıyla uzun adları birleştir ve büyük/küçük harf
  # farklılıklarını kaldır. Aksi halde aynı dosya hem "R_helpers_..._summary.txt"
  # hem de "R_HELP~1.TXT" olarak iki indirme kartı olarak görünür.
  #
  # CLI döndükten hemen sonra Windows üzerinde dosya mtime/size bilgisi kısa
  # süre oynayabilir. Normalizasyon veya staging başlamadan önce kısa ve
  # davranış-koruyucu bir kararlılık kontrolü uygula.
  tum_yollar <- wait_for_stable_claude_code_file_paths(
    file_paths = c(yeni_dosyalar, kaynak_yeni_dosyalar, arac_yollari)
  )

  # Yalnızca kullanıcıya indirilebilir çıktı/artifact dosyalarını yakala.
  # Mevcut proje kaynak dosyaları (.R, .py, .js vb.) analiz edilmiş veya okunmuş
  # olabilir; bunlar "oluşturulan dosya" olarak gösterilmemelidir.
  indirilebilir_uzantilar <- c(
    "txt", "md", "csv", "log", "json", "html", "htm", "rtf",
    "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pdf",
    "png", "jpg", "jpeg", "gif", "webp", "svg", "zip"
  )

  tum_yollar <- tum_yollar[
    tolower(tools::file_ext(tum_yollar)) %in% indirilebilir_uzantilar
  ]

  # Bilge Yolaç iç yardımcı çıktıları ve staging klasörü kullanıcı çıktısı değildir.
  if (length(tum_yollar)) {
    tum_yollar_norm <- gsub("\\\\", "/", tum_yollar)

    haric_desenler <- c(
      "/BILGE_YOLAC_DOKUMAN_REHBERI\\.md$",
      "/document_support/",
      "/\\.document_support/",
      "/bilge_yolac_downloads/"
    )

    for (desen in haric_desenler) {
      tum_yollar <- tum_yollar[
        !grepl(desen, tum_yollar_norm, perl = TRUE)
      ]
      tum_yollar_norm <- gsub("\\\\", "/", tum_yollar)
    }
  }

  if (!length(tum_yollar)) return(list())

  tum_yollar <- cc_policy_filter_generated_file_paths(
    tum_yollar,
    allowed_roots = allowed_roots,
    context = "çalışma çıktısı"
  )

  if (!length(tum_yollar)) return(list())

  # 3) .txt (ve benzeri düz metin) dosyaları için Türkçe karakter kodlamasını
  #    UTF-8 BOM olarak normalize et. Böylece Windows Notepad'de mojibake
  #    görülmeden açılabilir. .docx / .xlsx / .pdf gibi binary dosyalar
  #    otomatik olarak atlanır.
  tryCatch(
    normalize_claude_code_text_files(
      file_paths = tum_yollar,
      extensions = c("txt", "log", "csv", "md")
    ),
    error = function(e) NULL
  )

  # 4) Dosyaları indirme alanına kopyala
  indirmeler <- tryCatch(
    stage_claude_code_downloads(
      file_paths = tum_yollar,
      user_id = user_id,
      session_token = session_token,
      allowed_roots = allowed_roots
    ),
    error = function(e) list()
  )

  if (!length(indirmeler)) return(list())

  # Görüntülenecek göreli yolu hesapla
  for (i in seq_along(indirmeler)) {
    indirmeler[[i]]$display_path <- tryCatch(
      build_claude_code_display_path(
        file_path = indirmeler[[i]]$original_path,
        runtime_workdir = runtime_workdir,
        source_workdir = source_workdir
      ),
      error = function(e) basename(indirmeler[[i]]$original_path %||% "")
    )
  }

  indirmeler
}