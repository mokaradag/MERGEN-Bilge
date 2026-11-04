# Windows VM: bind adresi / SSO origin / kosuya ozel kaynak yolu sozlesmesi.
.vm_ux_functions <- function(path = "tests/scripts/run_vm_browser_ux_smoke.R") {
  env <- new.env(parent = globalenv())
  for (e in parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), path))) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.call(e[[3]]) &&
        identical(e[[3]][[1]], as.name("function"))) eval(e, env)
  }
  env
}

# Win32 gerçek dosyayı çözünce kısa/uzun ad ve ayırıcı farkı kimlik değildir.
.vm_ux_executable_identity <- function(path, windows = .Platform$OS.type == "windows",
                                       canonicalize = normalizePath) {
  value <- canonicalize(path, winslash = "/", mustWork = TRUE)
  if (windows) tolower(value) else value
}

test_that("Rscript kimligi Windows ad takmalarini kabul eder, kurulum ve mimariyi ayirir", {
  long <- "C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe"
  short <- "C:/PROGRA~1/R/R-4.6.1/bin/x64/Rscript.exe"
  spellings <- c(long, short, chartr("/", "\\", long), chartr("/", "\\", short),
                 "C:/Program Files/R/R-4.6.1/bin/./x64/Rscript.exe")
  # Windows dosya sistemi cozumunu yerel surucu gerektirmeden modelle.
  canonicalize <- function(path, winslash, mustWork) {
    expect_identical(winslash, "/")
    expect_true(mustWork)
    if (path %in% spellings) long else path
  }
  identity <- function(path) .vm_ux_executable_identity(path, TRUE, canonicalize)
  for (path in spellings) expect_identical(identity(path), identity(long))
  expect_identical(identity(toupper(long)), identity(long))
  for (different in c("C:/Program Files/R/R-4.5.0/bin/x64/Rscript.exe",
                      "C:/Program Files/R/R-4.6.1/bin/i386/Rscript.exe",
                      "D:/Other/R-4.6.1/bin/x64/Rscript.exe")) {
    expect_false(identical(identity(different), identity(long)))
  }
  active <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  expect_identical(.vm_ux_executable_identity(file.path(dirname(active), ".", basename(active))),
                   .vm_ux_executable_identity(active))
})

test_that("belgedeki SSO on kontrolu uygulama durdurulmadan yapilir ve dosyayi degistirmez", {
  doc <- read_source_text_utf8(file.path(resolve_repo_root_for_tests(), "docs/vm-browser-ux-smoke.md"))
  lines <- strsplit(doc, "\n", fixed = TRUE)[[1]]
  command <- lines[startsWith(lines, '& $rscript -e "') & grepl("SSO_ENABLED", lines, fixed = TRUE)]
  expect_length(command, 1L)
  expect_lt(match(command, lines), match("Ön kontrol başarılı olduktan sonra normal uygulamayı kendi konsolundan/normal işletim yöntemiyle durdurun. Aynı Window 1'de:", lines))
  expect_match(doc, "SSO pre-stop check FAILED; keep the normal app running.", fixed = TRUE)
  expr <- substr(command, nchar('& $rscript -e "') + 1L, nchar(command) - 1L)
  config <- withr::local_tempdir()
  withr::local_dir(config)
  withr::local_envvar(SSO_ENABLED = NA)
  expect_error(eval(parse(text = expr)), "SSO_ENABLED=TRUE is required")
  for (value in c("FALSE", "", "TRUE")) {
    writeLines(paste0("SSO_ENABLED=", value), ".Renviron")
    before <- readBin(".Renviron", "raw", 10000L)
    if (value == "TRUE") {
      expect_output(eval(parse(text = expr)), "OK: SSO configuration enabled.", fixed = TRUE)
    } else {
      expect_error(eval(parse(text = expr)), "SSO_ENABLED=TRUE is required")
    }
    expect_identical(readBin(".Renviron", "raw", 10000L), before)
  }
})

test_that("belgedeki profil konumu ve Edge ilkesi uretim durmadan ve login oncesinde denetlenir", {
  root <- resolve_repo_root_for_tests()
  doc <- read_source_text_utf8(file.path(root, "docs/vm-browser-ux-smoke.md"))
  lines <- strsplit(doc, "\n", fixed = TRUE)[[1]]
  checks <- which(startsWith(trimws(lines), '& $rscript -e "') &
                    grepl("ux_smoke_profile_path", lines, fixed = TRUE))
  expect_length(checks, 2L)
  stop_app <- which(startsWith(lines, "Ön kontrol başarılı olduktan sonra normal uygulamayı"))
  expect_length(stop_app, 1L)
  # Ayni konum+ilke kontrolu uretim durmadan once ve Edge login'den once kosar.
  expect_lt(checks[[1]], stop_app)
  expect_lt(stop_app, checks[[2]])
  expect_identical(trimws(lines[[checks[[1]]]]), trimws(lines[[checks[[2]]]]))
  expect_match(lines[[checks[[1]]]], "ux_smoke_check_edge_policy()", fixed = TRUE)
  # Profil dizini mustWork=TRUE kontrolunden once ayni yerden tanimlanip olusturulur.
  pre <- lines[seq_len(checks[[1]] - 1L)]
  define <- which(pre == '$env:MERGEN_BROWSER_UX_PROFILE_DIR = Join-Path $env:LOCALAPPDATA "MERGEN\\BrowserUxSmoke"')
  create <- which(pre == "New-Item -ItemType Directory -Force -Path $env:MERGEN_BROWSER_UX_PROFILE_DIR | Out-Null")
  expect_length(define, 1L)
  expect_identical(create, define + 1L)
  expect_identical(checks[[1]], create + 1L)
  expect_true('$env:MERGEN_BROWSER_UX_PROFILE_DIR = Join-Path $env:LOCALAPPDATA "MERGEN\\BrowserUxSmoke"' %in%
                trimws(lines[checks[[1]]:checks[[2]]]))
  expect_identical(lines[checks[[1]] + 1:3], c(
    "$profileCheck = $LASTEXITCODE", "Remove-Item Env:MERGEN_BROWSER_UX_PROFILE_DIR",
    'if ($profileCheck -ne 0) { throw "Edge profile location/policy pre-stop check FAILED; keep the normal app running." }'))
  command <- trimws(lines[[checks[[1]]]])
  expr <- substr(command, nchar('& $rscript -e "') + 1L, nchar(command) - 1L)
  fixture <- withr::local_tempdir()
  repo <- file.path(fixture, "repo")
  profile <- file.path(fixture, "BrowserUxSmoke")
  dir.create(file.path(repo, "artifacts/ai-validation"), recursive = TRUE)
  dir.create(profile)
  withr::local_dir(repo)
  withr::local_envvar(MERGEN_BROWSER_UX_PROFILE_DIR = profile, MERGEN_EVIDENCE_ARTIFACT_DIR = NA)
  env <- new.env(parent = globalenv())
  approved <- TRUE
  checked <- 0L
  env$source <- function(file, ...) {
    sys.source(file.path(root, file), envir = env)
    env$ux_smoke_check_edge_policy <- function() {
      checked <<- checked + 1L
      if (!approved) stop("Edge policy denied")
      invisible(TRUE)
    }
  }
  expect_true(eval(parse(text = expr), env))
  approved <- FALSE
  expect_error(eval(parse(text = expr), env), "Edge policy denied", fixed = TRUE)
  expect_identical(checked, 2L)
  # Repo icindeki profil uretim durmadan reddedilir; ilke adimina gecilmez.
  Sys.setenv(MERGEN_BROWSER_UX_PROFILE_DIR = file.path(repo, "artifacts/ai-validation"))
  expect_error(eval(parse(text = expr), env), "must be outside the repository", fixed = TRUE)
  expect_identical(checked, 2L)
  # Var olmayan profil mustWork=TRUE ile reddedilir; belge dizini once olusturur.
  Sys.setenv(MERGEN_BROWSER_UX_PROFILE_DIR = file.path(fixture, "olusturulmadi"))
  expect_error(suppressWarnings(eval(parse(text = expr), env)))
  expect_identical(checked, 2L)
})

