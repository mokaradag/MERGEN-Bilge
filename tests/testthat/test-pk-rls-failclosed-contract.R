# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-rls-failclosed-contract.R
# Açıklama: D6 / D6b — satır düzeyi güvenliğin KAPALI BAŞARISIZ olması, yetki
#           kodu normalleştirmesi ve Faz 3a `pk_meta_validate_actual_columns()`
#           bağlantısı (M8). Tümü çevrimdışı ve deterministiktir: gerçek DB,
#           LLM, tarayıcı, SSO, ağ veya gerçek sır KULLANILMAZ.
# ==============================================================================

.pk_rls_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  source(file.path(repo_root, "R", "helpers_pk_query_meta_schema.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_query_meta_access.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_rls.R"),
         encoding = "UTF-8", local = env)
  env
}

.pk_rls_read_bytes <- function(rel_path) {
  full <- file.path(resolve_repo_root_for_tests(), rel_path)
  # DOSYA VARLIGI ACIKCA IDDIA EDILIR.
  #
  # Bu okuyucu dosya yoksa "" donuyordu; guvenlik taramalarinin cogu
  # `expect_false(grepl(...))` bicimindedir ve BOS dize bu iddialari
  # KENDILIGINDEN saglar. Dosya yeniden adlandirilirsa sozlesme "basarili"
  # raporlarken kapali-basarisiz muhafizi artik hic dogrulanmiyor olurdu.
  testthat::expect_true(file.exists(full), info = rel_path)
  size <- suppressWarnings(file.info(full)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(txt)) "" else enc2utf8(txt)
}

# Aciklama satirlari taranmaz: bu dosyalar KASITLI olarak "pk_tr_fold
# kullanilmaz" / "MERGEN_PK_ENGINE arkasina saklanamaz" gibi cumleler icerir.
.pk_rls_code_only <- function(rel_path) {
  txt <- .pk_rls_read_bytes(rel_path)
  satirlar <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  satirlar <- satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)]
  paste(satirlar, collapse = "\n")
}

test_that("beyan edilen RLS sutunu sonucta yoksa plan DURDURUR, atlamaz (D6)", {
  env <- .pk_rls_env()

  plan <- env$pk_rls_plan(
    user_info = list(Yetki = "PY", allowed_projects = "P1",
                     scope_state_projects = "available", scope_state_depts = "not_applicable"),
    rls_cols = list(proje_kodu_col = "ProjeKodu"),
    actual_columns = c("BaskaSutun", "Deger")
  )

  expect_true(isTRUE(plan$abort))
  expect_identical(plan$reason, "missing_column")
  expect_length(plan$predicates, 0L)
})

test_that("cozulemeyen kapsam DURDURUR, bos kapsam SIFIR satir uretir (D6b)", {
  env <- .pk_rls_env()
  rls <- list(proje_kodu_col = "ProjeKodu")
  sutunlar <- c("ProjeKodu", "Deger")

  # 1) Izin sorgusu hata verdi -> kapsam cozulemedi -> DURDUR.
  cozulemedi <- env$pk_rls_plan(
    list(Yetki = "PY", allowed_projects = NULL, scope_state_projects = "unavailable", scope_state_depts = "not_applicable"),
    rls, sutunlar
  )
  expect_true(isTRUE(cozulemedi$abort))
  expect_identical(cozulemedi$reason, "scope_unavailable")

  # 2) Kullanici izin tablosunda yok -> kapsam BOS -> SIFIR satir.
  #    KRITIK: bu ASLA "tum satirlar" olmamalidir.
  bos <- env$pk_rls_plan(
    list(Yetki = "PY", allowed_projects = NULL, scope_state_projects = "empty", scope_state_depts = "not_applicable"),
    rls, sutunlar
  )
  expect_false(isTRUE(bos$abort))
  expect_true(isTRUE(bos$zero_rows))
  expect_length(bos$predicates, 0L)

  # 3) Durum alani hic tasinmayan eski cagri yolu GUVENLI tarafa duser.
  eski <- env$pk_rls_plan(list(Yetki = "PY", allowed_projects = NULL, scope_state_depts = "not_applicable"), rls, sutunlar)
  expect_true(isTRUE(eski$abort))
  expect_identical(eski$reason, "scope_unavailable")

  # 4) EPS rolleri icin de ayni sozlesme gecerlidir.
  for (rol in c("KY-P", "DIR-P")) {
    eps_bos <- env$pk_rls_plan(
      list(Yetki = rol, allowed_eps = NULL, scope_state_eps = "empty", scope_state_depts = "not_applicable"),
      list(eps_kodu_col = "EPSKodu"), c("EPSKodu")
    )
    expect_true(isTRUE(eps_bos$zero_rows), info = rol)
    expect_false(isTRUE(eps_bos$abort), info = rol)
  }
})

