# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_directory_listing.R
# Açıklama: Bilge Yolaç dizin listeleme, path varyantı deneme ve görünen dosya
#           adı çözümleme yardımcıları.
# ==============================================================================

# UNC/ağ paylaşımı/kodlama farkları için aynı dizinin olası varyasyonlarını üretir.
# NOT: tek ters slash'a göre değiştirme (çift slash yerine) `\\server\share\sub`
# gibi UNC yollarını doğru kanonik forma çevirir; orijinal form da korunur.
cc_build_dir_variants <- function(dir_path) {
  dir_raw <- as.character(dir_path %||% "")
  if (!length(dir_raw) || !nzchar(dir_raw[1])) return(character(0))

  dir_chr <- gsub("\\", "/", dir_raw, fixed = TRUE)

  unique(Filter(nzchar, c(
    dir_chr,
    dir_raw,
    enc2utf8(dir_chr),
    enc2native(dir_chr),
    if (grepl("^/[^/]", dir_chr) && !grepl("^//", dir_chr)) paste0("/", dir_chr) else NULL
  )))
}

# Aynı dizini hem sınırlı tarayıcı hem base R hem fs ile listelemeyi dener.
#
# KRİTİK: Bu fonksiyon ana Shiny olay döngüsünden de (dizin gezgini yenileme)
# çağrılır. Bu yüzden birincil yol `list.files()` DEĞİL, sınırlı artımlı
# numaralandırmadır; yüz binlerce girdili büyük/UNC bir klasör tüm oturumları
# bloke edemez. Sınırlı tarayıcı kullanılamazsa eski davranışa düşülür.
cc_list_dir_relaxed <- function(dir_path, max_entries = 500L, timeout_ms = 2000L) {
  # Sınırlı uygulama bulunduysa bu çağrıdan sonra ASLA sınırsız listelemeye
  # düşülmez. Özellikle yavaş UNC dizinlerinde zaman aşımı/hata sonucu boş
  # gelebilir; aynı dizini list.files()/fs::dir_ls() ile yeniden denemek ana
  # Shiny olay döngüsünü bloke eder.
  if (exists("cc_scan_list_dir_bounded", mode = "function", inherits = TRUE)) {
    sinirli <- try(
      cc_scan_list_dir_bounded(
        dir_path,
        max_entries = max_entries,
        timeout_ms = timeout_ms
      ),
      silent = TRUE
    )

    gecerli <- is.list(sinirli) && !inherits(sinirli, "try-error")
    # sinirli$ok == FALSE, listeleyici sürecin (find/PowerShell) kod
    # döndürerek başarısız olduğu, geçerli bir R listesi (try-error DEĞİL)
    # ama içerik güvenilmez anlamına gelir. Bu durumu "boş ama başarılı"
    # gibi ele almak, gerçek bir listeleme hatasını sessiz boş dizin gibi
    # gösterirdi.
    basarili <- gecerli && !isFALSE(sinirli$ok)
    entries <- if (basarili) sinirli$entries else character(0)
    hata <- if (gecerli) as.character(sinirli$error %||% "")[1] else "Sınırlı dizin listeleyici çalıştırılamadı."

    return(structure(
      unique(as.character(entries %||% character(0))),
      truncated = !basarili || isTRUE(sinirli$truncated),
      error = hata
    ))
  }

  files_base <- tryCatch(
    list.files(
      dir_path,
      full.names = TRUE,
      recursive = FALSE,
      all.files = FALSE
    ),
    error = function(e) character(0)
  )

  if (length(files_base) > 0) {
    return(unique(files_base))
  }

  dirs_fs <- tryCatch(
    as.character(fs::dir_ls(dir_path, recurse = FALSE, type = "directory")),
    error = function(e) character(0)
  )

  files_fs <- tryCatch(
    as.character(fs::dir_ls(dir_path, recurse = FALSE, type = "file")),
    error = function(e) character(0)
  )

  unique(c(dirs_fs, files_fs))
}

# Kalıcı dosya deposundaki iç storage adını kullanıcıya görünen ada çevirir.
cc_resolve_dir_display_name <- function(file_path, is_dir, user_id = NULL, idx_cache = list()) {
  if (isTRUE(is_dir)) {
    return(basename(file_path))
  }

  tryCatch(
    mergen_resolve_display_name(
      file_path,
      user_id = user_id,
      idx = idx_cache
    ),
    error = function(e) basename(file_path)
  )
}

# Tek dizin öğesini Bilge Yolaç dizin gezgini sözleşmesine uygun listeye çevirir.
cc_normalize_dir_entry <- function(file_path, user_id = NULL, idx_cache = list()) {
  f_norm <- tryCatch(
    normalize_mcp_path(file_path, must_exist = FALSE),
    error = function(e) as.character(file_path)
  )

  bilgi <- tryCatch(file.info(f_norm), error = function(e) NULL)

  klasor_mu <- tryCatch(isTRUE(bilgi$isdir[1]), error = function(e) FALSE)
  if (is.null(bilgi) || is.na(klasor_mu)) {
    klasor_mu <- tryCatch(
      isTRUE(dir.exists(f_norm)) || isTRUE(fs::dir_exists(f_norm)),
      error = function(e) FALSE
    )
  }

  boyut <- if (isTRUE(klasor_mu)) {
    NA_real_
  } else {
    suppressWarnings(as.numeric(tryCatch(bilgi$size[1], error = function(e) NA_real_)))
  }

  degistirilme <- tryCatch(as.character(bilgi$mtime[1]), error = function(e) "")

  list(
    ad = basename(f_norm),
    gorunen_ad = cc_resolve_dir_display_name(
      f_norm,
      is_dir = klasor_mu,
      user_id = user_id,
      idx_cache = idx_cache
    ),
    yol = f_norm,
    tip = if (isTRUE(klasor_mu)) "klasor" else "dosya",
    boyut = boyut,
    degistirilme = degistirilme
  )
}

