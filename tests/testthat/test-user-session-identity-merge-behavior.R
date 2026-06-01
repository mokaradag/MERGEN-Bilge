# ==============================================================================
# Dosya Yolu: tests/testthat/test-user-session-identity-merge-behavior.R
# Açıklama: R/helpers_user_session_identity.R içindeki saf
#           merge_user_profile_into_identity yardımcısının DAVRANIŞSAL testleri.
#           Mevcut test-user-session-identity-contract.R diğer kimlik
#           yardımcılarını kapsar; bu profil-birleştirme fonksiyonu doğrudan
#           çağrılarak test edilmiyordu:
#             - NULL/list-olmayan kimlik veya profil koruması
#             - MB_Users alan eşlemesi (KaynakAdi/KullaniciAdi/Departman/...)
#             - TR/EN anahtar önceliği (Türkçe anahtar İngilizceyi geçer)
#             - boş/NA profil değerinde mevcut kimlik değerine geri düşme
#             - KaynakAdi gelince first_name güncellemesi (extractFirstName)
#           SSO sunucusu/DB/ağ GEREKMEZ; yalnızca base R ve sentetik listeler.
# ==============================================================================

.idmerge_source_once <- function() {
  if (exists("merge_user_profile_into_identity", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# Koruma yolları
# ------------------------------------------------------------------------------
testthat::test_that("merge_user_profile_into_identity NULL/list-olmayan girdileri güvenli işler", {
  .idmerge_source_once()
  # Her iki taraf NULL -> boş liste
  testthat::expect_identical(merge_user_profile_into_identity(NULL, NULL), list())

  # Profil NULL/list-olmayan -> kimlik değişmeden döner
  id <- list(username = "x", full_name = "Var Olan")
  testthat::expect_identical(merge_user_profile_into_identity(id, NULL), id)
  testthat::expect_identical(merge_user_profile_into_identity(id, "liste-degil"), id)

  # Kimlik list-olmayan ama profil geçerli -> kimlik boş listeden başlar
  out <- merge_user_profile_into_identity("liste-degil", list(KullaniciAdi = "kadi"))
  testthat::expect_identical(out$username, "kadi")
})

# ------------------------------------------------------------------------------
# Alan eşlemesi
# ------------------------------------------------------------------------------
testthat::test_that("merge_user_profile_into_identity MB_Users profil alanlarını kimliğe eşler", {
  .idmerge_source_once()
  prof <- list(
    KullaniciAdi = "kadi",
    KaynakAdi = "Ahmet Yılmaz",
    Departman = "BT",
    Email = "a@x.com",
    Sicil = "123",
    Sektor = "Kamu",
    Mudurluk = "Genel Müdürlük",
    MasrafYeriKodu = "MK1"
  )
  out <- merge_user_profile_into_identity(list(), prof)
  testthat::expect_identical(out$username, "kadi")
  testthat::expect_identical(enc2utf8(out$full_name), enc2utf8("Ahmet Yılmaz"))
  testthat::expect_identical(out$department, "BT")
  testthat::expect_identical(out$email, "a@x.com")
  testthat::expect_identical(out$sicil, "123")
  testthat::expect_identical(out$sektor, "Kamu")
  testthat::expect_identical(enc2utf8(out$mudurluk), enc2utf8("Genel Müdürlük"))
  testthat::expect_identical(out$masraf_yeri_kodu, "MK1")
})

testthat::test_that("merge_user_profile_into_identity İngilizce eş adlarına da çözer", {
  .idmerge_source_once()
  out <- merge_user_profile_into_identity(
    list(),
    list(name = "Mehmet Kaya", departman = "Lojistik", email = "m@y.com")
  )
  testthat::expect_identical(enc2utf8(out$full_name), enc2utf8("Mehmet Kaya"))
  testthat::expect_identical(out$department, "Lojistik")
  testthat::expect_identical(out$email, "m@y.com")
})

# ------------------------------------------------------------------------------
# TR/EN öncelik ve boş değer fallback
# ------------------------------------------------------------------------------
testthat::test_that("merge_user_profile_into_identity Türkçe anahtarı İngilizce eş adından önceler", {
  .idmerge_source_once()
  prof <- list(
    username = "enuser", KullaniciAdi = "truser",
    department = "endept", Departman = "trdept"
  )
  out <- merge_user_profile_into_identity(list(), prof)
  testthat::expect_identical(out$username, "truser")
  testthat::expect_identical(out$department, "trdept")
})

testthat::test_that("merge_user_profile_into_identity boş/NA profil değerinde mevcut kimliği korur", {
  .idmerge_source_once()
  # Boş (sadece boşluk) KaynakAdi atlanır -> mevcut full_name korunur
  out <- merge_user_profile_into_identity(
    list(full_name = "Var Olan", department = "Eski"),
    list(KaynakAdi = "   ", Departman = NA)
  )
  testthat::expect_identical(out$full_name, "Var Olan")
  testthat::expect_identical(out$department, "Eski")

  # Hiç eşleşen alan yoksa kimlik alanları boş dizeye normalize edilir
  out_empty <- merge_user_profile_into_identity(list(), list(IlgisizAlan = "x"))
  testthat::expect_identical(out_empty$username, "")
  testthat::expect_identical(out_empty$full_name, "")
})

# ------------------------------------------------------------------------------
# first_name güncellemesi (extractFirstName)
# ------------------------------------------------------------------------------
testthat::test_that("merge_user_profile_into_identity KaynakAdi gelince first_name'i günceller", {
  .idmerge_source_once()
  # extractFirstName'i deterministik stub ile sağla; sonunda eski hale döndür.
  had <- exists("extractFirstName", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("extractFirstName", envir = globalenv(), inherits = FALSE) else NULL
  assign(
    "extractFirstName",
    function(full) trimws(strsplit(as.character(full), "\\s+")[[1]][1]),
    envir = globalenv()
  )
  withr::defer({
    if (had) {
      assign("extractFirstName", old, envir = globalenv())
    } else if (exists("extractFirstName", envir = globalenv(), inherits = FALSE)) {
      rm("extractFirstName", envir = globalenv())
    }
  })

  out <- merge_user_profile_into_identity(list(), list(KaynakAdi = "Ahmet Yılmaz"))
  testthat::expect_identical(out$first_name, "Ahmet")
})
