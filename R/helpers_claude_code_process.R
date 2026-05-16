# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_process.R
# Açıklama: Bilge Yolaç processx/CLI süreç, kodlama ve JSON çıktı yardımcıları.
#           Bu dosya yan etkisiz yardımcıları içerir; Shiny observer başlatmaz.
# ==============================================================================

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

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(metin, repair_mojibake = TRUE))
  }

  metin <- as.character(metin)
  sonuc <- tryCatch(enc2utf8(metin), error = function(e) metin)
  sonuc[is.na(metin)] <- NA_character_
  sonuc
}

# ------------------------------------------------------------------------------
# WINDOWS .CMD UYUMLULUĞU
# Windows'ta .cmd dosyaları cmd.exe üzerinden çalıştırılmalıdır.
# processx bazı sunucu ortamlarında .cmd'yi doğrudan çalıştıramaz.
# ------------------------------------------------------------------------------

# Tek eğik çizgiyle gelen Windows ağ yolu benzeri değer mi?
is_windows_single_slash_network_path <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\\\", "/", as.character(path[1]), fixed = TRUE)

  if (!grepl("^/[^/]", aday) || grepl("^//", aday)) {
    return(FALSE)
  }

  ilk_parca <- tolower(sub("^/([^/]+).*$", "\\1", aday))

  # /tmp/test gibi test/Unix-benzeri yolları UNC sayma.
  unix_benzeri_kokler <- c(
    "tmp", "temp", "var", "home", "usr", "opt", "etc",
    "bin", "sbin", "mnt", "media", "proc", "sys",
    "dev", "run"
  )

  !(ilk_parca %in% unix_benzeri_kokler)
}

# Windows UNC/ağ paylaşımı yolu mu?
is_windows_unc_path <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\\\", "/", as.character(path[1]), fixed = TRUE)

  grepl("^//[^/]+/[^/]+", aday) ||
    is_windows_single_slash_network_path(aday)
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

# cmd.exe /c tek satırında güvenli argüman tırnaklama
quote_windows_cmd_token <- function(x) {
  x <- as.character(x %||% "")[1]
  if (is.na(x)) {
    x <- ""
  }

  # Komut satırı tek satır olmalı; prompt içindeki satır kırılmaları cmd.exe
  # ayrıştırmasını bozmasın.
  x <- gsub("\r\n|\r|\n", " ", x, perl = TRUE)

  # shQuote(type = "cmd") processx + cmd.exe /c kombinasyonunda bazen
  # \"C:\...\claude.cmd\" üretir. cmd.exe bunu çalıştırılabilir yol değil,
  # literal kaçış karakterli metin gibi yorumlayabilir.
  paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
}

# Windows cmd.exe yolunu güvenli şekilde çözer
resolve_windows_cmd_path <- function() {
  adaylar <- unique(Filter(nzchar, c(
    Sys.getenv("ComSpec", ""),
    file.path(Sys.getenv("SystemRoot", "C:/Windows"), "System32", "cmd.exe"),
    Sys.which("cmd.exe"),
    "C:/Windows/System32/cmd.exe",
    "cmd.exe"
  )))

  for (aday in adaylar) {
    aday <- as.character(aday)[1]
    if (is.na(aday) || !nzchar(aday)) next

    if (identical(tolower(aday), "cmd.exe")) {
      return("cmd.exe")
    }

    if (file.exists(aday)) {
      return(normalizePath(aday, winslash = "\\", mustWork = FALSE))
    }
  }

  "cmd.exe"
}

