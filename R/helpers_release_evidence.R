# ==============================================================================
# Dosya Yolu: R/helpers_release_evidence.R
# Açıklama: Release/doğrulama kanıt artifact'larını (vm-evidence evidence.json,
#           ai-validation summary.json) ve günlük log sağlık sayaçlarını
#           SECRET-SAFE biçimde okuyan saf yardımcılar. Operatör görünürlüğü
#           içindir: hangi kanıt kapısı en son ne zaman, hangi sonuçla koştu?
#
#           Sınırlar:
#           - Saf okuma katmanıdır: Shiny/reactive/DB/LLM/ağ çağrısı YOKTUR.
#           - Artifact'lar sözleşme gereği zaten secret-safe yazılır; bu okuyucu
#             yine de YALNIZCA beyaz-listeli alanları seçer, ham içerik veya
#             ortam değeri asla döndürmez (savunma derinliği).
#           - Kanıt sınırı dürüstlüğü korunur: bulunamayan artifact "not_found"
#             olarak raporlanır, asla başarı gibi gösterilmez. SKIP edilen
#             adımlar kanıt DEĞİLDİR.
# ==============================================================================

# Log kuyruk penceresi üst sınırı. `max_lines` yalnızca "sonlu ve >= 1" diye
# doğrulanıyordu; devasa bir değer senkron okumayı GB ölçeğine çıkarıp
# Shiny sürecini bloke edebiliyordu.
.RELEASE_EVIDENCE_MAX_TAIL_LINES <- 200000L
# Kuyruk okumasi icin SERT bayt tavani: satir basina 512 bayt TAHMINI, uzun
# satirlarda istenen `max_lines` penceresinin cok altinda kaliyordu.
.RELEASE_EVIDENCE_MAX_TAIL_BYTES <- 67108864

