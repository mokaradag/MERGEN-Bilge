# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-existing-file-link-security-behavior.R
# Açıklama: format_claude_code_existing_file_link_html
#           (R/helpers_claude_code_existing_file_link.R) Bilge Yolaç doğrudan
#           indirme bağlantısı GÜVENLİK sınırını test eder (Faz 5 adversarial).
#           Mevcut encoding testi yalnızca "izinli kök verilmedi -> boş" ve happy
#           path'i kapsıyordu; ANCAK happy path testinde cc_policy_path_inside_roots
#           YÜKLENMEDİĞİ için izinli kök DIŞINDAKİ dosyanın reddedilmesi (gerçek
#           traversal/kaçış savunması) davranışsal olarak hiç sınanmamıştı. Bu
#           test gerçek yol politikasını (helpers_claude_code_path_policy.R)
#           yükleyerek şu sözleşmeleri kilitler:
#             * izinli kök DIŞINDAKİ var olan dosya -> boş bağlantı,
#             * izinli kök İÇİNDEKİ dosya -> kart üretilir,
#             * izinli kök verilmedi -> boş,
#             * var olmayan dosya / dizin / boş yol -> boş,
#             * HTML metakarakterli dosya adı -> htmlEscape ile nötrlenir (XSS).
#           Gerçek CLI/süreç/DB/ağ GEREKMEZ; yalnızca tempdir kullanılır.
# ==============================================================================

testthat::local_edition(3)

# Gerçek yol politikasıyla (cc_policy_path_inside_roots) birlikte yardımcıları
# izole ortama yükler. log_warn susturulur; CLAUDE_CODE_LOG_PREFIX stub'lanır.
.cefl_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$CLAUDE_CODE_LOG_PREFIX <- "[CC_TEST]"
  env$log_warn <- function(...) invisible(NULL)
  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_claude_code_path_policy.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_claude_code_downloads.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_claude_code_existing_file_link.R"), encoding = "UTF-8", local = env)
  env
}

testthat::test_that("izinli kök DIŞINDAKİ var olan dosya boş bağlantı döndürür (traversal/kaçış savunması)", {
  env <- .cefl_env()
  allowed_dir <- tempfile("cefl_allowed_"); dir.create(allowed_dir)
  other_dir <- tempfile("cefl_other_"); dir.create(other_dir)
  outside_file <- file.path(other_dir, "gizli.txt")
  writeLines("gizli icerik", outside_file)

  out <- env$format_claude_code_existing_file_link_html(
    file_path = outside_file,
    user_id = 1L,
    session_token = "sec_outside",
    allowed_roots = allowed_dir,
    display_path = "gizli.txt"
  )

  # Dosya gerçekten var ama izinli kök dışında -> kart üretilmemeli.
  testthat::expect_identical(out, "")
})

testthat::test_that("izinli kök İÇİNDEKİ dosya gerçek politika ile kart üretir (aşırı engelleme yok)", {
  testthat::skip_if_not_installed("shiny")
  env <- .cefl_env()
  allowed_dir <- tempfile("cefl_in_"); dir.create(allowed_dir)
  inside_file <- file.path(allowed_dir, "rapor.txt")
  writeLines("gecerli icerik", inside_file)

  out <- env$format_claude_code_existing_file_link_html(
    file_path = inside_file,
    user_id = 2L,
    session_token = "sec_inside",
    allowed_roots = allowed_dir,
    display_path = "rapor.txt"
  )

  testthat::expect_true(nzchar(out))
  testthat::expect_true(grepl("cc-generated-file-card", out, fixed = TRUE))
  testthat::expect_true(grepl("rapor.txt", out, fixed = TRUE))
})

testthat::test_that("izinli kök verilmediğinde boş bağlantı döndürür", {
  env <- .cefl_env()
  allowed_dir <- tempfile("cefl_noroot_"); dir.create(allowed_dir)
  f <- file.path(allowed_dir, "rapor.txt"); writeLines("x", f)

  out <- env$format_claude_code_existing_file_link_html(
    file_path = f,
    allowed_roots = character(0)
  )
  testthat::expect_identical(out, "")
})

