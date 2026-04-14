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
# NİYET TESPİTİ: İKİLİ DOKÜMAN ÜRETME / MEVCUTU OKUMA
# Bilge Yolaç doküman modu, çalışma dizinindeki mevcut .docx/.xlsx/.pdf
# dosyalarını yerel metin çıkarımıyla işler ve Claude'a "ikili üretim yasak"
# talimatı enjekte eder. Ancak kullanıcı YENİ bir ikili doküman oluşturmak
# istiyorsa bu kısıtlama .docx/.xlsx üretimini engeller. Bu yardımcılar
# üretme niyetini okuma niyetinden ayırır.
# ------------------------------------------------------------------------------

#' Kullanıcının ikili doküman ÜRETME niyeti olup olmadığını tespit et
#'
#' @param prompt Kullanıcı metni
#' @return TRUE/FALSE
prompt_requests_binary_document_creation <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))
  if (!nzchar(metin)) return(FALSE)

  # Türkçe + İngilizce üretme/yazma/kaydetme fiilleri
  uretme_deseni <- paste(
    c(
      "olu\u015ftur",       # oluştur
      "olustur",
      "yarat",
      "\u00fcret",          # üret
      "uret",
      "haz\u0131rla",       # hazırla
      "hazirla",
      "yaz\u0131l",         # yazıl
      "yazil",
      "kaydet",
      "d\u00f6n\u00fc\u015ft\u00fcr",  # dönüştür
      "donustur",
      "ekspor",
      "export",
      "generate",
      "create",
      "write",
      "produce",
      "save"
    ),
    collapse = "|"
  )

  if (!grepl(uretme_deseni, metin, perl = TRUE)) return(FALSE)

  # Üretim fiilinin yanında ikili doküman uzantısı veya adı geçmeli
  ikili_deseni <- paste(
    c(
      "\\.docx",
      "\\.doc\\b",
      "\\.xlsx",
      "\\.xls\\b",
      "\\.pdf",
      "\\.pptx",
      "\\.ppt\\b",
      "\\bdocx\\b",
      "\\bxlsx\\b",
      "\\bpdf\\b",
      "\\bpptx\\b",
      "\\bword\\b",
      "\\bexcel\\b",
      "\\bpowerpoint\\b"
    ),
    collapse = "|"
  )

  grepl(ikili_deseni, metin, perl = TRUE)
}

#' Kullanıcının MEVCUT ikili dokümanı OKUMA niyetini tespit et
#'
#' @param prompt Kullanıcı metni
#' @return TRUE/FALSE
prompt_requests_existing_document_reading <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))
  if (!nzchar(metin)) return(FALSE)

  okuma_deseni <- paste(
    c(
      "\\bokuy",            # oku / okuy...
      "\\boku\\b",
      "incele",
      "\u00f6zetle",        # özetle
      "ozetle",
      "\u00f6zet\u00e7",    # özetç...
      "\u00e7\u0131kar",    # çıkar (metni çıkar)
      "cikar",
      "i\u00e7eri\u011fi",  # içeriği
      "icerigi",
      "summari",
      "\\bread\\b",
      "\\bextract"
    ),
    collapse = "|"
  )

  grepl(okuma_deseni, metin, perl = TRUE)
}

# ------------------------------------------------------------------------------
# YOL KANONİKLEŞTİRME
# Windows 8.3 kısa dosya adlarını (R_HELP~1.TXT gibi) uzun kanonik forma
# çevirir. Aynı dosyanın hem uzun hem kısa formda indirme listesine
# eklenmesini engeller.
# ------------------------------------------------------------------------------

#' Dosya yolunu kanonik (uzun, mutlak) forma çevir
#'
#' @param path Ham dosya yolu
#' @return Kanonik yol veya orijinal değer
canonicalize_claude_code_file_path <- function(path) {
  path <- as.character(path %||% "")[1]
  if (!nzchar(path)) return("")

  # Dosya diskte mevcutsa mustWork = TRUE ile Windows 8.3 kısa adları uzun
  # forma çözümle. normalizePath(mustWork = TRUE) Windows'ta bu çözümü yapar.
  sonuc <- tryCatch(
    normalizePath(path, winslash = "/", mustWork = TRUE),
    error = function(e) NA_character_
  )

  if (is.na(sonuc) || !nzchar(sonuc)) {
    sonuc <- tryCatch(
      normalizePath(path, winslash = "/", mustWork = FALSE),
      error = function(e) path
    )
  }

  if (is.na(sonuc) || !nzchar(sonuc)) {
    return(path)
  }

  sonuc
}

#' Birden çok dosya yolunu kanonikleştir ve tekrarları kaldır
#'
#' Windows'ta büyük/küçük harf farkı olabileceği için karşılaştırmayı da
#' küçük harfe göre yapar; gerçek yolun kanonik hali korunur.
#'
#' @param paths Dosya yolları
#' @return Tekrarsız kanonik yol vektörü
deduplicate_claude_code_file_paths <- function(paths) {
  paths <- unique(Filter(nzchar, as.character(paths %||% character(0))))
  if (!length(paths)) return(character(0))

  kanonikler <- vapply(
    paths,
    canonicalize_claude_code_file_path,
    character(1),
    USE.NAMES = FALSE
  )

  kanonikler <- kanonikler[nzchar(kanonikler)]
  if (!length(kanonikler)) return(character(0))

  # Windows'ta büyük/küçük harf farkını da yok say
  anahtarlar <- tolower(kanonikler)
  ilk_gorunumler <- !duplicated(anahtarlar)

  kanonikler[ilk_gorunumler]
}

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
    # Windows 8.3 kısa adları uzun kanonik forma çevir
    yol_norm <- canonicalize_claude_code_file_path(ogeler[i])

    if (!nzchar(yol_norm)) next

    mtime_val <- suppressWarnings(as.numeric(bilgi$mtime[i]))
    size_val <- suppressWarnings(as.numeric(bilgi$size[i]))

    # Anahtarı küçük harfe çevir (Windows case-insensitive)
    anahtar <- tolower(yol_norm)

    sonuc[[anahtar]] <- list(
      path = yol_norm,
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

  for (anahtar in names(sonraki)) {
    eski <- once[[anahtar]]
    yeni <- sonraki[[anahtar]]

    # Kanonik yolu liste girdisinden al (eski sürümler sadece key tutuyor olabilir)
    yeni_yol <- yeni$path %||% anahtar
    if (!nzchar(yeni_yol)) next

    if (is.null(eski)) {
      yeni_veya_degisen <- c(yeni_veya_degisen, yeni_yol)
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
      yeni_veya_degisen <- c(yeni_veya_degisen, yeni_yol)
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

  # Kanonik form üzerinden tekrar dedup (emniyet kemeri)
  deduplicate_claude_code_file_paths(yeni_veya_degisen)
}

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

  # Windows 8.3 kısa adlarıyla uzun adları birleştir ve büyük/küçük harf
  # farklılıklarını kaldır. Aksi halde aynı dosya hem "R_helpers_..._summary.txt"
  # hem de "R_HELP~1.TXT" olarak iki indirme kartı olarak görünür.
  tum_yollar <- deduplicate_claude_code_file_paths(c(yeni_dosyalar, arac_yollari))

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
