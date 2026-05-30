# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-prompt-path-policy-behavior.R
# Açıklama: R/helpers_claude_code_prompt_security_policy.R prompt yol-niyeti
#           denetiminin saf yardımcıları için DAVRANIŞSAL testler:
#           cc_policy_prompt_has_write_intent (yazma niyeti tespiti),
#           cc_policy_extract_path_like_tokens (yol benzeri token çıkarımı) ve
#           cc_policy_path_is_absolute (mutlak yol kontrolü). Bilge Yolaç güvenlik
#           sınırının parçasıdır; CLI/dosya sistemi/ağ GEREKMEZ.
# ==============================================================================

.ccpolicy_source_once <- function() {
  if (exists("cc_policy_path_is_absolute", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R",
              "helpers_claude_code_prompt_security_policy.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# cc_policy_prompt_has_write_intent
# ------------------------------------------------------------------------------
testthat::test_that("cc_policy_prompt_has_write_intent Türkçe/İngilizce yazma niyetini yakalar", {
  .ccpolicy_source_once()
  testthat::expect_true(cc_policy_prompt_has_write_intent("yeni dosya oluştur"))
  testthat::expect_true(cc_policy_prompt_has_write_intent("dosyayı kaydet"))
  # ASCII büyük harf: tolower güvenilir, \bcreate\b eşleşir.
  testthat::expect_true(cc_policy_prompt_has_write_intent("CREATE A FILE please"))
  testthat::expect_true(cc_policy_prompt_has_write_intent("run rm now"))
  # Vektör prompt boşlukla birleştirilir.
  testthat::expect_true(cc_policy_prompt_has_write_intent(c("merhaba", "dosya yaz")))
})

testthat::test_that("cc_policy_prompt_has_write_intent salt-okuma/boş niyetlerde FALSE döner", {
  .ccpolicy_source_once()
  testthat::expect_false(cc_policy_prompt_has_write_intent("please explain the code"))
  testthat::expect_false(cc_policy_prompt_has_write_intent("bu fonksiyon ne yapar"))
  testthat::expect_false(cc_policy_prompt_has_write_intent(""))
  testthat::expect_false(cc_policy_prompt_has_write_intent(NULL))
  # İngilizce sözcük sınırı: "remover", \bremove\b ile eşleşmez.
  testthat::expect_false(cc_policy_prompt_has_write_intent("remover"))
})

# ------------------------------------------------------------------------------
# cc_policy_extract_path_like_tokens
# ------------------------------------------------------------------------------
testthat::test_that("cc_policy_extract_path_like_tokens Windows/UNC/mutlak/.. yollarını çıkarır", {
  .ccpolicy_source_once()
  # Windows sürücü yolu (ters bölü korunur).
  testthat::expect_identical(
    cc_policy_extract_path_like_tokens("lütfen C:\\Users\\test\\dosya.txt oluştur"),
    "C:\\Users\\test\\dosya.txt"
  )
  # Mutlak unix yolu (baştaki boşluk kırpılır).
  testthat::expect_identical(
    cc_policy_extract_path_like_tokens("oku /etc/passwd dosyasini"),
    "/etc/passwd"
  )
  # ../ göreli yolu.
  testthat::expect_identical(
    cc_policy_extract_path_like_tokens("../gizli/x.txt yaz"),
    "../gizli/x.txt"
  )
  # UNC // yolu.
  testthat::expect_identical(
    cc_policy_extract_path_like_tokens("//server/share/file yaz"),
    "//server/share/file"
  )
})

testthat::test_that("cc_policy_extract_path_like_tokens yok/punkt/tekrar durumlarını işler", {
  .ccpolicy_source_once()
  # Yol yoksa boş karakter vektörü.
  testthat::expect_identical(cc_policy_extract_path_like_tokens("merhaba dunya"), character(0))
  testthat::expect_identical(cc_policy_extract_path_like_tokens(""), character(0))
  testthat::expect_identical(cc_policy_extract_path_like_tokens(NULL), character(0))
  # Sondaki noktalama kırpılır.
  testthat::expect_identical(cc_policy_extract_path_like_tokens("yaz /tmp/a.txt."), "/tmp/a.txt")
  # Yinelenen yollar teke iner.
  testthat::expect_identical(cc_policy_extract_path_like_tokens("/tmp/a /tmp/a"), "/tmp/a")
})

# ------------------------------------------------------------------------------
# cc_policy_path_is_absolute
# ------------------------------------------------------------------------------
testthat::test_that("cc_policy_path_is_absolute Windows/unix/UNC mutlak yolları TRUE döner", {
  .ccpolicy_source_once()
  testthat::expect_true(cc_policy_path_is_absolute("C:\\Users\\x"))
  testthat::expect_true(cc_policy_path_is_absolute("D:/folder"))
  testthat::expect_true(cc_policy_path_is_absolute("/etc/passwd"))
  testthat::expect_true(cc_policy_path_is_absolute("//server/share"))
  # Vektör verilirse yalnızca ilk eleman değerlendirilir.
  testthat::expect_true(cc_policy_path_is_absolute(c("/abs", "rel")))
})

testthat::test_that("cc_policy_path_is_absolute göreli/boş/NULL yolları FALSE döner", {
  .ccpolicy_source_once()
  testthat::expect_false(cc_policy_path_is_absolute("rel/path"))
  testthat::expect_false(cc_policy_path_is_absolute("../up"))
  testthat::expect_false(cc_policy_path_is_absolute("file.txt"))
  testthat::expect_false(cc_policy_path_is_absolute(""))
  testthat::expect_false(cc_policy_path_is_absolute(NULL))
})