# Repo kökünü getwd() yerine sabit ve doğrulanmış adaylardan çözer.
# Shiny runtime sırasında getwd() tests/testthat gibi geçici dizinlere kayabilir.
#
# Açıkça verilen repo_root DOĞRUDAN onurlandırılır (çağıran kökü bilir; testler
# kendi fixture dizinini, gelecekteki çağıranlar gerçek app kökünü geçebilir).
# Yalnızca repo_root NULL/boş olduğunda app.R/global.R/R/www doğrulamalı
# otomatik tespit yapılır. Önceki davranış açık repo_root'u yok sayıp getwd()'ye
# düşebiliyordu; bu, fixture/explicit kök ile çağrıldığında artifact'ların yanlış
# dizinde aranmasına yol açıyordu.
release_evidence_resolve_repo_root <- function(repo_root = NULL) {
  explicit <- as.character(repo_root %||% "")[1]
  if (!is.na(explicit) && nzchar(explicit)) {
    # mustWork = FALSE olduğu için normalize var olmayan yolda da güvenle döner.
    return(normalizePath(explicit, winslash = "/", mustWork = FALSE))
  }

  adaylar <- unique(Filter(nzchar, c(
    Sys.getenv("MERGEN_REPO_ROOT", unset = ""),
    tryCatch(as.character(get0("repo_root", envir = globalenv(), inherits = TRUE) %||% "")[1],
             error = function(e) ""),
    getwd(),
    file.path(getwd(), ".."),
    file.path(getwd(), "../..")
  )))

  for (aday in adaylar) {
    kok <- tryCatch(
      normalizePath(aday, winslash = "/", mustWork = FALSE),
      error = function(e) aday
    )

    if (file.exists(file.path(kok, "app.R")) &&
        file.exists(file.path(kok, "global.R")) &&
        dir.exists(file.path(kok, "R")) &&
        dir.exists(file.path(kok, "www"))) {
      return(kok)
    }
  }

  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

# Artifact kökünü çözer: repo kökü altındaki artifacts/ dizini.
release_evidence_artifact_root <- function(repo_root = NULL) {
  file.path(release_evidence_resolve_repo_root(repo_root), "artifacts")
}

# Bir artifact ailesinin en yeni zaman damgalı alt dizinindeki hedef dosyayı
# bulur. Dizin adları (örn. 20260612-211836) ada göre azalan sıralanır;
# hedef dosyayı içeren ilk dizin kazanır. Bulunamazsa "".
release_evidence_latest_artifact <- function(base_dir, file_name) {
  if (is.null(base_dir) || length(base_dir) != 1L || is.na(base_dir) ||
      !nzchar(base_dir) || !dir.exists(base_dir)) {
    return("")
  }

  alt_dizinler <- list.dirs(base_dir, full.names = TRUE, recursive = FALSE)
  if (!length(alt_dizinler)) {
    return("")
  }

  # Zaman damgalı adlar sözlüksel sırada kronolojiktir; en yenisi başa gelir
  alt_dizinler <- alt_dizinler[order(basename(alt_dizinler), decreasing = TRUE)]

  for (dizin in alt_dizinler) {
    aday <- file.path(dizin, file_name)
    if (file.exists(aday)) {
      return(aday)
    }
  }

  ""
}

# Bir artifact ailesindeki, hedef dosyayı içeren TÜM zaman damgalı koşu
# dizinlerinin adlarını (basename) en yeniden eskiye sıralı döndürür. Operatöre
# "hangi koşular mevcut?" görünürlüğü ve koşu seçici (dropdown) için kaynak verir.
# Yalnızca dizin adı (ör. 20260613-133648) döner; tam yol taşınmaz.
release_evidence_list_runs <- function(base_dir, file_name) {
  if (is.null(base_dir) || length(base_dir) != 1L || is.na(base_dir) ||
      !nzchar(base_dir) || !dir.exists(base_dir)) {
    return(character(0))
  }

  alt_dizinler <- list.dirs(base_dir, full.names = TRUE, recursive = FALSE)
  if (!length(alt_dizinler)) {
    return(character(0))
  }

  # file.exists vektörel: hedef dosyayı içeren koşu dizinlerini seç.
  iceren <- alt_dizinler[file.exists(file.path(alt_dizinler, file_name))]
  if (!length(iceren)) {
    return(character(0))
  }

  adlar <- basename(iceren)
  adlar[order(adlar, decreasing = TRUE)]
}

# UI'den gelen koşu seçimini (run_id) güvenli bir zaman damgası adına indirger.
# Path traversal, ayraç veya beklenmeyen karakter içeren değerleri reddeder
# (savunma derinliği). Geçersizse "" döner; çağıran en yeni koşuya düşmelidir.
.release_evidence_safe_run_id <- function(run_id) {
  if (is.null(run_id) || length(run_id) != 1L || is.na(run_id)) {
    return("")
  }
  run_id <- as.character(run_id)[1]
  if (!nzchar(run_id) || !grepl("^[A-Za-z0-9._-]+$", run_id)) {
    return("")
  }
  if (!identical(run_id, basename(run_id))) {
    return("")
  }
  run_id
}

# Belirli bir koşu (run_id) dizinindeki hedef dosyayı döndürür. run_id boş,
# güvensiz veya bulunamıyorsa en yeni koşuya güvenle düşer. Bulunamazsa "".
release_evidence_artifact_for_run <- function(base_dir, run_id, file_name) {
  guvenli <- .release_evidence_safe_run_id(run_id)
  if (nzchar(guvenli) && !is.null(base_dir) && length(base_dir) == 1L &&
      !is.na(base_dir) && nzchar(base_dir)) {
    aday <- file.path(base_dir, guvenli, file_name)
    if (file.exists(aday)) {
      return(aday)
    }
  }
  release_evidence_latest_artifact(base_dir, file_name)
}

# JSON artifact'ını güvenle okur; bozuk/eksik dosyada NULL döner, asla durmaz.
release_evidence_read_json <- function(path) {
  if (is.null(path) || length(path) != 1L || is.na(path) ||
      !nzchar(path) || !file.exists(path)) {
    return(NULL)
  }

  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) NULL
  )
}