test_that("belgedeki tarayici sahiplik adaptoru uretim durmadan gercekten dogrulanir", {
  root <- resolve_repo_root_for_tests()
  lines <- strsplit(read_source_text_utf8(file.path(root, "docs/vm-browser-ux-smoke.md")), "\n", fixed = TRUE)[[1]]
  command <- which(startsWith(lines, '& $rscript -e "') &
                     grepl("ux_smoke_owned_browser_preflight()", lines, fixed = TRUE))
  expect_length(command, 1L)
  expect_lt(command, which(startsWith(lines, "Ön kontrol başarılı olduktan sonra normal uygulamayı")))
  expect_identical(lines[[command + 1L]],
    'if ($LASTEXITCODE -ne 0) { throw "Owned browser adapter pre-stop check FAILED; keep the normal app running." }')
  # Gercek Edge yasam dongusu kontrolu de uretim durmadan once ve basarisizlikta durdurucudur.
  edge_check <- which(startsWith(lines, '& $rscript -e "') &
                        grepl("ux_smoke_owned_browser_edge_preflight()", lines, fixed = TRUE))
  expect_length(edge_check, 1L)
  expect_identical(edge_check, command + 2L)
  expect_lt(edge_check, which(startsWith(lines, "Ön kontrol başarılı olduktan sonra normal uygulamayı")))
  expect_identical(lines[[edge_check + 1L]],
    'if ($LASTEXITCODE -ne 0) { throw "Owned Edge lifecycle pre-stop check FAILED; keep the normal app running." }')
  expect_match(lines[[edge_check]], "helpers_browser_ux_profile.R", fixed = TRUE)
  expr <- substr(lines[[command]], nchar('& $rscript -e "') + 1L, nchar(lines[[command]]) - 1L)
  withr::local_dir(root)
  env <- new.env(parent = globalenv())
  env$source <- function(file, ...) sys.source(file.path(root, file), envir = env)
  # Gercek adaptor yolu (Windows'ta PowerShell + ozel job) tarayicisiz kosar.
  expect_output(expect_true(eval(parse(text = expr), env)), "OK: owned browser adapter verified.", fixed = TRUE)
  # Siniflandirilmis adaptor hatasi ve yakalanmayan cikti PASS sayilmaz.
  expect_error(env$ux_smoke_owned_browser_preflight(run = function(...) stop(env$ux_smoke_owned_browser_error(
    "Owned browser launch or cleanup failed (stage=assign, win32=5).", "browser_launch_failed", "assign", "5"))),
    "adapter pre-stop check FAILED: Owned browser launch or cleanup failed (stage=assign, win32=5).", fixed = TRUE)
  expect_error(env$ux_smoke_owned_browser_preflight(run = function(...) list(status = 0L, stdout = "", stderr = "")),
               "probe output was not captured", fixed = TRUE)
  expect_error(env$ux_smoke_owned_browser_preflight(run = function(...) list(
    status = 3L, stdout = '<html><body><div id="status">OWNED_BROWSER_ADAPTER_OK</div></body></html>', stderr = "")),
    "probe output was not captured", fixed = TRUE)
})

test_that("belgedeki Edge secimi kullanici kurulumunu bulur ve onceligi korur", {
  root <- resolve_repo_root_for_tests()
  lines <- strsplit(read_source_text_utf8(file.path(root, "docs/vm-browser-ux-smoke.md")), "\n", fixed = TRUE)[[1]]
  starts <- which(startsWith(lines, '$edge = "'))
  ends <- which(lines == 'if (!(Test-Path -LiteralPath $edge -PathType Leaf)) { throw "Microsoft Edge bulunamadi." }')
  expect_length(starts, 2L)
  blocks <- lapply(starts, function(start) paste(lines[start:ends[ends >= start][[1]]], collapse = "\n"))
  expect_identical(blocks[[1]], blocks[[2]])
  expect_lt(starts[[1]], which(startsWith(lines, "Ön kontrol başarılı olduktan sonra normal uygulamayı")))
  skip_if(.Platform$OS.type != "windows", "PowerShell Windows dosya yolu secimi")
  fixture <- withr::local_tempdir()
  roots <- file.path(fixture, c("x86", "system", "user"))
  paths <- file.path(roots, "Microsoft", "Edge", "Application", "msedge.exe")
  for (path in paths) dir.create(dirname(path), recursive = TRUE)
  withr::local_envvar(c(MERGEN_TEST_EDGE_X86 = roots[[1]], MERGEN_TEST_EDGE_SYSTEM = roots[[2]],
                       MERGEN_TEST_EDGE_USER = roots[[3]], MERGEN_TEST_EXPECTED_EDGE = ""))
  # Windows sistem degiskenleri cocuk surecte, fixture girdilerinden acikca kurulur.
  script <- paste("$ErrorActionPreference='Stop'",
    "${env:ProgramFiles(x86)}=$env:MERGEN_TEST_EDGE_X86; $env:ProgramFiles=$env:MERGEN_TEST_EDGE_SYSTEM; $env:LOCALAPPDATA=$env:MERGEN_TEST_EDGE_USER",
    blocks[[1]],
    "if ([IO.Path]::GetFullPath($edge) -ne [IO.Path]::GetFullPath($env:MERGEN_TEST_EXPECTED_EDGE)) { throw 'Wrong Edge candidate' }",
    "Write-Output 'EDGE_LOOKUP_OK'", sep = "\n")
  for (selected in c(1L, 2L, 3L, NA_integer_)) {
    unlink(paths)
    if (!is.na(selected)) invisible(file.create(paths[selected:3L]))
    Sys.setenv(MERGEN_TEST_EXPECTED_EDGE = if (is.na(selected)) "" else paths[[selected]])
    result <- processx::run("powershell.exe", c("-NoProfile", "-NonInteractive", "-Command", script),
                           error_on_status = FALSE, timeout = 20)
    if (is.na(selected)) {
      expect_false(identical(result$status, 0L))
      expect_match(result$stderr, "Microsoft Edge bulunamadi.", fixed = TRUE)
    } else {
      expect_identical(result$status, 0L, info = result$stderr)
      expect_identical(trimws(result$stdout), "EDGE_LOOKUP_OK")
    }
  }
})