# processx'in sadece süreci başlatmak için kullanacağı güvenli yerel dizin
get_safe_processx_launch_workdir <- function(preferred = NULL) {
  adaylar <- c(
    preferred %||% "",
    Sys.getenv("TEMP", ""),
    Sys.getenv("TMP", ""),
    tempdir(),
    claude_code_config$default_workdir %||% ""
  )

  for (aday in adaylar) {
    if (!nzchar(aday) || !dir.exists(aday)) next

    aday_norm <- tryCatch(
      normalizePath(aday, winslash = "/", mustWork = FALSE),
      error = function(e) aday
    )

    # cmd.exe processx tarafından başlatılırken wd yerel ve basit olmalı.
    # Gerçek çalışma dizinine komut satırı içinde cd /d veya pushd ile geçilecek.
    if (.Platform$OS.type == "windows") {
      aday_slash <- gsub("\\\\", "/", aday_norm, fixed = TRUE)
      if (grepl("^//", aday_slash) || grepl("^/[^/]", aday_slash)) next
      if (grepl("[^ -~]", enc2utf8(aday_norm), perl = TRUE)) next
    }

    return(aday_norm)
  }

  normalizePath(tempdir(), winslash = "/", mustWork = FALSE)
}

# cmd.exe içinde gerçek çalışma dizinine geçip .cmd dosyasını çalıştıracak satırı kurar
build_windows_cmd_invocation_line <- function(cli_path, args, workdir = NULL) {
  cli_cmd <- normalizePath(cli_path, winslash = "\\", mustWork = FALSE)

  quoted_args <- vapply(
    args,
    quote_windows_cmd_token,
    character(1),
    USE.NAMES = FALSE
  )

  quoted_cli <- quote_windows_cmd_token(cli_cmd)

  if (is.null(workdir) || !nzchar(workdir)) {
    return(paste(
      c("call", quoted_cli, quoted_args),
      collapse = " "
    ))
  }

  hedef_dizin <- normalize_cmd_workdir(workdir)
  quoted_workdir <- quote_windows_cmd_token(hedef_dizin)

  if (is_windows_unc_path(workdir)) {
    return(paste(
      c(
        "pushd",
        quoted_workdir,
        "&&",
        "call",
        quoted_cli,
        quoted_args,
        "&",
        "popd"
      ),
      collapse = " "
    ))
  }

  paste(
    c(
      "cd",
      "/d",
      quoted_workdir,
      "&&",
      "call",
      quoted_cli,
      quoted_args
    ),
    collapse = " "
  )
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

    komut_satiri <- build_windows_cmd_invocation_line(
      cli_path = cli_path,
      args = args,
      workdir = workdir
    )

    if (is_windows_unc_path(workdir)) {
      log_info(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "UNC/ağ çalışma dizini cmd.exe içinde pushd ile eşlendi:",
        workdir
      ))
    } else {
      log_info(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Windows .cmd çalıştırması güvenli yerel launch wd ile başlatılıyor. Gerçek çalışma dizini:",
        workdir %||% ""
      ))
    }

	return(list(
	  command = resolve_windows_cmd_path(),
	  args = c("/d", "/c", komut_satiri),
	  env = env,
	  wd = get_safe_processx_launch_workdir(),
	  windows_verbatim_args = TRUE
	))
  }

  list(command = cli_path, args = args, env = NULL, wd = workdir)
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
    satir <- ensure_utf8(satir)
    satir <- trimws(satir)
    if (!nzchar(satir)) next

    tryCatch({
      nesne <- jsonlite::fromJSON(satir, simplifyVector = FALSE)

      if (exists("normalize_text_tree_utf8", mode = "function", inherits = TRUE)) {
        nesne <- normalize_text_tree_utf8(nesne, repair_mojibake = TRUE)
      }

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
	aday_slash <- gsub("\\\\", "/", aday)

	if (
	  .Platform$OS.type == "windows" &&
	  (
		grepl("^\\\\\\\\", aday) ||
		  grepl("^//", aday_slash) ||
		  grepl("^/[^/]", aday_slash)
	  )
	) next
    return(normalizePath(aday, winslash = "/", mustWork = FALSE))
  }

  normalizePath(tempdir(), winslash = "/", mustWork = FALSE)
}