# Tek skaler alanı güvenle çeker (yoksa varsayılan); ham yapılar dönmez.
.release_evidence_scalar <- function(x, name, default = "") {
  deger <- tryCatch(x[[name]], error = function(e) NULL)
  if (is.null(deger) || length(deger) < 1L) {
    return(default)
  }
  deger <- deger[[1]]
  if (is.null(deger) || is.na(deger)) {
    return(default)
  }
  as.character(deger)
}

# VM kanıt kapısının (run_vm_evidence_gate.R) en son evidence.json özetini
# beyaz-listeli alanlarla döndürür. Adım listesi yalnızca id/status/required
# üçlüsüne indirgenir; log yolları, detaylar ve notlar dışarı taşınmaz.
release_evidence_vm_summary <- function(repo_root = NULL, run_id = NULL) {
  repo_root <- release_evidence_resolve_repo_root(repo_root)

  base_dir <- file.path(release_evidence_artifact_root(repo_root), "vm-evidence")

  # Tüm mevcut koşular (en yeni başta) operatöre koşu seçimi/görünürlüğü sağlar.
  mevcut_kosular <- release_evidence_list_runs(base_dir, "evidence.json")

  # run_id verilmişse o koşu, aksi halde en yeni koşu okunur.
  yol <- release_evidence_artifact_for_run(base_dir, run_id, "evidence.json")

  bulunamadi <- list(
    found = FALSE,
    status = "not_found",
    artifact_path = "",
    available_runs = mevcut_kosular,
    selected_run = "",
    generated_at_utc = "",
    profile_effective = "",
    passed = 0L,
    failed = 0L,
    skipped = 0L,
    steps = list()
  )

  veri <- release_evidence_read_json(yol)
  if (is.null(veri)) {
    return(bulunamadi)
  }

  # Gösterilen koşunun zaman damgası adı (dizin basename'i; tam yol değil).
  secili_kosu <- basename(dirname(yol))

  sayilar <- veri$counts
  adimlar <- lapply(veri$steps, function(s) {
    list(
      id = .release_evidence_scalar(s, "id"),
      status = .release_evidence_scalar(s, "status", default = "unknown"),
      required = isTRUE(tryCatch(s$required, error = function(e) FALSE))
    )
  })

  list(
    found = TRUE,
    status = .release_evidence_scalar(veri, "overall_status", default = "unknown"),
    artifact_path = yol,
    available_runs = mevcut_kosular,
    selected_run = secili_kosu,
    generated_at_utc = .release_evidence_scalar(veri, "generated_at_utc"),
    profile_effective = .release_evidence_scalar(veri, "profile_effective"),
    passed = as.integer(.release_evidence_scalar(sayilar, "passed", default = "0")),
    failed = as.integer(.release_evidence_scalar(sayilar, "failed", default = "0")),
    skipped = as.integer(.release_evidence_scalar(sayilar, "skipped", default = "0")),
    steps = adimlar
  )
}

# ai_validate (ai_repo_check.R) en son summary.json özetini döndürür.
# Yalnızca dokümante kanıt alanları seçilir; ham adım çıktıları taşınmaz.
release_evidence_ai_validation_summary <- function(repo_root = NULL) {
  repo_root <- release_evidence_resolve_repo_root(repo_root)

  yol <- release_evidence_latest_artifact(
    file.path(release_evidence_artifact_root(repo_root), "ai-validation"),
    "summary.json"
  )

  bulunamadi <- list(
    found = FALSE,
    artifact_path = "",
    validation_execution_status = "not_found",
    profile_requested = "",
    profile_effective = "",
    failed_steps = NA_integer_,
    skipped_steps = NA_integer_,
    app_source_smoke_status = "",
    shiny_boot_smoke_status = "",
    browser_smoke_status = ""
  )

  veri <- release_evidence_read_json(yol)
  if (is.null(veri)) {
    return(bulunamadi)
  }

  .sayi <- function(name) {
    ham <- .release_evidence_scalar(veri, name, default = NA_character_)
    out <- suppressWarnings(as.integer(ham))
    if (length(out) != 1L) NA_integer_ else out
  }

  list(
    found = TRUE,
    artifact_path = yol,
    validation_execution_status = .release_evidence_scalar(
      veri, "validation_execution_status", default = "unknown"
    ),
    profile_requested = .release_evidence_scalar(veri, "profile_requested"),
    profile_effective = .release_evidence_scalar(veri, "profile_effective"),
    failed_steps = .sayi("failed_steps"),
    skipped_steps = .sayi("skipped_steps"),
    app_source_smoke_status = .release_evidence_scalar(veri, "app_source_smoke_status"),
    shiny_boot_smoke_status = .release_evidence_scalar(veri, "shiny_boot_smoke_status"),
    browser_smoke_status = .release_evidence_scalar(veri, "browser_smoke_status")
  )
}

