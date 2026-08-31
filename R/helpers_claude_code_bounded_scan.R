# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_bounded_scan.R
# Açıklama: Bilge Yolaç için gerçekten sınırlı (bounded) dizin tarayıcısı.
#           Tüm ağacı list.files(recursive = TRUE) ile numaralandırıp sonradan
#           kırpmak yerine, artımlı gezinir ve sınıra ulaşıldığı anda durur.
#           Bu dosya saf tarama sorumluluğu taşır: Shiny, reaktif değer, DB,
#           ağ veya süreç yönetimi içermez ve worker sürecinde çalışabilir.
# ==============================================================================

# Varsayılan olarak atlanan dizin adları (basename eşleşmesi).
cc_scan_default_excluded_dirs <- function() {
  c(
    ".git", ".svn", ".hg",
    "node_modules", ".Rproj.user", "packrat",
    "build", "dist", "target", "bin", "obj", "coverage",
    ".cache", "cache", "__pycache__", ".pytest_cache", ".mypy_cache",
    ".venv", "venv", ".tox",
    ".idea", ".vscode", ".gradle", ".terraform",
    "tmp", "temp", ".tmp",
    "claude_code_runtime", "claude_code_workspaces",
    "bilge_yolac_downloads", "document_support", ".document_support"
  )
}

# Kök dizine göre göreli yol eşleşmesiyle atlanan dizinler.
cc_scan_default_excluded_rel_paths <- function() {
  c("renv/library", "renv/staging", "renv/sandbox", "renv/cellar", "renv/python")
}

# Bilge Yolaç runtime düzeninde çıktı taramasına dahil edilmeyen alt klasörler.
cc_scan_runtime_excluded_dirs <- function() {
  c("metadata", "document_support")
}

.cc_scan_int <- function(value, default) {
  out <- suppressWarnings(as.numeric(value[1]))
  if (length(out) != 1L || is.na(out) || out < 0) {
    out <- suppressWarnings(as.numeric(default))
  }
  if (length(out) != 1L || is.na(out)) {
    return(Inf)
  }
  out
}

.cc_scan_norm <- function(path) {
  out <- tryCatch(
    normalizePath(path, winslash = "/", mustWork = FALSE),
    error = function(e) as.character(path)[1]
  )
  out <- gsub("\\", "/", as.character(out)[1], fixed = TRUE)
  # Kodlama işareti tek biçime getirilir: normalizePath() Windows'ta yerel
  # kodlamalı, list.files() ise UTF-8 işaretli dize döndürür. İkisi paste0()
  # ile birleşince karşılaştırmanın iki tarafı farklı kodlama yolundan geçer.
  enc2utf8(sub("(?<=.)/+$", "", out, perl = TRUE))
}

# Yol karşılaştırma anahtarı.
#
# KRİTİK: tolower() yerel/kodlama duyarlıdır. Türkçe Windows'ta (CP1254 tek
# baytlı yerel) yerel kodlamalı bir dizede bayt bazlı katlama uygulanır ve
# "İ" -> "ı" olur; UTF-8 işaretli aynı metinde ise geniş karakter yolu
# çalışır ve "İ" -> "i" olur. Karşılaştırmanın iki tarafı farklı kodlama
# işareti taşıyorsa aynı dosya adı EŞİT ÇIKMAZ. Bu yüzden katlamadan önce
# kodlama daima UTF-8'e sabitlenir.
.cc_scan_key <- function(path) {
  yol <- enc2utf8(as.character(path))
  if (.Platform$OS.type == "windows") tolower(yol) else yol
}

# Dizin bağlantısı (symlink/junction) mı? Takip edilmeyen bağlantılar hem
# döngüye hem de izinli kökün dışına kaçmaya yol açabilir.
#
# NOT: `Sys.readlink()` yalnızca POSIX'te anlamlıdır; Windows'ta HER yol için
# NA döner. Bu yüzden NA açıkça "bağlantı değil" olarak yorumlanır
# (nzchar(NA) TRUE olduğu için doğrudan kullanılamaz). Windows reparse
# noktaları bu ucuz kontrolle değil, tarayıcının zaten hesapladığı çözülmüş
# gerçek yol karşılaştırmasıyla (izinli kök + tekrar ziyaret kümesi)
# yakalanır; girdi başına ek `normalizePath()` maliyeti UNC paylaşımlarında
# taramayı belirgin biçimde yavaşlatırdı.
.cc_scan_is_link <- function(path) {
  hedef <- tryCatch(Sys.readlink(path), error = function(e) NA_character_)
  if (length(hedef) != 1L || is.na(hedef)) return(FALSE)
  nzchar(hedef)
}