test_that("belgedeki Edge on kontrolu login oncesinde repo ve tum artifact koklerini reddeder", {
  root <- resolve_repo_root_for_tests()
  doc <- read_source_text_utf8(file.path(root, "docs/vm-browser-ux-smoke.md"))
  lines <- strsplit(doc, "\n", fixed = TRUE)[[1]]
  # Window 2 kopyasi Edge baslatma blogunun icindedir (Window 1 kopyasi ayri test edilir).
  command <- lines[startsWith(lines, '    & $rscript -e "') & grepl("ux_smoke_profile_path", lines, fixed = TRUE)]
  expect_length(command, 1L)
  check <- match(command, lines)
  launch <- which(startsWith(trimws(lines), '& $edge "--user-data-dir='))
  expect_length(launch, 1L)
  expect_lt(check, launch)
  expect_identical(lines[[check - 3L]], "& {")
  expect_identical(trimws(lines[[check - 2L]]), "$ErrorActionPreference = 'Stop'")
  expect_match(lines[[check - 1L]], "if (([uri]$env:MERGEN_BROWSER_UX_BASE_URL).Scheme -ne 'https') { throw", fixed = TRUE)
  expect_identical(trimws(lines[[check + 1L]]), "if ($LASTEXITCODE -eq 0) {")
  expect_identical(launch, check + 2L)
  expect_identical(trimws(lines[[launch + 1L]]), "} else {")
  expect_match(lines[[launch + 2L]], "throw", fixed = TRUE)
  expect_identical(trimws(lines[[launch + 3L]]), "}")
  expect_identical(lines[[launch + 4L]], "}")
  command <- trimws(command)
  expr <- substr(command, nchar('& $rscript -e "') + 1L, nchar(command) - 1L)
  fixture <- withr::local_tempdir()
  repo <- file.path(fixture, "repo")
  artifact <- file.path(fixture, "evidence")
  profile <- file.path(fixture, "profile")
  for (dir in c(repo, artifact, profile, file.path(repo, "artifacts/ai-validation"))) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  withr::local_dir(repo)
  withr::local_envvar(MERGEN_EVIDENCE_ARTIFACT_DIR = artifact, MERGEN_BROWSER_UX_PROFILE_DIR = profile)
  env <- new.env(parent = globalenv())
  policies <- 0L
  env$source <- function(file) {
    sys.source(file.path(root, file), envir = env)
    env$ux_smoke_check_edge_policy <- function() { policies <<- policies + 1L; invisible(TRUE) }
  }
  eval(parse(text = expr), env)
  expect_identical(policies, 1L)
  for (blocked in c(repo, file.path(repo, "artifacts/ai-validation"), artifact)) {
    Sys.setenv(MERGEN_BROWSER_UX_PROFILE_DIR = blocked)
    expect_error(eval(parse(text = expr), env), "must be outside the repository", fixed = TRUE)
    expect_identical(policies, 1L, info = "konum reddedilince sonraki adima gecilmez")
  }
  expect_true(dir.exists(profile))
})

test_that("VM oneki dogrudan OpenSSL'den 24 kriptografik bayt alir ve hatayi gizlemez", {
  env <- .vm_ux_functions()
  calls <- list()
  bytes <- as.raw(c(0:15, 248:255))
  testthat::local_mocked_bindings(rand_bytes = function(n) {
    calls[[length(calls) + 1L]] <<- n
    bytes
  }, .package = "openssl")
  expect_identical(env$vm_ux_new_prefix(),
                   "__mergen_ux_000102030405060708090a0b0c0d0e0ff8f9fafbfcfdfeff")
  bytes <- rev(bytes)
  expect_identical(env$vm_ux_new_prefix(),
                   "__mergen_ux_fffefdfcfbfaf9f80f0e0d0c0b0a09080706050403020100")
  expect_identical(calls, list(24L, 24L))
  testthat::local_mocked_bindings(rand_bytes = function(...) stop("rng unavailable"), .package = "openssl")
  expect_error(env$vm_ux_new_prefix(), "rng unavailable", fixed = TRUE)
})

test_that("VM startup her kosuda yeni 192-bit onek uretir, URL guvenli kurulur", {
  env <- .vm_ux_functions()
  prefixes <- replicate(20, env$vm_ux_new_prefix())
  expect_true(all(vapply(prefixes, env$vm_ux_prefix_valid, logical(1))))
  expect_equal(length(unique(prefixes)), 20L)
  for (base in c("https://app.example.invalid/base", "https://app.example.invalid/base/")) {
    expect_identical(env$vm_ux_smoke_url(base, prefixes[[1]]),
                     paste0("https://app.example.invalid/base/", prefixes[[1]], "/ux-smoke.html?autostart=1"))
  }
  for (bad in c("", "/", "smoke", "www", "../", paste0(prefixes[[1]], "/"),
                paste0(prefixes[[1]], "\n"), paste(rep("f", 1000), collapse = ""))) {
    expect_false(env$vm_ux_prefix_valid(bad))
    expect_error(env$vm_ux_smoke_url("https://app.example.invalid", bad), "Invalid per-run")
  }
  for (bad in c("", "file:///tmp", "https://user:secret@app.example.invalid/base",
                "https://app.example.invalid/base?token=x", "https://app.example.invalid/base#x",
                "https://app.example.invalid/base\n", "https://app.example.invalid\\base")) {
    expect_error(env$vm_ux_base_url(bad), "MERGEN_BROWSER_UX_BASE_URL")
  }
  for (bad in c("http://app.example.invalid/base", "http://127.0.0.1.example.invalid",
                "http://localhost.example.invalid", "https://[::1]:8009")) {
    expect_error(env$vm_ux_base_url(bad), "MERGEN_BROWSER_UX_BASE_URL")
  }
  for (local in c("http://127.0.0.1:8009/base", "http://localhost:8009")) {
    expect_identical(env$vm_ux_base_url(local), local)
  }
})

