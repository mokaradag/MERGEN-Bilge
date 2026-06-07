# ==============================================================================
# Dosya Yolu: R/helpers_vision_context.R
# Açıklama:   Model Bağlamı'na eklenen görsellerin yapay zekâ isteğine güvenli
#             biçimde dahil edilmesi için saf yardımcılar.
#
#             Görsel anlama (vision) desteği iki kapıdan birlikte geçer:
#               1) Yapılandırma bayrağı (MERGEN_ENABLE_VISION / mergen.vision_enabled)
#               2) Modelin vision yeteneği (api_config$local_model_capabilities)
#             İkisi birden açık değilse metin yolu HİÇBİR koşulda değişmez ve
#             görseller için açık/yardımcı bir Türkçe not eklenir (sessiz
#             "okunamadı" hatası yerine). Vision aktifken görseller OpenAI
#             uyumlu çok-kipli (multimodal) `image_url` parçaları olarak eklenir.
#
#             Bu dosya Shiny oturumuna, reactive state'e veya ağ/HTTP'ye dokunmaz.
# ==============================================================================

# Desteklenen görsel uzantıları. Tek kaynak Dosya Yönetimi politikasıdır; izole
# bağlamda o helper yoksa güvenli sabit listeye düşer.
mergen_vision_image_extensions <- function() {
  if (exists("fm_image_extensions", mode = "function", inherits = TRUE)) {
    return(fm_image_extensions())
  }
  c("jpg", "jpeg", "png", "gif", "webp", "bmp", "svg")
}

# Bir dosya adının görsel olup olmadığını söyler.
mergen_is_image_file <- function(name) {
  if (!is.character(name) || length(name) < 1L || is.na(name[1]) || !nzchar(name[1])) {
    return(FALSE)
  }
  ext <- tolower(tools::file_ext(name[1]))
  nzchar(ext) && ext %in% mergen_vision_image_extensions()
}

# Görsel uzantısına göre MIME türü; bilinmeyen için octet-stream.
mergen_image_mime_type <- function(name) {
  ext <- tolower(tools::file_ext(as.character(name %||% "")[1]))
  switch(
    ext,
    "jpg" = ,
    "jpeg" = "image/jpeg",
    "png" = "image/png",
    "gif" = "image/gif",
    "webp" = "image/webp",
    "bmp" = "image/bmp",
    "svg" = "image/svg+xml",
    "application/octet-stream"
  )
}

# Vision GLOBAL kill-switch'i (yetenek-öncelikli tasarım).
# Gating'i asıl olarak modelin vision yeteneği belirler; bu bayrak yalnızca
# AÇIKÇA kapatıldığında (options(mergen.vision_enabled) veya
# MERGEN_ENABLE_VISION = false/0/hayır/off ...) vision'ı tamamen devre dışı
# bırakır. Ayarlanmamış veya tanınmayan değer KAPATMAZ; varsayılan AÇIK'tır.
# Böylece capabilities tablosunda bir modeli vision = TRUE işaretlemek yeterlidir.
mergen_vision_enabled <- function() {
  # Yalnızca açıkça "kapalı/false" anlamına gelen değerler vision'ı devre dışı bırakır.
  .vision_is_explicit_false <- function(x) {
    if (is.null(x) || length(x) < 1L) return(FALSE)
    if (is.logical(x)) return(isFALSE(x[1]))
    if (is.numeric(x)) return(!is.na(x[1]) && x[1] == 0)
    if (is.character(x)) {
      val <- tolower(trimws(x[1]))
      return(val %in% c("false", "f", "0", "no", "off",
                        "hayir", "hayır", "pasif", "kapali", "kapalı"))
    }
    FALSE
  }

  opt <- getOption("mergen.vision_enabled", NULL)
  if (!is.null(opt)) return(!.vision_is_explicit_false(opt))

  env <- Sys.getenv("MERGEN_ENABLE_VISION", "")
  if (!nzchar(env)) return(TRUE)
  !.vision_is_explicit_false(env)
}

# Modelin vision yeteneği var mı? Yetenekler yalnızca
# api_config$local_model_capabilities içinde açıkça tanımlandığında doğrudur
# (is_thinking_model ile aynı sözleşme). api_config verilmezse global'e bakılır.
mergen_is_vision_model <- function(model_id, api_config = NULL) {
  if (!is.character(model_id) || length(model_id) < 1L ||
      is.na(model_id[1]) || !nzchar(model_id[1])) {
    return(FALSE)
  }

  cfg <- api_config
  if (is.null(cfg) && exists("api_config", inherits = TRUE)) {
    cfg <- tryCatch(get("api_config", inherits = TRUE), error = function(e) NULL)
  }

  caps <- if (is.list(cfg)) cfg$local_model_capabilities else NULL
  if (is.null(caps) || is.null(caps[[model_id[1]]])) {
    return(FALSE)
  }

  isTRUE(caps[[model_id[1]]]$vision)
}

# Vision yolu aktif mi? Bayrak VE model yeteneği birlikte gereklidir.
mergen_vision_active <- function(model_id, api_config = NULL) {
  mergen_vision_enabled() && mergen_is_vision_model(model_id, api_config)
}

# Görsel için açık/yardımcı Türkçe not (vision kapalı/desteksiz veya görsel
# okunamadı durumlarında metin bloğuna eklenir).
mergen_vision_unavailable_note <- function(fname) {
  fname_chr <- as.character(fname %||% "")[1]
  paste0(
    "[Görsel dosyası: ", fname_chr, " — Bu görselin içeriği bu sürümde yapay zekâ ",
    "tarafından analiz edilemiyor (görsel anlama desteği etkin değil). ",
    "Lütfen görseldeki bilgiyi metin olarak yazın veya dosyayı metin/PDF biçiminde paylaşın.]"
  )
}

