# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-security-policy-contract.R
# Açıklama: Bilge Yolaç Claude Code güvenlik ilkesi sözleşmesini doğrular.
# ==============================================================================

.source_cc_security_policy_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$log_info <- function(...) invisible(NULL)
  test_env$log_warn <- function(...) invisible(NULL)
  test_env$log_error <- function(...) invisible(NULL)
  test_env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"

  test_env$claude_code_config <- list(
    default_workdir = "",
    allow_dangerous_permissions = FALSE,
    permission_mode = "acceptEdits",
    allowed_tools = "Read;Write;Edit;MultiEdit;Glob;Grep;LS;Bash",
    disallowed_tools = "",
    allowed_workdir_roots = "",
    allow_user_selected_workdirs = TRUE,
    allowed_output_roots = ""
  )

  test_env$get_user_workspace <- function(user_id, base_dir = NULL) {
    kok <- file.path(
      tempdir(),
      "cc_security_policy_test",
      paste0("user_", as.character(user_id %||% "default"))
    )
    dir.create(kok, recursive = TRUE, showWarnings = FALSE)
    normalizePath(kok, winslash = "/", mustWork = FALSE)
  }

  source(
    file.path(repo_root, "R", "helpers_claude_code_security_policy.R"),
    encoding = "UTF-8",
    local = test_env
  )

  # Yol/kök doğrulama helper'ları artık ayrı dosyada; testin bunlara da
  # erişebilmesi için path_policy yardımcılarını test ortamına yükle.
  source(
    file.path(repo_root, "R", "helpers_claude_code_path_policy.R"),
    encoding = "UTF-8",
    local = test_env
  )

  source(
    file.path(repo_root, "R", "helpers_claude_code_prompt_security_policy.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

test_that("Bilge Yolaç güvenlik ilkesi helper dosyası manifestte doğru yerde yüklenir", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(
    repo_root,
    "R",
    "helpers_claude_code_security_policy.R"
  )))

  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_claude_code_runtime_workdir.R",
      "R/helpers_claude_code_security_policy.R",
      "R/helpers_claude_code_path_policy.R",
      "R/helpers_claude_code_prompt_security_policy.R",
      "R/helpers_claude_code.R",
      "R/helpers_claude_code_streaming.R"
    ),
    label = "Bilge Yolaç güvenlik ilkesi source sırası bozulmuş:"
  )
})

test_that("cc_policy_normalize_path UNC yollarını drive harfine çevirmez", {
  test_env <- .source_cc_security_policy_for_test()

  # Windows VM'de normalizePath("//rehisds/...") mapped drive harfine
  # (örn. M:/rehisds/...) çözülebiliyor. UNC formu korunmazsa
  # is_problematic_windows_workdir UNC olarak algılamaz, runtime aynalama
  # atlanır ve cmd.exe spawn'lı CLI dizini boş görür.
  unc_input <- "//rehisds/uygulamalar/Primavera/PYB"
  unc_input_backslash <- "\\\\rehisds\\uygulamalar\\Primavera\\PYB"

  unc_forward <- test_env$cc_policy_normalize_path(unc_input, must_exist = FALSE)
  unc_backslash <- test_env$cc_policy_normalize_path(
    unc_input_backslash,
    must_exist = FALSE
  )

  expect_true(
    grepl("^//", unc_forward, perl = TRUE),
    info = paste0(
      "cc_policy_normalize_path UNC yolunu UNC olarak korumalıdır: ",
      unc_forward
    )
  )

  expect_true(
    grepl("^//", unc_backslash, perl = TRUE),
    info = paste0(
      "cc_policy_normalize_path ters slash UNC yolunu UNC olarak korumalıdır: ",
      unc_backslash
    )
  )

  expect_false(
    grepl("^[A-Za-z]:/", unc_forward, perl = TRUE),
    info = "UNC yol drive harfine çevrilmemelidir."
  )
})