test_that("VM startup ayni 0.0.0.0:8009 topolojisini ve gercek ortam aktarimini korur", {
  env <- .vm_ux_functions()
  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = NA, MERGEN_ALLOW_NETWORK_UX_SMOKE = NA,
                     MERGEN_UX_SMOKE_PATH = NA, MERGEN_HOST = NA, MERGEN_PORT = NA,
                     MERGEN_RUN_APP = NA)
  config <- withr::local_tempdir()
  withr::local_dir(config)
  writeLines(c("SSO_ENABLED=TRUE", "MERGEN_ENABLE_UX_SMOKE=false"), ".Renviron")
  original_config <- readBin(".Renviron", "raw", file.info(".Renviron")$size)
  withr::local_envvar(SSO_ENABLED = NA)
  runtime <- file.path(config, "run")
  env$vm_ux_revision <- function() paste(rep("a", 40L), collapse = "")
  first <- NULL
  # source sonrasi .Renviron override'ina ragmen gecici opt-in sonradan verilir.
  env$source <- function(...) {
    expect_identical(Sys.getenv("SSO_ENABLED"), "TRUE")
    env$SSO_ENABLED <- TRUE
    Sys.setenv(MERGEN_ENABLE_UX_SMOKE = "false")
  }
  env$run_mergen_app <- function(host, port, ...) {
    expect_identical(host, "0.0.0.0")
    expect_identical(port, 8009L)
    first <<- env$vm_ux_read_prefix(runtime)
    expect_identical(Sys.getenv("MERGEN_UX_SMOKE_PATH"), first)
    expect_identical(Sys.getenv("MERGEN_ENABLE_UX_SMOKE"), "true")
    expect_identical(Sys.getenv("MERGEN_ALLOW_NETWORK_UX_SMOKE"), "true")
    expect_error(env$vm_ux_start_app(runtime), "already exists")
  }
  env$vm_ux_start_app(runtime)
  expect_identical(readBin(".Renviron", "raw", file.info(".Renviron")$size), original_config)
  expect_false(dir.exists(runtime))
  expect_error(env$vm_ux_read_prefix(runtime), "No active smoke startup")
  env$run_mergen_app <- function(...) {
    expect_false(identical(env$vm_ux_read_prefix(runtime), first))
    stop("simulated bind/boot failure")
  }
  expect_error(env$vm_ux_start_app(runtime), "simulated bind/boot failure")
  expect_false(dir.exists(runtime))
  dir.create(runtime)
  writeLines("../www", file.path(runtime, "prefix"))
  expect_error(env$vm_ux_read_prefix(runtime), "Invalid VM smoke handshake")
})

test_that("VM wrapper PASS icin rendered sonucu ister ve gecici env degerlerini geri alir", {
  env <- .vm_ux_functions()
  env$vm_ux_revision <- function() strrep("a", 40L)
  withr::local_dir(resolve_repo_root_for_tests())
  runtime <- withr::local_tempdir()
  prefix <- env$vm_ux_new_prefix()
  writeBin(charToRaw(paste0(prefix, "\n", env$vm_ux_revision(), "\n")), file.path(runtime, "prefix"))
  env$vm_ux_runtime_dir <- function() runtime
  profile <- withr::local_tempdir()
  withr::local_envvar(MERGEN_BROWSER_UX_BASE_URL = "https://app.example.invalid/base",
                     MERGEN_BROWSER_UX_PROFILE_DIR = profile, MERGEN_UX_SMOKE_PATH = NA,
                     MERGEN_ALLOW_NETWORK_UX_SMOKE = NA, MERGEN_BROWSER_BIN = "C:/mock/Edge/msedge.exe")
  answer <- "OK: rendered #status is UX_SMOKE_DONE:PASS.\n"
  status <- 0L
  testthat::local_mocked_bindings(run = function(command, args, ...) {
    expect_identical(Sys.getenv("MERGEN_UX_SMOKE_PATH"), prefix)
    expect_identical(Sys.getenv("MERGEN_ALLOW_NETWORK_UX_SMOKE"), "true")
    expect_false(any(grepl("app.example.invalid|__mergen_ux_", args)))
    expect_true("--require-browser" %in% args)
    expect_false("--vanilla" %in% args)
    expect_true("--no-environ" %in% args)
    list(status = status, stdout = answer, stderr = "")
  }, .package = "processx")
  expect_true(env$vm_ux_main(character()))
  expect_identical(Sys.getenv("MERGEN_UX_SMOKE_PATH", unset = "unset"), "unset")
  expect_identical(Sys.getenv("MERGEN_ALLOW_NETWORK_UX_SMOKE", unset = "unset"), "unset")
  for (wrong in c("", "HTTP 200", "UX_SMOKE_DONE:PASS", "SKIP", "<script>UX_SMOKE_DONE:PASS</script>")) {
    answer <- wrong
    expect_error(env$vm_ux_main(character()), "rendered UX_SMOKE_DONE:PASS is required")
  }
  answer <- "OK: rendered #status is UX_SMOKE_DONE:PASS.\n"
  status <- 1L
  expect_error(env$vm_ux_main(character()), "rendered UX_SMOKE_DONE:PASS is required")
  # Basarisiz asama tek izinli satirla aktarilir; ham cocuk ciktisi gizli kalir.
  failure <- "UX_SMOKE_FAILURE: browser_launch_failed rendered=empty exit=124 adapter=assign win32=5"
  answer <- paste(c("Smoke URL: https://app.example.invalid/base/__mergen_ux_x/ux-smoke.html",
                    "Owned browser launch or cleanup failed (stage=assign, win32=5).", failure,
                    "--- browser stderr tail ---", "D:/gizli-profil/MERGEN/BrowserUxSmoke"),
                  collapse = "\n")
  out <- capture.output(expect_error(env$vm_ux_main(character()), "rendered UX_SMOKE_DONE:PASS is required"))
  expect_identical(out, failure)
  # Sozluk disi deger (onek, yol, URL) tasiyan satir aktarilmaz.
  for (forged in c(paste0("UX_SMOKE_FAILURE: browser_launch_failed adapter=", prefix),
                   "UX_SMOKE_FAILURE: browser_launch_failed adapter=D:/gizli-profil",
                   "UX_SMOKE_FAILURE: https://app.example.invalid/base",
                   "UX_SMOKE_FAILURE: browser_launch_failed adapter=assign extra text")) {
    answer <- forged
    out <- capture.output(expect_error(env$vm_ux_main(character()), "rendered UX_SMOKE_DONE:PASS is required"))
    expect_identical(out, "UX_SMOKE_FAILURE: unclassified")
  }
  # Siniflandirma basarisizligi asla PASS'e donusmez.
  answer <- paste("OK: rendered #status is UX_SMOKE_DONE:PASS.", failure, sep = "\n")
  status <- 1L
  expect_output(expect_error(env$vm_ux_main(character()), "rendered UX_SMOKE_DONE:PASS is required"), failure, fixed = TRUE)
})

