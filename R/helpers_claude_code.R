# ==============================================================================
# Dosya Yolu: R/helpers_claude_code.R
# Açıklama: Claude Code CLI ile etkileşim için arka plan işçi fonksiyonları.
#           processx paketi ile alt süreç yönetimi, CLI otomatik tespiti,
#           settings.json okuma, oturum yönetimi ve dosya sistemi işlemleri.
#           JSON çıktı desteği ile araç kullanımı ve kabuk komutlarını ayrıştırır.
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

workdir_has_binary_documents <- function(workdir, extensions = NULL) {
  if (is.null(workdir) || !nzchar(workdir) || !dir.exists(workdir)) return(FALSE)

  if (is.null(extensions) || !length(extensions)) {
    extensions <- get_claude_code_model_capabilities()$binary_doc_extensions
  }

  extensions <- tolower(as.character(extensions))
  if (!length(extensions)) return(FALSE)

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

#' Node.js çalıştırılabilir yolunu çözümler
#'
#' @return Geçerli node.exe yolu veya NULL
resolve_node_path <- function() {
  adaylar <- c(
    Sys.getenv("CLAUDE_CODE_NODE_PATH", ""),
    Sys.which("node.exe"),
    Sys.which("node"),
    file.path(Sys.getenv("ProgramFiles"), "nodejs", "node.exe"),
    file.path(Sys.getenv("ProgramFiles(x86)"), "nodejs", "node.exe"),
    file.path(Sys.getenv("LocalAppData"), "Programs", "nodejs", "node.exe"),
    file.path(Sys.getenv("NVM_SYMLINK"), "node.exe"),
    file.path(Sys.getenv("NVM_HOME"), "node.exe")
  )

  for (aday in adaylar) {
    if (!nzchar(aday)) next
    if (file.exists(aday)) {
      return(normalizePath(aday, winslash = "/", mustWork = FALSE))
    }
  }

  return(NULL)
}

# ------------------------------------------------------------------------------
# PROCESSX ÇIKTI KODLAMA DÜZELTMESİ
# Claude Code CLI her zaman UTF-8 çıktı üretir. Windows'ta R'ın kodlama
# sistemi (Encoding etiketleri, enc2utf8, iconv) güvenilir şekilde
# çalışmayabiliyor. Bu yüzden tüm ASCII-dışı karakterleri HTML sayısal
# varlıklarına (&#NNN;) çevirerek saf ASCII string elde ediyoruz.
# Böylece toJSON serileştirmesinde kodlama sorunu kökten ortadan kalkar.
# ------------------------------------------------------------------------------

#' ASCII-dışı karakterleri HTML sayısal varlıklarına çevirir
#'
#' @description R'ın kodlama etiketleme sorunlarını tamamen atlar.
#'   Tüm ASCII-dışı karakterler &#NNN; formatına dönüştürülür.
#'   Sonuç saf ASCII olduğu için toJSON/WebSocket sorunsuz çalışır.
#'   Tarayıcı HTML varlıklarını otomatik olarak doğru karaktere çevirir.
#' @param metin Karakter vektörü (tek veya çok elemanlı)
#' @return Saf ASCII metin (HTML varlıkları ile)
escape_non_ascii <- function(metin) {
  if (is.null(metin) || !length(metin)) return(metin)
  metin <- as.character(metin)

  vapply(metin, function(m) {
    if (!nzchar(m)) return(m)

    # Önce UTF-8 olarak yorumlamayı dene
    tryCatch({
      # iconv ile UTF-8 → UTF-8 doğrulaması
      test <- iconv(m, from = "UTF-8", to = "UTF-8")
      if (!is.na(test)) {
        Encoding(m) <- "UTF-8"
      } else {
        # Geçerli UTF-8 değilse yerel kodlamadan dönüştür
        m <- enc2utf8(m)
      }
    }, error = function(e) {
      tryCatch({ m <<- enc2utf8(m) }, error = function(e2) NULL)
    })

    # Karakter karakter dolaşıp ASCII-dışı olanları &#NNN; yap
    kod_noktalari <- tryCatch(utf8ToInt(m), error = function(e) NULL)
    if (is.null(kod_noktalari)) return(m)

    parcalar <- vapply(kod_noktalari, function(kn) {
      if (kn > 127L) {
        sprintf("&#%d;", kn)
      } else {
        intToUtf8(kn)
      }
    }, character(1))

    paste(parcalar, collapse = "")
  }, character(1), USE.NAMES = FALSE)
}

#' processx çıktısını UTF-8 olarak işaretlemeye çalışır
#'
#' @description processx okuması sonrası baytları UTF-8 olarak etiketler.
#'   jsonlite::fromJSON() ayrıştırması için hazırlık yapar.
#' @param metin processx'ten okunan ham metin
#' @return UTF-8 etiketli metin
ensure_utf8 <- function(metin) {
  if (is.null(metin) || !length(metin)) return(metin)
  metin <- as.character(metin)

  kodlamalar <- Encoding(metin)
  if (all(kodlamalar == "UTF-8")) return(metin)

  test <- iconv(metin, from = "UTF-8", to = "UTF-8")
  gecerli_utf8 <- !is.na(test)

  sonuc <- metin
  if (any(gecerli_utf8)) {
    Encoding(sonuc[gecerli_utf8]) <- "UTF-8"
  }
  if (any(!gecerli_utf8)) {
    sonuc[!gecerli_utf8] <- enc2utf8(metin[!gecerli_utf8])
  }
  sonuc
}

# ------------------------------------------------------------------------------
# WINDOWS .CMD UYUMLULUĞU
# Windows'ta .cmd dosyaları cmd.exe üzerinden çalıştırılmalıdır.
# processx bazı sunucu ortamlarında .cmd'yi doğrudan çalıştıramaz.
# ------------------------------------------------------------------------------

# Windows UNC/ağ paylaşımı yolu mu?
is_windows_unc_path <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\\\", "/", as.character(path[1]), fixed = TRUE)
  grepl("^//", aday)
}

