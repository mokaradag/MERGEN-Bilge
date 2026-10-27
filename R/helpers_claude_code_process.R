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
      # iconv ile UTF-8 -> UTF-8 doğrulaması
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
# npm Windows'ta CLI'yi bir .cmd betiğiyle sarar. Bu betik cmd.exe ile
# ÇALIŞTIRILMAZ: gerçek hedefi çözülüp argüman vektörüyle başlatılır.
# ------------------------------------------------------------------------------

# Tek eğik çizgiyle gelen Windows ağ yolu benzeri değer mi?
# NOT: gsub("\\\\", "/", x, fixed=TRUE) yalnızca ardışık çift ters slash'ı
# eşler. Kanonik UNC tespiti için TÜM ters slash'ları forward slash'a çevirip
# `^//server/share` desenini doğru yakalarız.
is_windows_single_slash_network_path <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\", "/", as.character(path[1]), fixed = TRUE)

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
# NOT: gsub("\\\\", "/", x, fixed=TRUE) yalnızca ardışık çift ters slash'ı
# eşler. `\\server\share\sub` girdisini doğru `//server/share/sub`'a
# çevirebilmek için tek ters slash'a göre değiştirme yaparız; bu hem
# `\\server\share`, hem `//server/share`, hem de karışık slash varyantlarını
# kanonik UNC formuna getirir.
is_windows_unc_path <- function(path) {
  if (.Platform$OS.type != "windows") return(FALSE)
  if (is.null(path) || !nzchar(path)) return(FALSE)

  aday <- gsub("\\", "/", as.character(path[1]), fixed = TRUE)

  grepl("^//[^/]+/[^/]+", aday) ||
    is_windows_single_slash_network_path(aday)
}

# Bir adayın processx `wd` değeri olarak Windows'ta güvenli olup olmadığını söyler
#
# UNC/ağ paylaşımı yolları ve ASCII dışı karakterler `cmd.exe` spawn bağlamında
# tutarsız davranır. Bu karar ADAY DÖNGÜSÜ ile FALLBACK dalı arasında PAYLAŞILIR;
# eskiden fallback aynı denetimden geçmiyordu ve döngünün REDDETTİĞİ bir
# `tempdir()` (UNC'ye yönlendirilmiş ya da Türkçe karakter taşıyan geçici klasör)
# yine de döndürülüyordu. Sonraki `processx` çağrısı geçersiz `wd` ile opak bir
# hata veriyordu.
cc_workdir_windows_safe <- function(path) {
  if (.Platform$OS.type != "windows") return(TRUE)

  aday <- as.character(path %||% "")[1]
  if (length(aday) != 1L || is.na(aday) || !nzchar(aday)) return(FALSE)

  aday_slash <- gsub("\\", "/", aday, fixed = TRUE)
  if (grepl("^//", aday_slash) || grepl("^/[^/]", aday_slash)) return(FALSE)
  if (grepl("[^ -~]", enc2utf8(aday), perl = TRUE)) return(FALSE)

  TRUE
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
    if (!isTRUE(cc_workdir_windows_safe(aday_norm))) next

    return(aday_norm)
  }

  # `tempdir()` silinmişse aday döngüsü onu ATLAR ve fallback aynı var olmayan
  # yolu döndürüyordu; `build_processx_command()` bu değeri `wd` olarak verdiği
  # için başlatma açık bir çalışma dizini hatası yerine opak bir `processx`
  # hatasıyla düşüyordu.
  yedek <- tempdir()
  if (!dir.exists(yedek)) {
    try(dir.create(yedek, recursive = TRUE, showWarnings = FALSE), silent = TRUE)
  }
  if (!dir.exists(yedek)) {
    stop(
      "Bilge Yolaç için güvenli bir başlatma dizini oluşturulamadı.",
      call. = FALSE
    )
  }
  if (!isTRUE(cc_workdir_windows_safe(yedek))) {
    stop(
      "Bilge Yolaç için yerel bir başlatma dizini bulunamadı.",
      call. = FALSE
    )
  }

  normalizePath(yedek, winslash = "/", mustWork = FALSE)
}