test_that("cc_policy_normalize_path baştaki çift + segment arası tek slash UNC'yi düzgün çevirir", {
  test_env <- .source_cc_security_policy_for_test()

  # Regresyon: gsub("\\\\", "/", x, fixed=TRUE) yalnızca ardışık çift ters
  # slash'ı eşler. Kullanıcı `\\rehisds\gruplar\MAYM\R` yazdığında baştaki iki
  # ters slash + segment arası tek ters slash bulunur; eski gsub yalnızca
  # baştaki çifti dönüştürdüğü için sonuç `/rehisds\gruplar\MAYM\R` olarak
  # bozuluyordu. Bu malformed yol downstream UNC tespit kayıplarına ve
  # cmd.exe'de "The system cannot find the path specified" hatasına yol açıyordu.
  ham_unc <- "\\\\rehisds\\gruplar\\MAYM\\R"
  beklenen <- "//rehisds/gruplar/MAYM/R"

  cozulen <- test_env$cc_policy_normalize_path(ham_unc, must_exist = FALSE)

  expect_equal(
    cozulen,
    beklenen,
    info = paste0(
      "Baştaki çift + segment arası tek ters slash içeren UNC yolu kanonik ",
      "forward slash UNC formuna çevrilmelidir."
    )
  )

  # Türkçe karakterli daha derin UNC yolları da korunmalı
  turkce_unc <- "\\\\rehisds\\gruplar\\MAYM\\PROJE YÖNETİMİ\\PYÖP Durumu"
  turkce_beklenen <- "//rehisds/gruplar/MAYM/PROJE YÖNETİMİ/PYÖP Durumu"

  turkce_cozulen <- test_env$cc_policy_normalize_path(
    turkce_unc,
    must_exist = FALSE
  )

  expect_equal(
    turkce_cozulen,
    turkce_beklenen,
    info = paste0(
      "Türkçe karakterli UNC yolu da kanonik UNC formunu korumalıdır: ",
      turkce_cozulen
    )
  )
})

test_that("CLI argümanları varsayılan olarak tehlikeli izin atlama içermez", {
  test_env <- .source_cc_security_policy_for_test()

  test_env$claude_code_config$allow_dangerous_permissions <- FALSE

  args <- test_env$cc_policy_build_cli_args(
    prompt = "Merhaba",
    output_format = "stream-json",
    include_partial_messages = TRUE,
    verbose = TRUE
  )

  expect_false(
    "--dangerously-skip-permissions" %in% args,
    info = "Tehlikeli izin atlama varsayılan olarak kapalı olmalıdır."
  )

  expect_true("--permission-mode" %in% args)
  expect_true("acceptEdits" %in% args)
  expect_true("--allowedTools" %in% args)

  expect_false("--append-system-prompt" %in% args)
  expect_equal(args[length(args) - 1L], "--")
  expect_equal(args[length(args)], "Merhaba")
  expect_false(any(grepl("Bilge Yolaç", args, fixed = TRUE)))
  expect_false(any(grepl("çalışma ilkesi", args, fixed = TRUE)))
  expect_false(any(grepl("ÇALIŞMA ALANI TALİMATI", args, fixed = TRUE)))

  expect_true("--print" %in% args)
  expect_true("--verbose" %in% args)
  expect_true("--include-partial-messages" %in% args)
  expect_true("stream-json" %in% args)
})

test_that("varsayılan izinli araçlar Bash dahil tüm standart Claude Code araçlarını içerir", {
  # MERGEN Bilge kurumsal/on-prem ortamda çalıştığı için Bash dahil standart
  # araçlar varsayılan olarak izinli olmalıdır. Aksi halde model gerçek
  # zamanlı kabuk komutları çalıştıramaz, kullanıcı ARAÇ KULLANIMLARI
  # listesinde canlı kabuk komutu göremez ve sayaç 0 gözükür.
  test_env <- .source_cc_security_policy_for_test()

  args <- test_env$cc_policy_build_cli_args(
    prompt = "ls -la çalıştır",
    output_format = "stream-json",
    include_partial_messages = TRUE,
    verbose = TRUE
  )

  allowed_index <- which(args == "--allowedTools")
  expect_length(allowed_index, 1L)

  separator_index <- which(args == "--")
  expect_length(separator_index, 1L)

  allowed_tokens <- args[(allowed_index + 1L):(separator_index - 1L)]

  beklenen_araclar <- c(
    "Read", "Write", "Edit", "MultiEdit",
    "Glob", "Grep", "LS", "Bash"
  )

  for (arac in beklenen_araclar) {
    expect_true(
      arac %in% allowed_tokens,
      info = sprintf(
        "%s aracı varsayılan izinli araçlar listesinde bulunmalıdır.",
        arac
      )
    )
  }
})