# Dağıtım sonrası duman testinin (run_post_deploy_smoke.R) en son
# post-deploy-smoke.json özetini beyaz-listeli alanlarla döndürür. Yalnızca genel
# sonuç, durum sayaçları ve kritik kontrol kimlikleri taşınır; ham log/ortam değeri
# veya kontrol detayı dışarı çıkmaz. Bulunamazsa dürüstçe not_found döner.
release_evidence_post_deploy_smoke_summary <- function(repo_root = NULL, run_id = NULL) {
  repo_root <- release_evidence_resolve_repo_root(repo_root)

  base_dir <- file.path(release_evidence_artifact_root(repo_root), "post-deploy-smoke")

  mevcut_kosular <- release_evidence_list_runs(base_dir, "post-deploy-smoke.json")
  yol <- release_evidence_artifact_for_run(base_dir, run_id, "post-deploy-smoke.json")

  bulunamadi <- list(
    found = FALSE,
    status = "not_found",
    should_fail = FALSE,
    artifact_path = "",
    available_runs = mevcut_kosular,
    selected_run = "",
    generated_at_utc = "",
    evaluated_at = "",
    total = 0L,
    pass_count = 0L,
    warn_count = 0L,
    critical_count = 0L,
    critical_failures = character(0)
  )

  veri <- release_evidence_read_json(yol)
  if (is.null(veri)) {
    return(bulunamadi)
  }

  secili_kosu <- basename(dirname(yol))
  sayilar <- veri$counts

  # critical_failures artifact'ta char vektörüdür (sağlık kontrol kimlikleri;
  # geliştirici-tanımlı, secret değil). veri ayrıştırılmış bir listedir; eksik
  # alanda $ erişimi NULL döner (hata vermez), bu yüzden tryCatch gerekmez.
  ham_cf <- veri$critical_failures
  kritik_basarisizliklar <- if (is.null(ham_cf) || !length(ham_cf)) {
    character(0)
  } else {
    cf <- as.character(unlist(ham_cf, use.names = FALSE))
    cf[!is.na(cf) & nzchar(cf)]
  }

  list(
    found = TRUE,
    status = .release_evidence_scalar(veri, "overall", default = "unknown"),
    should_fail = isTRUE(veri$should_fail),
    artifact_path = yol,
    available_runs = mevcut_kosular,
    selected_run = secili_kosu,
    generated_at_utc = .release_evidence_scalar(veri, "generated_at_utc"),
    evaluated_at = .release_evidence_scalar(veri, "evaluated_at"),
    total = as.integer(.release_evidence_scalar(veri, "total", default = "0")),
    pass_count = as.integer(.release_evidence_scalar(sayilar, "ok", default = "0")),
    warn_count = as.integer(.release_evidence_scalar(sayilar, "warning", default = "0")),
    critical_count = as.integer(.release_evidence_scalar(sayilar, "critical", default = "0")),
    critical_failures = kritik_basarisizliklar
  )
}