#' Yol bir bağlantı/reparse noktası mı (Windows dahil)
#'
#' `Sys.readlink()` Windows'ta çalışmadığı için junction/symlink tespiti
#' çözülmüş yolun sözlüksel konumdan sapmasıyla yapılır: gerçek bir dizin
#' `normalizePath(üst)/ad` ile aynı yere çözülürken bağlantı başka bir yere
#' çözülür. 8.3 kısa ad farkını ortadan kaldırmak için karşılaştırmanın iki
#' tarafı da `normalizePath()` üzerinden geçer.
#'
#' Bu kontrol girdi başına DEĞİL, seyrek çağrılan sınır noktalarında
#' (runtime bölge doğrulaması, çıktı hedefi) kullanılmalıdır.
#'
#' @param path Kontrol edilecek yol
#' @return Bağlantı ise TRUE
cc_path_is_reparse_link <- function(path) {
  yol <- as.character(path %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) return(FALSE)

  if (isTRUE(.cc_scan_is_link(yol))) return(TRUE)
  if (.Platform$OS.type != "windows") return(FALSE)

  if (!isTRUE(file.exists(yol)) && !isTRUE(dir.exists(yol))) return(FALSE)

  # Anonim işleyici sayısı bilinçli düşük tutulur (bkz. .cc_scan_list_entries);
  # bu yüzden tryCatch yerine try(silent = TRUE) kullanılır.
  cozulmus <- try(normalizePath(yol, winslash = "/", mustWork = TRUE), silent = TRUE)
  ust <- try(normalizePath(dirname(yol), winslash = "/", mustWork = TRUE), silent = TRUE)
  if (inherits(cozulmus, "try-error") || inherits(ust, "try-error")) return(FALSE)

  # Yalnızca ÜST DİZİNLER karşılaştırılır. Taban ad karşılaştırması Windows'ta
  # kırılgandır: normalizePath() 8.3 kısa adı uzun ada ve diskteki kanonik
  # harf büyüklüğüne çevirir, Türkçe adlarda ise kodlama/harf katlama farkı
  # oluşur. Bağlantı zaten üst dizini değiştirir; kök dışına kaçış ayrıca
  # çağıran tarafta izinli kök önekiyle denetlenir.
  !identical(
    .cc_scan_key(.cc_scan_norm(dirname(cozulmus))),
    .cc_scan_key(.cc_scan_norm(ust))
  )
}

