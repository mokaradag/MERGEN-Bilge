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

# Başarısız tarama sonrası kısa geri çekilme: aynı istek içindeki ardışık arama
# adımlarının aynı 20 saniyelik taramayı tekrar başlatmasını engeller.
FILE_INDEX_SCAN_FAIL_BACKOFF_SEC <- 30

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

# Sınırlı özyinelemeli tarama: dosya/dizin/derinlik/süre üst sınırları uygulanır
# (ana süreçte sınırsız list.files(recursive = TRUE) yerine). Sınır aşımı
# uyarı olarak loglanır; sınırlı tarayıcı yoksa eski yol kullanılır.
.file_index_scan_bounded <- function(base_path, pattern) {
  if (exists("cc_scan_directory_bounded", mode = "function", inherits = TRUE)) {
    sonuc <- tryCatch(
      cc_scan_directory_bounded(
        base_path,
        max_files = 50000L, max_dirs = 5000L, max_depth = 16L,
        max_total_bytes = Inf, max_elapsed_ms = 20000L, max_file_bytes = Inf,
        max_entries = 250000L
        # exclude_dirs / exclude_rel_paths DEVRE DIŞI BIRAKILMAZ: boş vektör
        # tarayıcının .git / node_modules / renv/library / document_support
        # varsayılanlarını iptal ediyor ve 50.000 dosya bütçesi bağımlılık
        # ağacında tükeniyordu (gerçek belge indekse hiç girmiyordu).
      ),
      error = function(e) NULL
    )
    if (is.list(sonuc)) {
      if (!isTRUE(sonuc$ok)) {
        # Sınırlı tarayıcı bilinçli olarak BAŞARISIZ döndü (ör. UNC'de dosya
        # boyutu okunamıyor). Yerel yürüyüş boyut doğrulaması yapmadığı için
        # tarayıcının reddettiği dosyaları indekslerdi; bu yüzden fallback'e
        # DÜŞÜLMEZ, boş sonuç döner.
        try(
          log_warn("[INDEX] Sınırlı tarama başarısız; indeksleme atlandı: {base_path}"),
          silent = TRUE
        )
        # Başarısızlık "eşleşen dosya yok" ile karıştırılmamalıdır: çağıran bu
        # işareti görüp boş indeksi TTL boyunca önbelleğe almaz.
        return(structure(character(0), scan_failed = TRUE))
      }
      if (isTRUE(sonuc$truncated)) {
        log_warn("[INDEX] Tarama sınırı aşıldı ({sonuc$truncated_reason}); indeks kısmi: {base_path}")
      }
      dosyalar <- as.character(sonuc$files)
      return(dosyalar[grepl(pattern, basename(dosyalar), ignore.case = TRUE, perl = TRUE)])
    }
  }

  # Sınırsız `list.files(recursive = TRUE)` fallback'i KALDIRILDI: büyük veya
  # yavaş bir UNC paylaşımında ana Shiny sürecini tarama bitene kadar
  # blokluyordu. Yerine aynı sınırları uygulayan yerel yürüyüş kullanılır.
  # Buraya yalnızca tarayıcı YOKSA veya istisna fırlattıysa gelinir.
  .file_index_walk_bounded(base_path, pattern)
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

# Yerel sınırlı yürüyüş: `cc_scan_directory_bounded` yüklü olmadığında (izole
# test, erken boot, worker) kullanılır. Dizin/dosya/derinlik/süre üst sınırları
# uygulanır; sınır aşımında sonuç KISMİ döner ve uyarı loglanır.
.file_index_walk_bounded <- function(base_path, pattern,
                                     max_files = 50000L, max_dirs = 5000L,
                                     max_depth = 16L, max_elapsed_ms = 20000L,
                                     max_entries = 20000L) {
  if (!isTRUE(dir.exists(base_path))) return(character(0))

  son <- Sys.time() + (max_elapsed_ms / 1000)
  bulunan <- character(0)
  kuyruk <- list(list(yol = base_path, derinlik = 0L))
  dizin_sayisi <- 0L
  sinir_asildi <- FALSE

  while (length(kuyruk)) {
    if (Sys.time() > son || dizin_sayisi >= max_dirs || length(bulunan) >= max_files) {
      sinir_asildi <- TRUE
      break
    }

    dugum <- kuyruk[[1]]
    kuyruk <- kuyruk[-1]
    dizin_sayisi <- dizin_sayisi + 1L

    girisler <- tryCatch(
      list.files(dugum$yol, full.names = TRUE, no.. = TRUE),
      error = function(e) character(0)
    )
    if (!length(girisler)) next

    # TEK dizin listesi de sınırlanır: çok geniş bir klasör (yüz binlerce
    # giriş) tek turda belleği doldurabilir.
    if (length(girisler) > max_entries) {
      sinir_asildi <- TRUE
      girisler <- girisler[seq_len(max_entries)]
    }

    dizin_mi <- dir.exists(girisler)
    # Bağlantı denetimi yalnızca DİZİN girişlerine uygulanıyordu; `rapor.pdf ->
    # /etc/hosts` gibi bir DOSYA bağlantısı base_path dışındaki hedefi indekse
    # taşıyabiliyordu (tarayıcı sözleşmesinden sapma). Dosyalar için UCUZ sonda
    # kullanılır; pahalı çözümleme aşağıda yalnızca dizinlere uygulanır.
    dosyalar <- girisler[!dizin_mi]
    if (length(dosyalar)) {
      dosyalar <- dosyalar[!vapply(
        dosyalar, .file_index_dosya_baglanti_mi, logical(1), USE.NAMES = FALSE
      )]
    }
    if (length(dosyalar)) {
      eslesen <- dosyalar[grepl(pattern, basename(dosyalar), ignore.case = TRUE, perl = TRUE)]
      # Kalan bütçeden fazlası eklenmez; döngü başındaki denetim tek başına
      # `max_files` üzerine taşmayı engellemiyordu.
      kalan <- max_files - length(bulunan)
      if (length(eslesen) > kalan) {
        sinir_asildi <- TRUE
        eslesen <- eslesen[seq_len(max(0L, kalan))]
      }
      if (length(eslesen)) bulunan <- c(bulunan, eslesen)
    }

    if (dugum$derinlik >= max_depth && any(dizin_mi)) {
      # En yüksek derinlikte alt dizinler taranmaz; sonuç KISMİDİR. İşaret
      # konmazsa daha derindeki dosya sessizce indeks dışı kalıyor ve
      # `search_file_in_folder()` "bulunamadı" diyordu.
      sinir_asildi <- TRUE
    }

    if (dugum$derinlik < max_depth) {
      for (alt in girisler[dizin_mi]) {
        # `max_dirs` yalnızca kuyruktan düğüm ALINMADAN önce denetleniyordu;
        # her dizin `max_entries` kadar alt dizin ekleyebildiği için kuyruk
        # bellek tüketecek boyuta ulaşabiliyordu.
        if ((dizin_sayisi + length(kuyruk)) >= max_dirs) {
          sinir_asildi <- TRUE
          break
        }
        # Sembolik bağlantı / Windows reparse point dizinleri atlanır:
        # `cc_scan_directory_bounded(..., follow_symlinks = FALSE)` ile aynı
        # sözleşme. Aksi hâlde `shared -> /other` gibi bir bağlantı base_path
        # dışındaki dosyaları indekse taşırdı.
        if (isTRUE(.file_index_baglanti_mi(alt))) next
        kuyruk[[length(kuyruk) + 1L]] <- list(yol = alt, derinlik = dugum$derinlik + 1L)
      }
    }
  }

  if (isTRUE(sinir_asildi)) {
    try(
      log_warn("[INDEX] Yerel tarama sınırı aşıldı; sonuç kısmi: {base_path}"),
      silent = TRUE
    )
  }

  unique(bulunan)
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

# Belirtilen klasördeki dosyaları tarar ve basename -> tam yol haritası oluşturur
.build_basename_index <- function(base_path, pattern = "\\.(docx|docm|doc|pdf|pptx|ppt|xlsx|xls|csv|txt|json|md|r|py|log)$", force = FALSE) {
  # not: büyük ağ klasörlerinde tekrar taramayı sınırlamak için TTL
  now <- Sys.time()
  key <- normalizePath(base_path, winslash = "/", mustWork = FALSE)
  ent <- .FILE_INDEX_CACHE[[key]]

  is_stale <- TRUE
  if (is.list(ent) && !is.null(ent$ts)) {
    age <- as.numeric(difftime(now, ent$ts, units = "mins"))
    is_stale <- isTRUE(age > FILE_INDEX_TTL_MIN)
  }

  # Taze başarısızlık belirteci: aynı istek içindeki sonraki arama adımları
  # 20 saniyelik taramayı tekrar başlatmasın.
  if (!isTRUE(force) && is.list(ent) && !is.null(ent$scan_failed_at)) {
    hata_yasi <- as.numeric(difftime(now, ent$scan_failed_at, units = "secs"))
    if (isTRUE(hata_yasi < FILE_INDEX_SCAN_FAIL_BACKOFF_SEC)) return(ent)
  }

  if (force || is_stale || is.null(ent) || is.null(ent$map)) {
    if (!dir.exists(base_path)) {
      log_warn("[INDEX] Klasör yok, indeks oluşturulamadı: {base_path}")
      # Bu erken yazım eviction denetimi yapmıyordu; farklı eksik taban
      # yollarıyla tekrar çağrı önbelleği üst sınırın ötesine büyütüyordu.
      .file_index_cache_evict_if_full(key)
      .FILE_INDEX_CACHE[[key]] <- list(ts = now, map = list())
      return(.FILE_INDEX_CACHE[[key]])
    }
    log_info("[INDEX] Taranıyor (TTL {FILE_INDEX_TTL_MIN}dk): {base_path}")

    # Yalnızca yaygın belge türleri.
    # Windows VM / UNC klasörlerinde geçici erişim hataları tüm uygulamayı
    # düşürmemeli; indeks boş döner ve sonraki TTL döngüsünde tekrar denenir.
    all_files <- .file_index_scan_bounded(base_path, pattern)

    # Geçici tarama hatası (ör. UNC'de boyut okunamaması) boş indeks olarak
    # önbelleğe alınırsa TTL boyunca her arama "bulunamadı" döner. Bu durumda
    # önceki giriş korunur, zaman damgası tazelenmez ve sonraki istek tekrar
    # dener.
    if (isTRUE(attr(all_files, "scan_failed"))) {
      if (is.list(ent) && !is.null(ent$map)) return(ent)
      # Önceki indeks yoksa `ts = NULL` önbelleğe YAZILMIYOR ve aynı arama
      # zinciri taramayı tekrar başlatıyordu (tek istekte 3 x 20 sn blokaj).
      # Kısa ömürlü bir başarısızlık belirteci saklanır; NORMAL TTL tazelenmez.
      .file_index_cache_evict_if_full(key)
      .FILE_INDEX_CACHE[[key]] <- list(
        ts = NULL, map = list(), scan_failed_at = now
      )
      return(.FILE_INDEX_CACHE[[key]])
    }

    all_files <- enc2utf8(as.character(all_files))
    all_files <- gsub("\\", "/", all_files, fixed = TRUE)
    all_files <- sort(unique(all_files[nzchar(all_files)]))

    # basename -> tam yol listesi (aynı ad birden fazlaysa liste tut)
    map <- split(all_files, tolower(basename(all_files)))
    .file_index_cache_evict_if_full(key)
    .FILE_INDEX_CACHE[[key]] <- list(ts = now, map = map)
  }

  .FILE_INDEX_CACHE[[key]]
}

# İndeksten basename eşleşmesi arar
.search_from_index <- function(base_path, target_filename) {
  idx <- .build_basename_index(base_path)
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
.search_with_hint <- function(base_path, hint) {
  if (!is.character(hint) || length(hint) == 0 || is.na(hint[1])) {
    return(NULL)
  }

  parts <- tryCatch(strsplit(as.character(hint[1]), "&&", fixed = TRUE)[[1]], error = function(e) character(0))
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(NULL)
  last <- tail(parts, 1)
  idx <- .build_basename_index(base_path)
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

.search_pdf_word_fallback <- function(base_path, hint) {
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

  idx <- .build_basename_index(base_path)
  all_paths <- unique(unlist(idx$map, use.names = FALSE))
  if (!length(all_paths)) return(NULL)

  word_exts <- c("docx", "docm", "doc")
  candidate_exts <- tolower(tools::file_ext(all_paths))
  candidate_stems <- tolower(tools::file_path_sans_ext(basename(all_paths)))
  cand <- all_paths[candidate_exts %in% word_exts & candidate_stems %in% target_stems]
  cand <- cand[vapply(cand, path_exists_relaxed, logical(1))]
  if (!length(cand)) return(NULL)

  left <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
  if (length(left)) {
    base_norm <- normalizePath(base_path, winslash = "/", mustWork = FALSE)
    cand_rel <- vapply(cand, function(p) {
      p_norm <- normalizePath(p, winslash = "/", mustWork = FALSE)
      prefix <- paste0(base_norm, "/")
      if (startsWith(p_norm, prefix)) substr(p_norm, nchar(prefix) + 1L, nchar(p_norm)) else p_norm
    }, character(1))
    scores <- vapply(cand_rel, .score_path_by_parts, integer(1), parts = left)
    cand <- cand[scores == length(left)]
    if (!length(cand)) return(NULL)
  }

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
.search_all_parts_contained <- function(base_path, hint) {
  if (!is.character(hint) || length(hint) == 0 || is.na(hint[1])) return(NULL)
  parts <- trimws(strsplit(as.character(hint[1]), "&&", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(NULL)
  if (nzchar(tools::file_ext(parts[length(parts)]))) return(NULL)

  idx <- .build_basename_index(base_path)
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
search_file_in_folder <- function(base_path, target_filename) {
  log_info("[FILE SEARCH] base='{base_path}', target='{target_filename}'")
  if (!dir.exists(base_path)) {
    log_error("[FILE SEARCH] taban klasör yok: '{base_path}'")
    return(NULL)
  }
  # 1) ÖNCE tam basename eşleşmesi (düz '&&' dosya adı tam eşleşmesi dahil).
  #    Bu adım ipucu-skorlu aramadan (2) ÖNCE gelmelidir: gerçek disk adı '&&'
  #    İÇEREN düz bir dosyaysa (kategori öneki gömülü ad), '.search_with_hint'
  #    yalnızca ipucunun SON parçasını basename sayıp arar; taban klasörde aynı
  #    son-parça adına sahip alakasız bir dosya varsa (ör. başka bir yerdeki
  #    düz "prosedur.pdf"), tam eşleşme önce denenmezse o alakasız dosya
  #    yanlışlıkla döndürülebilir.
  hit <- .search_from_index(base_path, target_filename)
  if (!is.null(hit)) {
    log_info("[FILE SEARCH] tam eşleşme: {hit}")
    return(hit)
  }
  # 2) '&&' ipucu varsa (gerçek alt klasör ipucu biçimi) skorlu arama dene.
  if (is.character(target_filename) && grepl("&&", target_filename, fixed = TRUE)) {
    hit_hint <- .search_with_hint(base_path, target_filename)
    if (!is.null(hit_hint)) {
      log_info("[FILE SEARCH] ipucu ile bulundu: {hit_hint}")
      return(hit_hint)
    }
  }
  # 3) Langflow PDF atıfı diskteki aynı adlı Word belgesine çözümlenebilir.
  hit_word <- .search_pdf_word_fallback(base_path, target_filename)
  if (!is.null(hit_word)) {
    log_info("[FILE SEARCH] aynı adlı Word belgesi bulundu: {hit_word}")
    return(hit_word)
  }
  # 4) '&&' düz dosya adı için son çare: tüm parçaları içeren en iyi aday
  if (is.character(target_filename) && grepl("&&", target_filename, fixed = TRUE)) {
    hit_all <- .search_all_parts_contained(base_path, target_filename)
    if (!is.null(hit_all)) {
      log_info("[FILE SEARCH] parça içerme ile bulundu: {hit_all}")
      return(hit_all)
    }
  }
  log_warn("[FILE SEARCH] eşleşme yok: target='{target_filename}'")
  NULL
}