test_that("generic browser VM akisinda yerel preflight ve dis URL ayri kullanilir; artifact redakte edilir", {
  withr::local_dir(resolve_repo_root_for_tests())
  env <- new.env(parent = globalenv())
  prefix <- .vm_ux_functions()$vm_ux_new_prefix()
  profile <- withr::local_tempdir()
  artifact <- withr::local_tempdir()
  binary <- tempfile(); writeLines("mock browser", binary)
  withr::defer(unlink(binary))
  base <- "https://private.example.invalid/base"
  withr::local_envvar(MERGEN_BROWSER_UX_BASE_URL = base, MERGEN_UX_SMOKE_PATH = prefix,
                     MERGEN_ALLOW_NETWORK_UX_SMOKE = "true", MERGEN_BROWSER_BIN = binary,
                     MERGEN_BROWSER_UX_PROFILE_DIR = profile)
  port <- "8017"
  env$commandArgs <- function(...) c("--artifact-dir", artifact, "--port", port)
  env$quit <- function(status) stop(structure(list(message = "runner exit", status = status), class = c("runner_exit", "error", "condition")))
  requests <- character()
  browser_url <- NULL
  browser_profile <- NULL
  browser_dom <- paste0('<div id="status">UX_SMOKE_DONE:PASS</div><a href="', base,
                       '/', prefix, '/x">x</a> https://private.example.invalid/redirect https://sso.example.invalid/auth')
  browser_run <- function(command, args, ...) {
    expect_true("--timeout=160000" %in% args)
    expect_false(any(startsWith(args, "--virtual-time-budget")))
    browser_url <<- tail(args, 1)
    browser_profile <<- sub("--user-data-dir=", "", args[startsWith(args, "--user-data-dir=")], fixed = TRUE)
    list(status = 0L, stdout = browser_dom,
         stderr = paste(base, utils::URLencode(base, reserved = TRUE), prefix, browser_profile,
                        chartr("/", "\\", browser_profile), encodeString(browser_profile, quote = "")))
  }
  expressions <- parse_r_file_utf8("tests/scripts/ai_browser_ux_smoke.R")
  run <- function() {
    for (e in expressions) {
      if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("read_url"))) {
        env$read_url <- function(target) {
          requests <<- c(requests, target)
          '<title>MERGEN UX Smoke</title><div id="status">Ready</div>'
        }
      } else {
        # Surec isletimi ayri gercek job testinde; burada uretim adapter siniri sahtelenir.
        if (is.call(e) && identical(e[[1]], as.name("quit"))) {
          env$ux_smoke_owned_browser_run <- browser_run
        }
        eval(e, env)
      }
    }
  }
  result <- tryCatch(run(), runner_exit = function(e) e)
  expect_identical(result$status, 0L)
  expect_identical(browser_url, paste0(base, "/", prefix, "/ux-smoke.html?autostart=1"))
  expect_identical(requests, c("http://127.0.0.1:8017", paste0("http://127.0.0.1:8017/", prefix, "/ux-smoke.html")))
  port <- "8009"
  logs <- paste(vapply(list.files(artifact, full.names = TRUE), read_source_text_utf8, character(1)), collapse = "\n")
  expect_false(grepl("private.example.invalid|sso.example.invalid|__mergen_ux_[0-9a-f]{48}", logs))
  expect_match(logs, "<MERGEN_BROWSER_UX_BASE_URL>", fixed = TRUE)
  expect_false(grepl(profile, logs, fixed = TRUE))
  expect_true(dir.exists(profile))
  # SSO formu ve hatta PASS statusu tasiyan hassas DOM hicbir zaman saklanmaz.
  for (dom in c('<form><input type="hidden" name="session_code" value="flow-state-sentinel"></form>',
                '<div id="status">UX_SMOKE_DONE:PASS</div><input name="state" value="flow-state-sentinel">')) {
    browser_dom <- dom
    Sys.unsetenv("MERGEN_BROWSER_UX_PROFILE_DIR")
    result <- tryCatch(run(), runner_exit = function(e) e)
    expect_identical(result$status, if (grepl('id="status"', dom, fixed = TRUE)) 0L else 1L)
    expect_false(dir.exists(browser_profile), info = "gecici profil basari ve hata sonunda temizlenir")
    logs <- paste(vapply(list.files(artifact, full.names = TRUE), read_source_text_utf8, character(1)), collapse = "\n")
    expect_false(grepl("flow-state-sentinel|session_code|<input|<form", logs))
    expect_false(grepl(browser_profile, logs, fixed = TRUE))
  }
})

test_that("Edge profil ilkesi dogrulanamazsa tarayici kapali kalir, ilke degeri yazilmaz", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "tests/scripts/helpers_browser_ux_profile.R"), local = env)
  answer <- list(status = 0L, stdout = "UX_SMOKE_EDGE_POLICY_OK\n", stderr = "")
  testthat::local_mocked_bindings(run = function(command, args, ...) {
    expect_identical(command, "powershell.exe")
    script <- tail(args, 1)
    for (token in c("UserDataDir", "LocalMachine", "CurrentUser", "Registry64", "Registry32", "GetValueNames")) {
      expect_match(script, token, fixed = TRUE)
    }
    answer
  }, .package = "processx")
  expect_true(env$ux_smoke_check_edge_policy(windows = TRUE))
  for (result in list(list(status = 2L, stdout = "sensitive-policy-value"),
                      list(status = 3L, stdout = ""), list(status = 0L, stdout = ""))) {
    answer <- result
    expect_error(env$ux_smoke_check_edge_policy(windows = TRUE), "No browser was launched", fixed = TRUE)
  }
})

