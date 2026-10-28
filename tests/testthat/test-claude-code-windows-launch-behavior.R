# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-windows-launch-behavior.R
# Açıklama: Bilge Yolaç CLI süreç sınırı. Çağıranın istem metni hiçbir zaman
#           cmd.exe komut kaynağı olmaz: npm .cmd betiği gerçek hedefine
#           (node.exe + cli.js veya claude.exe) çözülür ve argümanlar processx
#           argüman vektörüyle gider. Davranış testi sahte bir npm kurulumundaki
#           cli.js'yi GERÇEKTEN başlatır; cli.js aldığı argv'yi yazar. Windows
#           VM'de bu, gerçek CreateProcessW tırnaklama/ortam semantiğini sınar:
#           %DEĞİŞKEN%, !DEĞİŞKEN!, &, |, ^, <, >, tırnak ve satır sonları CLI'ye
#           harfiyen ulaşmalı, API anahtarı istem metnine genişlememelidir.
# ==============================================================================

.cc_launch_env <- function(platform = .Platform$OS.type) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$log_info <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$claude_code_config <- list(default_workdir = "")
  root <- resolve_repo_root_for_tests()
  sys.source(file.path(root, "R", "utils_text_encoding.R"), envir = env, keep.source = FALSE)
  sys.source(file.path(root, "R", "helpers_claude_code_process.R"), envir = env, keep.source = FALSE)
  sys.source(file.path(root, "R", "helpers_claude_code_api_key.R"), envir = env, keep.source = FALSE)
  env$.Platform <- list(OS.type = platform, file.sep = "/")
  env
}

# npm'in Windows'ta ürettiği cmd-shim düzeni (betik metni gerçek npm çıktısıyla aynı kalıpta).
.cc_fake_npm <- function(dir, target = c("js", "exe", "legacy")) {
  target <- match.arg(target)
  paket <- file.path(dir, "node_modules", "@anthropic-ai", "claude-code")
  dir.create(paket, recursive = TRUE, showWarnings = FALSE)
  cli <- file.path(paket, "cli.js")
  writeLines(c(
    "const fs = require('fs');",
    "const hex = s => Buffer.from(s, 'utf8').toString('hex');",
    "fs.writeSync(2, JSON.stringify({ argv: process.argv.slice(2).map(hex), cwd: hex(process.cwd()) }));",
    "fs.writeSync(1, JSON.stringify({ argv: process.argv.slice(2), cwd: process.cwd(),",
    "  sizinti: (process.env.ANTHROPIC_AUTH_TOKEN || '') }));"
  ), cli)
  shim <- switch(target,
    js = c(
      "@ECHO off", "GOTO start", ":find_dp0", "SET dp0=%~dp0", "EXIT /b", ":start", "SETLOCAL", "CALL :find_dp0", "",
      "IF EXIST \"%dp0%\\node.exe\" (", "  SET \"_prog=%dp0%\\node.exe\"", ") ELSE (", "  SET \"_prog=node\"",
      "  SET PATHEXT=%PATHEXT:;.JS;=;%", ")", "",
      "endLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & \"%_prog%\"  \"%dp0%\\node_modules\\@anthropic-ai\\claude-code\\cli.js\" %*"
    ),
    legacy = c(
      "@IF EXIST \"%~dp0\\node.exe\" (",
      "  \"%~dp0\\node.exe\"  \"%~dp0\\node_modules\\@anthropic-ai\\claude-code\\cli.js\" %*",
      ") ELSE (", "  @SETLOCAL", "  node  \"%~dp0\\node_modules\\@anthropic-ai\\claude-code\\cli.js\" %*", ")"
    ),
    exe = c("@ECHO off", "\"%dp0%\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe\"   %*")
  )
  if (identical(target, "exe")) {
    dir.create(file.path(paket, "bin"), showWarnings = FALSE)
    file.create(file.path(paket, "bin", "claude.exe"))
  }
  writeLines(shim, file.path(dir, "claude.cmd"))
  list(shim = file.path(dir, "claude.cmd"), cli = cli)
}

.cc_utf8_hex <- function(x) {
  vapply(enc2utf8(x), function(s) paste(format(charToRaw(s)), collapse = ""),
         character(1), USE.NAMES = FALSE)
}

.cc_hostile_prompts <- function() {
  c(
    "%ANTHROPIC_AUTH_TOKEN% %PATH% %COMSPEC%",
    "!ANTHROPIC_AUTH_TOKEN! ^& calc.exe & whoami | more > pwned.txt < nul",
    "\"; echo kacis & \" ' `x` $(id) $HOME",
    "satır1\nsatır2\r\n%USERPROFILE%",
    paste0("T", intToUtf8(c(0x00FC, 0x0072, 0x006B, 0x00E7, 0x0065)), " \\\\sunucu\\pay\\ \"%~dp0\" %%"),
    intToUtf8(c(0x011F, 0x015F, 0x0130, 0x0131, 0x00E7)),
    "C:\\Program Files\\ \\\" \\\\\" son\\"
  )
}

