# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_model_config.R
# Açıklama: Bilge Yolaç / Claude Code için CLI yolu, settings.json, model
#           katmanları ve model yetenek karar yardımcılarını içerir.
# ==============================================================================

# ------------------------------------------------------------------------------
# CLI YOLU OTOMATİK TESPİTİ
# Windows'ta npm global kurulumlar .cmd uzantılı dosya oluşturur.
# processx bu uzantıyı kendisi çözemez, açıkça belirtilmelidir.
# ------------------------------------------------------------------------------

#' Claude Code CLI yolunu otomatik tespit eder
#'
#' @param kullanici_yolu Kullanıcının elle girdiği yol (boş olabilir)
#' @return Geçerli CLI yolu veya NULL (bulunamadıysa)
resolve_claude_cli_path <- function(kullanici_yolu = "") {
  # Kullanıcı bir yol verdiyse öncelikle onu dene

  if (nzchar(kullanici_yolu)) {
    # Windows'ta .cmd uzantısı yoksa ekle
    if (.Platform$OS.type == "windows" && !grepl("\\.(cmd|exe|bat)$", kullanici_yolu, ignore.case = TRUE)) {
      cmd_yolu <- paste0(kullanici_yolu, ".cmd")
      if (file.exists(cmd_yolu)) {
        return(normalizePath(cmd_yolu, winslash = "/"))
      }
    }
    # Yol doğrudan mevcut mu?
    if (file.exists(kullanici_yolu)) {
      return(normalizePath(kullanici_yolu, winslash = "/"))
    }
  }

  # Otomatik tespit: Sys.which ile PATH'te ara
  if (.Platform$OS.type == "windows") {
    # Windows'ta claude.cmd'yi ara
    cmd_yolu <- Sys.which("claude.cmd")
    if (nzchar(cmd_yolu)) return(normalizePath(cmd_yolu, winslash = "/"))

    # Tipik npm global kurulum dizinini kontrol et
    npm_dizini <- file.path(Sys.getenv("APPDATA"), "npm")
    npm_claude <- file.path(npm_dizini, "claude.cmd")
    if (file.exists(npm_claude)) return(normalizePath(npm_claude, winslash = "/"))
  } else {
    # Linux/macOS: PATH'te claude'u ara
    cli_yolu <- Sys.which("claude")
    if (nzchar(cli_yolu)) return(normalizePath(cli_yolu))
  }

  return(NULL)
}

# ------------------------------------------------------------------------------
# SETTINGS.JSON OKUMA
# Claude Code'un kendi ayar dosyasını okuyarak model listesini ve
# varsayılan modeli alır. Bu dosya ~/.claude/settings.json konumundadır.
# ------------------------------------------------------------------------------

#' Claude Code settings.json dosyasını okur
#'
#' @return Liste: models (model isimleri), default_model, base_url, raw (ham veri)
read_claude_settings_json <- function() {
  # settings.json konumu
  if (.Platform$OS.type == "windows") {
    ayar_yolu <- file.path(Sys.getenv("USERPROFILE"), ".claude", "settings.json")
  } else {
    ayar_yolu <- file.path(Sys.getenv("HOME"), ".claude", "settings.json")
  }

  sonuc <- list(
    models = character(0),
    default_model = "",
    base_url = "",
    raw = NULL,
    dosya_yolu = ayar_yolu
  )

  if (!file.exists(ayar_yolu)) {
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "settings.json bulunamadı:", ayar_yolu))
    return(sonuc)
  }

  tryCatch({
    icerik <- jsonlite::fromJSON(ayar_yolu, simplifyVector = FALSE)
    sonuc$raw <- icerik

    # Varsayılan model
    if (!is.null(icerik$model) && nzchar(icerik$model)) {
      sonuc$default_model <- icerik$model
    }

    # Ortam değişkenleri içerisindeki modelleri topla
    model_listesi <- c()

    if (!is.null(icerik$env)) {
      env <- icerik$env

      # ANTHROPIC_BASE_URL
      if (!is.null(env$ANTHROPIC_BASE_URL)) {
        sonuc$base_url <- env$ANTHROPIC_BASE_URL
      }

      # ANTHROPIC_DEFAULT_*_MODEL değişkenlerini tara
      model_anahtarlari <- grep("^ANTHROPIC_DEFAULT_.*_MODEL$", names(env), value = TRUE)
      for (anahtar in model_anahtarlari) {
        model_adi <- env[[anahtar]]
        if (!is.null(model_adi) && nzchar(model_adi)) {
          # Anahtar adından etiketi çıkar (OPUS, SONNET, HAIKU, vb.)
          etiket <- gsub("^ANTHROPIC_DEFAULT_(.+)_MODEL$", "\\1", anahtar)
          model_listesi <- c(model_listesi, setNames(model_adi, etiket))
        }
      }
    }

    # Varsayılan model listeye dahil değilse ekle
    if (nzchar(sonuc$default_model) && !(sonuc$default_model %in% model_listesi)) {
      model_listesi <- c(setNames(sonuc$default_model, "VARSAYILAN"), model_listesi)
    }

    sonuc$models <- model_listesi

    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "settings.json okundu.",
                   length(model_listesi), "model bulundu.",
                   "Varsayılan:", sonuc$default_model))

  }, error = function(e) {
    log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "settings.json okunamadı:", conditionMessage(e)))
  })

  return(sonuc)
}

