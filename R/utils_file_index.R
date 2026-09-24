# ==============================================================================
# R/utils_file_index.R
# Dosya Yolu: R/utils_file_index.R
# Açıklama: Ağ/yerel klasörlerde hızlı dosya arama için önbellekli indeks
# mekanizması. basename -> tam yol eşlemesi tutar ve TTL ile yenilenir.
# global.R tarafından utils_path_helpers.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- HIZLI DOSYA İNDEKSİ (önbellekli) ---
.FILE_INDEX_CACHE <- new.env(parent = emptyenv())
FILE_INDEX_TTL_MIN <- suppressWarnings(as.numeric(Sys.getenv("MCP_INDEX_TTL_MIN", "10")))
if (is.na(FILE_INDEX_TTL_MIN) || FILE_INDEX_TTL_MIN <= 0) FILE_INDEX_TTL_MIN <- 10
# Önbellekte tutulan taban klasör sayısı üst sınırı (bellek sınırsız büyümez).
.FILE_INDEX_MAX_ENTRIES <- 32L

# Başarısız/KISMİ tarama sonrası geri çekilme (sn). Süre taramanın BİTİŞ
# anından ölçülür: başlangıç anı damgalandığında 40-70 sn süren bir UNC
# taraması bittiği anda süre dolmuş sayılıyor ve aynı tıklamanın sonraki arama
# adımı taramayı yeniden başlatıyordu (tek tıklamada üç tam tarama).
FILE_INDEX_SCAN_FAIL_BACKOFF_SEC <- 30

# PDF atfının diskte karşılık gelebileceği Word uzantıları (öncelik sırasıyla).
# Liste BİLİNÇLİ olarak dardır; kaynak tıklaması başka türe genişlemez.
FILE_INDEX_PDF_WORD_EXTS <- c("docx", "docm", "doc")

# Önbellek doluysa en eski girdi düşürülür (yeni anahtar eklenmeden önce).
.file_index_cache_evict_if_full <- function(key) {
  anahtarlar <- ls(envir = .FILE_INDEX_CACHE, all.names = TRUE)
  if (key %in% anahtarlar || length(anahtarlar) < .FILE_INDEX_MAX_ENTRIES) return(invisible(NULL))
  zamanlar <- vapply(anahtarlar, function(k) {
    ts <- .FILE_INDEX_CACHE[[k]]$ts
    if (inherits(ts, "POSIXct")) as.numeric(ts) else -Inf
  }, numeric(1))
  rm(list = anahtarlar[which.min(zamanlar)], envir = .FILE_INDEX_CACHE)
  invisible(NULL)
}

# Önbellek anahtarı: taban yolunun normalize biçimi (tarama başlatmaz).
.file_index_key <- function(base_path) {
  normalizePath(base_path, winslash = "/", mustWork = FALSE)
}

# Önbellekteki indeks girdisi; TARAMA BAŞLATMAZ (taranmamış taban için NULL).
.file_index_peek <- function(base_path) {
  .FILE_INDEX_CACHE[[.file_index_key(base_path)]]
}

# Girdi durumu: "fresh" (TTL içinde TAM tarama), "backoff" (son başarısız/kısmi
# taramanın BİTİŞİNDEN beri geri çekilme sürüyor) ya da "stale" (tarama gerekir).
# Yalnızca "stale" yeni bir taramaya izin verir.
.file_index_entry_state <- function(ent, now = Sys.time()) {
  if (!is.list(ent)) return("stale")
  if (!is.null(ent$scan_failed_at)) {
    hata_yasi <- as.numeric(difftime(now, ent$scan_failed_at, units = "secs"))
    if (isTRUE(hata_yasi < FILE_INDEX_SCAN_FAIL_BACKOFF_SEC)) return("backoff")
  }
  if (!is.null(ent$ts) && !is.null(ent$map)) {
    yas <- as.numeric(difftime(now, ent$ts, units = "mins"))
    if (isTRUE(yas <= FILE_INDEX_TTL_MIN)) return("fresh")
  }
  "stale"
}