test_that("VM belge ve kaynaklarda onayli URL runtime girdisidir, sabit ag smoke yolu yoktur", {
  root <- resolve_repo_root_for_tests()
  doc <- read_source_text_utf8(file.path(root, "docs/vm-browser-ux-smoke.md"))
  runner <- read_source_text_utf8(file.path(root, "tests/scripts/run_vm_browser_ux_smoke.R"))
  expect_match(doc, "0.0.0.0:8009", fixed = TRUE)
  expect_match(doc, "Read-Host", fixed = TRUE)
  expect_match(doc, "app.example.invalid", fixed = TRUE)
  expect_match(doc, "--start-app", fixed = TRUE)
  expect_false(grepl("/smoke/ux-smoke.html", runner, fixed = TRUE))
  expect_false(any(grepl("write.*[.]Renviron", strsplit(runner, "\n", fixed = TRUE)[[1]])))
  expect_match(doc, "source('tests/scripts/run_vm_evidence_gate.R', encoding='UTF-8')", fixed = TRUE)
  expect_false(grepl("R-4.6.0", doc, fixed = TRUE))
  expect_match(doc, "$env:MERGEN_RSCRIPT", fixed = TRUE)
  expect_match(doc, "Get-Command Rscript.exe", fixed = TRUE)
  expect_match(doc, "UserDataDir", fixed = TRUE)
  expect_match(doc, "Görev Yöneticisi", fixed = TRUE)
  expect_match(doc, "ortam dosyaları shell değerlerini ezebilir", fixed = TRUE)
  for (command in strsplit(doc, "\n", fixed = TRUE)[[1]]) {
    if (startsWith(command, "& $rscript")) expect_false(grepl("--vanilla|--no-init-file|--no-environ", command))
  }
  runbook <- read_source_text_utf8(file.path(root, "RUNBOOK.md"))
  technical <- read_source_text_utf8(file.path(root, "docs/technical-reference.md"))
  expect_false(grepl("port=28081|127.0.0.1:28081|28081/smoke/", paste(runbook, technical)))
  expect_match(runbook, "docs/vm-browser-ux-smoke.md", fixed = TRUE)
  expect_match(runbook, "& $rscript tests/scripts/run_vm_browser_ux_smoke.R", fixed = TRUE)
  expect_false(grepl("`Rscript tests/scripts/run_vm_browser_ux_smoke.R`", runbook, fixed = TRUE))
  workflow <- strsplit(runbook, "#### Standart tam evidence gate komutu", fixed = TRUE)[[1]][[2]]
  workflow <- strsplit(workflow, "#### Full isolated testthat davranışı", fixed = TRUE)[[1]][[1]]
  expect_false(grepl("R-4.6.0", workflow, fixed = TRUE))
  expect_match(technical, "vm-browser-ux-smoke.md", fixed = TRUE)
  for (guide in c(doc, runbook)) {
    expect_match(guide, "MERGEN_EVIDENCE_PROFILE=cloud", fixed = TRUE)
    expect_match(guide, "Renviron.site", fixed = TRUE)
    expect_match(guide, "Sys.setenv(MERGEN_EVIDENCE_PROFILE='vm', MERGEN_RSCRIPT_BIN=file.path(R.home('bin'), 'Rscript.exe'))", fixed = TRUE)
  }
  for (url in regmatches(doc, gregexpr("https://[^`[:space:]]+", doc))[[1]]) {
    expect_match(url, "https://app.example.invalid", fixed = TRUE)
  }
})

test_that("VM komutu profili R baslangicindan sonra secer ve ortam dosyalarini korur", {
  root <- resolve_repo_root_for_tests()
  guides <- lapply(c("docs/vm-browser-ux-smoke.md", "RUNBOOK.md"), function(path) {
    lines <- strsplit(read_source_text_utf8(file.path(root, path)), "\n", fixed = TRUE)[[1]]
    lines[startsWith(lines, '& $rscript -e "') & grepl("run_vm_evidence_gate.R", lines, fixed = TRUE)]
  })
  expect_length(guides[[1]], 1L)
  expect_identical(guides[[1]], guides[[2]])
  command <- guides[[1]][[1]]
  expect_true(endsWith(command, '" --full'))
  expr <- substr(command, nchar('& $rscript -e "') + 1L, nchar(command) - nchar('" --full'))
  # Belge Windows komutudur; Linux cocugunda yalniz calistirilabilir son eki uyarlanir.
  if (.Platform$OS.type != "windows") expr <- sub("'Rscript.exe'", "'Rscript'", expr, fixed = TRUE)
  # Gercek gate'in ortam yukleyicisi/profil karari; agir kanit adimlari kosulmaz.
  selected <- c("evidence_load_repo_renviron", "repo_renviron_loaded", "evidence_env_flag_true",
                "profile_requested", "profile_effective", "full_evidence", "rscript_bin")
  gate <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                   as.character(e[[2]]) %in% selected,
                 as.list(parse_r_file_utf8(file.path(root, "tests/scripts/run_vm_evidence_gate.R"))))
  fixture <- withr::local_tempdir()
  withr::local_dir(fixture)
  dir.create("tests/scripts", recursive = TRUE)
  writeLines(c(paste(".vm_ux_executable_identity <-", paste(deparse(.vm_ux_executable_identity), collapse = "\n")),
               unlist(lapply(gate, deparse)),
               'active_rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")',
               'stopifnot(profile_effective == "vm", full_evidence, isTRUE(getOption("vm.profile.loaded")), identical(.vm_ux_executable_identity(rscript_bin), .vm_ux_executable_identity(active_rscript)))',
               'cat(profile_effective)'), "tests/scripts/run_vm_evidence_gate.R")
  user_env <- file.path(fixture, ".Renviron")
  site_env <- file.path(fixture, "Renviron.site")
  profile <- file.path(fixture, "fixture.Rprofile")
  writeLines("options(vm.profile.loaded = TRUE)", profile)
  writeLines(character(), site_env)
  withr::local_envvar(MERGEN_EVIDENCE_PROFILE = "vm", MERGEN_RSCRIPT_BIN = "stale-shell-Rscript", R_ENVIRON_USER = user_env,
                     R_ENVIRON = site_env, R_PROFILE_USER = profile, R_PROFILE = profile)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  run_r <- function(expression, args = character()) {
    out <- system2(rscript, c("-e", shQuote(expression), args), stdout = TRUE, stderr = TRUE)
    expect_null(attr(out, "status"))
    paste(out, collapse = "\n")
  }
  for (where in c("user", "site")) {
    writeLines(if (where == "user") c("MERGEN_EVIDENCE_PROFILE=cloud", "MERGEN_RSCRIPT_BIN=stale-Rscript") else character(), user_env)
    writeLines(if (where == "site") c("MERGEN_EVIDENCE_PROFILE=cloud", "MERGEN_RSCRIPT_BIN=stale-Rscript") else character(), site_env)
    before <- lapply(c(user_env, site_env), function(path) readBin(path, "raw", file.info(path)$size))
    expect_identical(run_r("cat(Sys.getenv('MERGEN_EVIDENCE_PROFILE'))"), "cloud")
    expect_identical(run_r(expr, "--full"), "vm")
    expect_identical(lapply(c(user_env, site_env), function(path) readBin(path, "raw", file.info(path)$size)), before)
  }
  expect_identical(Sys.getenv("MERGEN_EVIDENCE_PROFILE"), "vm")
})


test_that("network startup eksik veya kapali SSO ile app.R kaynaklamadan durur", {
  env <- .vm_ux_functions()
  env$vm_ux_revision <- function() strrep("a", 40L)
  withr::local_dir(withr::local_tempdir())
  withr::local_envvar(SSO_ENABLED = NA)
  runtime <- file.path(getwd(), "run")
  env$source <- function(...) stop("app.R must not be sourced")
  for (value in c(NA_character_, "FALSE", "", "invalid")) {
    if (is.na(value)) unlink(".Renviron") else writeLines(paste0("SSO_ENABLED=", value), ".Renviron")
    Sys.unsetenv("SSO_ENABLED")
    expect_error(env$vm_ux_start_app(runtime), "requires SSO_ENABLED=TRUE", fixed = TRUE)
    expect_false(dir.exists(runtime))
  }
  writeLines("SSO_ENABLED=TRUE", ".Renviron")
  env$source <- function(...) { env$SSO_ENABLED <- FALSE }
  expect_error(env$vm_ux_start_app(runtime), "requires active application SSO", fixed = TRUE)
  expect_false(dir.exists(runtime))
})