# Bir dizinin girdilerini sınırlı biçimde listeler.
#
# KRİTİK ENCODING SÖZLEŞMESİ: Bu fonksiyon dizin girdilerini ASLA bir kabuk
# alt sürecinden (powershell.exe / find) okumaz. Windows'ta PowerShell çıktısı
# konsol OEM kod sayfasıyla (Türkçe Windows'ta CP857) yazılır; boru üzerinden
# okunan baytlar R tarafında yerel ANSI (CP1254) kabul edildiğinde Türkçe
# dosya adları bozulur (Ç->€, ş->Ÿ, ç->‡, İ->˜, ü/ı->kutu). Dahası PowerShell
# biçimlendirici uzun satırları konsol genişliğinde (varsayılan 120 sütun)
# katlar; uzun UNC yolları birden çok satıra bölünüp geçersiz yollara dönüşür.
# Her iki bozulma da dosyaların diskte bulunamamasına ve izole runtime input
# klasörünün boş kalmasına yol açar.
#
# Bu yüzden numaralandırma base R `list.files()` ile yapılır: adlar doğru
# kodlamada döner, uzun UNC yolları bölünmez ve süreç başlatma maliyeti
# (PowerShell için ~300-800 ms) ortadan kalkar. Sınırlar (max_entries,
# zaman aşımı) listeleme sonrasında uygulanır; tek bir dizinin okunması
# bir alt süreç başlatmaktan belirgin biçimde ucuzdur.
.cc_scan_list_entries <- function(path, max_entries, deadline_ms,
                                  allow_fs_fallback = TRUE) {
  limit <- max(0L, as.integer(max_entries))
  if (limit == 0L) return(list(entries = character(0), truncated = TRUE, reason = "max_entries"))

  # Anonim işleyici sayısı bilinçli olarak düşük tutulur (maintainability
  # ratchet bu dosyayı fonksiyon bütçesiyle korur); bu yüzden tryCatch yerine
  # try(silent = TRUE) kullanılır.
  gecen_ms <- as.numeric(difftime(Sys.time(), deadline_ms$started, units = "secs")) * 1000
  if (isTRUE(gecen_ms > deadline_ms$limit)) {
    return(list(entries = character(0), truncated = TRUE, reason = "timeout"))
  }

  # `all.files = FALSE` gizli/nokta ile başlayan girdileri dışarıda bırakır;
  # bu, gezginin eski (regresyon öncesi) davranışıyla aynıdır.
  ham <- try(
    list.files(path, all.files = FALSE, full.names = TRUE, recursive = FALSE, no.. = TRUE),
    silent = TRUE
  )
  if (inherits(ham, "try-error")) {
    stop(sprintf("Dizin listelenemedi: %s", conditionMessage(attr(ham, "condition"))))
  }

  entries <- as.character(ham %||% character(0))

  # Windows VM / UNC paylaşımlarında base R `list.files()` bazen erişilebilir
  # bir paylaşım için de boş döner. Bu yüzden boş sonuçta `fs` yedeğine düşülür;
  # `fs` de doğru kodlanmış adlar döndürdüğü için Türkçe adlar korunur.
  fs_yedegi <- FALSE
  fs_kesildi <- FALSE
  if (!length(entries) && isTRUE(allow_fs_fallback) &&
      requireNamespace("fs", quietly = TRUE)) {
    # YEDEK NUMARALANDIRMA BÜTÇE KAPISININ ARDINDADIR VE SÜREYLE SINIRLIDIR.
    #
    # `fs::dir_ls()` başlık-sınırlama (head-limit) ya da iptal API'si SUNMAZ:
    # çağrı tüm listeyi üretir. Bu yüzden (1) bütçe ZATEN tükenmişken ikinci
    # bir tam numaralandırma BAŞLATILMAZ ve (2) başlatıldığında KALAN bütçe
    # `setTimeLimit(transient = TRUE)` ile uygulanır. Aksi hâlde yavaş bir UNC
    # paylaşımında ana Shiny olay döngüsü `timeout_ms` sınırının çok ötesinde
    # bloke kalırdı. Çağıran (`allow_fs_fallback = FALSE`) yedeği tamamen de
    # kapatabilir.
    gecen_ms <- as.numeric(difftime(Sys.time(), deadline_ms$started, units = "secs")) * 1000
    kalan_ms <- deadline_ms$limit - gecen_ms
    if (!isTRUE(is.finite(kalan_ms)) || isTRUE(kalan_ms <= 0)) {
      return(list(entries = character(0), truncated = TRUE, reason = "timeout"))
    }

    # `fail = FALSE` erişim hatasını UYARIYA çevirir ve KISMİ liste döndürür;
    # uyarı yutulduğunda eksik sonuç BAŞARILI sayılıyordu. `warn = 2` uyarıyı
    # HATAYA çevirir, böylece kısmi sonuç aşağıda AÇIKÇA reddedilir (ek bir
    # işleyici kapanışı gerekmeden; dosya fonksiyon bütçesi sınırındadır).
    eski_warn <- getOption("warn")
    on.exit({ options(warn = eski_warn); setTimeLimit() }, add = TRUE)
    options(warn = 2L)
    setTimeLimit(elapsed = max(0.05, kalan_ms / 1000), transient = TRUE)
    yedek <- try(fs::dir_ls(path, recurse = FALSE, all = FALSE, fail = FALSE), silent = TRUE)
    setTimeLimit()
    options(warn = eski_warn)

    if (inherits(yedek, "try-error")) {
      mesaj <- conditionMessage(attr(yedek, "condition"))
      # SÜRE SINIRI KESİNTİSİ HATA DEĞİL, KIRPMADIR.
      if (grepl("elapsed time limit", mesaj, fixed = TRUE)) {
        return(list(entries = character(0), truncated = TRUE, reason = "timeout"))
      }
      stop(sprintf("Dizin listelenemedi: %s", mesaj))
    }

    entries <- as.character(yedek)
    # KIRPMA BİLDİRİLİR: `entries` burada kesilirse aşağıdaki
    # `length(entries) > limit` denetimi FALSE olur ve KISMİ liste TAM
    # sayılırdı; `cc_scan_directory_bounded()` de `max_entries` kırpmasını
    # hiç raporlamazdı.
    fs_kesildi <- length(entries) > limit
    if (isTRUE(fs_kesildi)) entries <- entries[seq_len(limit)]
    fs_yedegi <- TRUE
  }

  # `list.files()` erişilemeyen bir dizin için hata vermez, sessizce boş döner.
  # Gerçek erişim hatasını "boş dizin" gibi göstermemek için okunabilirliği
  # ayrıca doğrularız; aksi halde paylaşım/ACL hatası sessiz kalırdı.
  #
  # `fs::dir_ls(fail = FALSE)` de erişim hatasını UYARIYA çevirir ve KISMİ bir
  # liste döndürebilir; uyarı yutulduğunda eksik sonuç BAŞARILI sayılıyordu.
  # Bu yüzden yedek kullanıldığında okunabilirlik sonuç BOŞ OLMASA DA
  # doğrulanır.
  # OKUMA TEK BAŞINA YETMEZ: POSIX'te yalnızca `r` izni olan bir dizin
  # listelenebilir ama içindeki ögeler STAT EDİLEMEZ (`x`/arama izni gerekir).
  # `mode = 4L` böyle bir dizini geçirir; sonraki `file.info()` NA döner ve
  # tarama erişilemeyen yollarla `ok = TRUE` raporlardı. `mode = 5L` okuma ve
  # arama izinlerini BİRLİKTE doğrular (Windows'ta dizinler zaten çalıştırılabilir
  # sayılır; davranış değişmez).
  #
  # YEDEK BAŞARISI `file.access()` ÖN DENETİMİNDEN AYRILIR: bazı Windows UNC
  # yollarında `file.access(path, mode = 5L)` erişilebilir bir paylaşım için
  # de `-1` döndürür; yedek TEMİZ (uyarısız) ve DOLU bir liste ürettiğinde
  # eski koşul o geçerli sonucu atıp `listing_error` raporluyordu. Kısmi yedek
  # sonucu yukarıda ZATEN hata veriyor, bu yüzden burada yalnızca BOŞ sonuç
  # denetlenir.
  if (!length(entries) &&
      !identical(unname(file.access(path, mode = 5L))[1], 0L)) {
    stop(sprintf("Dizin listelenemedi: okuma/arama izni yok (%s)", path))
  }

  truncated <- FALSE
  reason <- ""

  if (length(entries) > limit || isTRUE(fs_kesildi)) {
    entries <- entries[seq_len(min(length(entries), limit))]
    truncated <- TRUE
    reason <- "max_entries"
  } else {
    gecen_ms <- as.numeric(difftime(Sys.time(), deadline_ms$started, units = "secs")) * 1000
    if (isTRUE(gecen_ms > deadline_ms$limit)) {
      truncated <- TRUE
      reason <- "timeout"
    }
  }

  list(entries = entries, truncated = truncated, reason = reason)
}

