# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-v1-compatibility-contract.R
# Açıklama: Motor sınırı sözleşmesi (master plan §10). `MERGEN_PK_ENGINE=v1`
#           iken D1–D5, D7–D9 ve D12 davranışları DEĞİŞMEMİŞ olmalıdır; yalnızca
#           dört çapraz-motor madde farklılaşabilir: koşulsuz RLS kapalı
#           başarısızlığı, salt-okunur SQL reddi, ODBC hata redaksiyonu ve
#           Faz 0 gözlem/durum tesisatı.
#
#           Tümü çevrimdışı ve deterministiktir: gerçek DB, LLM, tarayıcı, SSO,
#           ağ veya gerçek sır KULLANILMAZ.
# ==============================================================================

.pk_v1_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  for (f in c("helpers_pk_config.R", "helpers_pk_text_turkish.R",
              "helpers_pk_provenance.R", "helpers_pk_filter_compile.R", "helpers_pk_filter_group.R",
              "helpers_pk_filter_policy.R", "helpers_pk_analysis_filters_v2.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = env)
  }
  # apply_smart_filters ve v1 gövdesi; dispatch yüzeyi en sonda yüklenir.
  env$summarize_columns_for_ai <- function(...) ""
  source(file.path(repo_root, "R", "helpers_pk_analysis_filters_base.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_analysis_filters.R"),
         encoding = "UTF-8", local = env)
  # GÖZLEM KAYDI İSTEK KİMLİĞİ GEREKTİRİR (kapalı başarısız).
  # Kimliksiz kayıt artık hiç saklanmaz: süreç düzeyindeki gözlem ortamında
  # anahtar `request_id + query_id + query_name + question` birleşimidir ve
  # kimlik boşken aynı soruyu soran iki EŞZAMANLI kullanıcı tek anahtarı
  # paylaşıp birbirinin `matched_rows` değerini yayımlayabilirdi. Üretim yolu
  # kimliği daima taşır; sentetik gövde de aynı şekli kullanır.
  env$pk_provenance_current_request_id <- function(session) .PK_V1_ISTEK_KIMLIGI
  env
}

# Sentetik gövdenin kullandığı sabit istek kimliği.
.PK_V1_ISTEK_KIMLIGI <- "req-v1-sentetik"

# Yalnizca kod taranir; aciklama satirlari taranmaz (bayt guvenli okuma).
.pk_v1_code_only <- function(rel_path) {
  full <- file.path(resolve_repo_root_for_tests(), rel_path)
  size <- suppressWarnings(file.info(full)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(txt)) return("")
  satirlar <- strsplit(enc2utf8(txt), "\n", fixed = TRUE)[[1]]
  satirlar <- satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)]
  paste(satirlar, collapse = "\n")
}

.pk_v1_data <- function() {
  data.frame(
    ProjeAdi = c("SENTETIK RADAR", "SENTETIK ELEKTRONIK HARP", "SENTETIK LOJISTIK"),
    Durum = c("Aktif", "Aktif", "Pasif"),
    Butce = c(10, 20, 30),
    stringsAsFactors = FALSE
  )
}

# Ciktiyi bastirarak filtre uygular (v1 gövdesi bol miktarda cat() yazar).
.pk_v1_apply <- function(env, veri, talimat) {
  # `session` bu çerçevede TANIMLIDIR: gözlem bağlamı çağrı yığınını `session`
  # adı için tarar ve istek kimliğini oradan çözer. Üretimde bu değişken her
  # zaman kapsamdadır; sentetik gövde de aynı şekli kurar.
  session <- list()
  sonuc <- NULL
  utils::capture.output(
    sonuc <- env$apply_smart_filters(veri, talimat, "sentetik soru"),
    type = "output"
  )
  sonuc
}

test_that("v1 varsayilandir: bayrak verilmediginde motor v1'dir", {
  env <- .pk_v1_env()

  withr::with_envvar(list(MERGEN_PK_ENGINE = NA_character_), {
    withr::with_options(list(mergen.pk.engine = NULL), {
      expect_identical(env$pk_engine_mode(), "v1")
      expect_false(isTRUE(env$pk_engine_is_v2()))
    })
  })
})