# ERROR satırlarındaki geliştirici-tanımlı bağlam (context) etiketlerini sayar.
# Kaynak kalıp: "Error in <bağlam>: <mesaj>" (log_error_with_context çıktısı;
# hem bağlam hem mesaj zaten redakte edilmiş yazılır). YALNIZCA <bağlam> alınır
# (ilk iki noktaya kadar); mesaj İÇERİĞİ asla taşınmaz. Savunma derinliği için
# bağlam güvenli karakter sınıfına indirgenir ve 60 karaktere kırpılır.
# "Error in" kalıbına uymayan ERROR satırları "diğer" kovasına gider. En sık
# top_n bağlam azalan sayı sırasıyla list(context=, count=) olarak döner.
# Operatöre "hangi alt sistem en çok hata üretiyor?" görünürlüğü sağlar.
release_evidence_summarize_error_contexts <- function(error_lines, top_n = 6L) {
  if (is.null(error_lines) || !length(error_lines)) {
    return(list())
  }

  ham_ctx <- vapply(error_lines, function(line) {
    line <- as.character(line)[1]
    if (is.na(line) || !nzchar(line)) {
      return("diğer")
    }
    m <- regmatches(line, regexec("Error in ([^:]{1,120}):", line))[[1]]
    if (length(m) >= 2L && nzchar(trimws(m[[2]]))) {
      ctx <- trimws(m[[2]])
      # Savunma derinliği: yalnızca güvenli karakterler kalsın, 60 ile sınırla
      ctx <- gsub("[^A-Za-z0-9 ._/-]", "", ctx)
      ctx <- trimws(substr(ctx, 1L, 60L))
      if (!nzchar(ctx)) "diğer" else ctx
    } else {
      "diğer"
    }
  }, character(1), USE.NAMES = FALSE)

  sayim <- sort(table(ham_ctx), decreasing = TRUE)
  if (length(sayim) > top_n) {
    sayim <- sayim[seq_len(top_n)]
  }

  lapply(seq_along(sayim), function(i) {
    list(context = names(sayim)[i], count = as.integer(sayim[[i]]))
  })
}

# AI çağrı log satırlarından istek süresi (latency) özetini secret-safe üretir.
# Kaynak kalıp: log_ai_call() çıktısı
# "AI Call: user=..., model=..., duration=<saniye>s, success=<TRUE/FALSE>, tokens=...".
# YALNIZCA sayısal süreler (duration=<sayı>s) ve başarı/başarısızlık sayıları
# döner; kullanıcı kimliği, model adı veya başka içerik ASLA taşınmaz. Süre
# içermeyen/eşleşmeyen satırlar yok sayılır. Eşleşme yoksa boş liste döner; bu
# sayede operatör UI'sinde eski davranış korunur (alan boşsa hiçbir şey gösterilmez).
release_evidence_summarize_ai_call_latency <- function(ai_call_lines) {
  if (is.null(ai_call_lines) || !length(ai_call_lines)) {
    return(list())
  }

  # duration=<sayı>s kalıbından yalnızca sayısal süreyi çıkar (içerik taşınmaz)
  eslesme <- regmatches(
    ai_call_lines,
    regexpr("duration=[0-9]+\\.?[0-9]*s", ai_call_lines)
  )
  if (!length(eslesme)) {
    return(list())
  }

  sureler <- suppressWarnings(as.numeric(gsub("duration=|s", "", eslesme)))
  sureler <- sureler[!is.na(sureler) & sureler >= 0]
  if (!length(sureler)) {
    return(list())
  }

  list(
    count = length(sureler),
    min = round(min(sureler), 2),
    median = round(stats::median(sureler), 2),
    mean = round(mean(sureler), 2),
    max = round(max(sureler), 2),
    success_count = as.integer(sum(grepl("success=TRUE", ai_call_lines, fixed = TRUE))),
    fail_count = as.integer(sum(grepl("success=FALSE", ai_call_lines, fixed = TRUE)))
  )
}