test_that("allowedTools prompt argümanını yutamaz", {
  test_env <- .source_cc_security_policy_for_test()

  args <- test_env$cc_policy_build_cli_args(
    prompt = "Bu projedeki kodları incele.",
    output_format = "stream-json",
    include_partial_messages = TRUE,
    verbose = TRUE,
    workdir = "C:/Temp/TestProject"
  )

  separator_index <- which(args == "--")
  expect_length(separator_index, 1L)
  expect_equal(args[separator_index + 1L], "Bu projedeki kodları incele.")

  allowed_index <- which(args == "--allowedTools")
  expect_true(length(allowed_index) >= 1L)
  expect_true(allowed_index[1L] < separator_index)
})

test_that("permission mode bypass değerleri tehlikeli bayrağı dolaylı açamaz", {
  test_env <- .source_cc_security_policy_for_test()

  test_env$claude_code_config$allow_dangerous_permissions <- FALSE
  test_env$claude_code_config$permission_mode <- "bypassPermissions"

  args <- test_env$cc_policy_build_cli_args(
    prompt = "Merhaba",
    output_format = "json"
  )

  expect_false("--dangerously-skip-permissions" %in% args)
  expect_true("--permission-mode" %in% args)
  expect_true("acceptEdits" %in% args)
})

test_that("açık override verildiğinde tehlikeli izin atlama argümanı eklenir", {
  test_env <- .source_cc_security_policy_for_test()

  test_env$claude_code_config$allow_dangerous_permissions <- TRUE

  args <- test_env$cc_policy_build_cli_args(
    prompt = "Merhaba",
    output_format = "json"
  )

  expect_true(
    "--dangerously-skip-permissions" %in% args,
    info = "Tehlikeli mod yalnızca açık override ile argümanlara eklenmelidir."
  )
})

test_that("çalışma dizini yalnızca izin verilen kökler altında kabul edilir", {
  test_env <- .source_cc_security_policy_for_test()

  root <- withr::local_tempdir()
  allowed <- file.path(root, "allowed")
  outside <- file.path(root, "outside")
  dir.create(allowed, recursive = TRUE)
  dir.create(outside, recursive = TRUE)

  test_env$claude_code_config$allowed_workdir_roots <- allowed

  allowed_check <- test_env$cc_policy_validate_workdir(
    allowed,
    user_id = 42L
  )
  outside_check <- test_env$cc_policy_validate_workdir(
    outside,
    user_id = 42L
  )

  expect_true(isTRUE(allowed_check$ok))
  expect_false(isTRUE(outside_check$ok))
  expect_match(outside_check$error, "güvenlik ilkesi")
})

test_that("path traversal izin verilen kökün dışına çıkamaz", {
  test_env <- .source_cc_security_policy_for_test()

  root <- withr::local_tempdir()
  allowed <- file.path(root, "allowed")
  outside <- file.path(root, "outside")
  dir.create(allowed, recursive = TRUE)
  dir.create(outside, recursive = TRUE)

  traversal <- file.path(allowed, "..", "outside")

  test_env$claude_code_config$allowed_workdir_roots <- allowed

  traversal_check <- test_env$cc_policy_validate_workdir(
    traversal,
    user_id = 42L
  )

  expect_false(isTRUE(traversal_check$ok))
  expect_match(traversal_check$error, "güvenlik ilkesi")
})