# Dizin girişi bir sembolik bağlantı / reparse point mi? Windows'ta
# `Sys.readlink()` her yol için NA döndürdüğünden çözümlenmiş yol kendi sözlük
# konumuyla karşılaştırılır (paylaşılan `cc_path_is_reparse_link` ile aynı
# yaklaşım; o yardımcı yüklüyse doğrudan kullanılır).
.file_index_baglanti_mi <- function(yol) {
  if (exists("cc_path_is_reparse_link", mode = "function", inherits = TRUE)) {
    return(isTRUE(tryCatch(cc_path_is_reparse_link(yol), error = function(e) TRUE)))
  }
  hedef <- suppressWarnings(Sys.readlink(yol))
  if (length(hedef) == 1L && !is.na(hedef) && nzchar(hedef)) return(TRUE)
  cozulmus <- tryCatch(normalizePath(yol, winslash = "/", mustWork = FALSE),
                       error = function(e) NA_character_)
  ust <- tryCatch(
    normalizePath(dirname(yol), winslash = "/", mustWork = FALSE),
    error = function(e) NA_character_
  )
  if (is.na(cozulmus) || is.na(ust)) return(FALSE)
  !identical(dirname(cozulmus), ust)
}

# UCUZ dosya sondası: `.file_index_baglanti_mi()` giriş başına İKİ
# `normalizePath()` çağırır ve bu Windows'ta gerçek bir dosya sistemi çağrısıdır;
# on binlerce DOSYA girişine uygulandığında tarama dakikalarca sürüyordu.
# `cc_scan_directory_bounded` ile AYNI sözleşme: giriş döngüsünde yalnızca ucuz
# POSIX `Sys.readlink()` kullanılır (Windows'ta NA = bağlantı değil), pahalı
# çözümlemeli denetim yalnızca DİZİNLERE uygulanır (asıl kaçış riski oradadır).
.file_index_dosya_baglanti_mi <- function(yol) {
  hedef <- suppressWarnings(tryCatch(Sys.readlink(yol), error = function(e) NA_character_))
  length(hedef) == 1L && !is.na(hedef) && nzchar(hedef)
}

# Tek dizinin AD listesi. Paylaşılan sınırlı listeleyici yüklüyse kullanılır:
# UNC'de erişilebilir paylaşım için boş dönen `list.files()` durumunda `fs`
# yedeği ve okunabilirlik denetimi oradadır (ok = FALSE listelenemedi demektir).
.file_index_list_dir <- function(yol, kalan_ms, max_entries) {
  if (exists("cc_scan_list_dir_bounded", mode = "function", inherits = TRUE)) {
    return(cc_scan_list_dir_bounded(
      yol, max_entries = max_entries, timeout_ms = max(1, kalan_ms)
    ))
  }
  girisler <- try(list.files(yol, full.names = TRUE, no.. = TRUE), silent = TRUE)
  hata <- inherits(girisler, "try-error")
  # `list.files()` okunamayan klasörde hata vermez; boş sonuç yalnızca okunabilir
  # bir klasörde "boş" sayılır.
  if (!hata && !length(girisler)) {
    hata <- !isTRUE(dir.exists(yol)) ||
      !identical(unname(suppressWarnings(file.access(yol, 4L))), 0L)
  }
  list(entries = if (hata) character(0) else as.character(girisler),
       truncated = FALSE, ok = !hata)
}