# cmd.exe içinde kullanılacak çalışma dizinini Windows biçimine çevir
normalize_cmd_workdir <- function(path) {
  aday <- as.character(path %||% "")
  if (!nzchar(aday)) return("")

  aday <- gsub("/", "\\\\", aday, fixed = TRUE)

  # Tek ters slash ile başlayan UNC benzeri yolu çift ters slash yap
  if (grepl("^\\\\[^\\\\]", aday)) {
    aday <- paste0("\\", aday)
  }

  aday
}

#' processx için komut ve argümanları hazırlar
#' Windows'ta .cmd dosyalarını cmd.exe /c üzerinden sarar
#'
#' @param cli_path CLI çalıştırılabilir dosya yolu
#' @param args CLI argümanları
#' @param workdir Çalışma dizini
#' @return Liste: command, args, env, wd
build_processx_command <- function(cli_path, args, workdir = NULL) {
  if (.Platform$OS.type == "windows" && grepl("\\.cmd$", cli_path, ignore.case = TRUE)) {
    # cmd.exe için Windows stilinde dizin kullan
    npm_dizini <- normalizePath(dirname(cli_path), winslash = "\\", mustWork = FALSE)
    node_yolu <- resolve_node_path()
    node_dizini <- if (!is.null(node_yolu)) {
      normalizePath(dirname(node_yolu), winslash = "\\", mustWork = FALSE)
    } else {
      ""
    }

    # Mevcut ortam değişkenlerini al ve PATH/Path anahtarını yerinde güncelle
    env <- Sys.getenv()
    path_eslesmeleri <- which(tolower(names(env)) == "path")
    path_adi <- if (length(path_eslesmeleri) > 0) names(env)[path_eslesmeleri[1]] else "PATH"

    mevcut_path <- if (path_adi %in% names(env)) unname(env[[path_adi]]) else ""
    eklenecekler <- unique(Filter(nzchar, c(npm_dizini, node_dizini)))

    yeni_path <- mevcut_path
    for (dizin in rev(eklenecekler)) {
      if (!grepl(dizin, yeni_path, fixed = TRUE)) {
        yeni_path <- if (nzchar(yeni_path)) paste(dizin, yeni_path, sep = ";") else dizin
      }
    }

    env[[path_adi]] <- yeni_path

    # UNC çalışma dizininde cmd.exe doğrudan başlatılırsa C:\Windows'a düşebilir.
    # Bu yüzden ağ yolunu pushd ile geçici sürücüye eşleyip komutu orada çalıştır.
    if (is_windows_unc_path(workdir)) {
      hedef_dizin <- normalize_cmd_workdir(workdir)
      cli_cmd <- normalizePath(cli_path, winslash = "\\", mustWork = FALSE)
      quoted_args <- vapply(
        args,
        function(x) shQuote(as.character(x), type = "cmd"),
        character(1),
        USE.NAMES = FALSE
      )

      komut_satiri <- paste(
        c(
          "pushd",
          shQuote(hedef_dizin, type = "cmd"),
          "&&",
          "call",
          shQuote(cli_cmd, type = "cmd"),
          quoted_args,
          "&",
          "popd"
        ),
        collapse = " "
      )

      log_info(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "UNC çalışma dizini pushd ile eşlendi:",
        workdir
      ))

      return(list(
        command = Sys.getenv("ComSpec", "cmd.exe"),
        args = c("/d", "/c", komut_satiri),
        env = env,
        wd = get_safe_claude_cli_workdir(workdir)
      ))
    }

    list(
      command = Sys.getenv("ComSpec", "cmd.exe"),
      args = c("/d", "/c", normalizePath(cli_path, winslash = "\\", mustWork = FALSE), args),
      env = env,
      wd = workdir
    )
  } else {
    list(command = cli_path, args = args, env = NULL, wd = workdir)
  }
}

# ------------------------------------------------------------------------------
# CLAUDE CODE CLI ÇALIŞTIRMA (JSON ÇIKTI DESTEKLİ)
# --output-format json ile araç kullanımı ve kabuk komutlarını ayrıştırır
# ------------------------------------------------------------------------------