test_that("npm .cmd betiği kabuksuz hedefine çözülür (modern, eski ve .exe kalıpları)", {
  env <- .cc_launch_env("windows")
  for (kalip in c("js", "legacy")) {
    npm <- .cc_fake_npm(withr::local_tempdir(), kalip)
    file.create(file.path(dirname(npm$shim), "node.exe"))
    hedef <- env$cc_resolve_windows_cli_shim(npm$shim)
    expect_identical(basename(hedef$command), "node.exe", info = kalip)
    expect_identical(hedef$prefix_args, normalizePath(npm$cli, winslash = "/"), info = kalip)
  }
  npm <- .cc_fake_npm(withr::local_tempdir(), "exe")
  hedef <- env$cc_resolve_windows_cli_shim(npm$shim)
  expect_identical(basename(hedef$command), "claude.exe")
  expect_identical(hedef$prefix_args, character(0))
})

test_that("çözülemeyen .cmd betiği cmd.exe'ye düşmeden başlatmayı reddeder", {
  env <- .cc_launch_env("windows")
  dizin <- withr::local_tempdir()
  # Hedef bulunmayan, ya da yorumlayıcı/hedef sabit argümanı taşıyan (korunamayacak)
  # betikler reddedilir.
  dizin_hedef <- file.path(dizin, "node_modules", "pkg")
  dir.create(dizin_hedef, recursive = TRUE)
  file.create(file.path(dizin_hedef, "cli.js"))
  hedef_yolu <- "\"%dp0%\\node_modules\\pkg\\cli.js\""
  for (icerik in list(c("@echo off", "powershell -c %*"), c("@echo off", "\"%dp0%\\yok\\cli.js\" %*"),
                      c("@echo off", paste0("\"%_prog%\" --require ./init.js ", hedef_yolu, " %*")),
                      c("@echo off", paste0("\"%_prog%\" ", hedef_yolu, " --sabit %*")))) {
    writeLines(icerik, file.path(dizin, "claude.cmd"))
    expect_error(env$build_processx_command(file.path(dizin, "claude.cmd"), c("-p", "x")),
                 "Bilge Yola")
  }
  expect_error(env$build_processx_command(file.path(dizin, "yok.cmd"), "x"), "Bilge Yola")
})

test_that("Windows komutu argüman vektörüdür; cmd.exe ve komut satırı birleştirmesi yoktur", {
  env <- .cc_launch_env("windows")
  npm <- .cc_fake_npm(withr::local_tempdir(), "js")
  file.create(file.path(dirname(npm$shim), "node.exe"))
  istemler <- .cc_hostile_prompts()
  komut <- env$build_processx_command(npm$shim, c("-p", "--", istemler[1]), workdir = "/rehisds/proje")
  expect_identical(basename(komut$command), "node.exe")
  expect_identical(komut$args, c(normalizePath(npm$cli, winslash = "/"), "-p", "--", istemler[1]))
  expect_false(isTRUE(komut$windows_verbatim_args))
  expect_identical(komut$wd, "//rehisds/proje")
  expect_true(any(tolower(names(komut$env)) == "path"))
})

test_that("doğrudan cli.js başlatması PATH dışındaki node dizinini çocuk PATH'ine ekler", {
  env <- .cc_launch_env("windows")
  npm <- .cc_fake_npm(withr::local_tempdir(), "js")
  node_dizini <- withr::local_tempdir()
  file.create(file.path(node_dizini, "node.exe"))
  withr::local_envvar(CLAUDE_CODE_NODE_PATH = file.path(node_dizini, "node.exe"))
  komut <- env$build_processx_command(npm$cli, c("-p", "x"), workdir = "/rehisds/proje")
  expect_identical(komut$command, normalizePath(file.path(node_dizini, "node.exe"), winslash = "/"))
  expect_identical(komut$args, c(normalizePath(npm$cli, winslash = "/"), "-p", "x"))
  expect_identical(komut$wd, "//rehisds/proje")
  path_adi <- names(komut$env)[tolower(names(komut$env)) == "path"][1]
  ilk <- strsplit(unname(komut$env[[path_adi]]), ";", fixed = TRUE)[[1]][1]
  expect_identical(ilk, normalizePath(node_dizini, winslash = "\\"))

  # PATH'te yalnız adı önek olan başka dizin (node-old) varsa yine eklenir;
  # aynı dizin başka yazımla (/, büyük harf, sondaki ayraç) zaten varsa yinelenmez.
  hedef <- normalizePath(node_dizini, winslash = "\\")
  withr::with_envvar(c(PATH = paste0(hedef, "-old;C:\\Windows")), {
    yol <- unname(env$build_processx_command(npm$cli, "x")$env[["PATH"]])
    expect_identical(strsplit(yol, ";", fixed = TRUE)[[1]], c(hedef, paste0(hedef, "-old"), "C:\\Windows"))
  })
  withr::with_envvar(c(PATH = paste0(toupper(gsub("\\", "/", hedef, fixed = TRUE)), "/;C:\\Windows")), {
    yol <- unname(env$build_processx_command(npm$cli, "x")$env[["PATH"]])
    expect_length(strsplit(yol, ";", fixed = TRUE)[[1]], 2L)
  })

  # Windows dışı platformda ortam devralınır (değiştirilmez).
  unix <- .cc_launch_env("unix")
  expect_null(unix$build_processx_command(npm$cli, "x")$env)
})