# ------------------------------------------------------------------------------
# MODEL KATMAN EŞLEŞTİRME
# settings.json'daki teknik model adlarını kullanıcı dostu etiketlerle eşleştirir
# ------------------------------------------------------------------------------

#' Model listesini kullanıcı dostu katman etiketleriyle eşleştirir
#'
#' @param model_listesi Adlandırılmış karakter vektörü (anahtar=etiket, değer=model_id)
#' @return Adlandırılmış liste: her eleman list(etiket, ikon, aciklama, deger)
build_model_tier_choices <- function(model_listesi) {
  if (length(model_listesi) == 0) {
    return(list(list(
      etiket = claude_code_varsayilan_etiket,
      ikon = "fa-cog",
      ikon_unicode = "\u2699",
      aciklama = "Yapılandırma dosyasındaki varsayılan model",
      deger = ""
    )))
  }

  katmanlar <- claude_code_model_tiers
  sonuc <- list()

  for (i in seq_along(model_listesi)) {
    model_id <- unname(model_listesi[i])
    anahtar <- names(model_listesi)[i]

    # Katman eşleştirmesi yap (anahtar adındaki desene göre)
    eslesme <- NULL
    for (katman in katmanlar) {
      if (grepl(katman$anahtar_deseni, anahtar, ignore.case = TRUE)) {
        eslesme <- katman
        break
      }
    }

    if (is.null(eslesme)) {
      # Eşleşme bulunamadıysa varsayılan etiket kullan
      sonuc[[length(sonuc) + 1]] <- list(
        etiket = paste0(claude_code_varsayilan_etiket, " (", anahtar, ")"),
        ikon = "fa-cog",
        ikon_unicode = "\u2699",
        aciklama = paste("Model:", model_id),
        deger = model_id
      )
    } else {
      sonuc[[length(sonuc) + 1]] <- list(
        etiket = eslesme$etiket,
        ikon = eslesme$ikon,
        ikon_unicode = eslesme$ikon_unicode %||% "",
        aciklama = eslesme$aciklama,
        deger = model_id
      )
    }
  }

  # Sıralama: Hızlı -> Dengeli -> Güçlü -> Diğer
  siralama <- c("Hızlı", "Dengeli", "Güçlü")
  sonuc <- sonuc[order(match(
    sapply(sonuc, function(x) x$etiket),
    siralama,
    nomatch = length(siralama) + 1
  ))]

  return(sonuc)
}

# ------------------------------------------------------------------------------
# MODEL YETENEKLERİ VE DOKÜMAN UYUMLULUĞU
# Düşünen modeller bazı ikili doküman akışlarında sorun çıkarabildiği için
# model yetenekleri .Renviron üzerinden işaretlenir.
# ------------------------------------------------------------------------------

parse_claude_code_env_list <- function(deger) {
  if (is.null(deger) || !length(deger)) return(character(0))

  parcalar <- trimws(
    unlist(strsplit(as.character(deger[[1]]), "[,;\\n\\r]+", perl = TRUE))
  )

  unique(parcalar[nzchar(parcalar)])
}