#' Claude Code CLI komutunu arka planda çalıştır
#'
#' @param prompt Kullanıcının gönderdiği komut/soru metni
#' @param workdir Çalışma dizini (proje klasörü)
#' @param model Kullanılacak model adı (boş ise varsayılan kullanılır)
#' @param timeout_sec Zaman aşımı süresi (saniye)
#' @param session_id Oturum kimliği (izolasyon için)
#' @param cli_path Claude Code CLI çalıştırılabilir dosya yolu
#' @return Liste: success, output, error, duration, tool_uses (araç kullanımları)
run_claude_code <- function(prompt,
                            workdir = getwd(),
                            model = NULL,
                            timeout_sec = 300L,
                            session_id = NULL,
                            cli_path = NULL) {

  baslangic <- Sys.time()

  # Girdi doğrulaması
  if (!nzchar(trimws(prompt))) {
    return(list(
      success = FALSE,
      output = "",
      error = "Komut metni boş olamaz.",
      duration = 0,
      tool_uses = list(),
      session_id = NULL
    ))
  }

  # CLI yolunu çözümle (verilmediyse otomatik tespit et)
  if (is.null(cli_path) || !nzchar(cli_path)) {
    cli_path <- resolve_claude_cli_path(claude_code_config$cli_path)
  }
  if (is.null(cli_path)) {
    return(list(
      success = FALSE,
      output = "",
      error = "Claude Code CLI bulunamadı. Lütfen CLI yolunu kontrol edin.",
      duration = 0,
      tool_uses = list(),
      session_id = NULL
    ))
  }

  # Çalışma dizini kontrolü
  if (!dir.exists(workdir)) {
    return(list(
      success = FALSE,
      output = "",
      error = paste0("Çalışma dizini bulunamadı: ", workdir),
      duration = 0,
      tool_uses = list(),
      session_id = NULL
    ))
  }

  # CLI argümanları oluştur
  # --print: interaktif olmayan mod, çıktıyı doğrudan yazdır
  # --output-format json: yapılandırılmış çıktı (araç kullanımlarını da içerir)
  # --dangerously-skip-permissions: izin isteklerini otomatik kabul et
  #   (interaktif olmayan modda kullanıcı onayı verilemediği için gerekli)
  args <- c(
    "--print",
    "--output-format", "json",
    "--dangerously-skip-permissions"
  )

  # Model belirtilmişse ekle
  if (!is.null(model) && nzchar(model)) {
    args <- c(args, "--model", model)
  }

  # Oturum devamı: session_id varsa --resume ile önceki konuşmayı sürdür
  # Bu sayede CLI kendi iç hafızasından konuşma geçmişini yükler
  if (!is.null(session_id) && nzchar(session_id)) {
    args <- c(args, "--resume", session_id)
  }

  # Komutu (prompt) argüman olarak ekle
  args <- c(args, prompt)

  # Windows'ta .cmd dosyalarını cmd.exe üzerinden çalıştır
  # (RStudio sunucu oturumlarında processx doğrudan .cmd çalıştıramayabilir)
  komut <- build_processx_command(cli_path, args, workdir = workdir)

  # processx::process$new ile çalıştır (handle yönetimi daha güvenli)
  tryCatch({
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "CLI çalıştırılıyor:",
                   cli_path, paste(args[1:min(3, length(args))], collapse = " "), "..."))

    proc <- processx::process$new(
      command = komut$command,
      args = komut$args,
      env = komut$env,
      wd = komut$wd %||% workdir,
      stdout = "|",
      stderr = "|",
      cleanup = TRUE,
      cleanup_tree = TRUE
    )

    # Zaman aşımı ile bekle
    proc$wait(timeout = timeout_sec * 1000)

    # Zaman aşımı kontrolü (süreç hâlâ çalışıyorsa zaman aşımına uğramıştır)
    if (proc$is_alive()) {
      tryCatch(proc$kill(), error = function(e) NULL)
      sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
      log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Zaman aşımı:", timeout_sec, "sn"))
      return(list(
        success = FALSE,
        output = "",
        error = paste0("İşlem zaman aşımına uğradı (", timeout_sec, " saniye). ",
                       "Daha kısa bir komut deneyin veya zaman aşımı süresini artırın."),
        duration = round(sure, 1),
        tool_uses = list(),
        session_id = NULL
      ))
    }

    # Windows'ta processx yerel kodlama kullanır; UTF-8'e dönüştür
    stdout_metin <- ensure_utf8(proc$read_all_output())
    stderr_metin <- ensure_utf8(proc$read_all_error())
    cikis_kodu <- proc$get_exit_status()

    sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))

    if (identical(cikis_kodu, 0L)) {
      log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Başarılı - Süre:",
                     round(sure, 1), "sn"))

      # JSON çıktısını ayrıştır
      ayristirma <- parse_claude_code_json_output(stdout_metin)

      list(
        success = TRUE,
        output = ayristirma$text_output,
        error = "",
        duration = round(sure, 1),
        tool_uses = ayristirma$tool_uses,
        session_id = ayristirma$session_id
      )
    } else {
      hata_mesaji <- if (nzchar(stderr_metin)) stderr_metin else stdout_metin
      # Süslü parantezleri temizle (glue formatter çakışmasını önle)
      temiz_log <- gsub("[{}]", "", substr(hata_mesaji, 1, 200))
      log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Hata kodu:", cikis_kodu,
                     "- Mesaj:", temiz_log))
      list(
        success = FALSE,
        output = stdout_metin,
        error = hata_mesaji,
        duration = round(sure, 1),
        tool_uses = list(),
        session_id = NULL
      )
    }

  }, error = function(e) {
    sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
    hata_metni <- conditionMessage(e)

    # Süslü parantezleri temizle (glue formatter çakışmasını önle)
    temiz_hata <- gsub("[{}]", "", hata_metni)
    log_error(paste(CLAUDE_CODE_LOG_PREFIX, "CLI hatası:", temiz_hata))
    list(
      success = FALSE,
      output = "",
      error = paste0("Claude Code çalıştırılırken hata oluştu: ", hata_metni),
      duration = round(sure, 1),
      tool_uses = list(),
      session_id = NULL
    )
  })
}