test_that("D1: v1 AYNI sutundaki filtreleri HALA kesistirir (davranis degismedi)", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  talimat <- list(filters = list(
    list(column = "ProjeAdi", value = "RADAR", operation = "contains"),
    list(column = "ProjeAdi", value = "ELEKTRONIK HARP", operation = "contains")
  ))

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v1"), {
    v1 <- .pk_v1_apply(env, veri, talimat)
    # v1'in bilinen kusuru KORUNUR: kesisim -> 0 satir.
    expect_equal(nrow(v1), 0L)
  })

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v2"), {
    # v2 artik ayni sutundaki AYRI yapraklari da VE'ler: "birden cok yuklem
    # ayni sutuna deginiyor" gozleminden VEYA anlami CIKARILMAZ. VEYA istegi
    # ACIK olmalidir (cok degerli tek yaprak ya da `logic = "or"`).
    v2 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v2), 0L)

    acik <- .pk_v1_apply(env, veri, list(filters = list(
      list(column = "ProjeAdi", value = c("RADAR", "ELEKTRONIK HARP"),
           operation = "contains")
    )))
    expect_equal(nrow(acik), 2L)
  })
})

test_that("D2: v1 cok degerli filtreyi HALA kirpar (davranis degismedi)", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  talimat <- list(filters = list(
    list(column = "ProjeAdi",
         value = c("SENTETIK RADAR", "SENTETIK LOJISTIK"),
         operation = "exact_match")
  ))

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v1"), {
    v1 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v1), 1L)   # yalnizca ILK deger uygulandi
  })

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v2"), {
    v2 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v2), 2L)
  })
})

test_that("P0: HICBIR motor model uretimi filter_expression'i CALISTIRMAZ", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  # BU TEST ESKIDEN TERSINI SOYLUYORDU ("v1 filter_expression'i HALA
  # calistirir") ve boylece bir UZAKTAN KOD CALISTIRMA yolunu kasitli davranis
  # olarak belgeliyordu. `filter_expression` metni tamamen LLM uretimidir ve
  # LLM girdisi kullanici istemi ile sohbet gecmisinden beslenir; istem
  # enjeksiyonu ile buraya rastgele R kodu tasinabiliyordu. Mekanizma HER IKI
  # motordan da kaldirilmistir.
  talimat <- list(
    filters = list(),
    filter_expression = "{ .pk_v1_sayac <<- .pk_v1_sayac + 1L; Butce > 15 }"
  )

  for (motor in c("v1", "v2")) {
    withr::with_envvar(list(MERGEN_PK_ENGINE = motor), {
      env$.pk_v1_sayac <- 0L
      sonuc <- .pk_v1_apply(env, veri, talimat)
      # Ifade YOK SAYILIR: hicbir satir elenmez ve sayac artmaz.
      expect_equal(nrow(sonuc), 3L, info = paste("motor:", motor))
      expect_identical(env$.pk_v1_sayac, 0L, info = paste("motor:", motor))
    })
  }
})

test_that("D4: v1'de sifir eslesme politikasi YOKTUR", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  talimat <- list(filters = list(
    list(column = "ProjeAdi", value = "HIC OLMAYAN", operation = "exact_match")
  ))

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v1"), {
    v1 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v1), 0L)
    # v1 karar ozniteligi TASIMAZ.
    expect_null(attr(v1, env$PK_FILTER_V2_ATTR, exact = TRUE))
  })

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v2"), {
    v2 <- .pk_v1_apply(env, veri, talimat)
    karar <- attr(v2, env$PK_FILTER_V2_ATTR, exact = TRUE)
    expect_identical(karar$action, "refuse")
  })
})