test_that("düşmanca istem metni CLI'ye harfiyen ulaşır ve ortamdan genişlemez", {
  skip_if_not_installed("processx")
  node <- Sys.which("node")
  # Node yoksa Bilge Yolaç (npm CLI) da bu makinede çalışamaz; argv sınırı
  # yukarıdaki testlerde ayrıca doğrulanır.
  skip_if(!nzchar(node), "Node kullanılamıyor")

  # Gerçek platform dalı: Windows VM'de .cmd -> node.exe + cli.js, gerçek
  # CreateProcessW; diğer platformlarda .cmd dalı Windows'a zorlanır.
  env <- .cc_launch_env("windows")
  env$resolve_node_path <- function() normalizePath(node, winslash = "/")
  npm <- .cc_fake_npm(withr::local_tempdir(), "js")
  sir <- paste0("sk-test-", paste(sample(c(letters, 0:9), 24, TRUE), collapse = ""))
  # Türkçe karakterli çalışma dizini cmd.exe olmadan gerçek süreç cwd'si olur.
  calisma <- file.path(withr::local_tempdir(), enc2utf8("çalışma ğüşİ"))
  dir.create(calisma)

  # ASCII argv/cwd ile yalnız çıktı çözücüsünü sına. Yereli değiştirmeden
  # CP1254 dönüşümünü de üret: üretim ensure_utf8() bu metni zaten düzeltiyor.
  bilinen <- enc2utf8("Türkçe çalışma ğüşİ")
  kod <- paste0("const fs = require('fs'); const b = Buffer.from('", .cc_utf8_hex(bilinen),
                "', 'hex'); fs.writeSync(1, b); fs.writeSync(2, b);")
  ascii_wd <- if (.Platform$OS.type == "windows") paste0(Sys.getenv("SystemDrive"), "/") else "/"
  expect_true(all(as.integer(charToRaw(ascii_wd)) < 128L))
  for (kodlama in c("", "WINDOWS-1254", "UTF-8")) {
    probe <- processx::process$new(node, c("-e", kod), wd = ascii_wd,
                                  stdout = "|", stderr = "|", encoding = kodlama)
    probe$wait(20000)
    if (probe$is_alive()) {
      probe$kill()
      fail(paste("Çıktı çözücü süreci zaman aşımına uğradı:", kodlama))
      next
    }
    expect_identical(probe$get_exit_status(), 0L)
    for (metin in c(probe$read_all_output(), probe$read_all_error())) {
      tani <- paste(kodlama, Encoding(metin), .cc_utf8_hex(metin), Sys.getlocale("LC_CTYPE"))
      expect_identical(env$ensure_utf8(metin), bilinen, info = tani)
      if (identical(kodlama, "UTF-8")) expect_identical(metin, bilinen, info = tani)
    }
  }

  for (istem in .cc_hostile_prompts()) {
    argumanlar <- c("-p", "--output-format", "json", "--", istem)
    komut <- env$build_processx_command(npm$shim, argumanlar, workdir = calisma)
    komut$env <- env$cc_apply_runtime_api_key_env(komut$env, sir)
    expect_false(grepl("cmd(\\.exe)?$", komut$command, ignore.case = TRUE))

    proc <- processx::process$new(
      command = komut$command, args = komut$args, env = komut$env,
      wd = komut$wd %||% calisma, stdout = "|", stderr = "|",
      encoding = "UTF-8",
      windows_verbatim_args = isTRUE(komut$windows_verbatim_args)
    )
    proc$wait(20000)
    if (proc$is_alive()) {
      proc$kill()
      fail(paste("CLI süreci zaman aşımına uğradı:", istem))
      next
    }
    tani <- proc$read_all_error()
    expect_identical(proc$get_exit_status(), 0L, info = tani)
    # ASCII stderr, stdout'un Unicode çözücüsünden bağımsız olarak Node'un
    # aldığı argv/cwd UTF-8 baytlarını kanıtlar.
    expect_true(all(as.integer(charToRaw(tani)) < 128L))
    baytlar <- jsonlite::fromJSON(tani)
    expect_identical(baytlar$argv, .cc_utf8_hex(argumanlar), info = istem)
    expect_identical(baytlar$cwd, .cc_utf8_hex(normalizePath(calisma, winslash = "\\")),
                     info = istem)
    cikti <- jsonlite::fromJSON(proc$read_all_output(), simplifyVector = FALSE)
    alinan <- unlist(cikti$argv)
    expect_identical(alinan, argumanlar, info = istem)
    expect_identical(normalizePath(cikti$cwd, winslash = "/"),
                     normalizePath(calisma, winslash = "/"), info = istem)
    # Anahtar yalnızca ortamda bulunur; istem metnine genişlemez.
    expect_identical(cikti$sizinti, sir)
    expect_false(any(grepl(sir, alinan, fixed = TRUE)), info = istem)
  }
})