get_claude_code_model_capabilities <- function() {
  list(
    thinking_models = parse_claude_code_env_list(
      Sys.getenv("CLAUDE_CODE_THINKING_MODELS", "")
    ),
    binary_doc_extensions = tolower(
      parse_claude_code_env_list(
        Sys.getenv(
          "CLAUDE_CODE_BINARY_DOC_EXTENSIONS",
          "pdf,xlsx,xls,doc,docx,ppt,pptx"
        )
      )
    ),
    auto_fallback_non_thinking_for_binary_docs = isTRUE(
      as.logical(
        Sys.getenv(
          "CLAUDE_CODE_AUTO_FALLBACK_NON_THINKING_FOR_BINARY_DOCS",
          "TRUE"
        )
      )
    )
  )
}

get_claude_code_runtime_model_capabilities <- function(model_id = NULL) {
  model_id <- as.character(model_id %||% "")[1]

  env_caps <- get_claude_code_model_capabilities()

  local_caps <- tryCatch(
    get_local_model_capabilities(model_id, api_config),
    error = function(e) list()
  )

  list(
    thinking = isTRUE(local_caps$thinking) ||
      (
        nzchar(model_id) &&
          model_id %in% (env_caps$thinking_models %||% character(0))
      ),
    omit_temperature = isTRUE(local_caps$omit_temperature),
    stream_reasoning = isTRUE(local_caps$stream_reasoning),
    allow_reasoning_fallback = isTRUE(local_caps$allow_reasoning_fallback)
  )
}

is_claude_code_thinking_model <- function(model_id) {
  if (is.null(model_id) || !nzchar(model_id)) {
    return(FALSE)
  }

  isTRUE(get_claude_code_runtime_model_capabilities(model_id)$thinking)
}

prompt_mentions_binary_document_type <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))
  if (!nzchar(metin)) return(FALSE)

  tip_deseni <- paste(
    c(
      "\\bpdf\\b",
      "\\bexcel\\b",
      "\\bxlsx\\b",
      "\\bxls\\b",
      "\\bcsv\\b",
      "\\bdocx\\b",
      "\\bdoc\\b",
      "\\bword\\b",
      "\\bpptx\\b",
      "\\bppt\\b",
      "\\bpowerpoint\\b",
      "\\bspreadsheet\\b",
      "çalışma kitabı",
      "calisma kitabi",
      "elektronik tablo",
      "sunum"
    ),
    collapse = "|"
  )

  grepl(tip_deseni, metin, perl = TRUE)
}

prompt_requests_document_operation <- function(prompt) {
  metin <- tolower(enc2utf8(paste(as.character(prompt %||% ""), collapse = " ")))
  if (!nzchar(metin)) return(FALSE)

  # Türkçe çekimli fiilleri ve yaygın varyasyonları daha toleranslı yakala
  islem_deseni <- paste(
    c(
      "\\bok[a-zçğıöşü]*\\b",
      "\\bokuy[a-zçğıöşü]*\\b",
      "\\bincele[a-zçğıöşü]*\\b",
      "\\bözet[a-zçğıöşü]*\\b",
      "\\bozet[a-zçğıöşü]*\\b",
      "\\banaliz[a-zçğıöşü]*\\b",
      "\\byorumla[a-zçğıöşü]*\\b",
      "\\bkarşılaştır[a-zçğıöşü]*\\b",
      "\\bkarsilastir[a-zçğıöşü]*\\b",
      "\\blistele[a-zçğıöşü]*\\b",
      "\\bpdf\\b",
      "\\bexcel\\b",
      "\\bxlsx\\b",
      "\\bxls\\b",
      "\\bdosya[a-zçğıöşü]*\\b",
      "\\bdizin[a-zçğıöşü]*\\b",
      "\\bklasör[a-zçğıöşü]*\\b",
      "\\bklasor[a-zçğıöşü]*\\b",
      "\\bread\\b",
      "\\bsummariz[a-z]*\\b",
      "\\banaly[sz][a-z]*\\b",
      "\\bcompare\\b",
      "\\blist\\b"
    ),
    collapse = "|"
  )

  grepl(islem_deseni, metin, perl = TRUE)
}