test_that("D9: filtre zaman asimi v1'de 8 saniyede sabit kalir", {
  metin_yolu <- file.path(resolve_repo_root_for_tests(),
                          "R", "helpers_pk_analysis_filters_base.R")
  size <- suppressWarnings(file.info(metin_yolu)$size[1])
  con <- file(metin_yolu, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  metin <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  # v1 varsayilani 8 saniye olarak KORUNUR; yapilandirilabilir deger yalnizca
  # v2 dalinda tuketilir.
  expect_true(grepl("filter_timeout <- 8", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("MERGEN_PK_FILTER_TIMEOUT_SEC", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pk_engine_is_v2()", metin, fixed = TRUE, useBytes = TRUE))
})

test_that("v1 gozlem sozlesmesi (Faz 0) her iki motorda da korunur", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  talimat <- list(filters = list(
    list(column = "Durum", value = "Aktif", operation = "exact_match")
  ))

  for (motor in c("v1", "v2")) {
    withr::with_envvar(list(MERGEN_PK_ENGINE = motor), {
      sonuc <- .pk_v1_apply(env, veri, talimat)
      expect_equal(nrow(sonuc), 2L, info = motor)

      gozlem <- env$pk_filter_observation_take(list(
        request_id = .PK_V1_ISTEK_KIMLIGI, question = "sentetik soru"))
      expect_true(is.list(gozlem), info = motor)
      expect_identical(as.integer(gozlem$matched_rows), 2L, info = motor)
      expect_true(length(gozlem$applied_filters) > 0L, info = motor)
    })
  }
})

test_that("dort capraz-motor madde v1'de de ETKINDIR", {
  repo_root <- resolve_repo_root_for_tests()

  oku <- function(rel) {
    full <- file.path(repo_root, rel)
    size <- suppressWarnings(file.info(full)$size[1])
    con <- file(full, open = "rb")
    on.exit(close(con), add = TRUE)
    raw_data <- readBin(con, what = "raw", n = size)
    txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
    satirlar <- strsplit(enc2utf8(txt), "\n", fixed = TRUE)[[1]]
    satirlar <- satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)]
    paste(satirlar, collapse = "\n")
  }

  # 1) RLS kapali basarisizligi ve 2) salt-okunur SQL kapisi ve
  # 3) ODBC redaksiyonu: hicbiri motor bayragina bagli DEGILDIR.
  for (dosya in c("R/helpers_pk_rls.R", "R/helpers_pk_sql_readonly.R",
                  "R/helpers_pk_safe_errors.R")) {
    metin <- oku(dosya)
    expect_false(grepl("MERGEN_PK_ENGINE", metin, fixed = TRUE, useBytes = TRUE), info = dosya)
    expect_false(grepl("pk_engine_is_v2", metin, fixed = TRUE, useBytes = TRUE), info = dosya)
  }

  # 4) Faz 0 gozlem/durum tesisati da bayraktan bagimsizdir.
  gozlem <- oku("R/helpers_pk_analysis_filters.R")
  expect_true(grepl(".pk_filter_observation_store(", gozlem, fixed = TRUE, useBytes = TRUE))
})

test_that("v2'ye ozgu davranis dosyalari motor bayragina BAGLI kalir", {
  repo_root <- resolve_repo_root_for_tests()

  # Modul, v2 davranislarini yalnizca bayrak acikken devreye alir.
  full <- file.path(repo_root, "R", "module_proje_kaynak_analizi.R")
  size <- suppressWarnings(file.info(full)$size[1])
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  metin <- enc2utf8(suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  ))

  expect_true(grepl("pk_engine_is_v2(", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pk_filter_degraded_gate(", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pk_engine_v2 &&", metin, fixed = TRUE, useBytes = TRUE))
})

test_that("motor kipi sorgu metadatasindan (query$meta) cozulur", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()
  talimat <- list(filters = list(
    list(column = "Durum", operation = "exact_match", value = "Aktif")
  ))

  # `.pk_filter_observation_context()` cagri cercevesinden TAM sorgu nesnesini
  # toplar; motor kipi bu yuzden modulun okudugu alanla AYNI yerden
  # cozulmelidir. Aksi halde modul v2 sanip politika/butce uygularken filtreler
  # v1 govdesinde kalir ve D1-D5 sessizce devre disi kalirdi.
  cagir <- function(sorgu) {
    selected_query <- sorgu
    sonuc <- NULL
    utils::capture.output(
      sonuc <- env$apply_smart_filters(veri, talimat, "sentetik soru"),
      type = "output"
    )
    sonuc
  }

  withr::with_envvar(list(MERGEN_PK_ENGINE = NA_character_), {
    withr::with_options(list(mergen.pk.engine = NULL), {
      v2_sonuc <- cagir(list(id = "q", name = "Q", meta = list(engine = "v2")))
      expect_false(
        is.null(attr(v2_sonuc, env$PK_FILTER_V2_ATTR, exact = TRUE)),
        info = "meta$engine = v2 iken filtreler v2 govdesinde calismalidir."
      )

      # Ust duzey `engine` alani motor kipini DEGISTIRMEZ; modul onu okumaz.
      v1_sonuc <- cagir(list(id = "q", name = "Q", engine = "v2", meta = list()))
      expect_true(
        is.null(attr(v1_sonuc, env$PK_FILTER_V2_ATTR, exact = TRUE)),
        info = "Ust duzey engine alani v2'yi tetiklememelidir (modul meta okur)."
      )
    })
  })
})

