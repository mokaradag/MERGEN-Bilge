# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_downloads.R
# Açıklama: Bilge Yolaç tarafından üretilen dosyaları yerel Shiny bağlantıları ile
#           indirilebilir hale getirir. İnternet gerektirmez; dosyalar uygulama
#           altındaki bilge_yolac_downloads/ klasörüne kopyalanır.
# ==============================================================================

#' Görünürlük bekleme bütçesi için tek bir toplama penceresi aç
#'
#' Bir toplama (collect/staging) işlemi boyunca TOPLAM bekleme süresi
#' `file_settle_total_ms` ile sınırlıdır; her aday yol için ayrı bütçe
#' harcanmaz. Pencere kapandığında önceki durum geri yüklenir.
#'
#' @param budget_ms Toplam bütçe (ms); NULL ise yapılandırılmış değer
#' @return invisible(NULL)
.cc_path_visibility_budget <- new.env(parent = emptyenv())
.cc_path_visibility_budget$deadline <- NULL

cc_with_path_visibility_budget <- function(expr, budget_ms = NULL) {
  budget_ms <- suppressWarnings(as.numeric(budget_ms)[1])

  if (length(budget_ms) != 1L || !is.finite(budget_ms) || budget_ms < 0) {
    budget_ms <- suppressWarnings(as.numeric(
      tryCatch(cc_runtime_limit("file_settle_total_ms", 1200), error = function(e) 1200)
    )[1])
  }

  if (length(budget_ms) != 1L || !is.finite(budget_ms) || budget_ms < 0) {
    budget_ms <- 1200
  }

  onceki <- .cc_path_visibility_budget$deadline
  .cc_path_visibility_budget$deadline <- Sys.time() + (budget_ms / 1000)
  on.exit(.cc_path_visibility_budget$deadline <- onceki, add = TRUE)

  force(expr)
}

#' Etkin toplama bütçesinden kalan süreyi (ms) döndür
#'
#' @return Kalan ms veya pencere yoksa NULL
cc_path_visibility_budget_remaining <- function() {
  son <- .cc_path_visibility_budget$deadline
  if (is.null(son)) return(NULL)

  kalan <- as.numeric(difftime(son, Sys.time(), units = "secs")) * 1000
  if (!is.finite(kalan) || kalan < 0) return(0)
  kalan
}

#' Bir dosyanın görünür hale gelmesini sınırlı süre bekler
#'
#' Windows/UNC paylaşımlarında yeni yazılan dosya kısa süre `file.exists()`
#' için görünmeyebilir. Bekleme bütçesi yapılandırılabilir ve bu yardımcı
#' YALNIZCA arka plan worker'ında çağrılmalıdır; ana Shiny sürecinde
#' çağrılırsa tüm oturumlar bloke olur.
#'
#' @param path Beklenecek dosya yolu
#' @param budget_ms Toplam bekleme bütçesi (ms)
#' @return Dosya görünür olduysa TRUE
cc_wait_for_path_visible <- function(path, budget_ms = NULL) {
  yol <- as.character(path %||% "")[1]
  if (!nzchar(yol)) return(FALSE)

  # Görünürlük bütçesi TOPLAM bir bütçedir. Aynı toplama işleminde onlarca
  # aday yol denendiğinde her biri için ayrı ayrı tam bütçe harcanırsa
  # paylaşılan worker havuzu dakikalarca meşgul kalır. Etkin bir toplama
  # bütçesi varsa yalnızca KALAN süre kullanılır.
  if (is.null(budget_ms)) {
    kalan <- cc_path_visibility_budget_remaining()
    if (!is.null(kalan)) budget_ms <- kalan
  }

  budget_ms <- suppressWarnings(as.numeric(budget_ms)[1])

  if (length(budget_ms) != 1L || !is.finite(budget_ms)) {
    budget_ms <- suppressWarnings(as.numeric(
      tryCatch(cc_runtime_limit("file_settle_total_ms", 1200), error = function(e) 1200)
    )[1])
  }

  if (length(budget_ms) != 1L || !is.finite(budget_ms) || budget_ms < 0) {
    budget_ms <- 1200
  }

  son <- Sys.time() + (budget_ms / 1000)

  while (!isTRUE(file.exists(yol)) && Sys.time() < son) {
    Sys.sleep(0.05)
  }

  isTRUE(file.exists(yol))
}

