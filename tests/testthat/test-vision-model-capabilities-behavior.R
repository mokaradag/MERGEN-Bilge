# ==============================================================================
# Dosya Yolu: tests/testthat/test-vision-model-capabilities-behavior.R
# Açıklama: R/helpers_vision_model_capabilities.R saf yardımcılarının davranışını
#           doğrular: MERGEN_VISION_MODELS ayrıştırma ve yetenek tablosuna vision
#           işaretleme. Çevrimdışı/deterministik; gerçek config_api gerekmez.
# ==============================================================================

repo_root_vmc <- resolve_repo_root_for_tests()

.vmc_env <- new.env(parent = globalenv())
source(file.path(repo_root_vmc, "R/helpers_vision_model_capabilities.R"),
       encoding = "UTF-8", local = .vmc_env)

test_that("parse_vision_models_env ';'/',' ile ayırır, boşlukları trimler", {
  expect_setequal(
    .vmc_env$parse_vision_models_env("a;b,c"),
    c("a", "b", "c")
  )
  # Model kimlikleri boşluk içerebilir; yalnızca ; ve , ayırır
  expect_setequal(
    .vmc_env$parse_vision_models_env("technical name 1; technical name 6 , vmod"),
    c("technical name 1", "technical name 6", "vmod")
  )
  # Boş/NA -> boş vektör
  expect_identical(.vmc_env$parse_vision_models_env(""), character(0))
  expect_identical(.vmc_env$parse_vision_models_env(NA_character_), character(0))
  # Yinelenen ayırıcılar boş parça üretmez
  expect_setequal(.vmc_env$parse_vision_models_env("a;;,b"), c("a", "b"))
})

test_that("apply_vision_model_capabilities her girdiye vision=FALSE varsayılanı verir", {
  cfg <- list(local_model_capabilities = list(
    "m1" = list(thinking = FALSE),
    "m2" = list(thinking = TRUE, omit_temperature = TRUE)
  ))
  out <- .vmc_env$apply_vision_model_capabilities(cfg, character(0), env_value = "")
  expect_false(isTRUE(out$local_model_capabilities[["m1"]]$vision))
  expect_false(isTRUE(out$local_model_capabilities[["m2"]]$vision))
  # Mevcut alanlar korunur
  expect_true(isTRUE(out$local_model_capabilities[["m2"]]$thinking))
  expect_true(isTRUE(out$local_model_capabilities[["m2"]]$omit_temperature))
})

test_that("apply_vision_model_capabilities extra_vision_models'i TRUE yapar", {
  cfg <- list(local_model_capabilities = list(
    "m1" = list(thinking = FALSE),
    "deep-low" = list(thinking = TRUE)
  ))
  out <- .vmc_env$apply_vision_model_capabilities(cfg, c("deep-low"), env_value = "")
  expect_false(isTRUE(out$local_model_capabilities[["m1"]]$vision))
  expect_true(isTRUE(out$local_model_capabilities[["deep-low"]]$vision))
  # thinking korunur
  expect_true(isTRUE(out$local_model_capabilities[["deep-low"]]$thinking))
})

test_that("apply_vision_model_capabilities MERGEN_VISION_MODELS'ten TRUE yapar", {
  cfg <- list(local_model_capabilities = list(
    "m1" = list(thinking = FALSE),
    "m2" = list(thinking = FALSE)
  ))
  out <- .vmc_env$apply_vision_model_capabilities(cfg, character(0), env_value = "m2")
  expect_false(isTRUE(out$local_model_capabilities[["m1"]]$vision))
  expect_true(isTRUE(out$local_model_capabilities[["m2"]]$vision))
})

test_that("apply_vision_model_capabilities tabloda olmayan vision modeli için kayıt açar", {
  cfg <- list(local_model_capabilities = list("m1" = list(thinking = FALSE)))
  out <- .vmc_env$apply_vision_model_capabilities(cfg, c("yeni-vmod"), env_value = "")
  expect_true(isTRUE(out$local_model_capabilities[["yeni-vmod"]]$vision))
  # Güvenli temel kayıt: thinking FALSE
  expect_false(isTRUE(out$local_model_capabilities[["yeni-vmod"]]$thinking))
})

test_that("apply_vision_model_capabilities geçersiz girdiye güvenli davranır", {
  # api_config liste değilse aynen döner
  expect_identical(.vmc_env$apply_vision_model_capabilities(NULL), NULL)
  expect_identical(.vmc_env$apply_vision_model_capabilities("x"), "x")
  # capabilities yoksa boş tablo oluşturup vision modeli ekleyebilir
  out <- .vmc_env$apply_vision_model_capabilities(list(), c("vmod"), env_value = "")
  expect_true(isTRUE(out$local_model_capabilities[["vmod"]]$vision))
})