test_that("v2 gozlemi filtre DEGERINI korur (koken alt bilgisi bos yazmaz)", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  # Koken alt bilgisi (.pk_footer_filter_line) ve dusurulen filtre bozulma
  # metni (.pk_dropped_filter_degradations) filtreyi `f$value` alanindan okur;
  # v2 derleyicisinin normallestirilmis yapraginda ise alan adi COGULdur
  # (`values`). Bu iddia bir REGRESYON MUHAFIZIDIR, mevcut bir kusurun kaniti
  # DEGILDIR: bugun `$` kismi ad eslestirmesi sayesinde deger dogru yaziliyor.
  # Muhafiz, o tesadufi kurtarma kaybolursa (`[[` kullanimi ya da yapraga
  # "value" ile baslayan ikinci bir alan eklenmesi) alt bilginin sessizce
  # `Durum = ""` yazmaya baslamasini engeller.
  talimat <- list(filters = list(
    list(column = "Durum", operation = "exact_match", value = "Aktif"),
    list(column = "OlmayanSutun", operation = "exact_match", value = "X")
  ))

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v2"), {
    withr::with_options(list(mergen.pk.engine = NULL), {
      # `session` kapsamda OLMALIDIR: gözlem kaydı istek kimliği gerektirir
      # (bkz. `.pk_v1_apply()` içindeki aynı gerekçe).
      session <- list()
      utils::capture.output(
        sonuc <- env$apply_smart_filters(veri, talimat, "sentetik deger sorusu"),
        type = "output"
      )
      expect_false(is.null(attr(sonuc, env$PK_FILTER_V2_ATTR, exact = TRUE)))

      gozlem <- env$pk_filter_observation_take(list(
        request_id = .PK_V1_ISTEK_KIMLIGI, question = "sentetik deger sorusu"))
      expect_false(is.null(gozlem))

      expect_length(gozlem$applied_filters, 1L)
      uygulanan <- gozlem$applied_filters[[1]]
      expect_identical(uygulanan$column, "Durum")
      expect_identical(uygulanan$value, "Aktif")
      expect_identical(uygulanan$operation, "exact_match")

      expect_length(gozlem$dropped_filters, 1L)
      dusen <- gozlem$dropped_filters[[1]]$filter
      expect_identical(dusen$column, "OlmayanSutun")
      expect_identical(dusen$value, "X")

      # Alt bilgi satiri degeri gercekten yazar.
      satir <- env$.pk_footer_filter_line(list(
        filter_status = "ok_filtered", filters = gozlem$applied_filters
      ))
      expect_true(grepl("Aktif", satir, fixed = TRUE))
      expect_false(grepl('= ""', satir, fixed = TRUE))
    })
  })
})

# ==============================================================================
# Faz 2 — deterministik analiz + dışa aktarım (§5.7-§5.9, D17-D21)
#
# §10 dört çapraz-motor maddesini sayar ve Faz 2'nin HİÇBİRİ o listede yoktur.
# Bu yüzden analiz paketi, R'ye ait tablo/ek, epistemik istem ve D21 düzeltmesi
# YALNIZCA `MERGEN_PK_ENGINE=v2` altında etkin olmalıdır.
# ==============================================================================