test_that("UI'da açıkça seçilen mevcut çalışma dizini çalışma kökü olarak kabul edilir", {
  test_env <- .source_cc_security_policy_for_test()

  selected <- withr::local_tempdir()

  selected_check <- test_env$cc_policy_validate_workdir(
    selected,
    user_id = 42L,
    allow_selected_workdir = TRUE
  )

  expect_true(isTRUE(selected_check$ok))
  expect_equal(
    normalizePath(selected_check$path, winslash = "/", mustWork = TRUE),
    normalizePath(selected, winslash = "/", mustWork = TRUE)
  )
})

test_that("üretilen dosya filtreleme yalnızca izinli kökteki yolları bırakır", {
  test_env <- .source_cc_security_policy_for_test()

  root <- withr::local_tempdir()
  allowed <- file.path(root, "allowed")
  outside <- file.path(root, "outside")
  dir.create(allowed, recursive = TRUE)
  dir.create(outside, recursive = TRUE)

  inside_file <- file.path(allowed, "sonuc.txt")
  outside_file <- file.path(outside, "sonuc.txt")
  writeLines("izinli", inside_file, useBytes = TRUE)
  writeLines("engelli", outside_file, useBytes = TRUE)

  kept <- test_env$cc_policy_filter_generated_file_paths(
    c(inside_file, outside_file),
    allowed_roots = allowed,
    context = "test çıktısı"
  )

  expect_equal(length(kept), 1L)
  expect_equal(basename(kept), "sonuc.txt")
  expect_true(test_env$cc_policy_path_inside_roots(kept, allowed))
})

test_that("oturum ayarı tek başına tehlikeli izin atlamayı açamaz", {
  test_env <- .source_cc_security_policy_for_test()

  test_env$claude_code_config$allow_dangerous_permissions <- FALSE

  args <- test_env$cc_policy_build_cli_args(
    prompt = "Merhaba",
    output_format = "json",
    settings_data = list(
      claude_code_allow_dangerous_permissions = TRUE
    )
  )

  expect_false("--dangerously-skip-permissions" %in% args)
  expect_true("--permission-mode" %in% args)
  expect_true("acceptEdits" %in% args)
})

test_that("prompt içindeki dış yazma hedefleri CLI başlamadan engellenir", {
  test_env <- .source_cc_security_policy_for_test()

  root <- withr::local_tempdir()
  allowed <- file.path(root, "allowed")
  outside <- file.path(root, "outside")
  dir.create(allowed, recursive = TRUE)
  dir.create(outside, recursive = TRUE)

  inside_check <- test_env$cc_policy_validate_prompt_file_intent(
    prompt = "sonuc.txt dosyasını oluştur",
    workdir = allowed,
    allowed_roots = allowed
  )

  traversal_check <- test_env$cc_policy_validate_prompt_file_intent(
    prompt = "../outside/sonuc.txt dosyasını oluştur",
    workdir = allowed,
    allowed_roots = allowed
  )

  absolute_check <- test_env$cc_policy_validate_prompt_file_intent(
    prompt = paste0(outside, "/sonuc.txt dosyasını oluştur"),
    workdir = allowed,
    allowed_roots = allowed
  )

  expect_true(isTRUE(inside_check$ok))
  expect_false(isTRUE(traversal_check$ok))
  expect_false(isTRUE(absolute_check$ok))
  expect_match(traversal_check$error, "güvenlik ilkesi")
  expect_match(absolute_check$error, "güvenlik ilkesi")
})

test_that("prompt path-intent validation uzantısız ve var olmayan prose tokenlarını engellemez", {
  test_env <- .source_cc_security_policy_for_test()

  root <- withr::local_tempdir()
  allowed <- file.path(root, "allowed")
  dir.create(allowed, recursive = TRUE)

  prose_check <- test_env$cc_policy_validate_prompt_file_intent(
    prompt = paste(
      "Bu raporu oluştur ama şu ifadeyi normal metin olarak değerlendir:",
      "C:/BuSadeceMetinGibiGorunenBirIfade"
    ),
    workdir = allowed,
    allowed_roots = allowed
  )

  expect_true(
    isTRUE(prose_check$ok),
    info = paste(
      "Uzantısız ve diskte var olmayan path-benzeri metinler",
      "normal kullanıcı ifadesi olarak geçmelidir."
    )
  )
})