# npm cmd-shim (.cmd) betiğinin çağırdığı gerçek hedefi çözer. Betik YALNIZCA
# metin olarak okunur, asla çalıştırılmaz. npm kalıbı:
#   "%dp0%\node_modules\@anthropic-ai\claude-code\cli.js" %*
# Hedef JS ise node.exe (önce betiğin yanındaki, cmd-shim ile aynı) ile, yerel
# .exe ise doğrudan başlatılır. Çözülemeyen betik için kabuğa düşülmez.
cc_resolve_windows_cli_shim <- function(shim_path, max_bytes = 65536L) {
  yol <- normalizePath(as.character(shim_path %||% "")[1], winslash = "/", mustWork = FALSE)
  boyut <- suppressWarnings(file.info(yol)$size)
  if (is.na(boyut) || boyut <= 0 || boyut > max_bytes) {
    stop("Bilge Yolaç CLI başlatıcısı okunamadı: ", basename(yol), call. = FALSE)
  }
  baytlar <- readBin(yol, what = "raw", n = boyut)
  metin <- rawToChar(baytlar[baytlar != as.raw(0L)])
  eslesme <- gregexpr(
    "\"%~?dp0%?[\\\\/]([^\"%*<>|\r\n]+\\.(js|cjs|mjs|exe))\"",
    metin, perl = TRUE, ignore.case = TRUE
  )[[1]]
  cozulemedi <- function() {
    stop(
      "Bilge Yolaç CLI başlatıcısı (.cmd) çözümlenemedi; CLAUDE_CODE_CLI_PATH ",
      "ayarını cli.js veya claude.exe yoluna yönlendirin.",
      call. = FALSE
    )
  }
  if (eslesme[1] < 0L) cozulemedi()
  baslar <- as.integer(eslesme)
  bitisler <- baslar + attr(eslesme, "match.length") - 1L
  hedefler <- substring(metin, baslar, bitisler)
  # cmd-shim önce "%dp0%\\node.exe" varlığını sınar; çağrılan hedef son eşleşmedir.
  secilen <- which(!grepl("[\\\\/]node\\.exe\"$", hedefler, ignore.case = TRUE))
  if (!length(secilen)) {
    stop("Bilge Yolaç CLI başlatıcısının hedefi bulunamadı.", call. = FALSE)
  }
  secilen <- secilen[length(secilen)]
  # Hedefin satırında yorumlayıcıdan sonra ya da hedeften sonra sabit argüman
  # (ör. node --require ./init.js) varsa düşürülmez: başlatıcı reddedilir.
  satir_basi <- max(c(0L, gregexpr("\n", substr(metin, 1L, baslar[secilen] - 1L), fixed = TRUE)[[1]]))
  once <- trimws(substr(metin, satir_basi + 1L, baslar[secilen] - 1L))
  sonra <- trimws(sub("[\r\n].*$", "", substr(metin, bitisler[secilen] + 1L, nchar(metin))))
  exe_hedef <- grepl("\\.exe\"$", hedefler[secilen], ignore.case = TRUE)
  once_gecerli <- if (exe_hedef) {
    grepl("(^|[&(@])$", once, perl = TRUE)
  } else {
    grepl("(\"%_prog%\"|node\\.exe\"|(^|[\\s&(@])node)$", once, perl = TRUE, ignore.case = TRUE)
  }
  if (!once_gecerli || !identical(sonra, "%*")) cozulemedi()
  goreceli <- sub("^\"%~?dp0%?[\\\\/]", "", sub("\"$", "", hedefler[secilen]), perl = TRUE)
  hedef <- normalizePath(file.path(dirname(yol), gsub("\\", "/", goreceli, fixed = TRUE)),
                         winslash = "/", mustWork = FALSE)
  if (!file.exists(hedef) || dir.exists(hedef)) {
    stop("Bilge Yolaç CLI hedefi bulunamadı: ", basename(hedef), call. = FALSE)
  }

  if (grepl("\\.exe$", hedef, ignore.case = TRUE)) {
    return(list(command = hedef, prefix_args = character(0)))
  }

  yerel_node <- file.path(dirname(yol), "node.exe")
  node <- if (file.exists(yerel_node)) {
    normalizePath(yerel_node, winslash = "/", mustWork = FALSE)
  } else {
    resolve_node_path()
  }
  if (is.null(node)) {
    stop("Bilge Yolaç için node.exe bulunamadı (CLAUDE_CODE_NODE_PATH).", call. = FALSE)
  }
  list(command = node, prefix_args = hedef)
}