.pk_v2_result_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  env$safe_unlink_if_exists <- function(path) invisible(TRUE)
  env$normalize_pk_dataframe_utf8 <- function(df) df

  for (f in c("helpers_pk_config.R", "helpers_pk_text_turkish.R",
              "helpers_pk_provenance.R", "helpers_pk_prompt_budget.R",
              "helpers_pk_analysis_prompts.R", "helpers_pk_precision.R", "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R",
              "helpers_pk_analysis_packet.R", "helpers_pk_packet_render.R",
              "helpers_pk_numeric_provenance.R", "helpers_pk_export_plan.R",
              "helpers_pk_export_xlsx.R", "helpers_pk_answer_compose.R",
              "helpers_pk_statistical_summary.R", "helpers_pk_analysis_result.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = env)
  }
  env$MAX_ANALYSIS_PROMPT_CHARS <- 120000L
  env
}

.pk_v2_frames <- function() {
  yetkili <- data.frame(
    ProjeAdi = rep(c("SENTETIK A", "SENTETIK B"), each = 10),
    Saat = seq_len(20),
    stringsAsFactors = FALSE
  )
  list(secure = yetkili, filtered = yetkili[1:10, , drop = FALSE])
}

.pk_v2_query <- function() {
  list(id = "q_sentetik", name = "Sentetik Sorgu", description = "Sentetik açıklama",
       meta = list(column_meta = list(
         Saat = list(label = "Saat", role = "measure", unit = "saat", decimals = 1L,
                     additive = TRUE, capability = "labor.remaining_hours")
       )))
}

test_that("D21: v1 filtre ONCESI cerceveyi dondurur, v2 filtre SONRASI cerceveyi", {
  env <- .pk_v2_result_env()
  cerceve <- .pk_v2_frames()

  v1 <- NULL
  utils::capture.output(
    v1 <- env$pk_build_analysis_result(cerceve$filtered, cerceve$secure,
                                       .pk_v2_query(), "sentetik soru",
                                       engine_is_v2 = FALSE),
    type = "output"
  )
  expect_equal(nrow(v1$data), 20L)
  expect_identical(v1$type, "data_analysis")

  v2 <- env$pk_build_analysis_result(cerceve$filtered, cerceve$secure,
                                     .pk_v2_query(), "sentetik soru",
                                     engine_is_v2 = TRUE)
  expect_equal(nrow(v2$data), 10L)
  expect_identical(v2$type, "data_analysis")
})

test_that("Ortak Oturum koprusunun okudugu alanlar HER IKI motorda da korunur", {
  env <- .pk_v2_result_env()
  cerceve <- .pk_v2_frames()

  for (v2 in c(FALSE, TRUE)) {
    sonuc <- NULL
    utils::capture.output(
      sonuc <- env$pk_build_analysis_result(cerceve$filtered, cerceve$secure,
                                            .pk_v2_query(), "sentetik soru",
                                            engine_is_v2 = v2),
      type = "output"
    )
    expect_true(is.character(sonuc$prompt_context) && nzchar(sonuc$prompt_context),
                info = sprintf("engine_is_v2=%s icin prompt_context bos.", v2))
    expect_true(is.character(sonuc$user_context) && nzchar(sonuc$user_context))
    expect_identical(sonuc$query_name, "Sentetik Sorgu")
    expect_equal(sonuc$max_tokens, 4096)
  }
})

test_that("D20: 'markdown tablo uret' talimati v1'de DURUYOR, v2'de KALDIRILDI", {
  env <- .pk_v2_result_env()
  q <- .pk_v2_query()

  for (kip in c("summary", "full")) {
    v1_istem <- env$pk_build_analysis_system_prompt(kip, q)
    expect_true(grepl("markdown tablo", v1_istem, fixed = TRUE),
                info = "v1 istemi degistirilmemelidir (motor siniri).")

    v2_istem <- env$pk_build_analysis_system_prompt_v2(kip, q)
    expect_false(grepl("markdown tablo", v2_istem, fixed = TRUE))
    expect_true(grepl("TABLO ÜRETME", v2_istem, fixed = TRUE))
  }
})