#' Tek bir dizini sınırlı biçimde listele (özyinelemesiz)
#'
#' Ana Shiny sürecindeki dizin gezgini de dahil olmak üzere tek dizin
#' listelemesi gereken yerlerde `list.files()` yerine kullanılır: yüz binlerce
#' girdili düz bir klasörde bile en fazla `max_entries` öge okunur ve
#' `timeout_ms` bütçesi aşıldığında numaralandırma durur.
#'
#' @param path Listelenecek dizin
#' @param max_entries Okunacak maksimum öge sayısı
#' @param timeout_ms Toplam listeleme bütçesi (ms)
#' @return list(entries, truncated, reason, ok, error)
cc_scan_list_dir_bounded <- function(path,
                                     max_entries = 500L,
                                     timeout_ms = 2000L,
                                     allow_fs_fallback = TRUE) {
  yol <- as.character(path %||% "")[1]
  bos <- list(
    entries = character(0), truncated = FALSE, reason = "",
    ok = FALSE, error = ""
  )

  if (is.na(yol) || !nzchar(yol)) return(bos)
  if (!isTRUE(tryCatch(dir.exists(yol), error = function(e) FALSE))) return(bos)

  max_entries <- .cc_scan_int(max_entries, 500L)
  timeout_ms <- .cc_scan_int(timeout_ms, 2000L)

  sonuc <- tryCatch(
    .cc_scan_list_entries(
      yol,
      max_entries = max_entries,
      deadline_ms = list(started = Sys.time(), limit = timeout_ms),
      allow_fs_fallback = isTRUE(allow_fs_fallback)
    ),
    error = function(e) {
      list(
        entries = character(0), truncated = FALSE, reason = "listing_error",
        error = conditionMessage(e)
      )
    }
  )

  list(
    entries = as.character(sonuc$entries %||% character(0)),
    truncated = isTRUE(sonuc$truncated),
    reason = as.character(sonuc$reason %||% "")[1],
    ok = !nzchar(as.character(sonuc$error %||% "")[1]),
    error = as.character(sonuc$error %||% "")[1]
  )
}