workdir_has_binary_documents <- function(workdir, extensions = NULL, limits = NULL) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) return(FALSE)

  if (is.null(extensions) || !length(extensions)) {
    extensions <- get_claude_code_model_capabilities()$binary_doc_extensions
  }

  extensions <- tolower(as.character(extensions))
  if (!length(extensions)) return(FALSE)

  # Yalnızca kökün doğrudan altına bakmak, "input/reports/quarterly.pdf" gibi
  # kopyalanmış iç içe dokümanları kaçırıyordu; bu da doküman görevi tespitini
  # (ve dolayısıyla yerel metin çıkarımı yolunu) hiç tetiklemiyordu. Sınırlı
  # tarayıcı kullanılabiliyorsa küçük bir derinlikle özyinelemeli bakılır;
  # aksi halde eski davranışa (yalnızca kök) düşülür.
  if (exists("cc_scan_directory_bounded", mode = "function", inherits = TRUE)) {
    derinlik <- suppressWarnings(as.numeric(
      if (exists("cc_runtime_limit", mode = "function", inherits = TRUE)) {
        cc_runtime_limit("document_probe_max_depth", 4, limits)
      } else {
        4
      }
    ))
    if (!is.finite(derinlik) || derinlik < 0) derinlik <- 4

    tarama <- tryCatch(
      cc_scan_directory_bounded(
        root = workdir,
        max_files = 400L,
        max_dirs = 200L,
        max_depth = derinlik,
        max_elapsed_ms = 1500L,
        max_entries = 4000L,
        max_file_bytes = Inf,
        exclude_dirs = character(0),
        exclude_rel_paths = character(0)
      ),
      error = function(e) NULL
    )

    if (!is.null(tarama)) {
      if (!length(tarama$files)) return(FALSE)
      uzantilar <- tolower(tools::file_ext(tarama$files))
      return(any(nzchar(uzantilar) & uzantilar %in% extensions))
    }
  }

  ogeler <- tryCatch(
    list.files(
      workdir,
      recursive = FALSE,
      full.names = FALSE,
      all.files = FALSE,
      include.dirs = FALSE
    ),
    error = function(e) character(0)
  )

  if (!length(ogeler)) return(FALSE)

  uzantilar <- tolower(tools::file_ext(ogeler))
  any(nzchar(uzantilar) & uzantilar %in% extensions)
}

resolve_claude_code_execution_model <- function(selected_model,
                                                prompt = "",
                                                workdir = "",
                                                document_context = NULL) {
  sonuc <- list(
    allow_run = TRUE,
    model = selected_model %||% "",
    fallback_used = FALSE,
    reason = "",
    selected_model = selected_model %||% ""
  )

  yetenekler <- get_claude_code_model_capabilities()

  if (!isTRUE(yetenekler$auto_fallback_non_thinking_for_binary_docs)) {
    return(sonuc)
  }

  if (!isTRUE(is_claude_code_thinking_model(selected_model))) {
    return(sonuc)
  }

  ikili_dokuman_gorevi <- FALSE
  metin_on_hazirlama_basarili <- FALSE

  if (is.list(document_context) && length(document_context) > 0) {
    ikili_dokuman_gorevi <- isTRUE(document_context$has_binary_docs)
    metin_on_hazirlama_basarili <- isTRUE(document_context$text_sidecars_ready)
  } else {
    ikili_dokuman_gorevi <- isTRUE(prompt_mentions_binary_document_type(prompt)) ||
      (
        isTRUE(prompt_requests_document_operation(prompt)) &&
          isTRUE(
            workdir_has_binary_documents(
              workdir,
              yetenekler$binary_doc_extensions
            )
          )
      )
  }

  if (!isTRUE(ikili_dokuman_gorevi)) {
    return(sonuc)
  }

  if (isTRUE(metin_on_hazirlama_basarili)) {
    sonuc$reason <- paste(
      "İkili dokümanlar önceden düz metne dönüştürüldü.",
      "Seçili düşünme modeli korunuyor."
    )
    return(sonuc)
  }

  ayarlar <- read_claude_settings_json()

  fallback_adaylari <- unique(unname(ayarlar$models))
  fallback_adaylari <- fallback_adaylari[nzchar(fallback_adaylari)]
  fallback_adaylari <- fallback_adaylari[
    !vapply(fallback_adaylari, is_claude_code_thinking_model, logical(1))
  ]

  if (!length(fallback_adaylari)) {
    sonuc$allow_run <- FALSE
    sonuc$reason <- paste(
      "Seçili model düşünen bir model ve ikili doküman görevi için",
      "kullanılabilir düşünmeyen yedek model bulunamadı."
    )
    return(sonuc)
  }

  sonuc$model <- fallback_adaylari[1]
  sonuc$fallback_used <- !identical(sonuc$model, selected_model)

  if (isTRUE(sonuc$fallback_used)) {
    sonuc$reason <- paste(
      "İkili dokümanlar için ön metin çıkarımı hazır değil.",
      "Bu nedenle düşünmeyen modele geçildi."
    )
  }

  sonuc
}