#' Bilge Yolaç indirme kök klasörünü döndürür
#'
#' @return İndirme kök klasörü
get_claude_code_download_root <- function() {
  kok <- getOption("mergen.claude_code_download_root", "")

  if (!nzchar(kok)) {
    kok <- file.path(getwd(), "bilge_yolac_downloads")
    options(mergen.claude_code_download_root = kok)
  }

  if (!dir.exists(kok)) {
    dir.create(kok, recursive = TRUE, showWarnings = FALSE)
  }

  normalizePath(kok, winslash = "/", mustWork = FALSE)
}

#' URL/dizin segmentini güvenli hale getirir
#'
#' @param x Ham metin
#' @param fallback Boş kalırsa kullanılacak yedek değer
#' @return Güvenli segment
sanitize_claude_code_download_segment <- function(x, fallback = "oge") {
  x <- as.character(x %||% "")[1]
  x <- enc2utf8(x)
  x <- gsub("[^A-Za-z0-9._-]+", "_", x, perl = TRUE)
  x <- gsub("_+", "_", x, perl = TRUE)
  x <- sub("^_+", "", x, perl = TRUE)
  x <- sub("_+$", "", x, perl = TRUE)

  if (!nzchar(x)) {
    x <- fallback
  }

  x
}

#' Dosya boyutunu okunabilir metne çevirir
#'
#' @param bytes Bayt cinsinden boyut
#' @return Okunabilir boyut etiketi
format_claude_code_download_size <- function(bytes) {
  bytes <- suppressWarnings(as.numeric(bytes)[1])

  if (is.na(bytes)) return("Boyut bilinmiyor")
  if (bytes < 1024) return(paste0(bytes, " B"))
  if (bytes < 1024^2) return(paste0(round(bytes / 1024, 1), " KB"))
  if (bytes < 1024^3) return(paste0(round(bytes / 1024^2, 1), " MB"))

  paste0(round(bytes / 1024^3, 2), " GB")
}

#' Claude Code'un yazdığı hedef yolu gerçek dosyaya çözümler
#'
#' @param path_value Araç girdisinden gelen yol
#' @param runtime_workdir Claude Code'un gerçekten çalıştığı dizin
#' @param source_workdir Kullanıcının seçtiği/asıl kaynak dizin
#' @return Var olan dosya yolu veya boş metin
resolve_claude_code_generated_path <- function(path_value,
                                               runtime_workdir = "",
                                               source_workdir = "",
                                               allowed_roots = character(0)) {
  yol <- as.character(path_value %||% "")[1]
  if (!nzchar(yol)) return("")

  mutlak_mi <- grepl("^(?:[A-Za-z]:|/|\\\\\\\\)", yol)

  adaylar <- unique(Filter(nzchar, c(
    yol,
    if (!isTRUE(mutlak_mi) && nzchar(runtime_workdir)) file.path(runtime_workdir, yol) else NULL,
    if (!isTRUE(mutlak_mi) && nzchar(source_workdir)) file.path(source_workdir, yol) else NULL
  )))

  for (aday in adaylar) {
    aday_norm <- tryCatch(
      normalize_mcp_path(aday, must_exist = FALSE),
      error = function(e) normalizePath(aday, winslash = "/", mustWork = FALSE)
    )

    # Windows/UNC/ağ klasörlerinde yeni yazılan dosya bazen birkaç yüz ms
    # sonra bu süreç tarafından görünür hale geliyor. Ham yol fallback'ine
    # düşmeden önce sınırlı bütçeyle bekle (arka plan worker'ında çalışır).
    cc_wait_for_path_visible(aday_norm)

    if (isTRUE(file.exists(aday_norm)) && !isTRUE(dir.exists(aday_norm))) {
      if (length(allowed_roots) &&
          !cc_policy_path_inside_roots(aday_norm, allowed_roots, must_exist = FALSE)) {
        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Üretilen dosya izin verilen köklerin dışında bırakıldı:",
          gsub("[{}]", "", aday_norm)
        ))
        next
      }

      return(aday_norm)
    }
  }

  ""
}

