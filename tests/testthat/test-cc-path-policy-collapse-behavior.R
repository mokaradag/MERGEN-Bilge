# ==============================================================================
# Dosya Yolu: tests/testthat/test-cc-path-policy-collapse-behavior.R
# Açıklama: cc_policy_collapse_dot_segments için davranış testleri. Bilge Yolaç
#           yol güvenlik politikasının nokta-segment sadeleştirme katmanı;
#           UNC, sürücü harfi, mutlak ve göreli yollarda ".." kaçışlarının
#           köke sıkıştırılması (clamp) doğrulanır. Çevrimdışı ve deterministik.
# ==============================================================================

testthat::test_that("cc_policy_collapse_dot_segments göreli yolda nokta segmentlerini sadeleştirir", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_path_policy.R"),
         encoding = "UTF-8", local = env)

  # Basit ".." çözümü: a/b/../c -> a/c
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("a/b/../c"), "a/c")

  # "." segmentleri atlanır
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("a/./b/./c"), "a/b/c")

  # Göreli yolda başa taşan ".." korunur (mutlak değilse clamp edilmez)
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("../a"), "../a")
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("a/../../b"), "../b")
})

testthat::test_that("cc_policy_collapse_dot_segments mutlak yolda kök üstüne kaçışı sıkıştırır", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_path_policy.R"),
         encoding = "UTF-8", local = env)

  # Mutlak yolda kökün üzerine çıkan ".." yutulur (clamp): /a/../../b -> /b
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("/a/../../b"), "/b")

  # Tamamen tüketen kaçış kökte kalır
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("/a/.."), "/")
})

testthat::test_that("cc_policy_collapse_dot_segments UNC önekini korur ve içeriden kaçışı engeller", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_path_policy.R"),
         encoding = "UTF-8", local = env)

  # UNC kökü (//server/share) korunur, içindeki ".." normal çözülür
  testthat::expect_identical(
    env$cc_policy_collapse_dot_segments("//srv/share/a/../b"),
    "//srv/share/b"
  )

  # UNC kökünün üzerine çıkma denemesi paylaşım köküne sıkışır
  testthat::expect_identical(
    env$cc_policy_collapse_dot_segments("//srv/share/../../etc"),
    "//srv/share/etc"
  )

  # Gövdesi kalmayan UNC yol yalnızca kökü döndürür
  testthat::expect_identical(
    env$cc_policy_collapse_dot_segments("//srv/share/a/.."),
    "//srv/share"
  )

  # Ters bölü UNC biçimi de normalize edilir
  testthat::expect_identical(
    env$cc_policy_collapse_dot_segments("\\\\srv\\share\\a\\..\\b"),
    "//srv/share/b"
  )
})

testthat::test_that("cc_policy_collapse_dot_segments sürücü harfi önekini korur", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_path_policy.R"),
         encoding = "UTF-8", local = env)

  # Sürücü kökü korunur ve ".." çözülür: C:/a/./b/../c -> C:/a/c
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("C:/a/./b/../c"), "C:/a/c")

  # Sürücü kökünün üzerine çıkma sıkışır: C:/../../x -> C:/x
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("C:/../../x"), "C:/x")

  # Gövde kalmazsa sürücü kökü döner
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("C:/a/.."), "C:/")

  # Ters bölü sürücü yolu normalize edilir
  testthat::expect_identical(env$cc_policy_collapse_dot_segments("C:\\a\\..\\b"), "C:/b")
})

testthat::test_that("cc_policy_collapse_dot_segments kenar girdilerde güvenli boş döner", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_path_policy.R"),
         encoding = "UTF-8", local = env)

  testthat::expect_identical(env$cc_policy_collapse_dot_segments(NULL), "")
  testthat::expect_identical(env$cc_policy_collapse_dot_segments(""), "")
  testthat::expect_identical(env$cc_policy_collapse_dot_segments(NA_character_), "")

  # Türkçe karakterli segmentler bozulmadan korunur
  testthat::expect_identical(
    env$cc_policy_collapse_dot_segments("proje/çalışma/../özet/İstanbul"),
    "proje/özet/İstanbul"
  )
})