test_that("NA veya bos Yetki hata vermek yerine kapali basarisiz olur", {
  env <- .pk_rls_env()

  for (yetki in list(NA_character_, "", NULL, "   ")) {
    plan <- env$pk_rls_plan(list(Yetki = yetki, scope_state_depts = "not_applicable"), list(), c("A"))
    expect_true(isTRUE(plan$abort))
    expect_identical(plan$reason, "missing_role")
  }
})

test_that("ADMIN filtresiz kalir, kapsamli rol predikat uretir", {
  env <- .pk_rls_env()

  admin <- env$pk_rls_plan(list(Yetki = "ADMIN", scope_state_depts = "not_applicable"), list(proje_kodu_col = "ProjeKodu"), "ProjeKodu")
  expect_true(isTRUE(admin$admin))
  expect_false(isTRUE(admin$abort))

  py <- env$pk_rls_plan(
    list(Yetki = "PY", allowed_depts = "A", allowed_projects = c("P1", "P3"),
         scope_state_projects = "available"),
    list(masraf_yeri_col = "MasrafYeri", proje_kodu_col = "ProjeKodu"),
    c("MasrafYeri", "ProjeKodu", "Deger")
  )
  expect_false(isTRUE(py$abort))
  expect_length(py$predicates, 2L)
  expect_setequal(vapply(py$predicates, function(p) p$column, character(1)),
                  c("MasrafYeri", "ProjeKodu"))
})

test_that("kapsam cozulmus ama sutun beyan edilmemisse analiz DURDURULUR", {
  env <- .pk_rls_env()

  # ESKIDEN bu durum yalnizca `unenforced` alaninda raporlanip analiz DEVAM
  # EDIYORDU. Kullanici icin bir kapsam COZULMUS (yani kisitli bir kullanici)
  # iken o boyutta hicbir kisit uygulanmadan satir donmek, kullanicinin kapsami
  # disindaki kayitlari gormesi demektir. Yetkilendirme siniri "beyan
  # edilmemis" oldugu icin yok sayilamaz: karar KAPALI BASARISIZ'dir.
  plan <- env$pk_rls_plan(
    list(Yetki = "PY", allowed_projects = "P1", scope_state_projects = "available", scope_state_depts = "not_applicable"),
    list(),
    c("Deger")
  )
  expect_true(isTRUE(plan$abort))
  expect_identical(plan$reason, "unenforceable_column")
  expect_true(grepl("sutun beyan etmiyor", plan$detail, fixed = TRUE))

  # Rol bu boyutu HIC ima etmiyorsa (kapsam yok) durdurma da YOKTUR.
  # PR #705: "kapsam yok" iddiasi ARTIK ACIKCA BEYAN EDILMELIDIR. `NULL`
  # kapsam tek basina "kisit yok" anlamina GELMEZ; cozulememis kapsamdan
  # ayirt edilemedigi icin kapali basarisiz olunur.
  serbest <- env$pk_rls_plan(
    list(Yetki = "KY-P", allowed_eps = NULL, scope_state_eps = "not_applicable",
         allowed_depts = NULL, scope_state_depts = "not_applicable"),
    list(),
    c("Deger")
  )
  expect_false(isTRUE(serbest$abort))

  # BEYANSIZ NULL departman kapsami: "kisit yok" DEGIL, "cozulemedi" sayilir.
  beyansiz <- env$pk_rls_plan(
    list(Yetki = "KY-P", allowed_eps = NULL, scope_state_eps = "not_applicable",
         allowed_depts = NULL),
    list(),
    c("Deger")
  )
  expect_true(isTRUE(beyansiz$abort))
  expect_identical(beyansiz$reason, "scope_unavailable")

  # ACIKCA "unavailable" beyan edilen departman kapsami da DURDURUR.
  cozulemeyen <- env$pk_rls_plan(
    list(Yetki = "KY-P", allowed_eps = NULL, scope_state_eps = "not_applicable",
         allowed_depts = NULL, scope_state_depts = "unavailable"),
    list(masraf_yeri_col = "MasrafYeri"),
    c("Deger", "MasrafYeri")
  )
  expect_true(isTRUE(cozulemeyen$abort))
  expect_identical(cozulemeyen$reason, "scope_unavailable")
})