.cc_scan_result <- function(root,
                            files = character(0),
                            file_sizes = numeric(0),
                            directories = character(0),
                            total_bytes = 0,
                            elapsed_ms = 0,
                            truncated = FALSE,
                            truncated_reason = "",
                            errors = character(0),
                            skipped = character(0),
                            ok = TRUE) {
  list(
    ok = isTRUE(ok),
    root = root,
    files = files,
    file_sizes = file_sizes,
    directories = directories,
    file_count = length(files),
    dir_count = length(directories),
    total_bytes = total_bytes,
    elapsed_ms = elapsed_ms,
    truncated = isTRUE(truncated),
    truncated_reason = truncated_reason,
    errors = errors,
    skipped = skipped
  )
}

#' Bir dizini gerçekten sınırlı biçimde tara
#'
#' Artımlı gezinir; herhangi bir sınıra ulaşıldığında kalan ağacı hiç
#' numaralandırmadan durur ve `truncated_reason` alanını doldurur.
#'
#' @param root Taranacak kök dizin
#' @param max_files Maksimum dosya sayısı
#' @param max_dirs Maksimum dizin sayısı
#' @param max_depth Maksimum derinlik (kök = 0)
#' @param max_total_bytes Maksimum toplam bayt
#' @param max_elapsed_ms Maksimum tarama süresi (ms)
#' @param max_file_bytes Tek dosya için üst sınır (aşan dosya atlanır)
#' @param max_entries İşlenecek maksimum öge sayısı
#' @param exclude_dirs Atlanacak dizin adları
#' @param exclude_rel_paths Köke göre atlanacak göreli dizin yolları
#' @param follow_symlinks Dizin bağlantıları takip edilsin mi
#' @param allowed_root Çözülen yolların içinde kalması gereken kök
#' @return Yapılandırılmış tarama sonucu listesi
cc_scan_directory_bounded <- function(root,
                                      max_files = 2000L,
                                      max_dirs = 500L,
                                      max_depth = 6L,
                                      max_total_bytes = 200 * 1024^2,
                                      max_elapsed_ms = 4000L,
                                      max_file_bytes = 25 * 1024^2,
                                      max_entries = 20000L,
                                      exclude_dirs = cc_scan_default_excluded_dirs(),
                                      exclude_rel_paths = cc_scan_default_excluded_rel_paths(),
                                      follow_symlinks = FALSE,
                                      allowed_root = NULL) {
  baslangic <- Sys.time()

  ham_kok <- as.character(root %||% "")[1]
  if (is.na(ham_kok) || !nzchar(ham_kok)) {
    return(.cc_scan_result(root = "", ok = FALSE, truncated_reason = "invalid_root"))
  }

  kok <- .cc_scan_norm(ham_kok)

  if (!isTRUE(tryCatch(dir.exists(kok), error = function(e) FALSE))) {
    return(.cc_scan_result(root = kok, ok = FALSE, truncated_reason = "missing_root"))
  }

  max_files <- .cc_scan_int(max_files, 2000L)
  max_dirs <- .cc_scan_int(max_dirs, 500L)
  max_depth <- .cc_scan_int(max_depth, 6L)
  max_total_bytes <- .cc_scan_int(max_total_bytes, 200 * 1024^2)
  max_elapsed_ms <- .cc_scan_int(max_elapsed_ms, 4000L)
  max_file_bytes <- .cc_scan_int(max_file_bytes, 25 * 1024^2)
  max_entries <- .cc_scan_int(max_entries, 20000L)

  haric_adlar <- tolower(as.character(exclude_dirs %||% character(0)))
  haric_rel <- tolower(gsub("\\", "/", as.character(exclude_rel_paths %||% character(0)), fixed = TRUE))

  izin_kok <- if (is.null(allowed_root) || !nzchar(as.character(allowed_root)[1])) {
    kok
  } else {
    .cc_scan_norm(allowed_root)
  }
  izin_kok_key <- .cc_scan_key(izin_kok)

  dosyalar <- character(0)
  boyutlar <- numeric(0)
  dizinler <- character(0)
  hatalar <- character(0)
  atlananlar <- character(0)
  kok_listeleme_hatasi <- FALSE

  toplam_bayt <- 0
  islenen_oge <- 0
  kesildi <- FALSE
  kesme_nedeni <- ""

  gorulen <- new.env(parent = emptyenv())
  assign(.cc_scan_key(kok), TRUE, envir = gorulen)

  kuyruk <- list(list(path = kok, depth = 0L, rel = ""))

  gecen_ms <- function() {
    as.numeric(difftime(Sys.time(), baslangic, units = "secs")) * 1000
  }

  kes <- function(neden) {
    kesildi <<- TRUE
    if (!nzchar(kesme_nedeni)) kesme_nedeni <<- neden
    invisible(NULL)
  }

  while (length(kuyruk) > 0L && !isTRUE(kesildi)) {
    if (gecen_ms() > max_elapsed_ms) {
      kes("timeout")
      break
    }

    mevcut <- kuyruk[[1L]]
    kuyruk <- kuyruk[-1L]

    kalan_oge <- max_entries - islenen_oge
    listeleme <- tryCatch(
      .cc_scan_list_entries(
        mevcut$path,
        max_entries = kalan_oge,
        deadline_ms = list(started = baslangic, limit = max_elapsed_ms)
      ),
      error = function(e) {
        hatalar <<- c(hatalar, paste0(mevcut$rel, ": ", conditionMessage(e)))
        # Bir alt dizindeki ACL/paylaşım hatası erişilebilir kardeşlerin
        # taranmasını engellemez. Yalnızca kökün kendisi listelenemiyorsa
        # preflight için ölümcül bir tarama hatası olarak kalır.
        if (identical(mevcut$depth, 0L)) {
          kok_listeleme_hatasi <<- TRUE
          kes("listing_error")
        }
        list(entries = character(0), truncated = FALSE, reason = "")
      }
    )

    ogeler <- listeleme$entries
    if (isTRUE(listeleme$truncated)) kes(listeleme$reason)

    if (!length(ogeler)) next

    bilgi <- tryCatch(
      file.info(ogeler, extra_cols = FALSE),
      error = function(e) {
        hatalar <<- c(hatalar, paste0(mevcut$rel, ": ", conditionMessage(e)))
        NULL
      }
    )

    if (is.null(bilgi) || nrow(bilgi) == 0L) next

    for (i in seq_along(ogeler)) {
      islenen_oge <- islenen_oge + 1L
      if (islenen_oge > max_entries) {
        kes("max_entries")
        break
      }

      if (islenen_oge %% 64L == 0L && gecen_ms() > max_elapsed_ms) {
        kes("timeout")
        break
      }

      # Bağlantıyı normalizePath() hedefe çevirmeden önce, listeleyicinin
      # döndürdüğü özgün yol üzerinden denetle.
      ham_oge <- as.character(ogeler[i])
      baglanti_mi <- isTRUE(.cc_scan_is_link(ham_oge))
      oge <- .cc_scan_norm(ham_oge)
      oge_ad <- basename(gsub("\\", "/", ham_oge, fixed = TRUE))
      oge_rel <- if (nzchar(mevcut$rel)) paste0(mevcut$rel, "/", oge_ad) else oge_ad

      dizin_mi <- isTRUE(bilgi$isdir[i])

      if (dizin_mi) {
        if (tolower(oge_ad) %in% haric_adlar || tolower(oge_rel) %in% haric_rel) {
          atlananlar <- c(atlananlar, oge_rel)
          next
        }

        if (!isTRUE(follow_symlinks) && baglanti_mi) {
          atlananlar <- c(atlananlar, oge_rel)
          next
        }

        if (mevcut$depth + 1L > max_depth) {
          kes("max_depth")
          next
        }

        # Bağlantı/junction döngülerine ve izinli kök dışına kaçışa karşı
        # gerçek yol üzerinden tekrar ziyaret kontrolü yapılır.
        gercek <- tryCatch(
          normalizePath(oge, winslash = "/", mustWork = TRUE),
          error = function(e) oge
        )
        gercek <- .cc_scan_norm(gercek)
        gercek_key <- .cc_scan_key(gercek)

        if (!identical(gercek_key, izin_kok_key) &&
            !startsWith(gercek_key, paste0(izin_kok_key, "/"))) {
          atlananlar <- c(atlananlar, oge_rel)
          next
        }

        if (exists(gercek_key, envir = gorulen, inherits = FALSE)) {
          atlananlar <- c(atlananlar, oge_rel)
          next
        }
        assign(gercek_key, TRUE, envir = gorulen)

        if (length(dizinler) + 1L > max_dirs) {
          kes("max_directories")
          next
        }

        dizinler <- c(dizinler, oge)
        kuyruk[[length(kuyruk) + 1L]] <- list(
          path = oge,
          depth = mevcut$depth + 1L,
          rel = oge_rel
        )
        next
      }

      if (!isTRUE(follow_symlinks) && baglanti_mi) {
        atlananlar <- c(atlananlar, oge_rel)
        next
      }

      # Dosya bağlantıları takip edilse bile çözülmüş hedef izinli kökün
      # dışındaysa izole runtime'a alınmaz.
      gercek_dosya <- tryCatch(
        normalizePath(ham_oge, winslash = "/", mustWork = TRUE),
        error = function(e) oge
      )
      gercek_dosya <- .cc_scan_norm(gercek_dosya)
      gercek_dosya_key <- .cc_scan_key(gercek_dosya)
      if (!identical(gercek_dosya_key, izin_kok_key) &&
          !startsWith(gercek_dosya_key, paste0(izin_kok_key, "/"))) {
        atlananlar <- c(atlananlar, oge_rel)
        next
      }

      boyut <- suppressWarnings(as.numeric(bilgi$size[i]))
      if (!is.finite(boyut)) boyut <- 0

      if (boyut > max_file_bytes) {
        atlananlar <- c(atlananlar, oge_rel)
        next
      }

      if (length(dosyalar) + 1L > max_files) {
        kes("max_files")
        break
      }

      if (toplam_bayt + boyut > max_total_bytes) {
        kes("max_total_bytes")
        break
      }

      dosyalar <- c(dosyalar, oge)
      boyutlar <- c(boyutlar, boyut)
      toplam_bayt <- toplam_bayt + boyut
    }
  }

  .cc_scan_result(
    root = kok,
    files = dosyalar,
    file_sizes = boyutlar,
    directories = dizinler,
    total_bytes = toplam_bayt,
    elapsed_ms = round(gecen_ms(), 1),
    truncated = kesildi,
    truncated_reason = kesme_nedeni,
    errors = unique(hatalar),
    skipped = unique(atlananlar),
    ok = !isTRUE(kok_listeleme_hatasi)
  )
}

#' Tarama sonucundaki yolları köke göre göreli forma çevir
#'
#' @param paths Mutlak yollar
#' @param root Kök dizin
#' @return Göreli yollar (kök dışındakiler basename olarak döner)
cc_scan_relative_paths <- function(paths, root) {
  paths <- as.character(paths %||% character(0))
  if (!length(paths)) return(character(0))

  kok <- .cc_scan_norm(root %||% "")
  if (!nzchar(kok)) return(basename(paths))

  kok_key <- .cc_scan_key(kok)
  onek <- paste0(kok_key, "/")

  vapply(paths, function(p) {
    p_norm <- .cc_scan_norm(p)
    p_key <- .cc_scan_key(p_norm)

    if (startsWith(p_key, onek)) {
      substring(p_norm, nchar(kok) + 2L)
    } else {
      basename(p_norm)
    }
  }, character(1), USE.NAMES = FALSE)
}