test_that("D20: v2 istemi epistemik etiketleme kullanir ve benchmark istemez", {
  env <- .pk_v2_result_env()
  istem <- env$pk_build_analysis_system_prompt_v2("summary", .pk_v2_query())

  for (etiket in c("Gözlem", "Yorum", "Olası açıklama", "Öneri", "Sınırlılık")) {
    expect_true(grepl(etiket, istem, fixed = TRUE),
                info = sprintf("'%s' etiketi v2 isteminde yok.", etiket))
  }
  # TEST ADI "benchmark ISTEMEZ" diyor ama cıplak belirtec, modele benchmark
  # URETMESINI soyleyen bir istemde de bulunurdu. TAM OLUMSUZ ifade aranır.
  expect_true(grepl("Elinde benchmark verisi YOKTUR", istem, fixed = TRUE))
  expect_false(grepl("sektör benchmarks'leri ver", istem, fixed = TRUE))
  expect_true(grepl("uydurma", istem, fixed = TRUE))
  expect_false(grepl("KÖK SEBEP", istem, fixed = TRUE))
  expect_true(grepl("[fact:", istem, fixed = TRUE))
})

test_that("Olgular, R'ye ait blok ve ek YALNIZCA v2 sonucunda bulunur", {
  env <- .pk_v2_result_env()
  cerceve <- .pk_v2_frames()

  v1 <- NULL
  utils::capture.output(
    v1 <- env$pk_build_analysis_result(cerceve$filtered, cerceve$secure,
                                       .pk_v2_query(), "sentetik soru",
                                       engine_is_v2 = FALSE),
    type = "output"
  )
  expect_null(v1$pk_facts)
  expect_null(v1$pk_answer_block)
  expect_null(v1$pk_attachment)

  v2 <- env$pk_build_analysis_result(cerceve$filtered, cerceve$secure,
                                     .pk_v2_query(), "sentetik soru",
                                     engine_is_v2 = TRUE)
  expect_true(length(v2$pk_facts) > 0L)
  expect_true(is.character(v2$pk_answer_block))
  expect_true(grepl("Sonuç tablosu", v2$pk_answer_block, fixed = TRUE))
  expect_true(grepl("[fact:", v2$user_context, fixed = TRUE))
})

test_that("v1 yuku eski istatistiksel ozet bicimini KORUR", {
  env <- .pk_v2_result_env()
  cerceve <- .pk_v2_frames()

  v1 <- NULL
  utils::capture.output(
    v1 <- env$pk_build_analysis_result(cerceve$filtered, cerceve$secure,
                                       .pk_v2_query(), "sentetik soru",
                                       engine_is_v2 = FALSE),
    type = "output"
  )

  expect_true(grepl("ISTATISTIKSEL OZET", v1$user_context, fixed = TRUE))
  expect_true(grepl("ORNEK SATIRLAR (JSON)", v1$user_context, fixed = TRUE))
  expect_false(grepl("ANALIZ PAKETI", v1$user_context, fixed = TRUE))
  expect_false(grepl("[fact:", v1$user_context, fixed = TRUE))
})

test_that("Faz 2 dosyalari motor bayragina BAGLI kalir (sizinti yok)", {
  # Sonuc kurucusu ayrimi yapan TEK yerdir; alt katmanlar bayragi okumaz.
  for (dosya in c("R/helpers_pk_analysis_packet.R", "R/helpers_pk_packet_render.R",
                  "R/helpers_pk_export_plan.R", "R/helpers_pk_export_xlsx.R",
                  "R/helpers_pk_answer_compose.R", "R/helpers_pk_packet_stats.R")) {
    kod <- .pk_v1_code_only(dosya)
    expect_false(grepl("pk_engine_is_v2", kod, fixed = TRUE, useBytes = TRUE),
                 info = sprintf("%s motor bayragini okumamalidir.", dosya))
  }

  kod <- .pk_v1_code_only("R/helpers_pk_analysis_result.R")
  expect_true(grepl("engine_is_v2", kod, fixed = TRUE, useBytes = TRUE))
})