test_that("normal Rscript startup proje profili ve SSO konfigurasyonunu korur", {
  root <- resolve_repo_root_for_tests()
  fixture <- withr::local_tempdir()
  dir.create(file.path(fixture, "tests/scripts"), recursive = TRUE)
  dir.create(file.path(fixture, "R"))
  dir.create(file.path(fixture, "project-library"))
  file.copy(file.path(root, "tests/scripts/run_vm_browser_ux_smoke.R"), file.path(fixture, "tests/scripts"))
  expect_true(file.copy(file.path(root, "tests/scripts/helpers_evidence_checkout.R"), file.path(fixture, "tests/scripts")))
  file.copy(file.path(root, "R/config_sso.R"), file.path(fixture, "R"))
  writeLines(c("/startup.stdout", "/startup.stderr", "/startup-result.txt", "/startup-revision.txt"),
             file.path(fixture, ".gitignore"))
  writeLines(c("SSO_ENABLED=TRUE", "SSO_KEYCLOAK_URL=https://sso.example.invalid",
               "MERGEN_ENABLE_UX_SMOKE=false", "MERGEN_ALLOW_NETWORK_UX_SMOKE=false"), file.path(fixture, ".Renviron"))
  writeLines('.libPaths(c("project-library", .libPaths()))', file.path(fixture, ".Rprofile"))
  writeLines(c(
    'log_info <- function(...) invisible(NULL)',
    'source("R/config_sso.R", encoding = "UTF-8")',
    'stopifnot(SSO_ENABLED, basename(.libPaths()[1]) == "project-library")',
    'run_mergen_app <- function(host, port, ...) {',
    '  stopifnot(host == "0.0.0.0", port == 8009L, SSO_ENABLED,',
    '            Sys.getenv("MERGEN_ENABLE_UX_SMOKE") == "true",',
    '            Sys.getenv("MERGEN_ALLOW_NETWORK_UX_SMOKE") == "true")',
    '  writeLines("configured SSO startup", "startup-result.txt")',
    '  # El sikismasindaki atif alanini disaridan gozlemlemek icin kaydet.',
    '  handshake <- file.path(Sys.getenv("LOCALAPPDATA"), "MERGEN", "BrowserUxSmokeRun", "prefix")',
    '  writeLines(readLines(handshake)[[2]], "startup-revision.txt")',
    '}'
  ), file.path(fixture, "app.R"))
  before <- readBin(file.path(fixture, ".Renviron"), "raw", 10000L)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  runtime <- withr::local_tempdir()
  withr::local_envvar(LOCALAPPDATA = runtime,
                     R_ENVIRON_USER = file.path(fixture, ".Renviron"),
                     R_PROFILE_USER = file.path(fixture, ".Rprofile"))
  withr::local_dir(fixture)
  start_app <- function() {
    unlink(c("startup-result.txt", "startup-revision.txt"))
    status <- system2(rscript, c("--encoding=UTF-8", "tests/scripts/run_vm_browser_ux_smoke.R", "--start-app"),
                      stdout = "startup.stdout", stderr = "startup.stderr", timeout = 30)
    expect_identical(status, 0L, info = paste(readLines("startup.stderr"), collapse = "\n"))
    expect_identical(readLines("startup-result.txt"), "configured SSO startup")
    expect_identical(readBin(file.path(fixture, ".Renviron"), "raw", 10000L), before)
    expect_false(dir.exists(file.path(runtime, "MERGEN/BrowserUxSmokeRun")))
    readLines("startup-revision.txt")
  }
  # GitHub kaynak ZIP'i: .git yokken uygulama normal topoloji ve SSO ile baslar, SHA uydurulmaz.
  expect_false(file.exists(".git"))
  expect_identical(start_app(), "unattributed")
  if (!nzchar(Sys.which("git"))) {
    if (!file.exists(file.path(root, ".git"))) {
      skip("Git metadata'si olmayan dagitim kopyasinda Git atfi CI/source checkout'unda dogrulanir")
    }
    fail("git kullanilamiyor; dogrulanmis checkout atfi denetlenemedi")
  }
  processx::run("git", c("init", "--quiet"), wd = fixture)
  processx::run("git", c("add", "."), wd = fixture)
  processx::run("git", c("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                        "commit", "--quiet", "-m", "VM startup fixture"), wd = fixture)
  expect_identical(processx::run("git", c("status", "--porcelain"))$stdout, "")
  # Dogrulanmis temiz checkout tam SHA'yi el sikismasina baglar.
  head <- trimws(processx::run("git", c("rev-parse", "HEAD"))$stdout)
  expect_identical(start_app(), head)
  expect_identical(processx::run("git", c("status", "--porcelain"))$stdout, "")
  # Kirli checkout uygulamayi engellemez; yalniz commit atfi dusurulur.
  writeLines("kirli girdi", "dirty-checkout.txt")
  expect_identical(start_app(), "unattributed")
})

test_that("gecici UX PASS yeniden baslatilan uretim surecinin kaniti sayilmaz", {
  root <- resolve_repo_root_for_tests()
  for (file in c("RUNBOOK.md", "docs/vm-browser-ux-smoke.md")) {
    text <- read_source_text_utf8(file.path(root, file))
    expect_match(text, "üretim sürecini doğrulamaz", fixed = TRUE)
    expect_match(text, "Normal uygulama geçici smoke yolunu sunmamalıdır.", fixed = TRUE)
    expect_match(text, "run_post_deploy_smoke.R", fixed = TRUE)
  }
})


test_that("VM el sıkışması başlangıç revizyonuna bağlıdır ve bozuk kayıtlar kapalı kalır", {
  env <- .vm_ux_functions()
  runtime <- withr::local_tempdir()
  prefix <- env$vm_ux_new_prefix()
  revision <- strrep("a", 40L)
  env$vm_ux_revision <- function() revision
  path <- file.path(runtime, "prefix")
  write <- function(value) writeBin(charToRaw(value), path)
  record <- paste0(prefix, "\n", revision, "\n")
  write(record)
  expect_identical(env$vm_ux_read_prefix(runtime), prefix)
  revision <- strrep("b", 40L)
  expect_error(env$vm_ux_read_prefix(runtime), "restart --start-app in Window 1", fixed = TRUE)
  revision <- strrep("a", 40L)
  for (bad in c(prefix, paste0(prefix, "\ninvalid\n"), paste0(record, "extra\n"),
                paste0(prefix, "\n", strrep("a", 41L)), strrep("a", 10000L))) {
    write(bad)
    expect_error(env$vm_ux_read_prefix(runtime), "Invalid VM smoke handshake", fixed = TRUE)
  }
  writeBin(as.raw(c(0L, 10L)), path)
  expect_error(env$vm_ux_read_prefix(runtime), "Invalid VM smoke handshake", fixed = TRUE)
  # Atifsiz (ZIP) baslangic yalniz yine atifsiz agacla eslesir; SHA iddiasiyla karismaz.
  revision <- "unattributed"
  write(paste0(prefix, "\nunattributed\n"))
  expect_identical(env$vm_ux_read_prefix(runtime), prefix)
  revision <- strrep("a", 40L)
  expect_error(env$vm_ux_read_prefix(runtime), "restart --start-app in Window 1", fixed = TRUE)
  revision <- "unattributed"
  write(record)
  expect_error(env$vm_ux_read_prefix(runtime), "restart --start-app in Window 1", fixed = TRUE)
  write(paste0(prefix, "\nUNATTRIBUTED\n"))
  expect_error(env$vm_ux_read_prefix(runtime), "Invalid VM smoke handshake", fixed = TRUE)
})

test_that("VM başlangıcı source sırasında değişen revizyonla el sıkışması yayımlamaz", {
  env <- .vm_ux_functions()
  config <- withr::local_tempdir()
  withr::local_dir(config)
  withr::local_envvar(SSO_ENABLED = "TRUE", MERGEN_RUN_APP = NA, MERGEN_ENABLE_UX_SMOKE = NA,
                     MERGEN_ALLOW_NETWORK_UX_SMOKE = NA, MERGEN_UX_SMOKE_PATH = NA,
                     MERGEN_HOST = NA, MERGEN_PORT = NA)
  revision <- strrep("a", 40L)
  env$vm_ux_revision <- function() revision
  env$source <- function(...) { env$SSO_ENABLED <- TRUE; revision <<- strrep("b", 40L) }
  env$run_mergen_app <- function(...) stop("uygulama başlamamalı")
  runtime <- file.path(config, "run")
  expect_error(env$vm_ux_start_app(runtime), "Checkout changed during startup", fixed = TRUE)
  expect_false(dir.exists(runtime))
})

test_that("VM revizyonu yalniz dogrulanmis temiz checkout icin SHA atfeder, digerlerinde baslatmayi engellemez", {
  root <- resolve_repo_root_for_tests()
  tree <- withr::local_tempdir()
  dir.create(file.path(tree, "tests/scripts"), recursive = TRUE)
  file.copy(file.path(root, "tests/scripts/helpers_evidence_checkout.R"), file.path(tree, "tests/scripts"))
  env <- .vm_ux_functions()
  withr::local_dir(tree)
  # Kaynak ZIP'i: .git yok, Git cagrilmaz, SHA uydurulmaz.
  env$system2 <- function(...) stop("Git metadatasi yokken git cagrilmamali")
  expect_identical(env$vm_ux_revision(), "unattributed")
  dir.create(".git")
  dirty <- character()
  env$system2 <- function(command, args, ...) {
    if (args[[1]] == "status") dirty else strrep("a", 40L)
  }
  expect_identical(env$vm_ux_revision(), strrep("a", 40L))
  # Kirli/incelenemeyen checkout calisir ama commit atfi tasimaz.
  for (value in list(" M tracked.R", "?? untracked.R", structure(character(), status = 128L))) {
    dirty <- value
    expect_identical(env$vm_ux_revision(), "unattributed")
  }
})


test_that("VM belgesi tarihli kanıtı güncel HEAD kanıtından ve adım filtresini ortamdan ayırır", {
  root <- resolve_repo_root_for_tests()
  for (file in c("README.md", "docs/vm-evidence-status.md")) {
    text <- read_source_text_utf8(file.path(root, file))
    expect_match(text, "31 Ekim 2026", fixed = TRUE)
    expect_match(text, "13 passed, 0 failed, 0 skipped", fixed = TRUE)
    expect_match(text, "güncel HEAD", fixed = TRUE)
    expect_match(text, "VM koşumu tekrarlanmalıdır", fixed = TRUE)
  }
  text <- read_source_text_utf8(file.path(root, "RUNBOOK.md"))
  expect_match(text, "yalnız `.Renviron` veya shell içindeki `MERGEN_EVIDENCE_STEPS` adım filtresi yok sayılır", fixed = TRUE)
  expect_match(text, "`.Renviron` yüklenir; gerekli gerçek runtime yapılandırması sağlanmalıdır", fixed = TRUE)
})

test_that("belgeler kaynak ZIP akisini destekler ve commit atfini ayri tutar", {
  root <- resolve_repo_root_for_tests()
  for (file in c("RUNBOOK.md", "docs/vm-browser-ux-smoke.md", "docs/vm-evidence-status.md")) {
    text <- read_source_text_utf8(file.path(root, file))
    expect_match(text, "desteklenen VM test girdisidir", fixed = TRUE)
    expect_match(text, "`git.commit_attributed = false`", fixed = TRUE)
  }
})

test_that("VM kosucusu Windows'ta hazir Edge profili icin yalniz msedge.exe kabul eder", {
  env <- .vm_ux_functions()
  for (bin in c("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
                "C:\\Users\\x\\AppData\\Local\\Microsoft\\Edge\\Application\\MSEDGE.EXE")) {
    expect_identical(env$vm_ux_require_edge(bin, windows = TRUE), bin)
  }
  # Eski/yanlis override Chrome'u secip Edge ilke denetimini atlayamaz.
  for (bin in c("C:/Program Files/Google/Chrome/Application/chrome.exe", "chromium", "",
                "C:/tools/msedge.exe.bak", "C:/msedge.exe/chrome.exe")) {
    expect_error(env$vm_ux_require_edge(bin, windows = TRUE), "requires Microsoft Edge (msedge.exe)", fixed = TRUE)
  }
  # Windows disi yerel gelistirici kosumlari etkilenmez.
  expect_identical(env$vm_ux_require_edge("/usr/bin/chromium", windows = FALSE), "/usr/bin/chromium")
})

test_that("Windows profil redaksiyonu harf buyuklugune duyarsiz ve yol karakterlerini harfiyen esler", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "tests/scripts/helpers_browser_ux_profile.R"),
         local = env, encoding = "UTF-8")
  withr::local_envvar(USERPROFILE = "", LOCALAPPDATA = "")
  profile <- "C:\\Gizli\\Op.Er\\MERGEN\\BrowserUxSmoke (1)+[x]"
  text <- paste("a", toupper(profile), "b", tolower(chartr("\\", "/", profile)), "c", profile)
  # Edge yolu farkli harf buyuklugu veya ayiriciyla yazsa da sizmaz.
  expect_identical(env$ux_smoke_redact_profile(text, profile, windows = TRUE),
                   "a <BROWSER_PROFILE> b <BROWSER_PROFILE> c <BROWSER_PROFILE>")
  # Nokta/parantez gibi karakterler regex olarak genisletilmez.
  expect_identical(env$ux_smoke_redact_profile("C:\\Gizli\\OpXEr", profile, windows = TRUE), "C:\\Gizli\\OpXEr")
  # Windows disinda yollar harf duyarli kalir.
  expect_match(env$ux_smoke_redact_profile(text, profile, windows = FALSE), toupper(profile), fixed = TRUE)
})