# ------------------------------------------------------------------------------
# JSON ÇIKTI AYRIŞTIRMA
# Claude Code'un --output-format json çıktısını ayrıştırır.
# Her satır ayrı bir JSON nesnesidir (JSONL formatı).
# ------------------------------------------------------------------------------

#' Claude Code JSON çıktısını ayrıştırır
#'
#' @param ham_cikti CLI'dan gelen ham çıktı metni
#' @return Liste: text_output (metin çıktısı), tool_uses (araç kullanımları listesi)
parse_claude_code_json_output <- function(ham_cikti) {
  sonuc <- list(text_output = "", tool_uses = list(), session_id = NULL)

  if (is.null(ham_cikti) || !nzchar(ham_cikti)) return(sonuc)

  # JSONL satırlarını ayrıştır
  satirlar <- strsplit(ham_cikti, "\n")[[1]]
  metin_parcalari <- c()

  # Metin daha önce delta/blok olarak geldiyse result alanını ikinci kez eklememek için bayrak
  metin_zaten_toplandi <- FALSE

  # Araç girdisi delta biriktiricisi (stream-json formatı için)
  arac_girdi_tamponlari <- list()

  for (satir in satirlar) {
    satir <- trimws(satir)
    if (!nzchar(satir)) next

    tryCatch({
      nesne <- jsonlite::fromJSON(satir, simplifyVector = FALSE)
      tur <- nesne$type %||% ""

      # --- stream-json formatı (sarmalayıcı ile) ---
      if (tur == "stream_event") {
        olay <- nesne$event
        if (is.null(olay)) next

        # session_id sarmalayıcıda bulunur
        if (!is.null(nesne$session_id) && nzchar(nesne$session_id %||% "")) {
          sonuc$session_id <- nesne$session_id
        }

        olay_turu <- olay$type %||% ""

        if (olay_turu == "content_block_start") {
          blok <- olay$content_block
          if (!is.null(blok) && (blok$type %||% "") == "tool_use") {
            arac <- list(
              id = blok$id %||% "",
              name = blok$name %||% "",
              input = blok$input %||% list()
            )
            sonuc$tool_uses <- c(sonuc$tool_uses, list(arac))
            # Girdi tamponunu başlat
            arac_girdi_tamponlari[[blok$id %||% ""]] <- ""
          }

        } else if (olay_turu == "content_block_delta") {
          delta <- olay$delta
          if (!is.null(delta)) {
            delta_turu <- delta$type %||% ""
            if (delta_turu == "text_delta") {
              delta_metin <- delta$text %||% ""
              if (nzchar(delta_metin)) {
                metin_parcalari <- c(metin_parcalari, delta_metin)
                metin_zaten_toplandi <- TRUE
              }
            } else if (delta_turu == "input_json_delta") {
              # Araç girdisi parçasını biriktir (son araç için)
              if (length(sonuc$tool_uses) > 0) {
                son_arac_id <- sonuc$tool_uses[[length(sonuc$tool_uses)]]$id
                mevcut <- arac_girdi_tamponlari[[son_arac_id]] %||% ""
                arac_girdi_tamponlari[[son_arac_id]] <- paste0(
                  mevcut, delta$partial_json %||% ""
                )
              }
            }
          }

        } else if (olay_turu == "content_block_stop") {
          # Araç girdisi tamponunu JSON olarak ayrıştır ve araca ata
          if (length(sonuc$tool_uses) > 0) {
            son_arac <- sonuc$tool_uses[[length(sonuc$tool_uses)]]
            tampon <- arac_girdi_tamponlari[[son_arac$id]] %||% ""
            if (nzchar(tampon)) {
              tryCatch({
                sonuc$tool_uses[[length(sonuc$tool_uses)]]$input <-
                  jsonlite::fromJSON(tampon, simplifyVector = FALSE)
              }, error = function(e) NULL)
            }
          }

        } else if (olay_turu == "result") {
          sonuc_metin <- olay$result %||% ""
          if (!isTRUE(metin_zaten_toplandi) && nzchar(sonuc_metin)) {
            metin_parcalari <- c(metin_parcalari, sonuc_metin)
            metin_zaten_toplandi <- TRUE
          }
        }

        next
      }

      # --- Eski json formatı (geriye uyumluluk) ---
      if (tur == "text") {
        parca_metin <- nesne$content %||% ""
        if (nzchar(parca_metin)) {
          metin_parcalari <- c(metin_parcalari, parca_metin)
          metin_zaten_toplandi <- TRUE
        }

      } else if (tur == "tool_use") {
        arac <- list(
          id = nesne$id %||% "",
          name = nesne$name %||% "",
          input = nesne$input %||% list()
        )
        sonuc$tool_uses <- c(sonuc$tool_uses, list(arac))

      } else if (tur == "tool_result") {
        arac_id <- nesne$tool_use_id %||% ""
        icerik <- nesne$content %||% ""
        for (j in seq_along(sonuc$tool_uses)) {
          if (identical(sonuc$tool_uses[[j]]$id, arac_id)) {
            sonuc$tool_uses[[j]]$result <- icerik
            break
          }
        }

      } else if (tur == "result") {
        sonuc_metin <- nesne$result %||% ""
        if (!isTRUE(metin_zaten_toplandi) && nzchar(sonuc_metin)) {
          metin_parcalari <- c(metin_parcalari, sonuc_metin)
          metin_zaten_toplandi <- TRUE
        }
        if (!is.null(nesne$session_id) && nzchar(nesne$session_id %||% "")) {
          sonuc$session_id <- nesne$session_id
        }

      } else if (tur == "assistant") {
        if (!is.null(nesne$content) && is.list(nesne$content)) {
          for (blok in nesne$content) {
            blok_tur <- blok$type %||% ""
            if (blok_tur == "text") {
              blok_metin <- blok$text %||% ""
              if (nzchar(blok_metin)) {
                metin_parcalari <- c(metin_parcalari, blok_metin)
                metin_zaten_toplandi <- TRUE
              }
            } else if (blok_tur == "tool_use") {
              arac <- list(
                id = blok$id %||% "",
                name = blok$name %||% "",
                input = blok$input %||% list()
              )
              sonuc$tool_uses <- c(sonuc$tool_uses, list(arac))
            }
          }
        }
      }

    }, error = function(e) {
      metin_parcalari <<- c(metin_parcalari, satir)
    })
  }

  # paste() sonrası UTF-8 etiketini garanti altına al (Windows'ta
  # jsonlite::fromJSON çıktısı kodlama işaretini kaybedebilir)
  sonuc$text_output <- ensure_utf8(paste(metin_parcalari, collapse = ""))
  return(sonuc)
}

