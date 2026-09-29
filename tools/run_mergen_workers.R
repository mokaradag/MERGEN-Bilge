# ==============================================================================
# Dosya Yolu: tools/run_mergen_workers.R
# Aciklama: Cok-worker (horizontal scale) MERGEN Bilge baslatici.
#
# NEDEN: Tek Shiny/httpuv sureci ~400-425 escipzamanli baglantida TCP kabul/
#   backlog doygunlugu yasar (CPU dusukken connection_timeout baskin). Bunun
#   durust cozumu YATAY olceklemedir: ayni makinede (ya da makinelerde) BIRDEN
#   COK MERGEN worker sureci, her biri farkli MERGEN_PORT'ta, bir kurumsal
#   ters-vekil / yuk-dengeleyici (nginx, IIS ARR, HAProxy) arkasinda. Her worker
#   kendi httpuv kabul dongusune ve event-loop'una sahiptir; kabul kapasitesi
#   worker sayisiyla yaklasik dogrusal artar.
#
# TASARIM SOZLESMESI:
#   - VARSAYILAN DAVRANIS DEGISMEZ: MERGEN_WORKERS ayarlanmazsa worker sayisi 1'dir
#     (tek surec, mevcut davranisla ayni). Bu betik OPT-IN bir baslaticidir;
#     normal uretim launcher'i (run_mergen_prod.bat) tek sureci calistirmaya
#     devam eder.
#   - HARICI BAGIMLILIK EKLEMEZ: yalnizca mevcut 'processx' paketini kullanir.
#     CDN / internet / agir proxy bagimliligi YOK.
#   - WINDOWS-GUVENLI: Rscript yolu ve app.R repo kokunden cozulur; UNC/Turkce
#     yol varsayimi yapmaz. Bu betik bilincli olarak ASCII-only'dir (operasyonel
#     giris-noktasi betikleri konvansiyonu; farkli locale'lerde source/Rscript
#     ile guvenli calismak icin).
#   - source(...)-GUVENLI: quit() cagirmaz. MERGEN_WORKERS_DEFINE_ONLY=true iken
#     yalnizca fonksiyonlari tanimlar (otomatik baslatma yapmaz) -> test/inceleme.
#   - Saglik uc noktasi: her worker GET /healthz ve GET /readyz sunar
#     (R/helpers_app_http_routes.R); yuk-dengeleyici bunlarla worker'lari guvenle
#     havuza alip cikarir.
# ==============================================================================

# --- Yapilandirma okuma yardimcilari (ASCII-guvenli) ---

mergen_workers_env_int <- function(name, default) {
  raw <- trimws(Sys.getenv(name, unset = ""))
  if (!nzchar(raw)) return(as.integer(default))
  val <- suppressWarnings(as.integer(raw))
  if (is.na(val)) as.integer(default) else val
}

# Worker sayisi: MERGEN_WORKERS (varsayilan 1 = mevcut tek-surec davranisi).
# 1'den kucuk degerler 1'e yuvarlanir; makul ust sinir (CPU cekirdek baskisi)
# icin MERGEN_WORKERS_MAX (varsayilan 16) ile sinirlanir.
mergen_worker_count <- function() {
  n <- mergen_workers_env_int("MERGEN_WORKERS", 1L)
  if (is.na(n) || n < 1L) n <- 1L
  cap <- mergen_workers_env_int("MERGEN_WORKERS_MAX", 16L)
  if (is.na(cap) || cap < 1L) cap <- 16L
  min(n, cap)
}

# Temel port: MERGEN_BASE_PORT veya MERGEN_PORT (varsayilan 8009). Worker i,
# base + i portunu kullanir (i = 0..n-1).
mergen_worker_base_port <- function() {
  raw <- trimws(Sys.getenv("MERGEN_BASE_PORT", unset = ""))
  if (!nzchar(raw)) raw <- trimws(Sys.getenv("MERGEN_PORT", unset = "8009"))
  val <- suppressWarnings(as.integer(raw))
  if (is.na(val) || val < 1L || val > 65535L) return(8009L)
  val
}

mergen_worker_ports <- function(base = mergen_worker_base_port(),
                                count = mergen_worker_count()) {
  base <- as.integer(base)
  count <- max(1L, as.integer(count))
  as.integer(base + seq.int(0L, count - 1L))
}