# Bugünün uygulama logundaki ERROR/WARN satırlarını sınırlı pencerede sayar.
# Log satır İÇERİĞİ döndürülmez (redakte edilmiş olsa bile); yalnızca sayaç,
# son hata zaman öneki ve (yeni) güvenli bağlam kategorisi sayımı raporlanır.
# Dosya yoksa güvenli sıfır özeti döner.
release_evidence_log_health <- function(log_dir = NULL, max_lines = 2000L) {
  if (is.null(log_dir) || !nzchar(log_dir %||% "")) {
    log_dir <- trimws(Sys.getenv("MERGEN_LOG_DIR", "logs"))
  }

  log_yolu <- file.path(
    log_dir,
    sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d"))
  )

  bos <- list(
    found = FALSE,
    log_path = log_yolu,
    window_lines = 0L,
    window_truncated = FALSE,
    error_count = 0L,
    warn_count = 0L,
    last_error_at = "",
    error_contexts = list(),
    ai_call_latency = list()
  )

  if (!file.exists(log_yolu)) {
    return(bos)
  }

  # Byte-safe okuma: Windows VM logları ANSI/WINDOWS-1254 bayt içerebilir
  # (geçersiz UTF-8). Ham içerik startsWith/regexpr/regexec'i "input string is
  # invalid" ile kırıp TÜM Doğrulama Kanıtı sekmesini boşa düşürürdü (kök neden).
  # Öncelik byte-safe read_text_lines_utf8; izole bağlamda yoksa readBin + iconv.
  # Sınırlı KUYRUK okuması: dosyanın tamamını belleğe almak büyük üretim
  # loglarında yüzlerce MB tüketiyordu (max_lines penceresi ancak okumadan
  # SONRA uygulanıyordu). Satır başına ~512 bayt varsayımıyla yalnızca son
  # pencere okunur; kesilen ilk satır düşürülür.
  # max_lines TEK ve SONLU pozitif tam sayıya indirgenir: NA kuyruk penceresini
  # geçersiz yapıp tüm sekmeyi sessizce boş "found" durumuna düşürüyordu, Inf
  # ise hem kuyruk sınırını hem son pencere kırpmasını devre dışı bırakıyordu.
  max_lines <- suppressWarnings(as.numeric(max_lines)[1])
  if (length(max_lines) != 1L || !is.finite(max_lines) || max_lines < 1) {
    max_lines <- 2000L
  }
  # ÜST SINIR: 4000000 gibi sonlu ama devasa bir değer bu denetimi geçip
  # kuyruk penceresini ~2 GB'a çıkarıyor (senkron okuma Shiny sürecini
  # blokluyor veya belleği tüketiyor), daha büyük değerler ise as.integer()
  # taşmasıyla NA üretip sekmeyi sessizce boşaltıyordu.
  max_lines <- min(max_lines, .RELEASE_EVIDENCE_MAX_TAIL_LINES)
  max_lines <- as.integer(max_lines)

  # Pencere BAYT ile degil SATIR ile olculur: 512 baytlik tahmin, ortalama 2 KiB
  # satirlarda `max_lines = 2000` istegini ~512 satira dusuruyor ve atlanan
  # bolumdeki hata/uyarilar sayilmadigi halde kirpma RAPORLANMIYORDU.
  pencere_kesildi <- FALSE
  satirlar <- tryCatch({
    boyut <- suppressWarnings(as.numeric(file.info(log_yolu)$size[1]))
    if (!is.finite(boyut)) boyut <- 0
    kuyruk_bayt <- max(262144, as.numeric(max_lines) * 512)
    tum <- character(0)

    repeat {
      kuyruk_bayt <- min(kuyruk_bayt, .RELEASE_EVIDENCE_MAX_TAIL_BYTES)
      kesildi <- boyut > kuyruk_bayt

      ham <- if (kesildi) {
        baglanti <- file(log_yolu, open = "rb")
        seek(baglanti, where = boyut - kuyruk_bayt, origin = "start")
        parca <- readBin(baglanti, what = "raw", n = as.integer(kuyruk_bayt))
        close(baglanti)
        parca
      } else {
        readBin(log_yolu, what = "raw", n = as.integer(boyut))
      }

      metin <- iconv(list(ham), from = "WINDOWS-1254", to = "UTF-8", sub = "byte")[[1]]
      tum <- if (length(metin) == 1L && !is.na(metin) && nzchar(metin)) {
        strsplit(metin, "\r\n|\n|\r", perl = TRUE)[[1]]
      } else {
        character(0)
      }

      # Kuyruk okumasında ilk satır yarım olabilir.
      if (kesildi && length(tum) > 1L) tum <- tum[-1L]

      if (!kesildi || length(tum) >= max_lines) break
      if (kuyruk_bayt >= .RELEASE_EVIDENCE_MAX_TAIL_BYTES) {
        # Sert tavana ulasildi ve istenen satir sayisi hala saglanamadi.
        pencere_kesildi <<- TRUE
        break
      }
      kuyruk_bayt <- kuyruk_bayt * 4
    }

    if (exists("normalize_text_utf8", mode = "function")) {
      normalize_text_utf8(tum, repair_mojibake = TRUE)
    } else {
      tum
    }
  }, error = function(e) character(0))

  if (!length(satirlar)) {
    bos$found <- TRUE
    return(bos)
  }

  # Sınırlı pencere: yalnızca son max_lines satır incelenir
  if (length(satirlar) > max_lines) {
    satirlar <- satirlar[(length(satirlar) - max_lines + 1L):length(satirlar)]
  }

  hata_satirlari <- satirlar[startsWith(satirlar, "ERROR")]
  uyari_satirlari <- satirlar[startsWith(satirlar, "WARN")]
  # AI çağrı süresi satırları (log_ai_call çıktısı); yalnızca sayısal özet alınır
  ai_cagri_satirlari <- satirlar[grepl("AI Call:", satirlar, fixed = TRUE)]

  son_hata_zamani <- ""
  if (length(hata_satirlari)) {
    # Yalnızca köşeli parantezli zaman öneki çıkarılır; mesaj içeriği taşınmaz
    eslesme <- regmatches(
      hata_satirlari[length(hata_satirlari)],
      regexpr("\\[[0-9 :-]+\\]", hata_satirlari[length(hata_satirlari)])
    )
    if (length(eslesme)) {
      son_hata_zamani <- gsub("[][]", "", eslesme[1])
    }
  }

  list(
    found = TRUE,
    log_path = log_yolu,
    window_lines = length(satirlar),
    # Bayt tavani nedeniyle istenen satir penceresi saglanamadiysa ACIKCA
    # bildirilir; sessiz eksik sayim kanit gibi gorunuyordu.
    window_truncated = isTRUE(pencere_kesildi),
    error_count = length(hata_satirlari),
    warn_count = length(uyari_satirlari),
    last_error_at = son_hata_zamani,
    # Yalnızca bağlam etiketi + sayım; mesaj içeriği taşınmaz (secret-safe)
    error_contexts = release_evidence_summarize_error_contexts(hata_satirlari),
    # Yalnızca sayısal istek-süresi özeti; kullanıcı/model içeriği taşınmaz (secret-safe)
    ai_call_latency = release_evidence_summarize_ai_call_latency(ai_cagri_satirlari)
  )
}