#' CLI durum kontrolü için güvenli çalışma dizini seçer
#'
#' @param workdir Tercih edilen çalışma dizini
#' @return Yerel ve geçerli çalışma dizini yolu
get_safe_claude_cli_workdir <- function(workdir = NULL) {
  adaylar <- c(
    workdir %||% "",
    claude_code_config$default_workdir %||% "",
    tempdir()
  )

  for (aday in adaylar) {
    if (!nzchar(aday) || !dir.exists(aday)) next
    if (
      .Platform$OS.type == "windows" &&
      (grepl("^\\\\\\\\", aday) || grepl("^//", gsub("\\\\", "/", aday)))
    ) next
    return(normalizePath(aday, winslash = "/", mustWork = FALSE))
  }

  normalizePath(tempdir(), winslash = "/", mustWork = FALSE)
}

# ------------------------------------------------------------------------------
# CLAUDE CODE CLI DURUM KONTROLÜ
# ------------------------------------------------------------------------------

#' Claude Code CLI'nin kurulu ve erişilebilir olup olmadığını kontrol eder
#'
#' @param cli_path Claude Code CLI yolu (NULL ise otomatik tespit)
#' @return Liste: installed (mantıksal), version (sürüm metni), path (bulunan yol), error (hata)
check_claude_code_status <- function(cli_path = NULL, workdir = NULL) {
  # CLI yolunu çözümle
  if (is.null(cli_path) || !nzchar(cli_path)) {
    cli_path <- resolve_claude_cli_path(claude_code_config$cli_path)
  } else {
    cli_path <- resolve_claude_cli_path(cli_path)
  }

  if (is.null(cli_path)) {
    return(list(
      installed = FALSE,
      version = "",
      path = "",
      error = "Claude Code CLI bulunamadı. npm ile kurulu olduğundan emin olun."
    ))
  }

  tryCatch({
    # Windows UNC yolundan çalışırken cmd.exe hata verdiği için
    # durum kontrolünde güvenli yerel bir çalışma dizini kullan
    komut <- build_processx_command(cli_path, c("--version"), workdir = workdir)
    guvenli_wd <- get_safe_claude_cli_workdir(workdir)

    proc <- processx::process$new(
      command = komut$command,
      args = komut$args,
      env = komut$env,
      wd = komut$wd %||% guvenli_wd,
      stdout = "|",
      stderr = "|",
      cleanup = TRUE,
      cleanup_tree = TRUE
    )
	
    proc$wait(timeout = 10000)

    if (proc$is_alive()) {
      tryCatch(proc$kill(), error = function(e) NULL)
      return(list(installed = FALSE, version = "", path = cli_path,
                  error = "CLI zaman aşımına uğradı"))
    }

    # Windows'ta processx yerel kodlama kullanır; UTF-8'e dönüştür
    stdout_metin <- ensure_utf8(proc$read_all_output())
    cikis_kodu <- proc$get_exit_status()

    if (identical(cikis_kodu, 0L)) {
      surum <- trimws(stdout_metin)
      list(installed = TRUE, version = surum, path = cli_path, error = "")
    } else {
      stderr_metin <- ensure_utf8(proc$read_all_error())
      hata_detay <- paste0(
        "Çıkış kodu: ", cikis_kodu,
        " | stdout: ", substr(stdout_metin, 1, 200),
        " | stderr: ", substr(stderr_metin, 1, 200)
      )
      log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "CLI durum hatası:", gsub("[{}]", "", hata_detay)))
      list(installed = FALSE, version = "", path = cli_path, error = hata_detay)
    }
  }, error = function(e) {
    hata_metni <- conditionMessage(e)
    log_error(paste(CLAUDE_CODE_LOG_PREFIX, "CLI başlatma hatası:",
                    gsub("[{}]", "", hata_metni), "| Yol:", cli_path %||% "NULL"))
    list(
      installed = FALSE,
      version = "",
      path = cli_path,
      error = paste0("Claude Code çalıştırılamadı: ", hata_metni)
    )
  })
}