# Repo kokunu cozer (bu betik tools/ altinda; kok bir ust dizin). app.R varsa
# dogrular.
mergen_workers_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  base_dir <- if (length(file_arg) == 1L && nzchar(file_arg)) {
    dirname(normalizePath(file_arg, winslash = "/", mustWork = FALSE))
  } else {
    getwd()
  }
  cand <- c(
    normalizePath(file.path(base_dir, ".."), winslash = "/", mustWork = FALSE),
    normalizePath(getwd(), winslash = "/", mustWork = FALSE),
    normalizePath(Sys.getenv("MERGEN_REPO_ROOT", unset = "."), winslash = "/", mustWork = FALSE)
  )
  for (p in cand) {
    if (nzchar(p) && file.exists(file.path(p, "app.R"))) return(p)
  }
  cand[1]
}

# Rscript ikilisini cozer (calisan R oturumuyla ayni R kurulumunu tercih eder).
mergen_workers_rscript_path <- function() {
  exe <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  if (file.exists(exe)) return(exe)
  "Rscript"
}

# Cevrimici (presence) paylasim dizini: yalniz operator degeri aktarilir. Bos
# ise cocuk surec varsayilani kullanir: bu makinede ayni uygulama kokunden
# calisan TUM baslaticilarin paylastigi yerel dizin (R/helpers_user_presence_shared.R).
# Cevrimici gorunumu makine basinadir; UNC paylasim olay dongusunu bloklar.
mergen_workers_presence_dir <- function() {
  trimws(Sys.getenv("MERGEN_PRESENCE_SHARED_DIR", unset = ""))
}

# Her worker icin baslatma plani (port + env + komut). LAUNCH YAPMAZ; saf veri.
mergen_worker_launch_plan <- function(base = mergen_worker_base_port(),
                                      count = mergen_worker_count(),
                                      host = Sys.getenv("MERGEN_HOST", "0.0.0.0"),
                                      repo_root = mergen_workers_repo_root(),
                                      presence_dir = mergen_workers_presence_dir()) {
  ports <- mergen_worker_ports(base, count)
  rscript <- mergen_workers_rscript_path()
  lapply(seq_along(ports), function(i) {
    list(
      index = i,
      port = ports[[i]],
      host = host,
      command = rscript,
      args = c("app.R"),
      workdir = repo_root,
      env = c(
        MERGEN_RUN_APP = "true",
        MERGEN_PORT = as.character(ports[[i]]),
        MERGEN_HOST = host,
        # Cocuk surec paylasilan kaynaklari (log dosyasi, ozet kapasitesi)
        # worker sayisina gore bolusur.
        MERGEN_APP_WORKER_COUNT = as.character(length(ports)),
        MERGEN_APP_WORKER_INDEX = as.character(i),
        # Cevrimici paylasimi makineye YEREL dizinde (bos: uygulama varsayilani).
        MERGEN_PRESENCE_SHARED_DIR = presence_dir
      )
    )
  })
}

# Yuk-dengeleyici (ters-vekil) icin upstream ipucunu yazar (operatore rehber).
mergen_worker_print_plan <- function(plan) {
  cat("MERGEN Bilge multi-worker plani:\n")
  for (spec in plan) {
    cat(sprintf("  worker %d -> %s:%d\n", spec$index, spec$host, spec$port))
  }
  cat("\nTers-vekil upstream ornegi (nginx):\n")
  cat("  upstream mergen {\n")
  cat("    least_conn;\n")
  for (spec in plan) {
    cat(sprintf("    server 127.0.0.1:%d;  # health: /healthz /readyz\n", spec$port))
  }
  cat("  }\n")
  invisible(plan)
}