test_that("Sayisal koken dogrulamasi olgu SAKLANMAMISSA hic calismaz (v1 yolu)", {
  env <- .pk_v2_result_env()
  oturum <- list(userData = new.env(parent = emptyenv()))

  env$pk_provenance_stash(oturum, "\n\n---\n**Analiz Kaynağı**\n- Sorgu: q\n")
  metin <- env$pk_provenance_decorate("Yanit 999 [fact:uydurma.sum.overall].", oturum)

  # Olgu yoksa dogrulama devreye girmez ve metin oldugu gibi kalir.
  expect_true(grepl("[fact:uydurma.sum.overall]", metin, fixed = TRUE))
  expect_true(grepl("Analiz Kaynağı", metin, fixed = TRUE))
})

test_that("Olgu saklandiginda isaretler silinir ve blok alt bilginin ONUNE gelir", {
  env <- .pk_v2_result_env()
  oturum <- list(userData = new.env(parent = emptyenv()))
  olgular <- env$pk_measure_facts(c(1, 2, 3), "Saat",
                                  list(label = "Saat", unit = "saat", decimals = 1L),
                                  additive = TRUE)
  kimlik <- Filter(function(o) identical(o$aggregation, "sum"), olgular)[[1]]$fact_id

  env$pk_provenance_stash(
    oturum,
    paste0("\n\n**Önizleme**\n\n| a |\n", "\n\n---\n**Analiz Kaynağı**\n- Sorgu: q\n"),
    facts = olgular, query_id = "q_sentetik"
  )

  metin <- NULL
  utils::capture.output(
    metin <- env$pk_provenance_decorate(
      sprintf("Toplam 6,0 saat [fact:%s].", kimlik), oturum
    ),
    type = "output"
  )

  expect_false(grepl("[fact:", metin, fixed = TRUE))
  expect_true(grepl("Toplam 6,0 saat.", metin, fixed = TRUE))
  # HER İKİ İŞARETÇİNİN VARLIĞI ÖNCE KANITLANIR. `regexpr()` desen yoksa `-1`
  # döner; önizleme bloğu üretilmez olsa bile `-1 < <konum>` DOĞRU kalır ve
  # test bozuk üretim çıktısı için BAŞARILI raporlardı.
  onizleme_pos <- regexpr("Önizleme", metin, fixed = TRUE)
  kaynak_pos <- regexpr("Analiz Kaynağı", metin, fixed = TRUE)
  expect_gt(onizleme_pos, 0L)
  expect_gt(kaynak_pos, 0L)
  expect_lt(onizleme_pos, kaynak_pos)
})

test_that("Alt bilgi ek satirini gosterir ama RLS oncesi sayiyi ASLA yazmaz", {
  env <- .pk_v2_result_env()

  alt <- env$pk_build_provenance_footer(list(
    query_id = "q_sentetik", query_name = "Sentetik Sorgu",
    filter_status = "ok_filtered", filters = list(),
    authorized_rows = 12405L, filtered_rows = 312L, pre_rls_rows = 41930L,
    attachment = list(status = "ok", files = list(list(
      name = "sentetik.xlsx", rows = 312L, cols = 14L, url = "session/pk_export_x"
    )))
  ))

  expect_true(grepl("**Ek:**", alt, fixed = TRUE))
  expect_true(grepl("sentetik.xlsx", alt, fixed = TRUE))
  expect_true(grepl("312 satır × 14 sütun", alt, fixed = TRUE))
  expect_true(grepl("12.405", alt, fixed = TRUE))
  expect_false(grepl("41.930", alt, fixed = TRUE))
  expect_false(grepl("41930", alt, fixed = TRUE))
})

test_that("Reddedilen ek alt bilgide de GORUNUR", {
  env <- .pk_v2_result_env()
  alt <- env$pk_build_provenance_footer(list(
    query_id = "q_sentetik", query_name = "Sentetik", filter_status = "ok_filtered",
    authorized_rows = 10L, filtered_rows = 10L,
    attachment = list(status = "refused", files = list(),
                      message = "Sonuç kümesi çok büyük; lütfen daraltın.")
  ))

  expect_true(grepl("Üretilmedi", alt, fixed = TRUE))
  expect_true(grepl("daraltın", alt, fixed = TRUE))
})