# ------------------------------------------------------------------------------
# BAĞLANTI TESTİ
# ------------------------------------------------------------------------------

#' API bağlantısını test eder
#'
#' @param cli_path Claude Code CLI yolu (NULL ise otomatik tespit)
#' @param model Test edilecek model (opsiyonel)
#' @param workdir Çalışma dizini
#' @return Liste: success, message, details
test_claude_code_connection <- function(cli_path = NULL,
                                        model = NULL,
                                        workdir = tempdir()) {
  # Öncelikle CLI kontrolü yap
  durum <- check_claude_code_status(cli_path, workdir = workdir)
  if (!durum$installed) {
    return(list(
      success = FALSE,
      message = "Claude Code CLI bulunamadı veya erişilemez.",
      details = durum$error
    ))
  }

  # Basit bir test komutu gönder (kısa ve hızlı)
  test_sonuc <- run_claude_code(
    prompt = "Sadece 'OK' yaz, başka bir şey yazma.",
    workdir = workdir,
    model = model,
    timeout_sec = 60L,
    cli_path = durum$path
  )

  if (test_sonuc$success) {
    list(
      success = TRUE,
      message = paste0("Bağlantı başarılı! Claude Code v", durum$version),
      details = paste0("CLI: ", durum$path, " | Yanıt süresi: ", test_sonuc$duration, " sn")
    )
  } else {
    list(
      success = FALSE,
      message = "Claude Code CLI çalışıyor ancak API bağlantısı başarısız.",
      details = test_sonuc$error
    )
  }
}

# ------------------------------------------------------------------------------
# KULLANICI ÇALIŞMA DİZİNİ YÖNETİMİ
# ------------------------------------------------------------------------------

#' Kullanıcı için izole bir çalışma alanı oluşturur veya mevcut olanı döndürür
#'
#' @param user_id Kullanıcı kimliği
#' @param base_dir Temel dizin (varsayılan: tempdir altında)
#' @return Çalışma dizini yolu
get_user_workspace <- function(user_id, base_dir = NULL) {
  if (is.null(base_dir) || !nzchar(base_dir)) {
    base_dir <- file.path(tempdir(), "claude_code_workspaces")
  }

  user_dir <- file.path(base_dir, paste0("user_", user_id))

  if (!dir.exists(user_dir)) {
    dir.create(user_dir, recursive = TRUE, showWarnings = FALSE)
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Kullanıcı çalışma alanı oluşturuldu:",
                   user_dir))
  }

  return(normalizePath(user_dir, mustWork = FALSE))
}

# Windows cmd.exe için problem çıkarabilecek yol mu?
is_problematic_windows_workdir <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\\\", "/", as.character(path[1]), fixed = TRUE)

  unc_mi <- grepl("^//", aday)
  ascii_disi_var_mi <- grepl("[^ -~]", enc2utf8(aday), perl = TRUE)

  isTRUE(unc_mi || ascii_disi_var_mi)
}

# Dizin içeriğini yerel çalışma alanına aynala
mirror_directory_to_local_workspace <- function(source_dir, target_dir) {
  if (!dir.exists(target_dir)) {
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
  }

  ogeler <- tryCatch(
    list.files(
      source_dir,
      full.names = TRUE,
      recursive = FALSE,
      all.files = FALSE,
      include.dirs = TRUE
    ),
    error = function(e) character(0)
  )

  if (!length(ogeler)) {
    return(invisible(TRUE))
  }

  kopya_ok <- tryCatch(
    file.copy(
      from = ogeler,
      to = target_dir,
      overwrite = TRUE,
      recursive = TRUE,
      copy.mode = TRUE,
      copy.date = TRUE
    ),
    error = function(e) rep(FALSE, length(ogeler))
  )

  if (any(!kopya_ok)) {
    for (i in seq_along(ogeler)) {
      if (isTRUE(kopya_ok[i])) next

      kaynak <- ogeler[i]
      hedef <- file.path(target_dir, basename(kaynak))

      tryCatch({
        if (dir.exists(kaynak)) {
          if (dir.exists(hedef)) unlink(hedef, recursive = TRUE, force = TRUE)
          fs::dir_copy(kaynak, hedef, overwrite = TRUE)
        } else {
          fs::file_copy(kaynak, hedef, overwrite = TRUE)
        }
      }, error = function(e) {
        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Yerel aynalama sırasında öge kopyalanamadı:",
          basename(kaynak),
          "-",
          conditionMessage(e)
        ))
      })
    }
  }

  invisible(TRUE)
}

