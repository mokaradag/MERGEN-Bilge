# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-review-705-filter-entity-behavior.R
# Açıklama: PR #705 inceleme bulgularının FİLTRE/VARLIK regresyon sözleşmeleri.
#           Tamamen çevrimdışı ve deterministiktir: DB, LLM, tarayıcı, SSO, ağ
#           ya da gizli değer GEREKMEZ. Fixture'lar sentetiktir.
# ==============================================================================

.pk705_filter_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  for (dosya in c("helpers_pk_text_turkish.R", "helpers_pk_query_meta_schema.R",
                  "helpers_pk_query_meta_access.R", "helpers_pk_filter_compile.R",
                  "helpers_pk_filter_group.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

.pk705_data <- function() {
  data.frame(
    Proje = c("ANKA", "AKINCI", "KIZILELMA", "ANKA"),
    Yil = c(2024L, 2024L, 2023L, 2023L),
    Bitis = as.POSIXct(c("2024-05-01 09:00:00", "2024-04-30 23:00:00",
                         "2024-05-01 23:30:00", "2024-06-01 00:00:00"), tz = "UTC"),
    Deger = c(1, 2, 3, 4),
    stringsAsFactors = FALSE
  )
}

# --- U5: KATI `less_than` gün sonuna genişlemez --------------------------------

test_that("less_than yalniz-tarih degeri GUN BASINDA biter", {
  env <- .pk705_filter_env()
  d <- .pk705_data()

  kati <- env$pk_filter_leaf_mask(
    d, env$pk_filter_normalize_leaf(
      list(column = "Bitis", operation = "less_than", value = "2024-05-01")
    )
  )
  expect_true(isTRUE(kati$ok))
  # 1 Mayis 09:00 ve 23:30 kayitlari DISARIDA kalmalidir.
  expect_equal(sum(kati$mask), 1L)

  kapsayici <- env$pk_filter_leaf_mask(
    d, env$pk_filter_normalize_leaf(
      list(column = "Bitis", operation = "less_or_equal", value = "2024-05-01")
    )
  )
  expect_true(isTRUE(kapsayici$ok))
  # Kapsayici sinir gun SONUNA genisler: 1 Mayis'in tamami dahildir.
  expect_equal(sum(kapsayici$mask), 3L)
})

# --- U15: desteklenmeyen mantik birlestiricisi REDDEDILIR ---------------------

test_that("bilinmeyen grup islecleri sessizce AND'e cevrilmez", {
  env <- .pk705_filter_env()
  d <- .pk705_data()

  for (islec in c("not", "xor", "andd", "nor")) {
    sonuc <- env$.pk_filter_eval_group(d, list(
      operator = islec,
      children = list(list(column = "Proje", operation = "equals", value = "ANKA"))
    ))
    expect_null(sonuc$mask, info = sprintf("islec kabul edildi: %s", islec))
    expect_true(length(sonuc$dropped) > 0L)
  }

  # Gecerli belirtecler CALISMAYA devam eder.
  for (islec in c("or", "veya", "and", "ve")) {
    sonuc <- env$.pk_filter_eval_group(d, list(
      operator = islec,
      children = list(list(column = "Proje", operation = "equals", value = "ANKA"))
    ))
    expect_false(is.null(sonuc$mask), info = sprintf("gecerli islec reddedildi: %s", islec))
  }
})

# --- U14: KISMEN degerlendirilen grup REDDEDILIR ------------------------------

test_that("bir cocugu dusen mantik grubu TAMAMEN reddedilir", {
  env <- .pk705_filter_env()
  d <- .pk705_data()

  sonuc <- env$.pk_filter_eval_group(d, list(
    operator = "and",
    children = list(
      list(column = "OlmayanSutun", operation = "equals", value = "X"),
      list(column = "Yil", operation = "equals", value = "2024")
    )
  ))

  # Yil-yalniz maske ile DEVAM ETMEK, kullanicinin ifadesini genisletmek olurdu.
  expect_null(sonuc$mask)
  expect_true(length(sonuc$dropped) >= 1L)
  expect_length(sonuc$applied, 0L)
})

# --- U46: `column_meta` tanimliyken BEYAN EDILMEMIS sutun filtrelenemez -------

test_that("column_meta VARKEN beyan edilmemis sutun ENGELLENIR", {
  env <- .pk705_filter_env()
  sorgu <- list(id = "q_syn", meta = list(column_meta = list(
    Proje = list(label = "Proje", role = "id", filterable = TRUE)
  )))

  expect_true(env$.pk_filter_meta_blocks(sorgu, "SonradanEklenenSutun"))
  expect_false(env$.pk_filter_meta_blocks(sorgu, "Proje"))

  # `column_meta` HIC yoksa (Tier-0 / v1) eski davranis KORUNUR.
  expect_false(env$.pk_filter_meta_blocks(list(id = "q_v1", meta = list()), "HerhangiSutun"))
})

# --- U8 + U27: grup yapraklari GERCEK sutun adiyla raporlanir -----------------

test_that("mantik grubu yapraklari applied/groups kaydinda GERCEK sutunla gorunur", {
  env <- .pk705_filter_env()
  d <- .pk705_data()

  # Mantik gruplari `filters` icinde INERT VERI olarak tasinir.
  derleme <- env$pk_filter_compile(
    d,
    filters = list(
      list(column = "Yil", operation = "equals", value = "2024"),
      list(operator = "or", children = list(
        list(column = "Proje", operation = "equals", value = "ANKA"),
        list(column = "Proje", operation = "equals", value = "AKINCI")
      ))
    )
  )

  sutunlar <- vapply(derleme$groups, function(g) as.character(g$column)[1], character(1))
  expect_true("Proje" %in% sutunlar)
  expect_true("Yil" %in% sutunlar)
  # Sentetik `__group__` adi asagi akisa SIZMAZ.
  expect_false("__group__" %in% sutunlar)
})

# --- U9: mantik grubu yapraklari VARLIK cozumlemesine ulasir ------------------

test_that("varlik cozumleyicisi grup cocuklarini gezer", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  for (.pk705_dosya in c("helpers_pk_entity_tree.R", "helpers_pk_entity_apply.R")) source(file.path(repo_root, "R", .pk705_dosya),
         encoding = "UTF-8", local = env)

  filtreler <- list(
    list(column = "Yil", value = "2024"),
    list(operator = "or", children = list(
      list(column = "Proje", value = "anka"),
      list(operator = "and", children = list(
        list(column = "Proje", value = "akinci")
      ))
    ))
  )

  yollar <- env$.pk_entity_leaf_paths(filtreler)
  expect_length(yollar, 3L)

  sutunlar <- vapply(yollar, function(y) env$.pk_entity_pluck(filtreler, y)$column,
                     character(1))
  expect_setequal(sutunlar, c("Yil", "Proje", "Proje"))

  # Yerinde guncelleme MANTIKSAL YAPIYI korur.
  guncel <- env$.pk_entity_set_leaf_value(filtreler, yollar[[3]], "AKINCI")
  expect_equal(guncel[[2]]$operator, "or")
  expect_equal(guncel[[2]]$children[[2]]$children[[1]]$value, "AKINCI")
  expect_equal(guncel[[1]]$value, "2024")
})

# --- P4-12: karar kaydi entity_role + column_meta tasir ----------------------

test_that("cozumleyici karari baglam kaydinin BEKLEDIGI alanlari tasir", {
  guvenlik <- readBin(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_entity_apply.R"),
    "raw", file.info(file.path(resolve_repo_root_for_tests(), "R",
                               "helpers_pk_entity_apply.R"))$size
  )
  metin <- iconv(rawToChar(guvenlik), from = "UTF-8", to = "UTF-8", sub = "byte")

  expect_true(grepl("karar$entity_role <- varlik_rolu", metin, fixed = TRUE))
  expect_true(grepl("karar$column_meta <- cmeta", metin, fixed = TRUE))
})