# Sınırlı indeks taraması: YALNIZCA AD listelemesi. `cc_scan_directory_bounded()`
# her DOSYA için iki `normalizePath()` ve boyut okuması yapar; UNC'de bunlar ağ
# gidiş-dönüşüdür, süre yalnızca 64 girişte bir denetlenir ve boyut sarmalayıcısı
# bütçe DIŞINDA çalışır. ~1000 belgelik bir modelde 20 sn bütçe böylece 40-70
# sn'ye taşıyordu. İndeks boyut kullanmaz; kanonik kapsama denetimi seçilen TEK
# aday için tıklama anında yapılır (`.preview_path_inside`). Dizin/dosya/
# derinlik/süre sınırları uygulanır; sınır aşımında sonuç KISMİ işaretlenir,
# kök listelenemezse BAŞARISIZ işaretlenir. Tek bir dizin çağrısı işletim
# sisteminde bloklanabileceği için süre bütçesi kesin duvar saati garantisi
# DEĞİLDİR; bu yüzden tıklama yolu taramayı yalnızca son çare olarak kullanır.
.file_index_scan_bounded <- function(base_path, pattern,
                                     max_files = 50000L, max_dirs = 5000L,
                                     max_depth = 16L, max_elapsed_ms = 20000L,
                                     max_entries = 20000L) {
  # Kök görünmüyorsa (UNC kopması) sonuç "boş klasör" değil BAŞARISIZ taramadır.
  if (!isTRUE(dir.exists(base_path))) return(structure(character(0), scan_failed = TRUE))

  # Bağımlılık/önbellek ağaçları atlanır (tarayıcı varsayılanlarıyla aynı);
  # aksi hâlde dosya bütçesi gerçek belgelere ulaşmadan tükeniyordu.
  haric_ad <- tolower(if (exists("cc_scan_default_excluded_dirs", mode = "function", inherits = TRUE)) {
    cc_scan_default_excluded_dirs()
  } else c(".git", "node_modules", "document_support", ".document_support"))
  haric_rel <- tolower(if (exists("cc_scan_default_excluded_rel_paths", mode = "function", inherits = TRUE)) {
    cc_scan_default_excluded_rel_paths()
  } else "renv/library")

  baslangic <- Sys.time()
  kalan_ms <- function() {
    max_elapsed_ms - as.numeric(difftime(Sys.time(), baslangic, units = "secs")) * 1000
  }
  parcalar <- list()
  sayac <- 0L
  kuyruk <- list(list(yol = base_path, derinlik = 0L, rel = ""))
  dizin_sayisi <- 0L
  sinir_asildi <- FALSE

  while (length(kuyruk)) {
    if (kalan_ms() <= 0 || dizin_sayisi >= max_dirs || sayac >= max_files) {
      sinir_asildi <- TRUE
      break
    }

    dugum <- kuyruk[[1]]
    kuyruk <- kuyruk[-1]
    dizin_sayisi <- dizin_sayisi + 1L

    liste <- .file_index_list_dir(dugum$yol, kalan_ms(), max_entries)
    if (!isTRUE(liste$ok) && identical(dugum$derinlik, 0L)) {
      # Kök listelenemedi: "eşleşen dosya yok" ile karıştırılmaz; çağıran boş
      # indeksi TTL boyunca önbelleğe almaz ve önceki indeksi korur.
      try(log_warn("[INDEX] Kök klasör listelenemedi; indeksleme atlandı: {base_path}"), silent = TRUE)
      return(structure(character(0), scan_failed = TRUE))
    }
    # Tek dizin listesi de sınırlıdır (çok geniş klasör / süre bitimi). Alt
    # dizin listelenemediyse (geçici UNC/erişim hatası) o alt ağaç eksiktir;
    # indeks TAM sayılıp TTL boyunca önbelleğe alınmaz.
    if (isTRUE(liste$truncated) || !isTRUE(liste$ok)) sinir_asildi <- TRUE
    girisler <- as.character(liste$entries)
    if (!length(girisler)) next

    dizin_mi <- dir.exists(girisler)
    # Desen ÖNCE uygulanır; ucuz dosya bağlantısı sondası (POSIX `Sys.readlink`)
    # yalnızca eşleşen belgelere uygulanır. `rapor.pdf -> /etc/hosts` gibi bir
    # DOSYA bağlantısı indekse alınmaz.
    dosyalar <- girisler[!dizin_mi]
    dosyalar <- dosyalar[grepl(pattern, basename(dosyalar), ignore.case = TRUE, perl = TRUE)]
    if (length(dosyalar)) {
      dosyalar <- dosyalar[!vapply(
        dosyalar, .file_index_dosya_baglanti_mi, logical(1), USE.NAMES = FALSE
      )]
      # Kalan bütçeden fazlası eklenmez.
      kalan <- max_files - sayac
      if (length(dosyalar) > kalan) {
        sinir_asildi <- TRUE
        dosyalar <- dosyalar[seq_len(max(0L, kalan))]
      }
      if (length(dosyalar)) {
        parcalar[[length(parcalar) + 1L]] <- dosyalar
        sayac <- sayac + length(dosyalar)
      }
    }

    if (dugum$derinlik >= max_depth && any(dizin_mi)) {
      # En yüksek derinlikte alt dizinler taranmaz; sonuç KISMİDİR.
      sinir_asildi <- TRUE
    }

    if (dugum$derinlik < max_depth) {
      for (alt in girisler[dizin_mi]) {
        # Kuyruk da `max_dirs` ile sınırlıdır (bellek).
        if ((dizin_sayisi + length(kuyruk)) >= max_dirs) {
          sinir_asildi <- TRUE
          break
        }
        ad <- basename(gsub("\\", "/", alt, fixed = TRUE))
        rel <- if (nzchar(dugum$rel)) paste0(dugum$rel, "/", ad) else ad
        if (tolower(ad) %in% haric_ad || tolower(rel) %in% haric_rel) next
        # Sembolik bağlantı / Windows reparse point dizinleri İZLENMEZ; aksi
        # hâlde `shared -> /other` gibi bir bağlantı taban dışını indekse taşır.
        if (isTRUE(.file_index_baglanti_mi(alt))) next
        kuyruk[[length(kuyruk) + 1L]] <- list(yol = alt, derinlik = dugum$derinlik + 1L, rel = rel)
      }
    }
  }

  if (isTRUE(sinir_asildi)) {
    try(log_warn("[INDEX] Tarama sınırı aşıldı; indeks kısmi: {base_path}"), silent = TRUE)
  }

  # KISMİ sonuç İŞARETLENİR: eksik indeks TAM indeks gibi TTL boyunca
  # önbelleğe alınırsa taramanın ulaşamadığı MEVCUT dosyalar "bulunamadı" döner.
  bulunan <- as.character(unlist(parcalar, use.names = FALSE))
  structure(unique(bulunan), scan_partial = isTRUE(sinir_asildi))
}