# Problemli ağ/Unicode dizinlerini yerel ASCII çalışma klasörüne taşır
prepare_claude_runtime_workdir <- function(workdir, user_id = NULL) {
  if (is.null(workdir) || !nzchar(workdir)) {
    return(list(
      runtime_workdir = workdir,
      source_workdir = workdir,
      mirrored = FALSE
    ))
  }

  source_dir <- tryCatch(
    normalize_mcp_path(workdir, must_exist = FALSE),
    error = function(e) as.character(workdir)
  )

  dir_ok <- tryCatch(
    isTRUE(dir.exists(source_dir)) || isTRUE(fs::dir_exists(source_dir)),
    error = function(e) FALSE
  )

  if (!isTRUE(dir_ok)) {
    return(list(
      runtime_workdir = workdir,
      source_workdir = workdir,
      mirrored = FALSE
    ))
  }

  if (!is_problematic_windows_workdir(source_dir)) {
    return(list(
      runtime_workdir = source_dir,
      source_workdir = source_dir,
      mirrored = FALSE
    ))
  }

  local_base <- file.path(
    tempdir(),
    "claude_code_runtime",
    paste0("user_", as.character(user_id %||% "default")),
    "active_dir"
  )

  if (dir.exists(local_base)) {
    unlink(local_base, recursive = TRUE, force = TRUE)
  }

  dir.create(local_base, recursive = TRUE, showWarnings = FALSE)

  mirror_directory_to_local_workspace(source_dir, local_base)

  local_base <- normalizePath(local_base, winslash = "/", mustWork = FALSE)

  log_info(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Problemli çalışma dizini yerel alana aynalandı:",
    source_dir,
    "->",
    local_base
  ))

  list(
    runtime_workdir = local_base,
    source_workdir = source_dir,
    mirrored = TRUE
  )
}

# Yerel çalışma alanındaki değişiklikleri kaynak dizine geri senkronlar
sync_claude_runtime_workdir_back <- function(runtime_workdir, source_workdir) {
  if (is.null(runtime_workdir) || !nzchar(runtime_workdir)) return(invisible(FALSE))
  if (is.null(source_workdir) || !nzchar(source_workdir)) return(invisible(FALSE))
  if (!dir.exists(runtime_workdir)) return(invisible(FALSE))
  if (!dir.exists(source_workdir)) return(invisible(FALSE))

  mirror_directory_to_local_workspace(runtime_workdir, source_workdir)

  log_info(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Yerel çalışma alanı kaynak dizine geri senkronlandı:",
    runtime_workdir,
    "->",
    source_workdir
  ))

  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# DİZİN LİSTELEME
# ------------------------------------------------------------------------------

