# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-vm-proven-defaults.R
# Açıklama: 2026-08-20 Windows VM üzerinde ölçülerek doğrulanan PK seçim
#           varsayılanları ve üretim-sorgusu semantik küresyon regresyonları.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  for (dosya in c(
    "helpers_pk_config.R",
    "helpers_pk_text_turkish.R",
    "helpers_pk_query_meta_schema.R",
    "helpers_pk_query_meta_access.R",
    "helpers_pk_query_meta.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

.pk_vm_test_library <- function(ids) {
  lapply(ids, function(id) {
    list(
      id = id,
      name = paste("Sentetik", id),
      sql = "SELECT 1",
      rls_columns = list(
        masraf_yeri_col = NULL,
        proje_kodu_col = NULL,
        eps_kodu_col = NULL
      )
    )
  })
}

test_that("VM'de doğrulanan seçim varsayılanları kalıcıdır", {
  keys <- c("MERGEN_PK_SELECT_TIMEOUT_SEC", "MERGEN_PK_SELECT_PASS_A_CHARS")
  old_env <- Sys.getenv(keys, unset = NA_character_, names = TRUE)
  opt_names <- vapply(keys, pk_config_option_key, character(1))
  old_opts <- stats::setNames(lapply(opt_names, function(nm) getOption(nm, NULL)), opt_names)

  on.exit({
    for (key in keys) {
      old <- old_env[[key]]
      if (is.na(old)) {
        Sys.unsetenv(key)
      } else {
        do.call(Sys.setenv, stats::setNames(list(old), key))
      }
    }
    options(old_opts)
  }, add = TRUE)

  Sys.unsetenv(keys)
  options(stats::setNames(rep(list(NULL), length(opt_names)), opt_names))

  expect_identical(pk_config_resolve("MERGEN_PK_SELECT_TIMEOUT_SEC"), 60L)
  expect_identical(pk_config_resolve("MERGEN_PK_SELECT_PASS_A_CHARS"), 200000L)
})

test_that("optional_when_absent yalnız bilinen checkout envanterinde yokluğu tolere eder", {
  optional_curated <- list(
    gen_00 = list(optional_when_absent = TRUE, entity = "project")
  )

  # GitHub checkout'undaki dört yer tutucu sorguda gen_00'nun bulunmaması
  # beklenir; doğrulanmış üretim kaydı bu kesin envanter için boot'u düşürmez.
  expect_no_error(
    pk_query_meta_attach(
      .pk_vm_test_library(PK_META_CHECKOUT_PLACEHOLDER_IDS),
      auto = list(), local = list(), curated = optional_curated,
      aliases = list(), registry = list()
    )
  )

  # Aynı istisna açıkça beyan edilmemiş bir typo/stale id için geçerli değildir.
  expect_error(
    pk_query_meta_attach(
      .pk_vm_test_library(PK_META_CHECKOUT_PLACEHOLDER_IDS),
      auto = list(), local = list(),
      curated = list(gen_typo = list(entity = "project")),
      aliases = list(), registry = list()
    ),
    "bulunmayan sorgu id"
  )

  # Üretim benzeri farklı bir envanterde optional_when_absent stale id'yi
  # gizleyemez; gerçek sorgu silinir/yeniden adlandırılırsa fail-closed kalır.
  expect_error(
    pk_query_meta_attach(
      .pk_vm_test_library(c("prod_001", "prod_002")),
      auto = list(), local = list(), curated = optional_curated,
      aliases = list(), registry = list()
    ),
    "bulunmayan sorgu id"
  )

  # Üretim sorgusu mevcut olduğunda semantik kayıt normal şekilde iliştirilir.
  sonuc <- pk_query_meta_attach(
    .pk_vm_test_library("gen_00"),
    auto = list(), local = list(), curated = optional_curated,
    aliases = list(), registry = list()
  )

  expect_identical(sonuc[[1]]$meta$entity, "project")
})