# İndeks yollarını tabana göre göreli hale getirir (girdi başına normalizePath
# çağırmadan; ham ve normalize edilmiş taban önekleri dize kıyasıyla denenir).
.file_index_relative_paths <- function(paths, base_path) {
  onekler <- unique(c(
    paste0(sub("/+$", "", gsub("\\", "/", as.character(base_path), fixed = TRUE)), "/"),
    paste0(sub("/+$", "", normalizePath(base_path, winslash = "/", mustWork = FALSE)), "/")
  ))
  out <- paths
  # Windows'ta sürücü harfi/klasör adı farklı büyüklükte dönebilir; duyarlı
  # kıyas hiçbir öneki eşleştirmiyor, mutlak yol korunuyor ve `.search_with_hint`
  # taban yoldaki rastlantısal sözcüklerle yanlış dosya döndürebiliyordu.
  kucult <- function(x) if (identical(.Platform$OS.type, "windows")) tolower(x) else x
  paths_key <- kucult(paths)
  kalan <- rep(TRUE, length(paths))
  for (onek in onekler) {
    hit <- kalan & startsWith(paths_key, kucult(onek))
    out[hit] <- substring(paths[hit], nchar(onek) + 1L)
    kalan <- kalan & !hit
  }
  out
}

# Belirtilen klasördeki dosyaları tarar ve basename -> tam yol haritası oluşturur.
# Taze (TTL içinde tam) ya da geri çekilmedeki girdi YENİDEN TARANMAZ (`force`
# hariç); böylece aynı taban kısa sürede ikinci kez taranmaz.
.build_basename_index <- function(base_path, pattern = "\\.(docx|docm|doc|pdf|pptx|ppt|xlsx|xls|csv|txt|json|md|r|py|log)$", force = FALSE) {
  key <- .file_index_key(base_path)
  ent <- .FILE_INDEX_CACHE[[key]]
  if (!isTRUE(force) && .file_index_entry_state(ent) %in% c("fresh", "backoff")) {
    return(ent)
  }

  # TTL tazeliği taramanın BAŞLANGICINDAN (veri o andan beri değişmiş olabilir),
  # geri çekilme ise BİTİŞİNDEN ölçülür.
  baslangic <- Sys.time()

  # Geçici tarama hatası (klasör görünmüyor / kök listelenemedi) boş indeks
  # olarak TTL boyunca önbelleğe alınırsa her arama "bulunamadı" döner. Önceki
  # harita korunur, `ts` TAZELENMEZ ve geri çekilme damgası yazılır; eviction
  # denetimi de yapılır (farklı eksik taban yolları önbelleği büyütmez).
  basarisiz_kaydet <- function(zaman) {
    .file_index_cache_evict_if_full(key)
    onceki <- if (is.list(ent) && !is.null(ent$map)) ent$map else list()
    onceki_ts <- if (is.list(ent)) ent$ts else NULL
    .FILE_INDEX_CACHE[[key]] <- list(ts = onceki_ts, map = onceki, scan_failed_at = zaman)
    .FILE_INDEX_CACHE[[key]]
  }

  if (!dir.exists(base_path)) {
    log_warn("[INDEX] Klasör yok, indeks oluşturulamadı: {base_path}")
    return(basarisiz_kaydet(baslangic))
  }
  log_info("[INDEX] Taranıyor (TTL {FILE_INDEX_TTL_MIN}dk): {base_path}")

  # Yalnızca yaygın belge türleri. Windows VM / UNC klasörlerinde geçici erişim
  # hataları tüm uygulamayı düşürmemeli.
  all_files <- .file_index_scan_bounded(base_path, pattern)
  bitis <- Sys.time()

  if (isTRUE(attr(all_files, "scan_failed"))) return(basarisiz_kaydet(bitis))

  kismi <- isTRUE(attr(all_files, "scan_partial"))

  all_files <- enc2utf8(as.character(all_files))
  all_files <- gsub("\\", "/", all_files, fixed = TRUE)
  all_files <- sort(unique(all_files[nzchar(all_files)]))

  # basename -> tam yol listesi (aynı ad birden fazlaysa liste tut)
  map <- split(all_files, tolower(basename(all_files)))
  .file_index_cache_evict_if_full(key)
  # KISMİ tarama TAM TTL ile önbelleğe ALINMAZ. Harita yine saklanır (eksik
  # indeks boş indeksten iyidir) ancak `ts` yazılmaz; geri çekilme damgası
  # yakın zamandaki aramaların taramayı yeniden başlatmasını engeller.
  .FILE_INDEX_CACHE[[key]] <- if (kismi) {
    list(ts = NULL, map = map, scan_failed_at = bitis)
  } else {
    list(ts = baslangic, map = map)
  }
  .FILE_INDEX_CACHE[[key]]
}