test_that("pk_rls_code_norm asgari kalir ve pk_tr_fold boru hattini KULLANMAZ", {
  env <- .pk_rls_env()

  # Kirpma ve NFC yapar; buyuk/kucuk harf, ek veya noktalama DOKUNULMAZ.
  expect_identical(env$pk_rls_code_norm("  P1234  "), "P1234")
  expect_identical(env$pk_rls_code_norm("EPS-01"), "EPS-01")
  expect_false(identical(env$pk_rls_code_norm("ABC"), env$pk_rls_code_norm("abc")))
  expect_false(identical(env$pk_rls_code_norm("P-1"), env$pk_rls_code_norm("P1")))

  # Kanonik olarak es NFD/NFC yazimlar ayni anahtara duser.
  nfc <- intToUtf8(c(80L, 214L))                 # "PÖ"
  nfd <- intToUtf8(c(80L, 79L, 776L))            # "PO" + birlesik umlaut
  expect_identical(env$pk_rls_code_norm(nfc), env$pk_rls_code_norm(nfd))

  metin <- .pk_rls_code_only("R/helpers_pk_rls.R")
  expect_false(
    grepl("pk_tr_fold(", metin, fixed = TRUE, useBytes = TRUE),
    info = "Yetkilendirme kodlari pk_tr_fold boru hattindan GECMEMELIDIR."
  )
})

test_that("farkli yetkilendirme kodlarinin ayni anahtara cokmesi SERT HATADIR", {
  env <- .pk_rls_env()

  # Ayni kodun bosluk/NFC yazim farklari CAKISMA DEGILDIR.
  expect_true(isTRUE(env$pk_rls_assert_code_keys(c("P1", "P2", " P1 "))$ok))

  nfc <- intToUtf8(c(80L, 214L))
  nfd <- intToUtf8(c(80L, 79L, 776L))
  expect_true(isTRUE(env$pk_rls_assert_code_keys(c(nfc, nfd))$ok))

  # Bugunku asgari normallestirici ile cakisma URETILEMEZ. Muhafazanin degeri,
  # normallestirme ILERIDE gevsetilirse devreye girmesidir. Bunu kanitlamak icin
  # AYNI dosya taze bir ortama source edilir ve yalnizca pk_rls_code_norm
  # gevsetilir; sourcelanan tum fonksiyonlarin kapanis ortami bu ortam
  # oldugundan gevsetme tum zincire yansir.
  gevsek <- .pk_rls_env()
  gevsek$pk_rls_code_norm <- function(x) tolower(trimws(as.character(x)))

  cakisma <- gevsek$pk_rls_assert_code_keys(c("P1", "p1"))
  expect_false(isTRUE(cakisma$ok))
  expect_true(length(cakisma$collisions) > 0L)

  # Plan katmani ayni muhafazayi kullanir; gevsetilmis normallestirici ile
  # kapsam kodu cakismasi RLS'i DURDURUR.
  plan <- gevsek$pk_rls_plan(
    list(Yetki = "PY", allowed_projects = c("P1", "p1"),
         scope_state_projects = "available", scope_state_depts = "not_applicable"),
    list(proje_kodu_col = "ProjeKodu"),
    c("ProjeKodu")
  )
  expect_true(isTRUE(plan$abort))
  expect_identical(plan$reason, "code_collision")

  # Ayni girdi, gevsetilmemis uretim normallestiricisi ile TEMIZDIR.
  expect_true(isTRUE(env$pk_rls_assert_code_keys(c("P1", "p1"))$ok))
})