testthat::test_that("var olmayan dosya, dizin yolu ve boş yol boş bağlantı döndürür", {
  env <- .cefl_env()
  allowed_dir <- tempfile("cefl_missing_"); dir.create(allowed_dir)

  # Var olmayan dosya.
  out_missing <- env$format_claude_code_existing_file_link_html(
    file_path = file.path(allowed_dir, "yok.txt"),
    allowed_roots = allowed_dir
  )
  testthat::expect_identical(out_missing, "")

  # Dizin (dosya değil).
  out_dir <- env$format_claude_code_existing_file_link_html(
    file_path = allowed_dir,
    allowed_roots = allowed_dir
  )
  testthat::expect_identical(out_dir, "")

  # Boş yol.
  testthat::expect_identical(
    env$format_claude_code_existing_file_link_html(file_path = "", allowed_roots = allowed_dir),
    ""
  )
  # NA yol.
  testthat::expect_identical(
    env$format_claude_code_existing_file_link_html(file_path = NA, allowed_roots = allowed_dir),
    ""
  )
})

testthat::test_that("HTML metakarakterli dosya adı çıktıda htmlEscape ile nötrlenir (XSS sınırı)", {
  testthat::skip_if_not_installed("shiny")
  env <- .cefl_env()
  allowed_dir <- tempfile("cefl_xss_"); dir.create(allowed_dir)

  # Platformdan bağımsız bölüm: display_path (altyazı) eleman-metni escape'i.
  # display_path tamamen çağıran kontrolündedir; gerçek dosya adına ihtiyaç
  # duymaz, bu yüzden Windows dosya adı kısıtlamalarına (< > " yasak) takılmaz
  # ve XSS sınırı her platformda gerçekten sınanır.
  safe_file <- file.path(allowed_dir, "rapor.txt")
  writeLines("gecerli", safe_file)
  out_safe <- env$format_claude_code_existing_file_link_html(
    file_path = safe_file,
    user_id = 3L,
    session_token = "sec_xss_safe",
    allowed_roots = allowed_dir,
    display_path = "kotu<b>altyazi"
  )
  testthat::expect_true(nzchar(out_safe))
  # Altyazıdaki açı parantezleri eleman-metni bağlamında escape edilir.
  testthat::expect_true(grepl("kotu&lt;b&gt;altyazi", out_safe, fixed = TRUE))
  # Ham (escape edilmemiş) <b> etiketi altyazıdan çıktıya sızmamalı.
  testthat::expect_false(grepl("<b>altyazi", out_safe, fixed = TRUE))

  # Yalnızca dosya sisteminin izin verdiği platformlarda (ör. Linux): gerçek
  # dosya adındaki < > " karakterleri öznitelik bağlamı escape'ini (&quot;)
  # de sınar. Windows dosya adlarında bu karakterler GEÇERSİZ olduğundan dosya
  # oluşturulamaz; bu durumda yalnızca öznitelik-escape doğrulaması atlanır,
  # platformdan bağımsız bölüm yine de gerçek kapsama sağlar. tryCatch hem
  # uyarıyı hem hatayı yutar (strict suite stop_on_warning = TRUE).
  evil_name <- "kotu<b>\"x.txt"
  evil_file <- file.path(allowed_dir, evil_name)
  created <- tryCatch(
    {
      writeLines("x", evil_file)
      isTRUE(file.exists(evil_file))
    },
    warning = function(w) FALSE,
    error = function(e) FALSE
  )

  if (isTRUE(created)) {
    out <- env$format_claude_code_existing_file_link_html(
      file_path = evil_file,
      user_id = 3L,
      session_token = "sec_xss",
      allowed_roots = allowed_dir,
      display_path = evil_name
    )

    testthat::expect_true(nzchar(out))
    # Açı parantezleri ve çift tırnak escape edilmiş olmalı.
    testthat::expect_true(grepl("&lt;b&gt;", out, fixed = TRUE))
    testthat::expect_true(grepl("&quot;", out, fixed = TRUE))
    # Ham (escape edilmemiş) dosya-adı etiketi çıktıda bulunmamalı.
    testthat::expect_false(grepl("<b>", out, fixed = TRUE))
  }
})