#' Belirtilen dizindeki dosya ve klasörleri listeler
#'
#' @param path Dizin yolu
#' @param max_items Maksimum öğe sayısı
#' @return Dosya/klasör bilgileri listesi
list_directory_contents <- function(path, max_items = 100L, user_id = NULL) {
  if (is.null(path) || !nzchar(path)) {
    return(list(
      success = FALSE,
      items = list(),
      error = "Dizin yolu boş."
    ))
  }

  # UNC/ağ paylaşımı/kodlama farkları için aynı dizinin olası varyasyonlarını üret
  build_dir_variants <- function(dir_path) {
    dir_chr <- gsub("\\\\", "/", as.character(dir_path %||% ""), fixed = TRUE)
    if (!nzchar(dir_chr)) return(character(0))

    unique(Filter(nzchar, c(
      dir_chr,
      enc2utf8(dir_chr),
      enc2native(dir_chr),
      if (grepl("^/[^/]", dir_chr)) paste0("/", dir_chr) else NULL
    )))
  }

  # Aynı dizini hem base R hem fs ile listelemeyi dene
  list_dir_relaxed <- function(dir_path) {
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

  aday_dizinler <- build_dir_variants(path)

  if (!length(aday_dizinler)) {
    return(list(
      success = FALSE,
      items = list(),
      error = paste0("Dizin bulunamadı: ", path)
    ))
  }

  calisan_dizin <- NULL
  tum_ogeler <- character(0)

  for (aday in aday_dizinler) {
    dizin_var_mi <- tryCatch(path_exists_relaxed(aday), error = function(e) FALSE)

    if (!isTRUE(dizin_var_mi)) {
      dizin_var_mi <- tryCatch(
        isTRUE(dir.exists(aday)) || isTRUE(fs::dir_exists(aday)),
        error = function(e) FALSE
      )
    }

    if (!isTRUE(dizin_var_mi)) next

    bulunan_ogeler <- list_dir_relaxed(aday)

    # En azından çalışan dizini kaydet
    if (is.null(calisan_dizin)) {
      calisan_dizin <- aday
    }

    # İçerik bulduysak bunu tercih et
    if (length(bulunan_ogeler) > 0) {
      calisan_dizin <- aday
      tum_ogeler <- bulunan_ogeler
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

  gorunen_ad_getir <- function(dosya_yolu, klasor_mu) {
    if (isTRUE(klasor_mu)) {
      return(basename(dosya_yolu))
    }

    tryCatch(
      mergen_resolve_display_name(
        dosya_yolu,
        user_id = user_id,
        idx = idx_cache
      ),
      error = function(e) basename(dosya_yolu)
    )
  }

  ogeler <- lapply(gosterilecek_ogeler, function(f) {
    f_norm <- tryCatch(
      normalize_mcp_path(f, must_exist = FALSE),
      error = function(e) as.character(f)
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
      gorunen_ad = gorunen_ad_getir(f_norm, klasor_mu),
      yol = f_norm,
      tip = if (isTRUE(klasor_mu)) "klasor" else "dosya",
      boyut = boyut,
      degistirilme = degistirilme
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

  list(
    success = TRUE,
    items = ogeler,
    error = "",
    toplam = length(tum_ogeler),
    resolved_path = tryCatch(
      normalize_mcp_path(calisan_dizin, must_exist = FALSE),
      error = function(e) calisan_dizin
    )
  )
}

# ------------------------------------------------------------------------------
# ÇIKTI BİÇİMLENDİRME
# ------------------------------------------------------------------------------

#' Claude Code çıktısını HTML formatına dönüştürür
#'
#' @param output Ham çıktı metni
#' @return HTML formatlı metin
format_claude_code_output <- function(output) {
  if (is.null(output) || !nzchar(output)) {
    return("")
  }

  # Markdown'ı HTML'e dönüştür (commonmark paketi ile)
  # NOT: Mojibake düzeltmesi JavaScript tarafında yapılır (fixHtmlMojibake)
  tryCatch({
    html <- commonmark::markdown_html(output, extensions = TRUE)
    return(html)
  }, error = function(e) {
    # Dönüşüm başarısız olursa ham metni döndür
    escaped <- htmltools::htmlEscape(output)
    return(paste0("<pre>", escaped, "</pre>"))
  })
}

# ------------------------------------------------------------------------------
# ARAÇ KULLANIMI HTML BİÇİMLENDİRME
# Araç kullanımlarını (bash, dosya okuma/yazma) okunabilir HTML bloklarına çevirir
# ------------------------------------------------------------------------------

#' Araç kullanımlarını HTML formatına dönüştürür
#'
#' @param tool_uses Araç kullanımları listesi
#' @return HTML formatlı metin
format_tool_uses_html <- function(tool_uses) {
  if (length(tool_uses) == 0) return("")

  html_parcalari <- lapply(tool_uses, function(arac) {
    arac_adi <- arac$name %||% "bilinmeyen"
    girdi <- arac$input %||% list()
    sonuc_metni <- arac$result %||% ""

    # Araç türüne göre ikon ve başlık belirle
    if (grepl("bash|execute|shell", arac_adi, ignore.case = TRUE)) {
      ikon <- "terminal"
      baslik <- "Kabuk Komutu"
      komut <- girdi$command %||% girdi$cmd %||% ""
      icerik <- if (nzchar(komut)) {
        paste0('<code class="cc-tool-command">', htmltools::htmlEscape(komut), '</code>')
      } else ""
    } else if (grepl("read|file_read", arac_adi, ignore.case = TRUE)) {
      ikon <- "file-code"
      baslik <- "Dosya Okuma"
      dosya <- girdi$path %||% girdi$file_path %||% ""
      icerik <- if (nzchar(dosya)) {
        paste0('<span class="cc-tool-path">', htmltools::htmlEscape(dosya), '</span>')
      } else ""
    } else if (grepl("write|file_write|edit", arac_adi, ignore.case = TRUE)) {
      ikon <- "pen"
      baslik <- "Dosya Yazma"
      dosya <- girdi$path %||% girdi$file_path %||% ""
      icerik <- if (nzchar(dosya)) {
        paste0('<span class="cc-tool-path">', htmltools::htmlEscape(dosya), '</span>')
      } else ""
    } else if (grepl("search|grep|glob", arac_adi, ignore.case = TRUE)) {
      ikon <- "search"
      baslik <- "Arama"
      desen <- girdi$pattern %||% girdi$query %||% ""
      icerik <- if (nzchar(desen)) {
        paste0('<span class="cc-tool-path">', htmltools::htmlEscape(desen), '</span>')
      } else ""
    } else {
      ikon <- "cog"
      baslik <- arac_adi
      icerik <- ""
    }

    # Sonuç metnini kısalt (çok uzunsa)
    sonuc_html <- ""
    if (nzchar(sonuc_metni)) {
      sonuc_kisaltilmis <- if (nchar(sonuc_metni) > 500) {
        paste0(substr(sonuc_metni, 1, 500), "...")
      } else {
        sonuc_metni
      }
      sonuc_html <- paste0(
        '<div class="cc-tool-result"><pre>',
        htmltools::htmlEscape(sonuc_kisaltilmis),
        '</pre></div>'
      )
    }

    paste0(
      '<div class="cc-tool-block">',
      '<div class="cc-tool-header">',
      '<i class="fas fa-', ikon, '"></i> ',
      '<span class="cc-tool-title">', htmltools::htmlEscape(baslik), '</span>',
      '</div>',
      if (nzchar(icerik)) paste0('<div class="cc-tool-content">', icerik, '</div>') else "",
      sonuc_html,
      '</div>'
    )
  })

  paste(html_parcalari, collapse = "\n")
}

# ------------------------------------------------------------------------------
# RASTGELE DÜŞÜNME MESAJI SEÇ
# ------------------------------------------------------------------------------

#' Aktif karaktere göre rastgele bir düşünme mesajı döndürür
#'
#' @param karakter_id Aktif karakter kimliği (mergen, ulgen, kayra, erlik, umay)
#' @return Düşünme mesajı metni
get_thinking_message <- function(karakter_id = "mergen") {
  # Karakter mesajlarını al
  karakter_mesajlari <- claude_code_thinking_messages[[karakter_id]]

  # Genel mesajlarla birleştir
  tum_mesajlar <- c(
    claude_code_thinking_messages[["genel"]],
    if (!is.null(karakter_mesajlari)) karakter_mesajlari
  )

  # Rastgele seç
  sample(tum_mesajlar, 1)
}