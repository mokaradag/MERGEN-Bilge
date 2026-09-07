# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-security-policy-behavior.R
# Açıklama: R/helpers_claude_code_security_policy.R GÜVENLİK-KRİTİK ilke
#           yardımcılarının DAVRANIŞSAL testleri. Mevcut sözleşme testi çoğunlukla
#           cc_policy_build_cli_args/workdir/path üzerinden gider; aşağıdaki saf/
#           doğrudan yardımcılar davranışsal olarak KAPSANMIYORDU:
#             - cc_policy_truthy (toleranslı boolean coercion)
#             - cc_policy_cli_list (araç listesi ayrıştırma)
#             - cc_policy_user_prompt (prompt skalar daraltma)
#             - cc_policy_append_prompt_argument ('--' sonlandırıcı SÖZLEŞMESİ)
#             - cc_policy_permission_mode (tehlikeli mod -> acceptEdits)
#             - cc_policy_dangerous_permissions_allowed (oturum ayarı TEK BAŞINA açamaz)
#           Determinizm için claude_code_config ve ilgili çevre değişkenleri test
#           sırasında kontrol edilir ve geri yüklenir. processx/CLI/ağ GEREKMEZ.
# ==============================================================================

.ccsec_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  # Güvenlik ilkesi log dalları bu sembolleri runtime'da kullanır; izole
  # çalıştırmada eksikse zararsız stub tanımlanır (tam pakette zaten vardır).
  if (!exists("CLAUDE_CODE_LOG_PREFIX", inherits = TRUE)) {
    assign("CLAUDE_CODE_LOG_PREFIX", "[CLAUDE_CODE]", envir = globalenv())
  }
  if (!exists("log_warn", mode = "function", inherits = TRUE)) {
    assign("log_warn", function(...) invisible(NULL), envir = globalenv())
  }
  if (!exists("cc_policy_truthy",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_security_policy.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# claude_code_config global'ini ve çevre değişkenlerini geçici kontrol eder.
.ccsec_with <- function(config, env, code) {
  had_cfg <- exists("claude_code_config", envir = globalenv(), inherits = FALSE)
  old_cfg <- if (had_cfg) get("claude_code_config", envir = globalenv()) else NULL
  nms <- names(env)
  old_env <- as.list(Sys.getenv(nms, names = TRUE, unset = NA_character_))

  on.exit({
    if (had_cfg) {
      assign("claude_code_config", old_cfg, envir = globalenv())
    } else if (exists("claude_code_config", envir = globalenv(), inherits = FALSE)) {
      rm("claude_code_config", envir = globalenv())
    }
    for (nm in nms) {
      v <- old_env[[nm]]
      if (is.na(v)) Sys.unsetenv(nm) else { a <- list(v); names(a) <- nm; do.call(Sys.setenv, a) }
    }
  }, add = TRUE)

  assign("claude_code_config", config, envir = globalenv())
  for (nm in nms) {
    v <- env[[nm]]
    if (is.na(v)) Sys.unsetenv(nm) else { a <- list(v); names(a) <- nm; do.call(Sys.setenv, a) }
  }
  force(code)
}

.ccsec_neutral_cfg <- function(...) {
  base <- list(
    permission_mode = "",
    allow_dangerous_permissions = FALSE,
    allowed_tools = character(0),
    disallowed_tools = character(0)
  )
  modifyList(base, list(...))
}

# ------------------------------------------------------------------------------
# cc_policy_truthy
# ------------------------------------------------------------------------------
testthat::test_that("cc_policy_truthy toleranslı truthy değerleri tanır", {
  .ccsec_source_once()
  testthat::expect_true(cc_policy_truthy(TRUE))
  for (v in c("1", "true", "TRUE", "yes", "y", "evet", "on", "enabled", " True ")) {
    testthat::expect_true(cc_policy_truthy(v), info = v)
  }
})

testthat::test_that("cc_policy_truthy falsy/boş/NULL değerlerde FALSE döner", {
  .ccsec_source_once()
  testthat::expect_false(cc_policy_truthy(FALSE))
  testthat::expect_false(cc_policy_truthy(NULL))
  testthat::expect_false(cc_policy_truthy(character(0)))
  for (v in c("0", "false", "no", "hayir", "off", "random")) {
    testthat::expect_false(cc_policy_truthy(v), info = v)
  }
})

# ------------------------------------------------------------------------------
# cc_policy_cli_list
# ------------------------------------------------------------------------------
testthat::test_that("cc_policy_cli_list ayraçları böler, trimler, boşları atar, tekiller", {
  .ccsec_source_once()
  testthat::expect_identical(cc_policy_cli_list(NULL), character(0))
  testthat::expect_identical(cc_policy_cli_list(""), character(0))
  testthat::expect_identical(cc_policy_cli_list("Read;Write;Edit"), c("Read", "Write", "Edit"))
  testthat::expect_identical(cc_policy_cli_list("Read, Write , Glob"), c("Read", "Write", "Glob"))
  # Ardışık ayraç/boş atılır, tekrar tekilleşir.
  testthat::expect_identical(cc_policy_cli_list("Read;;Read;Bash"), c("Read", "Bash"))
  # Vektör girdi her öğeyi böler.
  testthat::expect_identical(cc_policy_cli_list(c("Read;Write", "Bash")), c("Read", "Write", "Bash"))
})

# ------------------------------------------------------------------------------
# cc_policy_user_prompt
# ------------------------------------------------------------------------------
testthat::test_that("cc_policy_user_prompt prompt'u skalar metne daraltır", {
  .ccsec_source_once()
  testthat::expect_identical(cc_policy_user_prompt(NULL), "")
  testthat::expect_identical(cc_policy_user_prompt(NA_character_), "")
  testthat::expect_identical(cc_policy_user_prompt("merhaba"), "merhaba")
  # Vektör -> yalnızca ilk öğe.
  testthat::expect_identical(cc_policy_user_prompt(c("ilk", "ikinci")), "ilk")
})

# ------------------------------------------------------------------------------
# cc_policy_append_prompt_argument ('--' sonlandırıcı güvenlik sözleşmesi)
# ------------------------------------------------------------------------------
testthat::test_that("cc_policy_append_prompt_argument prompt'u '--' sonrasına koyar", {
  .ccsec_source_once()
  args <- c("--allowedTools", "Read", "Write")
  donen <- cc_policy_append_prompt_argument(args, "dosyayı incele")
  testthat::expect_identical(donen, c("--allowedTools", "Read", "Write", "--", "dosyayı incele"))
  # '--' her zaman prompt'tan hemen önce olmalı (variadic yutmayı engeller).
  sep_idx <- which(donen == "--")
  testthat::expect_identical(donen[sep_idx + 1L], "dosyayı incele")
  # Boş prompt'ta bile '--' korunur.
  testthat::expect_identical(
    cc_policy_append_prompt_argument(character(0), NULL),
    c("--", "")
  )
})

# ------------------------------------------------------------------------------
# cc_policy_permission_mode (tehlikeli mod nötrlenir)
# ------------------------------------------------------------------------------
testthat::test_that("cc_policy_permission_mode kaynak yokken boş, geçerli modu döndürür", {
  .ccsec_source_once()
  # Hiç kaynak yok -> "".
  testthat::expect_identical(
    .ccsec_with(.ccsec_neutral_cfg(), list(CLAUDE_CODE_PERMISSION_MODE = NA_character_),
                cc_policy_permission_mode()),
    ""
  )
  # Çevreden geçerli mod (env config'i geçersiz kılar).
  testthat::expect_identical(
    .ccsec_with(.ccsec_neutral_cfg(), list(CLAUDE_CODE_PERMISSION_MODE = "plan"),
                cc_policy_permission_mode()),
    "plan"
  )
  testthat::expect_identical(
    .ccsec_with(.ccsec_neutral_cfg(), list(CLAUDE_CODE_PERMISSION_MODE = "acceptEdits"),
                cc_policy_permission_mode()),
    "acceptEdits"
  )
})

testthat::test_that("cc_policy_permission_mode tehlikeli/bilinmeyen modu acceptEdits'e indirger", {
  .ccsec_source_once()
  for (m in c("bypassPermissions", "bypass", "dangerous", "dangerously-skip-permissions")) {
    donen <- .ccsec_with(.ccsec_neutral_cfg(), list(CLAUDE_CODE_PERMISSION_MODE = m),
                         cc_policy_permission_mode())
    testthat::expect_identical(donen, "acceptEdits", info = m)
  }
  # Bilinmeyen değer de güvenli acceptEdits'e düşer.
  testthat::expect_identical(
    .ccsec_with(.ccsec_neutral_cfg(), list(CLAUDE_CODE_PERMISSION_MODE = "saçmaDeger"),
                cc_policy_permission_mode()),
    "acceptEdits"
  )
})

testthat::test_that("cc_policy_permission_mode oturum ayarı merkezi modu yalnızca daraltabilir", {
  .ccsec_source_once()

  # Merkezi mod gevşekken oturum ayarı DARALTABİLİR.
  daraltma <- .ccsec_with(
    .ccsec_neutral_cfg(),
    list(CLAUDE_CODE_PERMISSION_MODE = "acceptEdits"),
    cc_policy_permission_mode(
      settings_data = list(claude_code_permission_mode = "plan")
    )
  )
  testthat::expect_identical(daraltma, "plan")

  # Aynı katılık seviyesi kabul edilir.
  esit <- .ccsec_with(
    .ccsec_neutral_cfg(),
    list(CLAUDE_CODE_PERMISSION_MODE = "default"),
    cc_policy_permission_mode(
      settings_data = list(claude_code_permission_mode = "default")
    )
  )
  testthat::expect_identical(esit, "default")

  # Merkezi `plan` kısıtı oturum ayarıyla GENİŞLETİLEMEZ (yetki yükseltme).
  for (istenen in c("default", "acceptEdits")) {
    genisletme <- .ccsec_with(
      .ccsec_neutral_cfg(),
      list(CLAUDE_CODE_PERMISSION_MODE = "plan"),
      cc_policy_permission_mode(
        settings_data = list(claude_code_permission_mode = istenen)
      )
    )
    testthat::expect_identical(genisletme, "plan", info = istenen)
  }

  # Merkezi mod tanımsızsa oturum ayarı geçerli kalır.
  merkezsiz <- .ccsec_with(
    .ccsec_neutral_cfg(),
    list(CLAUDE_CODE_PERMISSION_MODE = ""),
    cc_policy_permission_mode(
      settings_data = list(claude_code_permission_mode = "acceptEdits")
    )
  )
  testthat::expect_identical(merkezsiz, "acceptEdits")
})

testthat::test_that("tehlikeli mod açıkken --disallowedTools yine uygulanır", {
  .ccsec_source_once()

  args <- .ccsec_with(
    .ccsec_neutral_cfg(),
    list(
      CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS = "TRUE",
      CLAUDE_CODE_DISALLOWED_TOOLS = "WebFetch;Bash"
    ),
    cc_policy_build_cli_args(prompt = "merhaba")
  )

  testthat::expect_true("--dangerously-skip-permissions" %in% args)
  testthat::expect_true("--disallowedTools" %in% args)
  testthat::expect_true(all(c("WebFetch", "Bash") %in% args))
})

testthat::test_that("izin listesi tanımlıyken tehlikeli kip reddedilir (kapsam/mcp)", {
  .ccsec_source_once()

  # `bypassPermissions` altında `--allowedTools` BAĞLAYICI DEĞİLDİR ve tümleyeni
  # kapsam desenleri (`Bash(git status)`) ile `mcp__*` araçları için güvenle
  # hesaplanamaz. Bu yüzden izin listesi tanımlıyken tehlikeli kip reddedilir.
  for (liste in c("Read;Grep", "Bash(git status)", "mcp__sunucu__arac", "Bash(git *);Read")) {
    args <- .ccsec_with(
      .ccsec_neutral_cfg(),
      list(
        CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS = "TRUE",
        CLAUDE_CODE_ALLOWED_TOOLS = liste
      ),
      cc_policy_build_cli_args(prompt = "merhaba")
    )

    testthat::expect_false("--dangerously-skip-permissions" %in% args, info = liste)
    testthat::expect_true("--allowedTools" %in% args, info = liste)
    # Kapsamlı/MCP araç adı tümleyen üzerinden YASAKLANMAZ.
    testthat::expect_false("--disallowedTools" %in% args, info = liste)
  }
})

testthat::test_that("izin listesi yokken tehlikeli kip yalnızca yasak listesini uygular", {
  .ccsec_source_once()

  args <- .ccsec_with(
    .ccsec_neutral_cfg(),
    list(
      CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS = "TRUE",
      CLAUDE_CODE_ALLOWED_TOOLS = "",
      CLAUDE_CODE_DISALLOWED_TOOLS = "WebFetch"
    ),
    cc_policy_build_cli_args(prompt = "merhaba")
  )

  testthat::expect_true("--dangerously-skip-permissions" %in% args)
  testthat::expect_true("--disallowedTools" %in% args)
  testthat::expect_true("WebFetch" %in% args)
  # İzin listesi YOK: tümleyen hiç üretilmez.
  testthat::expect_false("--allowedTools" %in% args)
})

# ------------------------------------------------------------------------------
# cc_policy_dangerous_permissions_allowed (oturum ayarı TEK BAŞINA açamaz)
# ------------------------------------------------------------------------------
testthat::test_that("cc_policy_dangerous_permissions_allowed varsayılan kapalıdır", {
  .ccsec_source_once()
  testthat::expect_false(
    .ccsec_with(.ccsec_neutral_cfg(),
                list(CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS = "FALSE"),
                cc_policy_dangerous_permissions_allowed())
  )
})

testthat::test_that("cc_policy_dangerous_permissions_allowed yalnızca env/config ile açılır", {
  .ccsec_source_once()
  # Çevreden açık.
  testthat::expect_true(
    .ccsec_with(.ccsec_neutral_cfg(),
                list(CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS = "TRUE"),
                cc_policy_dangerous_permissions_allowed())
  )
  # Merkezi config'ten açık.
  testthat::expect_true(
    .ccsec_with(.ccsec_neutral_cfg(allow_dangerous_permissions = TRUE),
                list(CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS = "FALSE"),
                cc_policy_dangerous_permissions_allowed())
  )
})

testthat::test_that("cc_policy_dangerous_permissions_allowed oturum ayarı TEK BAŞINA açamaz (güvenlik)", {
  .ccsec_source_once()
  # Yalnızca oturum/kullanıcı ayarı TRUE, env/config kapalı -> yine FALSE.
  testthat::expect_false(
    .ccsec_with(
      .ccsec_neutral_cfg(),
      list(CLAUDE_CODE_ALLOW_DANGEROUS_PERMISSIONS = "FALSE"),
      cc_policy_dangerous_permissions_allowed(
        settings_data = list(claude_code_allow_dangerous_permissions = TRUE)
      )
    )
  )
})

# ------------------------------------------------------------------------------
# cc_policy_permission_args (CLI izin bayrakları birleştirme)
# ------------------------------------------------------------------------------
# Bu CLI sözleşmesini sabit env ile çağıran yardımcı (config alanlarını test eder).
.ccsec_perm_args <- function(config) {
  .ccsec_with(
    config,
    list(
      CLAUDE_CODE_PERMISSION_MODE = "",
      CLAUDE_CODE_ALLOWED_TOOLS = "",
      CLAUDE_CODE_DISALLOWED_TOOLS = ""
    ),
    cc_policy_permission_args()
  )
}

testthat::test_that("cc_policy_permission_args izin modu ve izinli araçları CLI bayraklarına çevirir", {
  .ccsec_source_once()
  args <- .ccsec_perm_args(
    .ccsec_neutral_cfg(permission_mode = "acceptEdits", allowed_tools = "Read;Write;Edit")
  )
  testthat::expect_identical(
    args,
    c("--permission-mode", "acceptEdits", "--allowedTools", "Read", "Write", "Edit")
  )
})

testthat::test_that("cc_policy_permission_args 'default' modunda --permission-mode bayrağı eklemez", {
  .ccsec_source_once()
  args <- .ccsec_perm_args(
    .ccsec_neutral_cfg(permission_mode = "default", allowed_tools = "Read")
  )
  testthat::expect_false("--permission-mode" %in% args)
  testthat::expect_identical(args, c("--allowedTools", "Read"))
})

testthat::test_that("cc_policy_permission_args disallowedTools'ı ayrı bayrakla ekler", {
  .ccsec_source_once()
  args <- .ccsec_perm_args(
    .ccsec_neutral_cfg(disallowed_tools = "WebFetch;Bash")
  )
  testthat::expect_identical(args, c("--disallowedTools", "WebFetch", "Bash"))
})

testthat::test_that("cc_policy_permission_args mod ve araç yoksa boş argüman döndürür", {
  .ccsec_source_once()
  args <- .ccsec_perm_args(.ccsec_neutral_cfg())
  testthat::expect_identical(args, character(0))
})

testthat::test_that("cc_policy_permission_args env ve config araçlarını birleştirip tekilleştirir", {
  .ccsec_source_once()
  args <- .ccsec_with(
    .ccsec_neutral_cfg(permission_mode = "plan", allowed_tools = "Read"),
    list(
      CLAUDE_CODE_PERMISSION_MODE = "",
      CLAUDE_CODE_ALLOWED_TOOLS = "Read;Grep",
      CLAUDE_CODE_DISALLOWED_TOOLS = ""
    ),
    cc_policy_permission_args()
  )
  # Read hem config hem env'de var; tekilleştirilir
  testthat::expect_identical(
    args,
    c("--permission-mode", "plan", "--allowedTools", "Read", "Grep")
  )
})

testthat::test_that("cc_policy_permission_args settings_data izin modunu onurlar", {
  .ccsec_source_once()
  args <- .ccsec_with(
    .ccsec_neutral_cfg(),
    list(
      CLAUDE_CODE_PERMISSION_MODE = "",
      CLAUDE_CODE_ALLOWED_TOOLS = "",
      CLAUDE_CODE_DISALLOWED_TOOLS = ""
    ),
    cc_policy_permission_args(
      settings_data = list(claude_code_permission_mode = "acceptEdits")
    )
  )
  testthat::expect_identical(args, c("--permission-mode", "acceptEdits"))
})
