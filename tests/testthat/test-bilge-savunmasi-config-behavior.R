# ==============================================================================
# Dosya Yolu: tests/testthat/test-bilge-savunmasi-config-behavior.R
# Açıklama: Bilge Savunması yapılandırma katmanının davranış testleri:
#           özellik bayrağı çözümü, persona oyun manifesti (kanonik kimlik
#           kaynağına bağlılık), harita/zorluk katalogları ve deterministik
#           haftalık meydan okuma türetimi. Tamamen çevrimdışıdır; DB, ağ,
#           tarayıcı veya Shiny oturumu GEREKMEZ.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("normalize_character_id", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "config_characters.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("bilge_savunmasi_enabled", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "config_bilge_savunmasi.R"),
           encoding = "UTF-8", local = globalenv())
  }
})

test_that("özellik bayrağı varsayılan olarak açıktır ve yalnızca açık kapalı değerleriyle kapanır", {
  eski_env <- Sys.getenv("MERGEN_BILGE_SAVUNMASI_ENABLED", unset = NA)
  eski_opt <- getOption("mergen.bilge_savunmasi.enabled", default = NULL)
  on.exit({
    if (is.na(eski_env)) {
      Sys.unsetenv("MERGEN_BILGE_SAVUNMASI_ENABLED")
    } else {
      Sys.setenv(MERGEN_BILGE_SAVUNMASI_ENABLED = eski_env)
    }
    options(mergen.bilge_savunmasi.enabled = eski_opt)
  }, add = TRUE)

  options(mergen.bilge_savunmasi.enabled = NULL)
  Sys.unsetenv("MERGEN_BILGE_SAVUNMASI_ENABLED")
  expect_true(bilge_savunmasi_enabled())

  Sys.setenv(MERGEN_BILGE_SAVUNMASI_ENABLED = "FALSE")
  expect_false(bilge_savunmasi_enabled())
  Sys.setenv(MERGEN_BILGE_SAVUNMASI_ENABLED = "kapalı")
  expect_false(bilge_savunmasi_enabled())
  Sys.setenv(MERGEN_BILGE_SAVUNMASI_ENABLED = "0")
  expect_false(bilge_savunmasi_enabled())

  # Anlamsız değerler oyunu kapatmaz (yalnızca açık kapalı değerleri kapatır).
  Sys.setenv(MERGEN_BILGE_SAVUNMASI_ENABLED = "belki")
  expect_true(bilge_savunmasi_enabled())

  # Seçenek ortam değişkeninden önceliklidir.
  Sys.setenv(MERGEN_BILGE_SAVUNMASI_ENABLED = "TRUE")
  options(mergen.bilge_savunmasi.enabled = FALSE)
  expect_false(bilge_savunmasi_enabled())
  options(mergen.bilge_savunmasi.enabled = "off")
  expect_false(bilge_savunmasi_enabled())
  options(mergen.bilge_savunmasi.enabled = TRUE)
  expect_true(bilge_savunmasi_enabled())
})

test_that("persona oyun manifesti kanonik kimlik kaynağından türetilir", {
  manifest <- bs_persona_manifest()

  expect_length(manifest, 5L)
  idler <- vapply(manifest, function(p) p$id, character(1))
  expect_identical(sort(idler), sort(CHARACTER_VALID_IDS))

  # Kimlik alanları config_characters.R kayıtlarıyla birebir aynıdır.
  for (persona in manifest) {
    kayit <- get_character_record(persona$id)
    expect_identical(persona$ad, kayit$label)
    expect_identical(persona$tam_ad, kayit$full_name)
    expect_identical(persona$unvan, kayit$subtitle)
    expect_identical(persona$aksan, kayit$accent)
    expect_identical(persona$avatar, kayit$avatar)
    expect_identical(persona$portre, kayit$image)
    expect_true(nzchar(persona$rol))
    expect_true(nzchar(persona$yetenek_id))
    expect_true(nzchar(persona$yetenek_ad))
  }

  # Modern yetenek kimlikleri persona sözleşmesindeki beşliyi kullanır.
  yetenekler <- vapply(manifest, function(p) p$yetenek_id, character(1))
  expect_identical(
    sort(yetenekler),
    sort(c("cozum_dalgasi", "sinyal_taramasi", "rota_projesi",
           "dogrulama_isini", "rehber_halkasi"))
  )
})

test_that("persona oyun manifesti eski mitolojik kimlik içermez", {
  manifest <- bs_persona_manifest()
  metin <- tolower(paste(unlist(manifest), collapse = " "))
  for (eski in c("mergen", "ulgen", "kayra", "erlik", "umay")) {
    expect_false(
      grepl(paste0("\\b", eski, "\\b"), metin, perl = TRUE),
      info = paste0("Manifest eski kimlik içermemeli: ", eski)
    )
  }
})