#' Araç kullanımlarından üretilen dosya yollarını toplar
#'
#' @param tool_uses Claude Code araç kullanımları
#' @param runtime_workdir Claude Code runtime dizini
#' @param source_workdir Kullanıcının seçtiği/asıl kaynak dizin
#' @return Dosya yolları
list_claude_code_generated_file_paths <- function(tool_uses,
                                                  runtime_workdir = "",
                                                  source_workdir = "",
                                                  allowed_roots = character(0),
                                                  user_id = 0L) {
  if (!length(tool_uses)) return(character(0))

  if (!length(allowed_roots)) {
    allowed_roots <- cc_policy_allowed_output_roots(
      user_id = user_id,
      workdir = runtime_workdir %||% source_workdir
    )
  }

  dosyalar <- character(0)

  for (arac in tool_uses) {
    arac_adi <- tolower(as.character(arac$name %||% "")[1])
    if (!nzchar(arac_adi)) next

    # Yalnızca dosya üretme/değiştirme araçlarını hedefle
    if (!grepl("write|edit|file_write", arac_adi, ignore.case = TRUE)) {
      next
    }

    girdi <- arac$input %||% list()
    hedef_yol <- girdi$path %||% girdi$file_path %||% ""

    cozulen_yol <- resolve_claude_code_generated_path(
      path_value = hedef_yol,
      runtime_workdir = runtime_workdir,
      source_workdir = source_workdir,
      allowed_roots = allowed_roots
    )

    if (nzchar(cozulen_yol)) {
      dosyalar <- c(dosyalar, cozulen_yol)
    }
  }

  unique(dosyalar[nzchar(dosyalar)])
}

#' Dosyaları indirilebilir klasöre kopyalar
#'
#' @param file_paths Kaynak dosya yolları
#' @param user_id Kullanıcı kimliği
#' @param session_token Shiny oturum anahtarı
#' @return İndirme kayıtları listesi
stage_claude_code_downloads <- function(file_paths,
                                        user_id = 0L,
                                        session_token = "",
                                        allowed_roots = character(0)) {
  file_paths <- unique(Filter(nzchar, as.character(file_paths %||% character(0))))

  if (!length(file_paths)) return(list())

  if (!length(allowed_roots)) {
    allowed_roots <- cc_policy_allowed_output_roots(user_id = user_id)
  }

  file_paths <- cc_policy_filter_generated_file_paths(
    file_paths,
    allowed_roots = allowed_roots,
    context = "indirilecek dosya"
  )

  if (!length(file_paths)) return(list())

  kok <- get_claude_code_download_root()

  kullanici_etiketi <- sanitize_claude_code_download_segment(
    paste0("user_", as.character(user_id %||% 0L)),
    fallback = "user_0"
  )

  oturum_etiketi <- sanitize_claude_code_download_segment(
    paste0("session_", as.character(session_token %||% "anonim")),
    fallback = "session_anonim"
  )

  hedef_dizin <- file.path(kok, kullanici_etiketi, oturum_etiketi)
  if (!dir.exists(hedef_dizin)) {
    dir.create(hedef_dizin, recursive = TRUE, showWarnings = FALSE)
  }

  sonuc <- list()

  for (i in seq_along(file_paths)) {
    kaynak <- file_paths[i]

    # Dosya yazma işlemi bitmiş görünse bile özellikle Windows/UNC üzerinde
    # file.exists() kısa süre FALSE dönebilir. İndirme kartını kaçırmamak için
    # sınırlı bütçeyle bekle.
    cc_wait_for_path_visible(kaynak)

    if (!isTRUE(file.exists(kaynak)) || isTRUE(dir.exists(kaynak))) next

    # Bekleme sırasında modelin gecikmiş alt süreci dosyayı symlink/junction
    # ile değiştirmiş olabilir. Web-served staging kopyasından hemen önce yolu
    # yeniden çöz ve izinli kök/link politikasını tekrar uygula.
    yeniden_onayli <- cc_policy_filter_generated_file_paths(
      kaynak,
      allowed_roots = allowed_roots,
      context = "indirilecek dosya"
    )
    kaynak_key <- cc_policy_normalize_path(kaynak, must_exist = TRUE)
    kaynak_ata <- cc_policy_normalize_path(dirname(kaynak), must_exist = TRUE)
    beklenen_kaynak <- cc_policy_normalize_path(
      file.path(kaynak_ata, basename(kaynak)), must_exist = FALSE
    )
    baglanti <- !identical(kaynak_key, beklenen_kaynak) || isTRUE(tryCatch({
      hedef <- Sys.readlink(kaynak)
      !is.na(hedef) && nzchar(hedef)
    }, error = function(e) FALSE))
    if (length(yeniden_onayli) != 1L || !identical(yeniden_onayli[1], kaynak_key) ||
        isTRUE(baglanti)) next

    orijinal_ad <- basename(kaynak)

    guvenli_ad <- sanitize_claude_code_download_segment(
      orijinal_ad,
      fallback = paste0("dosya_", i)
    )

    hedef_ad <- paste0(
      format(Sys.time(), "%Y%m%d-%H%M%S"),
      "_",
      sprintf("%02d", i),
      "_",
      guvenli_ad
    )

    hedef_yol <- file.path(hedef_dizin, hedef_ad)

    kopyalandi <- tryCatch(
      file.copy(
        from = kaynak,
        to = hedef_yol,
        overwrite = TRUE,
        copy.mode = TRUE,
        copy.date = TRUE
      ),
      error = function(e) FALSE
    )

    if (!isTRUE(kopyalandi)) next

    # URL/HTML kartı üretmeden önce staged hedef dosyanın gerçekten görünür
    # olduğundan emin ol. Böylece href, dosya hazır olmadan ekrana basılmaz.
    cc_wait_for_path_visible(hedef_yol)

    if (!isTRUE(file.exists(hedef_yol)) || isTRUE(dir.exists(hedef_yol))) next

    boyut <- suppressWarnings(as.numeric(file.info(hedef_yol)$size[1]))

    url <- paste(
      "bilge_yolac_downloads",
      utils::URLencode(kullanici_etiketi, reserved = TRUE),
      utils::URLencode(oturum_etiketi, reserved = TRUE),
      utils::URLencode(hedef_ad, reserved = TRUE),
      sep = "/"
    )

    sonuc[[length(sonuc) + 1]] <- list(
      original_path = tryCatch(
        normalize_mcp_path(kaynak, must_exist = FALSE),
        error = function(e) normalizePath(kaynak, winslash = "/", mustWork = FALSE)
      ),
      download_path = tryCatch(
        normalizePath(hedef_yol, winslash = "/", mustWork = FALSE),
        error = function(e) hedef_yol
      ),
      display_name = orijinal_ad,
      download_name = orijinal_ad,
      url = url,
      size = boyut,
      size_label = format_claude_code_download_size(boyut)
    )
  }

  sonuc
}