# Tek eğik çizgili ağ yolu (/sunucu/pay) süreç çalışma dizini için UNC'ye çevrilir.
cc_windows_launch_wd <- function(workdir) {
  if (is.null(workdir) || !nzchar(workdir)) return(workdir)
  if (isTRUE(is_windows_single_slash_network_path(workdir))) {
    return(paste0("/", gsub("\\", "/", workdir, fixed = TRUE)))
  }
  workdir
}

#' processx için komut ve argümanları hazırlar
#'
#' Çağıranın verdiği argümanlar (istem metni dâhil) HER ZAMAN ayrık bir argüman
#' vektörü olarak süreç başlatıcıya gider; cmd.exe/kabuk komut satırına metin
#' olarak gömülmez. Windows'ta .cmd/.bat npm betikleri cmd.exe yerine gerçek
#' hedeflerine (node.exe + cli.js ya da claude.exe) çözülür; aksi hâlde istem
#' içindeki %DEĞİŞKEN%, &, |, ^ gibi diziler kabukta yorumlanıp çocuk sürecin
#' (API anahtarı taşıyan) ortamından genişleyebilirdi.
#'
#' @param cli_path CLI çalıştırılabilir dosya yolu
#' @param args CLI argümanları
#' @param workdir Çalışma dizini
#' @return Liste: command, args, env, wd
build_processx_command <- function(cli_path, args, workdir = NULL) {
  if (grepl("\\.(c|m)?js$", cli_path, ignore.case = TRUE)) {
    node <- resolve_node_path()
    if (is.null(node)) {
      stop("Bilge Yolaç için node bulunamadı (CLAUDE_CODE_NODE_PATH).", call. = FALSE)
    }
    return(list(
      command = node,
      args = c(normalizePath(cli_path, winslash = "/", mustWork = FALSE), args),
      env = NULL,
      wd = if (.Platform$OS.type == "windows") cc_windows_launch_wd(workdir) else workdir
    ))
  }

  if (.Platform$OS.type == "windows" && grepl("\\.(cmd|bat)$", cli_path, ignore.case = TRUE)) {
    hedef <- cc_resolve_windows_cli_shim(cli_path)

    npm_dizini <- normalizePath(dirname(cli_path), winslash = "\\", mustWork = FALSE)
    node_yolu <- resolve_node_path()
    node_dizini <- if (!is.null(node_yolu)) {
      normalizePath(dirname(node_yolu), winslash = "\\", mustWork = FALSE)
    } else {
      ""
    }

    # Mevcut ortam değişkenlerini al ve PATH/Path anahtarını yerinde güncelle
    # (CLI'nin kendi alt süreçleri node/npm araçlarını bulabilsin).
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

    log_info(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Windows CLI betiği kabuksuz başlatılıyor:",
      basename(hedef$command),
      "Çalışma dizini:",
      workdir %||% ""
    ))

    return(list(
      command = hedef$command,
      args = c(hedef$prefix_args, args),
      env = env,
      wd = cc_windows_launch_wd(workdir),
      windows_verbatim_args = FALSE
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
#' @param prefer_result_text Ham çıktı KIRPILMIŞ bir tampondan geliyorsa TRUE.
#'   Delta tabanlı metin eksik olduğu için son `result` kaydındaki TAM metin
#'   biriken deltaların YERİNE geçer. Tam akışta (varsayılan FALSE) davranış
#'   değişmez: `result` metni ikinci kez eklenmez.
#' @return Liste: text_output (metin çıktısı), tool_uses (araç kullanımları listesi)
parse_claude_code_json_output <- function(ham_cikti, prefer_result_text = FALSE) {
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
          if (nzchar(sonuc_metin)) {
            if (isTRUE(prefer_result_text)) {
              # KIRPILMIŞ tamponda delta metni EKSİKTİR; tam `result` metni
              # birikeni DEĞİŞTİRİR (eklenmez, yoksa metin çift görünürdü).
              metin_parcalari <- sonuc_metin
              metin_zaten_toplandi <- TRUE
            } else if (!isTRUE(metin_zaten_toplandi)) {
              metin_parcalari <- c(metin_parcalari, sonuc_metin)
              metin_zaten_toplandi <- TRUE
            }
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
        if (nzchar(sonuc_metin)) {
          if (isTRUE(prefer_result_text)) {
            metin_parcalari <- sonuc_metin
            metin_zaten_toplandi <- TRUE
          } else if (!isTRUE(metin_zaten_toplandi)) {
            metin_parcalari <- c(metin_parcalari, sonuc_metin)
            metin_zaten_toplandi <- TRUE
          }
        }
        if (!is.null(nesne$session_id) && nzchar(nesne$session_id %||% "")) {
          sonuc$session_id <- nesne$session_id
        }

      } else if (tur == "assistant") {
        # Claude Code CLI stream-json çıktısında asistan içerik blokları
        # genelde nesne$message$content altında gelir
        # ({"type":"assistant","message":{"content":[...]}}). Eski kod yalnızca
        # nesne$content yolundan okuduğu için tool_use blokları gözden
        # kaçıyor ve ARAÇ KULLANIMLARI sayacı (0) görünüyordu. Her iki yolu
        # da destekleyerek tool_use bloklarını doğru topla.
        icerik_bloklari <- nesne$message$content
        if (is.null(icerik_bloklari)) {
          icerik_bloklari <- nesne$content
        }

        # Bazı on-prem proxy varyantları içerik bloklarını tek nesne olarak
        # ({"type":"tool_use",...}) gönderebiliyor; standart Anthropic formatı
        # ise her zaman dizidir. Tek nesne ise listeye sar ki standart iterasyon
        # çalışsın.
        if (!is.null(icerik_bloklari) &&
            is.list(icerik_bloklari) &&
            !is.null(icerik_bloklari$type)) {
          icerik_bloklari <- list(icerik_bloklari)
        }

        if (!is.null(icerik_bloklari) && is.list(icerik_bloklari)) {
          for (blok in icerik_bloklari) {
            if (!is.list(blok)) next
            blok_tur <- blok$type %||% ""
            if (blok_tur == "text") {
              # --include-partial-messages açıkken aynı metin önce
              # content_block_delta text_delta olarak stream_event akışında
              # geldi; sonra asistan toplu bloku tekrar geliyor. Sayaç olarak
              # metin_zaten_toplandi = TRUE ise asistan bloktaki metni
              # tekrar eklemeyiz, aksi halde son metin iki kere yazılır.
              if (isTRUE(metin_zaten_toplandi)) next

              blok_metin <- blok$text %||% ""
              if (nzchar(blok_metin)) {
                metin_parcalari <- c(metin_parcalari, blok_metin)
                metin_zaten_toplandi <- TRUE
              }
            } else if (blok_tur == "tool_use") {
              arac_id <- blok$id %||% ""
              zaten_var <- FALSE
              if (nzchar(arac_id)) {
                for (j in seq_along(sonuc$tool_uses)) {
                  if (identical(sonuc$tool_uses[[j]]$id, arac_id)) {
                    zaten_var <- TRUE
                    break
                  }
                }
              }

              # stream_event yolu aynı tool_use'u zaten eklediyse tekrar ekleme.
              if (!isTRUE(zaten_var)) {
                arac <- list(
                  id = arac_id,
                  name = blok$name %||% "",
                  input = blok$input %||% list()
                )
                sonuc$tool_uses <- c(sonuc$tool_uses, list(arac))
              }
            }
          }
        }

        # session_id asistan mesajının sarmalayıcısında da gelebilir
        if (!is.null(nesne$session_id) && nzchar(nesne$session_id %||% "")) {
          sonuc$session_id <- nesne$session_id
        }

      } else if (tur == "user") {
        # Tool result'lar Claude Code CLI'da user blokları içinde gelir
        # ({"type":"user","message":{"content":[{"type":"tool_result",...}]}}).
        # Bu olayları yakalayıp ilgili tool_use'a result alanını ekleyelim.
        icerik_bloklari <- nesne$message$content
        if (is.null(icerik_bloklari)) {
          icerik_bloklari <- nesne$content
        }

        # Tek nesne formunu da destekle (bazı proxy varyantları için)
        if (!is.null(icerik_bloklari) &&
            is.list(icerik_bloklari) &&
            !is.null(icerik_bloklari$type)) {
          icerik_bloklari <- list(icerik_bloklari)
        }

        if (!is.null(icerik_bloklari) && is.list(icerik_bloklari)) {
          for (blok in icerik_bloklari) {
            if (!is.list(blok)) next
            blok_tur <- blok$type %||% ""
            if (blok_tur != "tool_result") next

            arac_id <- blok$tool_use_id %||% ""
            tr_icerik <- blok$content %||% ""

            if (is.list(tr_icerik)) {
              parca_listesi <- character(0)
              for (parca in tr_icerik) {
                if (is.list(parca)) {
                  parca_listesi <- c(parca_listesi, as.character(parca$text %||% ""))
                }
              }
              tr_icerik <- paste(parca_listesi, collapse = "")
            }

            for (j in seq_along(sonuc$tool_uses)) {
              if (identical(sonuc$tool_uses[[j]]$id, arac_id)) {
                sonuc$tool_uses[[j]]$result <- tr_icerik
                break
              }
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
    # CLI durum kontrolü için güvenli YEREL dizin gerekir; UNC/ağ paylaşımı ve
    # ASCII dışı yollar paylaşılan yardımcı ile reddedilir.
    if (!isTRUE(cc_workdir_windows_safe(aday))) next
    return(normalizePath(aday, winslash = "/", mustWork = FALSE))
  }

  # `tempdir()` silinmişse aday döngüsü onu ATLAR ve fallback aynı var olmayan
  # yolu döndürüyordu; sonraki `processx` çağrısı geçersiz `wd` ile başlamıyordu.
  yedek <- tempdir()
  if (!dir.exists(yedek)) {
    try(dir.create(yedek, recursive = TRUE, showWarnings = FALSE), silent = TRUE)
  }
  if (!dir.exists(yedek)) {
    stop(
      "Bilge Yolaç için güvenli bir çalışma dizini oluşturulamadı.",
      call. = FALSE
    )
  }
  # Fallback aday döngüsüyle AYNI Windows denetiminden geçer; aksi hâlde
  # döngünün reddettiği bir UNC/ASCII dışı `tempdir()` yine döndürülüyordu.
  if (!isTRUE(cc_workdir_windows_safe(yedek))) {
    stop(
      "Bilge Yolaç için yerel bir çalışma dizini bulunamadı.",
      call. = FALSE
    )
  }

  normalizePath(yedek, winslash = "/", mustWork = FALSE)
}