test_that("hicbir yapilandirma degeri fail-open filtrelemeyi geri getiremez", {
  metin <- .pk_rls_code_only("R/helpers_pk_rls.R")
  guvenlik <- .pk_rls_code_only("R/helpers_pk_analysis_security_summary.R")

  for (dosya in list(metin, guvenlik)) {
    expect_false(
      grepl("MERGEN_PK_ENGINE", dosya, fixed = TRUE, useBytes = TRUE),
      info = "RLS kapali basarisizligi motor bayragina baglanamaz."
    )
  }

  expect_false(
    grepl("pk_engine_is_v2", metin, fixed = TRUE, useBytes = TRUE),
    info = "RLS karari motor bayragina baglanamaz."
  )
  expect_true(
    grepl("pk_rls_plan(", guvenlik, fixed = TRUE, useBytes = TRUE),
    info = "apply_rls_to_data saf plan katmanini kullanmalidir."
  )
})

test_that("kullaniciya gosterilen RLS mesaji ic ayrinti sizdirmaz", {
  env <- .pk_rls_env()

  mesaj <- env$PK_RLS_ABORT_USER_MESSAGE
  expect_true(nzchar(mesaj))
  for (sizinti in c("ProjeKodu", "MasrafYeri", "EPSKodu", "DSN", "SELECT", "scope_unavailable")) {
    expect_false(grepl(sizinti, mesaj, fixed = TRUE),
                 info = sprintf("Mesaj ic ayrinti sizdiriyor: %s", sizinti))
  }
})

test_that("M8 baglandi: gercek-sutun kapisi RLS uyusmazliginda KOSULSUZ durdurur", {
  env <- .pk_rls_env()

  sorgu <- list(id = "q_sentetik", rls_columns = list(proje_kodu_col = "ProjeKodu"))

  # RLS sutunu gercek sonucta yok -> fail_closed -> her iki motorda da durdurur.
  for (v2 in c(FALSE, TRUE)) {
    kapi <- env$pk_meta_actual_column_gate(sorgu, c("Baska", "Deger"), v2)
    expect_true(isTRUE(kapi$abort), info = sprintf("engine_is_v2=%s", v2))
  }

  # Uyusan sonuc -> temiz.
  temiz <- env$pk_meta_actual_column_gate(sorgu, c("ProjeKodu", "Deger"), FALSE)
  expect_false(isTRUE(temiz$abort))
  expect_false(isTRUE(temiz$engine_abort))
})

test_that("RLS DISI metadata uyusmazligi yalnizca v2'de durdurur", {
  env <- .pk_rls_env()

  # Beyan edilen metadata sutunu gercek sonucta yok; RLS beyani ise DOGRU.
  sorgu <- list(
    id = "q_sentetik",
    rls_columns = list(proje_kodu_col = "ProjeKodu"),
    meta = list(column_meta = list(OlmayanOlcu = list(role = "measure")))
  )

  v1 <- env$pk_meta_actual_column_gate(sorgu, c("ProjeKodu"), FALSE)
  expect_false(isTRUE(v1$abort))
  expect_false(isTRUE(v1$engine_abort))
  expect_true(length(v1$warn) > 0L)

  v2 <- env$pk_meta_actual_column_gate(sorgu, c("ProjeKodu"), TRUE)
  expect_false(isTRUE(v2$abort))
  expect_true(isTRUE(v2$engine_abort))
})

test_that("gercek-sutun kapisi cagri yerlerinde BAGLIDIR", {
  modul <- .pk_rls_read_bytes("R/module_proje_kaynak_analizi.R")
  derin <- .pk_rls_read_bytes("R/helpers_deep_analysis.R")

  for (dosya in list(modul, derin)) {
    expect_true(
      grepl("pk_meta_actual_column_gate(", dosya, fixed = TRUE, useBytes = TRUE),
      info = "M8 kapisi RLS'ten once cagrilmalidir."
    )
    expect_true(
      grepl("pk_rls_error", dosya, fixed = TRUE, useBytes = TRUE),
      info = "Kapali basarisiz RLS kosulu cagri yerinde ele alinmalidir."
    )
  }
})