#' Araç kullanımından indirilebilir dosya listesi üretir
#'
#' @param tool_uses Claude Code araç kullanımları
#' @param runtime_workdir Claude Code runtime dizini
#' @param source_workdir Kullanıcının seçtiği/asıl kaynak dizin
#' @param user_id Kullanıcı kimliği
#' @param session_token Shiny oturum anahtarı
#' @return İndirme kayıtları listesi
collect_claude_code_generated_downloads <- function(tool_uses,
                                                    runtime_workdir = "",
                                                    source_workdir = "",
                                                    user_id = 0L,
                                                    session_token = "") {
  allowed_roots <- cc_policy_allowed_output_roots(
    user_id = user_id,
    workdir = runtime_workdir %||% source_workdir
  )

  dosya_yollari <- list_claude_code_generated_file_paths(
    tool_uses = tool_uses,
    runtime_workdir = runtime_workdir,
    source_workdir = source_workdir,
    allowed_roots = allowed_roots,
    user_id = user_id
  )

  if (!length(dosya_yollari)) return(list())

  indirmeler <- stage_claude_code_downloads(
    file_paths = dosya_yollari,
    user_id = user_id,
    session_token = session_token,
    allowed_roots = allowed_roots
  )

  if (!length(indirmeler)) return(list())

  for (i in seq_along(indirmeler)) {
    indirmeler[[i]]$display_path <- build_claude_code_display_path(
      file_path = indirmeler[[i]]$original_path,
      runtime_workdir = runtime_workdir,
      source_workdir = source_workdir
    )
  }

  indirmeler
}