# İndeksten basename eşleşmesi arar. `idx` verilirse o indeks girdisi kullanılır
# (arama aşamaları aynı taramayı paylaşır); verilmezse indeks kurulur.
.search_from_index <- function(base_path, target_filename, idx = NULL) {
  if (is.null(idx)) idx <- .build_basename_index(base_path)
  if (!length(idx$map)) return(NULL)
  key <- tolower(basename(target_filename))
  cand <- idx$map[[key]]
  if (is.null(cand) || !length(cand)) return(NULL)
  for (p in cand) { if (path_exists_relaxed(p)) return(p) }
  NULL
}

# Yardımcı: ipucu parçalarını yol ile skorla (kaç parça geçiyor?)
.score_path_by_parts <- function(path, parts) {
  if (length(parts) == 0) return(0L)
  p <- tolower(path)
  sum(vapply(parts, function(s) grepl(tolower(trimws(s)), p, fixed = TRUE), logical(1)))
}

# 'A&&B&&C.docx' ipucu ile arama (indeksteki tüm C.docx adaylarını A/B parçalarına göre puanla)
.search_with_hint <- function(base_path, hint, idx = NULL) {
  if (!is.character(hint) || length(hint) == 0 || is.na(hint[1])) {
    return(NULL)
  }

  parts <- tryCatch(strsplit(as.character(hint[1]), "&&", fixed = TRUE)[[1]], error = function(e) character(0))
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(NULL)
  last <- tail(parts, 1)
  if (is.null(idx)) idx <- .build_basename_index(base_path)
  cand <- idx$map[[tolower(basename(last))]]
  if (is.null(cand) || !length(cand)) return(NULL)

  left <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
  if (!length(left)) {
    for (p in cand) { if (path_exists_relaxed(p)) return(p) }
    return(NULL)
  }

  cand_rel <- .file_index_relative_paths(as.character(cand), base_path)
  scores <- vapply(cand_rel, .score_path_by_parts, integer(1), parts = left)
  # İpucu skoru yalnızca adayın taban klasöre göre göreli yolunda sol parçaların
  # TÜMÜ geçtiğinde güvenilir kabul edilir. Mutlak taban yolundaki rastlantısal
  # sözcükler (örn. geçici klasör adı) yanlış dosyayı geçerli kılamaz.
  if (!length(scores) || max(scores, na.rm = TRUE) < length(left)) return(NULL)

  ord <- order(scores, decreasing = TRUE, na.last = NA)
  for (i in ord) {
    if (scores[[i]] < length(left)) next
    p <- cand[[i]]
    if (path_exists_relaxed(p)) return(p)
  }
  NULL
}

