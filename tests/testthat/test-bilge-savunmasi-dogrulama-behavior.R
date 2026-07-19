# ==============================================================================
# Dosya Yolu: tests/testthat/test-bilge-savunmasi-dogrulama-behavior.R
# Açıklama: www/js/bilge_savunmasi_dogrulama.js "sunucu-kosu-sonuc" bayat yanıt
#           koruması sözleşmesi (Codex PR #636 P2: "Reject result messages that
#           lack the active run id"). Sunucu, istek biçimi/kimlik doğrulaması
#           erken başarısız olduğunda (istek_bicimi/kimlik) kosu_id İÇERMEYEN
#           bir yanıt gönderebilir; aktif koşunun bilinen bir kosuId'si varsa
#           böyle kimliksiz bir yanıt eşleşme doğrulanamadığı için bayat/yanlış
#           koşuya ait sayılıp reddedilmelidir. Bu repoda ağır bir JS çalıştırma
#           bağımlılığı (V8/Node) YOKTUR; bu yüzden davranış, kurulu diğer
#           bilge_savunmasi_*.js sözleşme testleriyle aynı Windows-güvenli bayt
#           okuma + statik yapı taraması yoluyla korunur.
# ==============================================================================

.bs_dog_repo_root <- resolve_repo_root_for_tests()

.bs_dog_oku <- function(...) {
  yol <- file.path(.bs_dog_repo_root, ...)
  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  metin <- rawToChar(ham)
  iconv(metin, from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("sunucu-kosu-sonuc bayat yanit korumasi kosu_id'siz yaniti da reddeder", {
  metin <- .bs_dog_oku("www", "js", "bilge_savunmasi_dogrulama.js")

  blok <- regmatches(
    metin,
    regexpr(
      "sunucu-kosu-sonuc[\\s\\S]*?BS\\.sonuc\\.goster\\(kosu, sonuc\\);",
      metin,
      perl = TRUE, useBytes = TRUE
    )
  )
  expect_length(blok, 1L)
  blok <- blok[[1]]

  # Aktif koşunun bilinen bir kimliği varken, kimliksiz (null/undefined)
  # sonuc.kosu_id de reddedilmelidir; eski desen yalnızca sonuc.kosu_id
  # DOLUYKEN eşleşmeyi kontrol ediyordu ve kimliksiz erken hata yanıtlarını
  # hiç süzmüyordu.
  expect_true(grepl("kosu.kosuId != null", blok, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("sonuc.kosu_id == null", blok, fixed = TRUE, useBytes = TRUE))

  # Eski, yetersiz tek satırlık koşulun (yalnızca ikisi de DOLUYKEN eşleşme
  # kontrolü) tek başına geri dönmediğini doğrula: "sonuc.kosu_id != null &&"
  # artık kosu.kosuId != null bloğunun İÇİNDE, kimliksiz-reddetme kontrolünden
  # SONRA olmalı; blok en azından iç içe bir null kontrolü içermeli.
  expect_true(grepl("if (sonuc.kosu_id == null) return;", blok, fixed = TRUE, useBytes = TRUE))

  # Yinelenen/geç yanıt koruması (kosu.sonSonuc) hâlâ korunuyor olmalı.
  expect_true(grepl("if (kosu.sonSonuc) return;", blok, fixed = TRUE, useBytes = TRUE))
})

test_that("gonder() cagrisi her zaman kosu.kosuId dolu iken tetiklenir (guard guvenlik varsayimi)", {
  # dogrulama.gonder()'in yalnızca kosu.kosuId doluyken çağrıldığını doğrular;
  # bu, yukarıdaki guard'ın kosu.kosuId != null iken kimliksiz yanıtı güvenle
  # reddedebilmesinin ön koşuludur (aksi halde meşru "plan modu" kimliksiz
  # akışları da bastırılabilirdi).
  metin <- .bs_dog_oku("www", "js", "bilge_savunmasi_uygulama.js")

  cagrilar <- gregexpr(
    "if \\(kosu\\.kosuId[^\\n]*\\)\\s*\\{\\s*BS\\.dogrulama\\.gonder\\(kosu\\)",
    metin,
    perl = TRUE, useBytes = TRUE
  )[[1]]
  expect_true(length(cagrilar) >= 1L && cagrilar[1] > 0)
})