# Worker'lari baslatir ve canli tutar. dry_run = TRUE ise yalnizca plani dondurur
# (test/inceleme; gercek surec baslatmaz).
mergen_start_workers <- function(dry_run = FALSE) {
  plan <- mergen_worker_launch_plan()
  # Tum port araligi baslatmadan once dogrulanir: 65535'i asan port cocugu
  # hemen oldurur ve yeniden baslatma butcesi tum kumeyi kapatirdi.
  ports <- vapply(plan, function(spec) as.integer(spec$port), integer(1))
  if (any(is.na(ports) | ports < 1L | ports > 65535L)) {
    stop(sprintf("Gecersiz worker port araligi: %d-%d (1-65535 olmali). MERGEN_BASE_PORT/MERGEN_WORKERS degerlerini kontrol edin.",
                 min(ports, na.rm = TRUE), max(ports, na.rm = TRUE)), call. = FALSE)
  }
  mergen_worker_print_plan(plan)

  if (isTRUE(dry_run)) {
    return(invisible(plan))
  }

  if (!requireNamespace("processx", quietly = TRUE)) {
    stop("tools/run_mergen_workers.R icin 'processx' paketi gereklidir.", call. = FALSE)
  }

  # Cocuk ciktisi baslaticinin konsoluna aktarilir: okunmayan boru dolunca
  # worker'in sonraki yazimi bloklanir ve istek islemeyi durdururdu.
  start_one <- function(spec) {
    p <- processx::process$new(
      command = spec$command,
      args = spec$args,
      wd = spec$workdir,
      env = c("current", spec$env),
      stdout = "", stderr = "",
      supervise = TRUE
    )
    cat(sprintf("[WORKER] baslatildi port=%d pid=%s\n", spec$port,
                tryCatch(as.character(p$get_pid()), error = function(e) "?")))
    p
  }

  # Temizlik ilk worker'dan ONCE kaydedilir: toplu baslatma yarida hata
  # verirse o ana kadar baslayan cocuklar yetim kalmaz.
  procs <- list()
  on.exit({
    for (pw in procs) try(pw$proc$kill(), silent = TRUE)
  }, add = TRUE)
  for (spec in plan) {
    procs[[length(procs) + 1L]] <- list(spec = spec, proc = start_one(spec), restarts = 0L,
                                        started = Sys.time())
  }

  # Olen worker yeniden baslatilir; boylece ozet kapasitesi/kuyruk paylari
  # (MERGEN_APP_WORKER_COUNT) canli surec kumesiyle uyumlu kalir. Butce ardisik
  # cokmeleri sayar: worker MERGEN_WORKERS_STABLE_SECONDS boyunca calisinca
  # sifirlanir. Butce biterse tum kume kapatilir (yarim kume paylari yanlis boler).
  max_restarts <- mergen_workers_env_int("MERGEN_WORKERS_MAX_RESTARTS", 5L)
  stable_secs <- mergen_workers_env_int("MERGEN_WORKERS_STABLE_SECONDS", 600L)
  repeat {
    for (k in seq_along(procs)) {
      alive <- tryCatch(procs[[k]]$proc$is_alive(), error = function(e) FALSE)
      if (alive) {
        if (procs[[k]]$restarts > 0L &&
            as.numeric(difftime(Sys.time(), procs[[k]]$started, units = "secs")) >= stable_secs) {
          procs[[k]]$restarts <- 0L
        }
        next
      }
      if (procs[[k]]$restarts >= max_restarts) {
        cat(sprintf("[WORKER] port=%d yeniden baslatma butcesi bitti; tum worker'lar kapatiliyor.\n",
                    procs[[k]]$spec$port))
        return(invisible(procs))
      }
      procs[[k]]$restarts <- procs[[k]]$restarts + 1L
      cat(sprintf("[WORKER] port=%d durdu; yeniden baslatiliyor (%d/%d).\n",
                  procs[[k]]$spec$port, procs[[k]]$restarts, max_restarts))
      # Baslatma hatasi dongude kalir: yuva olu kalir, sonraki turda butce
      # icinde yeniden denenir; saglikli worker'lar kapatilmaz.
      yeni <- tryCatch(start_one(procs[[k]]$spec), error = function(e) {
        cat(sprintf("[WORKER] port=%d baslatilamadi: %s\n", procs[[k]]$spec$port, conditionMessage(e)))
        NULL
      })
      if (!is.null(yeni)) {
        procs[[k]]$proc <- yeni
        procs[[k]]$started <- Sys.time()
      }
    }
    Sys.sleep(2)
  }
}

# --- Otomatik baslatma kapisi ---
# MERGEN_WORKERS_DEFINE_ONLY=true iken yalnizca fonksiyonlari tanimlar (test/
# inceleme). Aksi halde dogrudan calistirilinca worker'lari baslatir.
if (!identical(tolower(trimws(Sys.getenv("MERGEN_WORKERS_DEFINE_ONLY", ""))), "true")) {
  mergen_start_workers(dry_run = identical(tolower(trimws(Sys.getenv("MERGEN_WORKERS_DRY_RUN", ""))), "true"))
}