.search_pdf_word_fallback <- function(base_path, hint, idx = NULL) {
  if (!is.character(hint) || length(hint) == 0 || is.na(hint[1])) return(NULL)

  parts <- trimws(strsplit(as.character(hint[1]), "&&", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(NULL)

  last <- tail(parts, 1)
  if (!identical(tolower(tools::file_ext(last)), "pdf")) return(NULL)

  target_stems <- unique(tolower(c(
    tools::file_path_sans_ext(basename(as.character(hint[1]))),
    tools::file_path_sans_ext(basename(last))
  )))
  target_stems <- target_stems[nzchar(target_stems)]
  if (!length(target_stems)) return(NULL)

  if (is.null(idx)) idx <- .build_basename_index(base_path)
  all_paths <- unique(unlist(idx$map, use.names = FALSE))
  if (!length(all_paths)) return(NULL)

  word_exts <- FILE_INDEX_PDF_WORD_EXTS
  candidate_exts <- tolower(tools::file_ext(all_paths))
  candidate_stems <- tolower(tools::file_path_sans_ext(basename(all_paths)))
  cand <- all_paths[candidate_exts %in% word_exts & candidate_stems %in% target_stems]
  if (!length(cand)) return(NULL)

  left <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
  if (length(left)) {
    # Göreli yol DİZE işlemiyle çıkarılır; aday başına `normalizePath()` UNC'de
    # ağ gidiş-dönüşüdür ve Windows'ta harf büyüklüğü farkını da kaçırıyordu.
    cand_rel <- .file_index_relative_paths(as.character(cand), base_path)
    scores <- vapply(cand_rel, .score_path_by_parts, integer(1), parts = left)
    cand <- cand[scores == length(left)]
  }
  # Varlık denetimi puanlamadan SONRA: yalnızca kalan adaylar yoklanır.
  cand <- cand[vapply(cand, path_exists_relaxed, logical(1), USE.NAMES = FALSE)]
  if (!length(cand)) return(NULL)

  priorities <- match(tolower(tools::file_ext(cand)), word_exts)
  cand <- cand[priorities == min(priorities)]
  if (length(cand) != 1L) return(NULL)

  cand[[1]]
}

# '&&' parçalarının TÜMÜNÜ (son parça dahil) yol içinde barındıran indeks
# girişini seçer. '&&' düz dosya adının parçasıysa (dizin değil; disk basename'i
# 'A&&B&&dosya.pdf' gibi '&&' içerir) tam ad bu yolla yakalanır: '.search_with_hint'
# yalnızca son parçayı basename varsayıp başarısız olur, bu yardımcı ise tüm
# parçaların geçtiği en iyi adayı bulur. Boşluk/büyük-küçük harf farklarına da
# dayanıklıdır. Tüm parçalar geçmiyorsa (best < parça sayısı) NULL döner.
#
# GÜVENLİK: bu son çare yalnızca UZANTISIZ son parça için etkindir (opt-in).
# Bu noktaya gelindiğinde tam basename eşleşmesi (adım 1) VE ipucu-skorlu
# arama (adım 2, son parçanın TAM basename eşleşmesini arar) zaten başarısız
# olmuştur. Son parçanın bir uzantısı varsa (ör. "prosedur.pdf"), yalnızca
# alt-dize içerme skoruna dayanarak dosya açmak, atıflanan gerçek dosya DİSKTE
# YOKKEN yanlışlıkla benzer adlı ALAKASIZ bir dosyayı (ör. "eski-prosedur.pdf")
# önizlemeye açabilir. Bu durumda "bulunamadı" demek, yanlış belge açmaktan
# daha güvenlidir; bu yüzden uzantılı son parçalarda bu son çare devre dışıdır.
.search_all_parts_contained <- function(base_path, hint, idx = NULL) {
  if (!is.character(hint) || length(hint) == 0 || is.na(hint[1])) return(NULL)
  parts <- trimws(strsplit(as.character(hint[1]), "&&", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(NULL)
  if (nzchar(tools::file_ext(parts[length(parts)]))) return(NULL)

  if (is.null(idx)) idx <- .build_basename_index(base_path)
  if (!length(idx$map)) return(NULL)
  all_paths <- unlist(idx$map, use.names = FALSE)
  if (!length(all_paths)) return(NULL)

  rel_paths <- .file_index_relative_paths(as.character(all_paths), base_path)
  scores <- vapply(rel_paths, .score_path_by_parts, integer(1), parts = parts)
  if (max(scores) < length(parts)) return(NULL)
  ord <- order(scores, decreasing = TRUE, na.last = NA)
  for (i in ord) {
    p <- all_paths[[i]]
    if (path_exists_relaxed(p)) return(p)
  }
  NULL
}

# Akıllı arama: önce TAM basename eşleşmesi, sonra ipucu, sonra güvenli tür eşlemesi.
# TÜM aşamalar TEK indeks girdisini paylaşır: her aşama kendi indeksini
# kurduğunda kısmi/başarısız taramadan sonra taramayı yeniden başlatabiliyordu
# (tek tıklamada üç tam tarama). `idx` verilirse hiç tarama yapılmaz.
search_file_in_folder <- function(base_path, target_filename, idx = NULL) {
  log_info("[FILE SEARCH] base='{base_path}', target='{target_filename}'")
  if (!dir.exists(base_path)) {
    log_error("[FILE SEARCH] taban klasör yok: '{base_path}'")
    return(NULL)
  }
  if (is.null(idx)) idx <- .build_basename_index(base_path)
  # 1) ÖNCE tam basename eşleşmesi (düz '&&' dosya adı tam eşleşmesi dahil).
  #    Bu adım ipucu-skorlu aramadan (2) ÖNCE gelmelidir: gerçek disk adı '&&'
  #    İÇEREN düz bir dosyaysa (kategori öneki gömülü ad), '.search_with_hint'
  #    yalnızca ipucunun SON parçasını basename sayıp arar; taban klasörde aynı
  #    son-parça adına sahip alakasız bir dosya varsa (ör. başka bir yerdeki
  #    düz "prosedur.pdf"), tam eşleşme önce denenmezse o alakasız dosya
  #    yanlışlıkla döndürülebilir.
  hit <- .search_from_index(base_path, target_filename, idx = idx)
  if (!is.null(hit)) {
    log_info("[FILE SEARCH] tam eşleşme: {hit}")
    return(hit)
  }
  # 2) '&&' ipucu varsa (gerçek alt klasör ipucu biçimi) skorlu arama dene.
  if (is.character(target_filename) && grepl("&&", target_filename, fixed = TRUE)) {
    hit_hint <- .search_with_hint(base_path, target_filename, idx = idx)
    if (!is.null(hit_hint)) {
      log_info("[FILE SEARCH] ipucu ile bulundu: {hit_hint}")
      return(hit_hint)
    }
  }
  # 3) Langflow PDF atıfı diskteki aynı adlı Word belgesine çözümlenebilir.
  hit_word <- .search_pdf_word_fallback(base_path, target_filename, idx = idx)
  if (!is.null(hit_word)) {
    log_info("[FILE SEARCH] aynı adlı Word belgesi bulundu: {hit_word}")
    return(hit_word)
  }
  # 4) '&&' düz dosya adı için son çare: tüm parçaları içeren en iyi aday
  if (is.character(target_filename) && grepl("&&", target_filename, fixed = TRUE)) {
    hit_all <- .search_all_parts_contained(base_path, target_filename, idx = idx)
    if (!is.null(hit_all)) {
      log_info("[FILE SEARCH] parça içerme ile bulundu: {hit_all}")
      return(hit_all)
    }
  }
  log_warn("[FILE SEARCH] eşleşme yok: target='{target_filename}'")
  NULL
}