# Görseli güvenli boyut sınırıyla base64 data-url'e çevirir; başarısızsa NULL.
# Varsayılan üst sınır 5 MB'tır; aşan veya okunamayan görsel için NULL döner.
mergen_build_image_data_url <- function(path, max_bytes = 5L * 1024L * 1024L) {
  if (!is.character(path) || length(path) < 1L || is.na(path[1]) || !nzchar(path[1])) {
    return(NULL)
  }

  readable <- tryCatch(
    if (exists("resolve_readable_path", mode = "function", inherits = TRUE)) {
      resolve_readable_path(path[1])
    } else {
      path[1]
    },
    error = function(e) path[1]
  )

  exists_ok <- tryCatch(
    if (exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
      path_exists_relaxed(readable)
    } else {
      file.exists(readable)
    },
    error = function(e) FALSE
  )
  if (!isTRUE(exists_ok)) return(NULL)

  sz <- tryCatch(file.info(readable)$size, error = function(e) NA_real_)
  if (is.na(sz) || sz <= 0 || sz > max_bytes) return(NULL)

  b64 <- tryCatch({
    raw_bytes <- readBin(readable, what = "raw", n = sz)
    if (!length(raw_bytes)) return(NULL)
    base64enc::base64encode(raw_bytes)
  }, error = function(e) NULL)

  if (is.null(b64) || !nzchar(b64)) return(NULL)

  paste0("data:", mergen_image_mime_type(path[1]), ";base64,", b64)
}

# OpenAI uyumlu çok-kipli kullanıcı içeriği üretir:
#   [ {type:"text", text:...}, {type:"image_url", image_url:{url:...}}, ... ]
# Metin boşsa metin parçası atlanır; geçerli görsel yoksa sade parça listesi döner.
mergen_build_vision_user_content <- function(text, image_data_urls) {
  parts <- list()

  if (is.character(text) && length(text) >= 1L && !is.na(text[1]) && nzchar(text[1])) {
    parts <- c(parts, list(list(type = "text", text = text[1])))
  }

  for (u in image_data_urls) {
    if (is.character(u) && length(u) >= 1L && !is.na(u[1]) && nzchar(u[1])) {
      parts <- c(parts, list(list(type = "image_url", image_url = list(url = u[1]))))
    }
  }

  parts
}

# none (MCP kapalı) modunda dosya bloklarını ve (vision aktifse) görsel
# data-url'lerini hazırlar. Metin/belge dosyaları için mevcut davranış korunur;
# görseller vision aktifse data-url'e çevrilir, aksi halde açık nota dönüşür.
mergen_vision_prepare_context_blocks <- function(uploaded_names,
                                                 summary_store,
                                                 current_file_store,
                                                 per_file_cap,
                                                 vision_active = FALSE,
                                                 read_fn = NULL) {
  if (is.null(read_fn)) {
    read_fn <- if (exists("readFileContentToString", mode = "function", inherits = TRUE)) {
      readFileContentToString
    } else {
      function(...) ""
    }
  }

  file_blocks <- character(0)
  image_data_urls <- character(0)

  for (fname in uploaded_names) {
    # GÖRSEL DOSYALAR: vision aktifse data-url, değilse açık not.
    if (mergen_is_image_file(fname)) {
      fobj <- current_file_store[[fname]] %||% NULL
      fpath <- if (is.list(fobj)) as.character(fobj$datapath %||% fobj$path %||% "")[1] else ""

      data_url <- if (isTRUE(vision_active) && nzchar(fpath)) {
        mergen_build_image_data_url(fpath)
      } else {
        NULL
      }

      if (!is.null(data_url)) {
        image_data_urls <- c(image_data_urls, data_url)
        file_blocks <- c(
          file_blocks,
          paste0("### ", fname, "\n[Görsel, analiz için isteğe eklendi.]")
        )
      } else {
        file_blocks <- c(
          file_blocks,
          paste0("### ", fname, "\n", mergen_vision_unavailable_note(fname))
        )
      }
      next
    }

    # METİN/BELGE DOSYALARI: mevcut özet/alıntı davranışı korunur.
    sumtxt <- summary_store[[fname]] %||% ""

    if (!is.character(sumtxt) || !nzchar(sumtxt[1])) {
      fobj <- current_file_store[[fname]] %||% NULL

      if (is.list(fobj)) {
        fpath <- fobj$datapath %||% fobj$path %||% ""

        path_ok <- nzchar(fpath) && tryCatch(
          if (exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
            path_exists_relaxed(fpath)
          } else {
            file.exists(fpath)
          },
          error = function(e) FALSE
        )

        if (isTRUE(path_ok)) {
          rawtxt <- read_fn(list(
            name = fname,
            datapath = fpath,
            size = file.info(fpath)$size
          ))
          sumtxt <- substr(rawtxt %||% "", 1, per_file_cap)
        }
      }
    } else {
      sumtxt <- as.character(sumtxt[1])
      if (nchar(sumtxt) > per_file_cap) sumtxt <- substr(sumtxt, 1, per_file_cap)
    }

    file_blocks <- c(file_blocks, paste0("### ", fname, "\n", sumtxt))
  }

  list(file_blocks = file_blocks, image_data_urls = image_data_urls)
}