test_that("harita kataloğu altı haritayı doğru kilit zinciriyle taşır", {
  katalog <- bs_harita_katalogu()

  # Bilinçli genişletme: kampanya 3 -> 6 haritaya çıktı (Veri Labirenti,
  # Sinyal Vadisi, Karar Zirvesi eklendi); kilit zinciri doğrusaldır.
  expect_identical(
    names(katalog),
    c("baglam_kapisi", "celiski_kavsagi", "bilgi_cekirdegi",
      "veri_labirenti", "sinyal_vadisi", "karar_zirvesi")
  )
  expect_null(katalog$baglam_kapisi$acilis_kosulu)
  expect_identical(katalog$celiski_kavsagi$acilis_kosulu, "baglam_kapisi")
  expect_identical(katalog$bilgi_cekirdegi$acilis_kosulu, "celiski_kavsagi")
  expect_identical(katalog$veri_labirenti$acilis_kosulu, "bilgi_cekirdegi")
  expect_identical(katalog$sinyal_vadisi$acilis_kosulu, "veri_labirenti")
  expect_identical(katalog$karar_zirvesi$acilis_kosulu, "sinyal_vadisi")

  expect_identical(katalog$baglam_kapisi$dalga_sayisi, 8L)
  expect_identical(katalog$celiski_kavsagi$dalga_sayisi, 10L)
  expect_identical(katalog$bilgi_cekirdegi$dalga_sayisi, 12L)
  expect_identical(katalog$veri_labirenti$dalga_sayisi, 12L)
  expect_identical(katalog$sinyal_vadisi$dalga_sayisi, 14L)
  expect_identical(katalog$karar_zirvesi$dalga_sayisi, 16L)

  # Kilit zinciri sıralaması doğrusaldır (her harita bir öncekine bağlıdır).
  for (kayit in katalog) {
    expect_true(kayit$taban_cekirdek > 0)
    expect_true(kayit$dalga_dusman_ust_siniri > 0)
    expect_true(nzchar(kayit$ad))
    # Dalga sayısı, düşman/patron sayı vektörlerinin uzunluğuyla tutarlı.
    expect_length(kayit$dalga_dusman_sayilari, kayit$dalga_sayisi)
    expect_length(kayit$dalga_patron_sayilari, kayit$dalga_sayisi)
    expect_true(all(kayit$dalga_dusman_sayilari <= kayit$dalga_dusman_ust_siniri))
  }

  zorluklar <- bs_zorluk_katalogu()
  expect_identical(names(zorluklar), c("normal", "gelismis"))
  expect_true(zorluklar$gelismis$puan_carpani > zorluklar$normal$puan_carpani)
})

test_that("oyun müzik kataloğu üç grup taşır ve boş klasörlerde güvenli çalışır", {
  gruplar <- bs_muzik_gruplari()
  expect_identical(gruplar, c("menu", "bolum_1", "bolum_2"))

  # Boş/yok dizin: her grup boş liste; oyun sessiz ama tam işlevli kalır.
  bos <- bs_muzik_katalogu(tempfile())
  expect_identical(names(bos), gruplar)
  for (g in gruplar) expect_length(as.character(bos[[g]]), 0L)

  # Parça konulunca gruptan URL listesi üretilir (I() ile dizi olarak gider).
  kok <- tempfile()
  dir.create(file.path(kok, "menu"), recursive = TRUE)
  writeLines("x", file.path(kok, "menu", "tema_01.mp3"))
  writeLines("x", file.path(kok, "menu", "tema_02.ogg"))
  dolu <- bs_muzik_katalogu(kok)
  urller <- as.character(dolu$menu)
  expect_length(urller, 2L)
  expect_true(all(grepl("^assets/bilge_savunmasi/muzik/menu/", urller)))
  expect_true(inherits(dolu$menu, "AsIs"))
})

test_that("hafta kodu ve tohum türetimi deterministiktir", {
  sabit_tarih <- as.POSIXct("2026-07-15 12:00:00", tz = "Europe/Istanbul")

  kod1 <- bs_hafta_kodu(sabit_tarih)
  kod2 <- bs_hafta_kodu(sabit_tarih + 3600)
  expect_identical(kod1, kod2)
  expect_match(kod1, "^\\d{4}-W\\d{2}$")

  # Aynı hafta kodu her zaman aynı tohumu üretir.
  expect_identical(bs_hafta_tohumu(kod1), bs_hafta_tohumu(kod1))
  expect_true(bs_hafta_tohumu(kod1) >= 1L)

  # Farklı haftalar farklı tohum üretir.
  sonraki_hafta <- bs_hafta_kodu(sabit_tarih + 7 * 24 * 3600)
  expect_false(identical(kod1, sonraki_hafta))
  expect_false(identical(bs_hafta_tohumu(kod1), bs_hafta_tohumu(sonraki_hafta)))
})

test_that("haftalık meydan okuma bileşimi deterministik ve geçerlidir", {
  sabit_tarih <- as.POSIXct("2026-07-15 12:00:00", tz = "Europe/Istanbul")

  meydan1 <- bs_haftalik_meydan_okuma(sabit_tarih)
  meydan2 <- bs_haftalik_meydan_okuma(sabit_tarih + 24 * 3600)

  # Aynı hafta içinde tüm oyuncular aynı bileşimi alır.
  expect_identical(meydan1$hafta_kodu, meydan2$hafta_kodu)
  expect_identical(meydan1$harita, meydan2$harita)
  expect_identical(meydan1$tohum, meydan2$tohum)
  expect_identical(meydan1$degistirici$id, meydan2$degistirici$id)

  expect_true(meydan1$harita %in% names(bs_harita_katalogu()))
  expect_identical(meydan1$zorluk, "gelismis")
  expect_identical(meydan1$sema, BS_SEMA_SURUMU)

  # Farklı hafta harita rotasyonunu değiştirebilir; en azından kod değişir.
  gelecek <- bs_haftalik_meydan_okuma(sabit_tarih + 21 * 24 * 3600)
  expect_false(identical(meydan1$hafta_kodu, gelecek$hafta_kodu))
})

test_that("başarım kataloğu benzersiz kimlikli ve iki türlüdür", {
  katalog <- bs_basarim_katalogu()
  idler <- vapply(katalog, function(b) b$id, character(1))
  turler <- vapply(katalog, function(b) b$tur, character(1))

  expect_false(any(duplicated(idler)))
  expect_true(all(turler %in% c("basarim", "acilim")))
  expect_true("ilk_zafer" %in% idler)
  expect_true("kampanya_ustasi" %in% idler)
  expect_true(any(turler == "acilim"))
})