#' Araç çağrılarındaki yazma yollarını yedek olarak indirilebilir kayıtlara çevir
#'
#' Snapshot/diff yolu sessiz kaldığında (örn. Windows kısa ad eşleşmesi, UNC
#' normalizasyon farkı veya zamanlama) araç çağrılarındaki Write/Edit/MultiEdit
#' mutlak yollarını doğrudan tarayıp diskte gerçekten bulunanları indirilebilir
#' kayıtlara dönüştürür. Politika kontrolü için kaynak çalışma dizinini de
#' izinli köklere ekler; böylece aynalanmış UNC akışlarında dosya runtime
#' aynasında veya kaynak dizinde olduğunda da kart oluşturulabilir.
#'
#' @param tool_uses Claude Code araç kullanımları
#' @param runtime_workdir Claude Code runtime dizini
#' @param source_workdir Kullanıcının seçtiği/asıl kaynak dizin
#' @param user_id Kullanıcı kimliği
#' @param session_token Shiny oturum anahtarı
#' @return İndirme kayıtları listesi
cc_stage_tool_use_write_paths_as_downloads <- function(tool_uses,
                                                       runtime_workdir = "",
                                                       source_workdir = "",
                                                       user_id = 0L,
                                                       session_token = "",
                                                       layout = NULL,
                                                       limits = NULL) {
  if (!length(tool_uses)) return(list())

  allowed_roots <- cc_policy_allowed_output_roots(
    user_id = user_id,
    workdir = runtime_workdir %||% source_workdir
  )

  # Aynalamada runtime ve kaynak farklı olabilir; ikisi de izinli kabul edilir.
  if (nzchar(source_workdir %||% "")) {
    source_root <- cc_policy_normalize_path(source_workdir, must_exist = FALSE)
    if (nzchar(source_root)) {
      allowed_roots <- unique(c(allowed_roots, source_root))
    }
  }

  yollar <- character(0)

  for (arac in tool_uses) {
    arac_adi <- tolower(as.character(arac$name %||% "")[1])
    if (!nzchar(arac_adi)) next
    if (!grepl("write|edit|file_write", arac_adi, perl = TRUE)) next

    girdi <- arac$input %||% list()
    raw_yol <- as.character(girdi$path %||% girdi$file_path %||% "")[1]
    if (!nzchar(raw_yol)) next

    aday <- normalizePath(raw_yol, winslash = "/", mustWork = FALSE)

    # Yedek yolda da aynı zamanlama farkını tolere et.
    cc_wait_for_path_visible(aday)

    if (isTRUE(file.exists(aday)) && !isTRUE(dir.exists(aday))) {
      yollar <- c(yollar, aday)
    }
  }

  yollar <- unique(yollar[nzchar(yollar)])
  if (!length(yollar)) return(list())

  yollar <- cc_policy_filter_generated_file_paths(
    yollar,
    allowed_roots = allowed_roots,
    context = "araç çağrısından üretilen dosya"
  )

  # Yedek yol da aynı bölge/boyut sözleşmesine uyar.
  if (exists("cc_filter_download_candidates", mode = "function", inherits = TRUE)) {
    suzme <- tryCatch(
      cc_filter_download_candidates(yollar, layout = layout, limits = limits),
      error = function(e) NULL
    )
    if (is.list(suzme)) yollar <- suzme$paths
  }

  if (!length(yollar)) return(list())

  indirmeler <- tryCatch(
    stage_claude_code_downloads(
      file_paths = yollar,
      user_id = user_id,
      session_token = session_token,
      allowed_roots = allowed_roots
    ),
    error = function(e) list()
  )

  if (!length(indirmeler)) return(list())

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

#' Akış çalıştırması için indirilebilir dosya kayıtlarını birincil + yedek topla
#'
#' Önce snapshot/diff + araç çağrısı tabanlı birincil yolu dener
#' (collect_claude_code_workdir_changes_downloads). Sonuç boşsa araç çağrılarındaki
#' mutlak Write/Edit/MultiEdit yollarını fiziksel olarak diskte ararak yedek
#' kayıtlar üretir. Böylece kart yalnızca primary yol başarılı olduğunda değil,
#' Claude'un yazdığı dosya disk üzerinde varsa da kullanıcıya gösterilir.
#'
#' @param before_snapshot Çalıştırma öncesi snapshot
#' @param tool_uses Claude Code araç kullanımları
#' @param runtime_workdir Claude Code runtime dizini
#' @param source_workdir Kullanıcının seçtiği kaynak dizin
#' @param user_id Kullanıcı kimliği
#' @param session_token Shiny oturum anahtarı
#' @return İndirme kayıtları listesi
cc_collect_streaming_run_downloads <- function(before_snapshot,
                                               tool_uses = list(),
                                               runtime_workdir = "",
                                               source_workdir = "",
                                               user_id = 0L,
                                               session_token = "",
                                               changed_files = NULL,
                                               exclude_dirs = NULL,
                                               limits = NULL,
                                               layout = NULL) {
  birincil <- tryCatch(
    collect_claude_code_workdir_changes_downloads(
      before_snapshot = before_snapshot,
      tool_uses = tool_uses,
      runtime_workdir = runtime_workdir,
      source_workdir = source_workdir,
      user_id = user_id,
      session_token = session_token,
      changed_files = changed_files,
      exclude_dirs = exclude_dirs,
      limits = limits,
      layout = layout
    ),
    error = function(e) list()
  )

  if (length(birincil)) return(birincil)

  cc_stage_tool_use_write_paths_as_downloads(
    tool_uses = tool_uses,
    runtime_workdir = runtime_workdir,
    source_workdir = source_workdir,
    user_id = user_id,
    session_token = session_token,
    layout = layout,
    limits = limits
  )
}

# NOT: format_claude_code_existing_file_link_html ve
# format_claude_code_generated_downloads_html R/helpers_claude_code_downloads_html.R
# dosyasına taşındı (maintainability ratchet düşürme amaçlı bölünme).
