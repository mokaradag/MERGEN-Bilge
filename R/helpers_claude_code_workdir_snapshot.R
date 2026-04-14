# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_workdir_snapshot.R
# Açıklama: Bilge Yolaç çalışma dizini için çalıştırma öncesi/sonrası dosya
#           anlık görüntüsü (snapshot) üretir, yeni/değişmiş dosyaları tespit
#           eder ve üretilen .txt dosyalarının Türkçe karakter kodlamasını
#           UTF-8'e normalize eder. Böylece Claude Code CLI'ın kendi
#           araçlarıyla (Bash ile python/officer gibi) .docx, .xlsx veya .txt
#           gibi dosyalar oluşturduğunda bu dosyalar da indirme bağlantısına
#           çevrilebilir ve Windows Notepad'de mojibake görülmeden açılabilir.
#           Tüm akış çevrimdışı çalışır; ek paket veya internet gerektirmez.
# ==============================================================================

# ------------------------------------------------------------------------------
# ÇALIŞMA DİZİNİ ANLIK GÖRÜNTÜSÜ
# Claude Code çalıştırılmadan önce dizindeki tüm dosyaların (mtime + boyut)
# haritasını çıkarır. Çalıştırma bittiğinde karşılaştırma yapılır ve
# yeni/değişmiş dosyalar tespit edilir.
# ------------------------------------------------------------------------------

#' Çalışma dizinindeki dosyaların anlık görüntüsünü al
#'
#' @param workdir Taranacak kök dizin
#' @param recursive Alt dizinleri de tara (varsayılan TRUE)
#' @param max_files Performans için üst sınır
#' @return Yol -> list(mtime, size) biçiminde isimlendirilmiş liste
snapshot_claude_code_workdir_files <- function(workdir,
                                                recursive = TRUE,
                                                max_files = 5000L) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) {
    return(list())
  }

  ogeler <- tryCatch(
    list.files(
      workdir,
      full.names = TRUE,
      recursive = recursive,
      all.files = FALSE,
      include.dirs = FALSE,
      no.. = TRUE
    ),
    error = function(e) character(0)
  )

  if (!length(ogeler)) {
    return(list())
  }

  # Yalnızca gerçek dosyaları tut (yanlışlıkla dizin yakalanmışsa çıkar)
  ogeler <- ogeler[!dir.exists(ogeler)]

  if (!length(ogeler)) {
    return(list())
  }

  if (length(ogeler) > max_files) {
    ogeler <- ogeler[seq_len(max_files)]
  }

  bilgi <- tryCatch(file.info(ogeler), error = function(e) NULL)

  if (is.null(bilgi) || nrow(bilgi) == 0L) {
    return(list())
  }

  sonuc <- list()

  for (i in seq_along(ogeler)) {
    yol_norm <- tryCatch(
      normalizePath(ogeler[i], winslash = "/", mustWork = FALSE),
      error = function(e) ogeler[i]
    )

    mtime_val <- suppressWarnings(as.numeric(bilgi$mtime[i]))
    size_val <- suppressWarnings(as.numeric(bilgi$size[i]))

    sonuc[[yol_norm]] <- list(
      mtime = if (is.finite(mtime_val)) mtime_val else NA_real_,
      size = if (is.finite(size_val)) size_val else NA_real_
    )
  }

  sonuc
}

#' İki anlık görüntü arasındaki yeni veya değişmiş dosyaları döndür
#'
#' @param before_snapshot snapshot_claude_code_workdir_files çıktısı
#' @param workdir Tekrar taranacak dizin
#' @param recursive Alt dizinleri de tara
#' @param max_files Üst sınır
#' @return Yeni/değişmiş dosyaların yollarını içeren karakter vektörü
diff_claude_code_workdir_snapshot <- function(before_snapshot,
                                               workdir,
                                               recursive = TRUE,
                                               max_files = 5000L) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) {
    return(character(0))
  }

  sonraki <- snapshot_claude_code_workdir_files(
    workdir = workdir,
    recursive = recursive,
    max_files = max_files
  )

  if (!length(sonraki)) {
    return(character(0))
  }

  once <- if (is.list(before_snapshot)) before_snapshot else list()

  yeni_veya_degisen <- character(0)

  for (yol in names(sonraki)) {
    eski <- once[[yol]]
    yeni <- sonraki[[yol]]

    if (is.null(eski)) {
      yeni_veya_degisen <- c(yeni_veya_degisen, yol)
      next
    }

    degisti <- FALSE

    if (!isTRUE(all.equal(eski$mtime, yeni$mtime))) {
      degisti <- TRUE
    }

    if (!isTRUE(all.equal(eski$size, yeni$size))) {
      degisti <- TRUE
    }

    if (isTRUE(degisti)) {
      yeni_veya_degisen <- c(yeni_veya_degisen, yol)
    }
  }

  # Bilge Yolaç iç yardımcı çıktılarını hariç tut
  # (doküman özet destek dizini, rehber dosyası vb.)
  haric_desenler <- c(
    "/BILGE_YOLAC_DOKUMAN_REHBERI\\.md$",
    "/document_support/",
    "/\\.document_support/"
  )

  for (desen in haric_desenler) {
    yeni_veya_degisen <- yeni_veya_degisen[
      !grepl(desen, yeni_veya_degisen, perl = TRUE)
    ]
  }

  unique(yeni_veya_degisen)
}

# ------------------------------------------------------------------------------
# TÜRKÇE .TXT KODLAMA NORMALİZASYONU
# Claude Code CLI, Windows VM üzerinde bazen Türkçe karakterleri UTF-8
# olarak yazmayabilir veya BOM üretmediği için Notepad dosyayı CP1254 olarak
# yorumlayarak mojibake gösterir. Bu yardımcı dosyayı güvenli biçimde
# yeniden okur, geçerli UTF-8 değilse WINDOWS-1254 olarak yorumlar, ardından
# UTF-8 (BOM ile) olarak geri yazar.
# ------------------------------------------------------------------------------

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
    # Windows Türkçe kod sayfası (CP1254) ve yedek kodlamalar
    denemeler <- c("WINDOWS-1254", "CP1254", "latin5", "latin1")

    metin_utf8 <- NA_character_

    for (kod in denemeler) {
      aday <- tryCatch(
        {
          ham_metin <- rawToChar(icerik_ham)
          Encoding(ham_metin) <- "unknown"
          donusum <- iconv(
            ham_metin,
            from = kod,
            to = "UTF-8",
            sub = NA
          )
          donusum
        },
        error = function(e) NA_character_
      )

      if (!is.na(aday) && nzchar(aday)) {
        metin_utf8 <- aday
        break
      }
    }

    if (is.na(metin_utf8) || !nzchar(metin_utf8)) {
      return(FALSE)
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
                                                           tool_uses = list(),
                                                           runtime_workdir = "",
                                                           source_workdir = "",
                                                           user_id = 0L,
                                                           session_token = "") {
  # 1) Çalışma dizini taraması ile yeni/değişmiş dosyaları bul
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

  # 2) Araç kullanımlarından gelen yolları da ekle (yedek)
  arac_yollari <- tryCatch(
    list_claude_code_generated_file_paths(
      tool_uses = tool_uses,
      runtime_workdir = runtime_workdir,
      source_workdir = source_workdir
    ),
    error = function(e) character(0)
  )

  tum_yollar <- unique(c(yeni_dosyalar, arac_yollari))
  tum_yollar <- tum_yollar[nzchar(tum_yollar)]

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
      session_token = session_token
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
