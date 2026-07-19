# ==============================================================================
# Dosya Yolu: tests/testthat/test-persona-sprite-contract.R
# Açıklama: Modern persona piksel sprite seti ve ortak çizim yardımcısı
#           sözleşmeleri. Zenginleştirilmiş sprite verisinin (5 kare,
#           genişletilmiş palet: deri/saç/aksesuar) beş kanonik persona için
#           tanımlı olduğunu, eski mitolojik kimlik içermediğini ve hem Bilge
#           Yolaç düşünme animasyonunun hem de karşılama sahnesinin ortak
#           açık/koyu temaya duyarlı çizici üzerinden çalıştığını doğrular.
#           Statik bayt taraması; tarayıcı/DB/ağ GEREKMEZ.
# ==============================================================================

.ps_repo_root <- resolve_repo_root_for_tests()

.ps_oku <- function(...) {
  yol <- file.path(.ps_repo_root, ...)
  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
}

.ps_iceriyor <- function(metin, kalip) {
  grepl(kalip, metin, fixed = TRUE, useBytes = TRUE)
}

test_that("persona sprite verisi beş kanonik personayı zengin palet + 5 kareyle taşır", {
  veri <- .ps_oku("www", "js", "claude_code_pixel_chars.js")

  for (id in c("emre", "selin", "deniz", "can", "ipek")) {
    expect_true(.ps_iceriyor(veri, paste0(id, ": {")),
                info = paste("Persona eksik:", id))
  }
  # Genişletilmiş palet: deri (4), deri-gölge (5), saç (6), detay (7),
  # aksesuar (8) her persona için tanımlıdır.
  expect_true(.ps_iceriyor(veri, "palette: {"))
  # Persona tema renkleri kanonik aksan renkleriyle hizalıdır.
  expect_true(.ps_iceriyor(veri, "'#7C4DFF'"))  # emre
  expect_true(.ps_iceriyor(veri, "'#2F6DF6'"))  # selin
  expect_true(.ps_iceriyor(veri, "'#12A97B'"))  # deniz
  expect_true(.ps_iceriyor(veri, "'#B66A2C'"))  # can
  expect_true(.ps_iceriyor(veri, "'#E98686'"))  # ipek
  # Her persona için beş poz karesi (idle/nefes/düşünme A/düşünme B/selamlama).
  expect_true(.ps_iceriyor(veri, "Kare 5: Selamlama"))
  expect_true(.ps_iceriyor(veri, "Kare 3: Düşünme A"))

  # Beş kare sayısını her persona bloğunda doğrula (kare yorumları sayılır).
  kare_sayilari <- lengths(regmatches(
    veri, gregexpr("// Kare 1: Duru", veri, fixed = TRUE)
  ))
  expect_gte(kare_sayilari, 5L)   # beş persona x en az bir "Kare 1"
})

test_that("persona sprite seti eski mitolojik kimlik içermez", {
  veri <- tolower(.ps_oku("www", "js", "claude_code_pixel_chars.js"))
  for (eski in c("mergen", "ulgen", "kayra", "erlik", "umay")) {
    expect_false(
      grepl(paste0("\\b", eski, "\\b"), veri, perl = TRUE),
      info = paste0("Sprite verisi eski kimlik içermemeli: ", eski)
    )
  }
})

test_that("ortak piksel çizici açık/koyu temaya duyarlıdır ve geriye uyumludur", {
  render <- .ps_oku("www", "js", "pixel_sprite_render.js")
  expect_true(.ps_iceriyor(render, "window.MergenPixelSprite"))
  expect_true(.ps_iceriyor(render, "aktifTema"))
  # Tema tespiti data-theme özniteliğinden yapılır; koyu varsayılandır.
  expect_true(.ps_iceriyor(render, 'getAttribute("data-theme")'))
  # Açık temada koyu kontur, koyu temada açık kontur (net okunurluk).
  expect_true(.ps_iceriyor(render, "konturRenk"))
  # Palet değeri çözümü genişletilmiş palete VE eski color/darkColor'a düşer.
  expect_true(.ps_iceriyor(render, "charData.palette"))
  expect_true(.ps_iceriyor(render, "charData.color"))
})

test_that("düşünme animasyonu ve karşılama sahnesi ortak çiziciyi kullanır", {
  # Bilge Yolaç düşünme animasyonu.
  cc <- .ps_oku("www", "js", "claude_code.js")
  expect_true(.ps_iceriyor(cc, "window.MergenPixelSprite"))
  expect_true(.ps_iceriyor(cc, "MergenPixelSprite.ciz("))

  # Çalışma Alanı retro karşılama sahnesi.
  karsilama <- .ps_oku("www", "js", "bilge_yolac_karsilama.js")
  expect_true(.ps_iceriyor(karsilama, "window.MergenPixelSprite"))
  expect_true(.ps_iceriyor(karsilama, "MergenPixelSprite.ciz("))
  # Zenginleştirilmiş kareler: yürüyüşte idle<->nefes, düşünmede 2-3 döner.
  expect_true(.ps_iceriyor(karsilama, "veri.frames.length"))
})

test_that("ortak piksel çizici manifest sırasında persona verisinden sonra yüklenir", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(.ps_repo_root, "R", "utils_safe_source.R"), envir = env)
  sys.source(file.path(.ps_repo_root, "R", "config_ui_assets.R"), envir = env)

  kurallar <- env$ui_asset_js_order_rules
  ikili_var <- function(once, sonra) {
    any(vapply(kurallar, function(k) {
      length(k) == 2 && k[1] == once && k[2] == sonra
    }, logical(1)))
  }
  expect_true(ikili_var("js/claude_code_pixel_chars.js",
                        "js/pixel_sprite_render.js"))
  expect_true(ikili_var("js/pixel_sprite_render.js", "js/claude_code.js"))
  expect_true(ikili_var("js/pixel_sprite_render.js",
                        "js/bilge_yolac_karsilama.js"))
})