#' Belirtilen dizindeki dosya ve klasörleri listeler
#'
#' @param path Dizin yolu
#' @param max_items Maksimum öğe sayısı
#' @param user_id Kullanıcı kimliği; kalıcı depolama görünen ad çözümlemesi için kullanılır
#' @return Dosya/klasör bilgileri listesi
list_directory_contents <- function(path, max_items = 100L, user_id = NULL) {
  if (is.null(path) || !nzchar(path)) {
    return(list(
      success = FALSE,
      items = list(),
      error = "Dizin yolu boş."
    ))
  }

  aday_dizinler <- cc_build_dir_variants(path)

  if (!length(aday_dizinler)) {
    return(list(
      success = FALSE,
      items = list(),
      error = paste0("Dizin bulunamadı: ", path)
    ))
  }

  calisan_dizin <- NULL
  tum_ogeler <- character(0)
  kesildi <- FALSE
  listeleme_hatasi <- ""

  # Gezginde en fazla `max_items` öge gösterilir; sıralama için biraz fazlasını
  # okumak yeterlidir. Böylece dev klasörlerde bile okuma maliyeti sabittir.
  listeleme_siniri <- max(as.integer(max_items %||% 100L), 1L) * 5L

  for (aday in aday_dizinler) {
    dizin_var_mi <- tryCatch(path_exists_relaxed(aday), error = function(e) FALSE)

    if (!isTRUE(dizin_var_mi)) {
      dizin_var_mi <- tryCatch(
        isTRUE(dir.exists(aday)) || isTRUE(fs::dir_exists(aday)),
        error = function(e) FALSE
      )
    }

    if (!isTRUE(dizin_var_mi)) next

    bulunan_ogeler <- cc_list_dir_relaxed(aday, max_entries = listeleme_siniri)

    # BAŞARISIZLIK (sinirli$ok == FALSE) da boş sonuç dönebilir; yalnızca
    # "içerik bulundu" dalında kontrol etmek onu sessiz "boş dizin" gösterirdi.
    if (is.null(calisan_dizin)) {
      calisan_dizin <- aday
      kesildi <- isTRUE(attr(bulunan_ogeler, "truncated", exact = TRUE))
      listeleme_hatasi <- as.character(attr(bulunan_ogeler, "error", exact = TRUE) %||% "")[1]
    }

    # İçerik bulduysak bunu tercih et
    if (length(bulunan_ogeler) > 0) {
      calisan_dizin <- aday
      kesildi <- isTRUE(attr(bulunan_ogeler, "truncated", exact = TRUE))
      listeleme_hatasi <- as.character(attr(bulunan_ogeler, "error", exact = TRUE) %||% "")[1]
      tum_ogeler <- as.character(bulunan_ogeler)
      break
    }
  }

  if (is.null(calisan_dizin)) {
    return(list(
      success = FALSE,
      items = list(),
      error = paste0("Dizin bulunamadı: ", path)
    ))
  }

  tum_ogeler <- unique(tum_ogeler)
  gosterilecek_ogeler <- head(tum_ogeler, max_items)

  idx_cache <- tryCatch(.load_index(), error = function(e) list())

  ogeler <- lapply(gosterilecek_ogeler, function(f) {
    cc_normalize_dir_entry(
      f,
      user_id = user_id,
      idx_cache = idx_cache
    )
  })

  # Klasörleri üstte, ardından ada göre sırala
  if (length(ogeler) > 1) {
    siralama <- order(
      vapply(ogeler, function(x) x$tip != "klasor", logical(1)),
      tolower(vapply(ogeler, function(x) x$gorunen_ad %||% x$ad %||% "", character(1)))
    )
    ogeler <- ogeler[siralama]
  }

  # listeleme_hatasi yalnızca GERÇEK hatada (sinirli$ok == FALSE) doludur;
  # max_entries kesmesi "" bırakır. Gerçek hata success = TRUE ile gizlenmez.
  basarisiz_mi <- nzchar(listeleme_hatasi)

  list(
    success = !basarisiz_mi,
    items = ogeler,
    error = if (basarisiz_mi) listeleme_hatasi else "",
    toplam = length(tum_ogeler),
    truncated = isTRUE(kesildi),
    truncated_reason = if (isTRUE(kesildi) && basarisiz_mi) listeleme_hatasi else "",
    resolved_path = tryCatch(
      normalize_mcp_path(calisan_dizin, must_exist = FALSE),
      error = function(e) calisan_dizin
    )
  )
}