# Operatör görünümü için birleşik release kanıt özeti. Tüm alt özetler
# secret-safe alan seçiminden geçer; bulunamayan kanıtlar dürüstçe
# not_found olarak işaretlenir ve asla kanıt yerine geçmez.
release_evidence_overview <- function(repo_root = NULL, log_dir = NULL, run_id = NULL) {
  repo_root <- release_evidence_resolve_repo_root(repo_root)

  # Alt özetler içsel olarak güvenlidir: JSON okuma tryCatch'lidir ve log okuma
  # byte-safe'dir; bu yüzden tek bir okuyucu artık tüm sekmeyi boşa düşürmez.
  # (module_health.R reaktifi ayrıca üst düzey tryCatch ile sarmalar.)
  list(
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    vm_evidence = release_evidence_vm_summary(repo_root, run_id = run_id),
    ai_validation = release_evidence_ai_validation_summary(repo_root),
    post_deploy_smoke = release_evidence_post_deploy_smoke_summary(repo_root),
    log_health = release_evidence_log_health(log_dir),
    proof_note = paste(
      "SKIP edilen adımlar kanıt değildir; cloud profili VM/SSO/DB/SQL Server",
      "Türkçe kodlama/gerçek tarayıcı kanıtı üretmez. Yalnızca 'passed' adımlar",
      "ilgili kapsam için kanıttır."
    )
  )
}