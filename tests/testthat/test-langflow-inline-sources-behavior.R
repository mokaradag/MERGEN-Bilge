# ==============================================================================
# Dosya Yolu: tests/testthat/test-langflow-inline-sources-behavior.R
# Açıklama: Langflow yanıtlarının METİN İÇİNE yazılmış düz "Kaynak:" bölümü ve
#           satır içi <sup>(n)</sup> üstsimge atıflarının tıklanabilir Kaynakça'ya
#           yükseltilmesini test eder (R/helpers_langflow_inline_sources.R ve
#           R/helpers_langflow_sources.R kırıntı yolu render'ı). Bazı akışlar
#           kaynakları yapısal JSON alanında değil metnin sonunda yazar; bu katman
#           o biçimi yakalar. Tüm testler çevrimdışı ve deterministiktir (gerçek
#           Langflow/ağ/DB/tarayıcı yoktur) ve genel, kurum-adı içermeyen örnekler
#           kullanır. Dosya adları düz (dizin olmayan) '&&' ayraçlı gerçek adlardır.
# ==============================================================================

.source_langflow_inline_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  for (f in c(
    "R/utils_common.R",
    "R/utils_text_encoding.R",
    "R/helpers_langflow_sources.R",
    "R/helpers_langflow_inline_sources.R"
  )) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  env
}

test_that(".langflow_inline_sup_to_citation <sup>(n)</sup> atıflarını [n]'e çevirir", {
  env <- .source_langflow_inline_env()
  f <- env$.langflow_inline_sup_to_citation

  expect_identical(f("Metin<sup>(1)</sup> devam."), "Metin[1] devam.")
  expect_identical(f("A<sup>1</sup> B<sup>(2)</sup>"), "A[1] B[2]")
  # Tek üstsimgede birden çok sayı
  expect_identical(f("X<sup>(1)(2)</sup>"), "X[1][2]")
  expect_identical(f("X<sup>1, 2</sup>"), "X[1][2]")
  # Büyük/küçük harf duyarsız etiket
  expect_identical(f("Y<SUP>(3)</SUP>"), "Y[3]")
  # <sup> yoksa metin değişmez
  expect_identical(f("Sade metin."), "Sade metin.")
  # Rakamsız üstsimge kaldırılır
  expect_identical(f("A<sup>x</sup>B"), "AB")
  # num_map ile yeniden eşleme (orijinal numara -> pozisyon)
  expect_identical(f("A<sup>(1)</sup> C<sup>(3)</sup>", num_map = c("1" = "1", "3" = "2")), "A[1] C[2]")
  # Eşleşmeyen numara olduğu gibi korunur (subscript hatası vermez)
  expect_identical(f("A<sup>(9)</sup>", num_map = c("1" = "1")), "A[9]")
  # Boş güvenli
  expect_identical(f(""), "")
})

test_that("mergen_langflow_parse_prose_sources sondaki 'Kaynak:' bölümünü ayrıştırır ve düzyazıyı ayırır", {
  env <- .source_langflow_inline_env()
  parse <- env$mergen_langflow_parse_prose_sources

  metin <- paste0(
    "İşçilik saatleri girilir.<sup>(1)</sup>\n",
    "Hafta sonu girişi yapılabilir.<sup>(2)</sup>\n\n",
    "Kaynak:\n",
    "(1) Program Yönetimi&&Alt Süreç&&İşçilik Girişi Talimatı.docx\n",
    "(2) Program Yönetimi&&Alt Süreç&&İşçilik Girişi Talimatı.pdf\n"
  )
  res <- parse(metin)
  expect_false(is.null(res))
  expect_length(res$records, 2L)

  expect_identical(res$records[[1]]$path, "Program Yönetimi&&Alt Süreç&&İşçilik Girişi Talimatı.docx")
  expect_identical(res$records[[1]]$title, "İşçilik Girişi Talimatı.docx")
  expect_identical(res$records[[1]]$type, "docx")
  expect_identical(res$records[[1]]$num, "1")
  expect_identical(res$records[[2]]$type, "pdf")

  # Düzyazı bölüm başlıktan öncesidir; üstsimge etiketleri henüz çevrilmemiştir.
  expect_false(grepl("Kaynak:", res$prose, fixed = TRUE))
  expect_match(res$prose, "İşçilik saatleri girilir", fixed = TRUE)
  expect_match(res$prose, "<sup>(1)</sup>", fixed = TRUE)
})

test_that("mergen_langflow_parse_prose_sources başlık/giriş varyantlarını tanır", {
  env <- .source_langflow_inline_env()
  parse <- env$mergen_langflow_parse_prose_sources

  # "Kaynaklar" başlığı (iki nokta yok), "1." biçimi
  r1 <- parse("Metin.\n\nKaynaklar\n1. Grup&&rapor.pdf\n")
  expect_false(is.null(r1))
  expect_length(r1$records, 1L)
  expect_identical(r1$records[[1]]$title, "rapor.pdf")

  # "Kaynakça:" başlığı, markdown kalın süsü, "1)" biçimi
  r2 <- parse("Metin.\n\n**Kaynakça:**\n1) Grup&&kilavuz.docx\n")
  expect_false(is.null(r2))
  expect_length(r2$records, 1L)
  expect_identical(r2$records[[1]]$type, "docx")

  # Tek parçalı (kategori öneksiz) düz dosya adı
  r3 <- parse("Metin.\n\nKaynak:\n(1) tekil_dosya.pdf\n")
  expect_false(is.null(r3))
  expect_identical(r3$records[[1]]$path, "tekil_dosya.pdf")
})

test_that("mergen_langflow_parse_prose_sources bölüm yoksa/geçersiz kaynakta NULL döner (kaynak uydurmaz)", {
  env <- .source_langflow_inline_env()
  parse <- env$mergen_langflow_parse_prose_sources

  expect_null(parse("Kaynak göstermeyen sade bir yanıt metni."))
  expect_null(parse(""))
  expect_null(parse(NULL))

  # URL / mutlak yol / sürücü harfi / gezinme reddi
  expect_null(parse("Metin.\n\nKaynak:\n(1) https://ornek.gecersiz/dosya.pdf\n"))
  expect_null(parse("Metin.\n\nKaynak:\n(1) /kok/gizli/dosya.pdf\n"))
  expect_null(parse("Metin.\n\nKaynak:\n(1) C:/gizli/dosya.docx\n"))
  expect_null(parse("Metin.\n\nKaynak:\n(1) ust&&..&&dosya.pdf\n"))
  # Belge uzantısı olmayan giriş
  expect_null(parse("Metin.\n\nKaynak:\n(1) sadece_metin_ek_yok\n"))
  # Başlık gibi görünen ama giriş içermeyen satır bölümü tetiklemez
  expect_null(parse("Kaynaklar aşağıda listelenmiştir ve önemlidir."))
})

test_that("mergen_langflow_finalize_answer üstsimgeleri çevirir ve düzyazı Kaynak'ı imzalı işaretleyiciye yükseltir", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_inline_env()
  finalize <- env$mergen_langflow_finalize_answer
  split <- env$mergen_kaynakca_marker_split

  metin <- paste0(
    "Bir cümle.<sup>(1)</sup>\n",
    "İki cümle.<sup>(2)</sup>\n\n",
    "Kaynak:\n",
    "(1) Grup 1&&Kalite&&prosedur.pdf\n",
    "(2) Grup 1&&Kalite&&kilavuz.docx\n"
  )
  out <- finalize(metin, list())

  # <sup>(n)</sup> -> [n]
  expect_match(out, "Bir cümle.[1]", fixed = TRUE)
  expect_match(out, "İki cümle.[2]", fixed = TRUE)
  expect_false(grepl("<sup>", out, fixed = TRUE))
  # Düzyazı "Kaynak:" bölümü söküldü; imzalı Kaynakça işaretleyici bloğu eklendi
  expect_false(grepl("\nKaynak:\n", out, fixed = TRUE))
  expect_match(out, "\n\nKaynakça:\n[KAYNAK 1]", fixed = TRUE)

  # İşaretleyici bloğu geri ayrıştırılabilir (bütünlük kodu geçerli)
  sp <- split(out)
  expect_false(is.null(sp))
  expect_length(sp$entries, 2L)
  expect_identical(sp$entries[[1]]$path, "Grup 1&&Kalite&&prosedur.pdf")
  expect_identical(sp$entries[[2]]$type, "docx")
})

test_that("mergen_langflow_finalize_answer eksik/atlanan numaralı Kaynak'ta üstsimgeyi pozisyona hizalar", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_inline_env()
  finalize <- env$mergen_langflow_finalize_answer

  # Model (1) ve (3) numaralamış (2 atlanmış); üstsimgeler pozisyona (1,2) eşlenir
  # ki data-entry ile hizalanıp doğru kaynağa kaysın.
  metin <- paste0(
    "Cümle bir.<sup>(1)</sup>\n",
    "Cümle iki.<sup>(3)</sup>\n\n",
    "Kaynak:\n",
    "(1) Grup&&birinci.pdf\n",
    "(3) Grup&&ucuncu.pdf\n"
  )
  out <- finalize(metin, list())
  expect_match(out, "Cümle bir.[1]", fixed = TRUE)
  expect_match(out, "Cümle iki.[2]", fixed = TRUE)
})

test_that("mergen_langflow_finalize_answer yapısal kaynaklar varken düzyazı ayrıştırmaz; üstsimge kimlik eşlemesi", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_inline_env()
  finalize <- env$mergen_langflow_finalize_answer

  structured <- list(list(title = "Kalite Prosedürü", path = "surecler/kalite/prosedur.pdf", page = "3", type = "pdf"))
  out <- finalize("Cevap<sup>(1)</sup> metni.", structured)
  expect_match(out, "Cevap[1] metni.", fixed = TRUE)
  expect_match(out, "[KAYNAK 1] Kalite Prosedürü", fixed = TRUE)
})

test_that("mergen_kaynakca_marker_html '&&' düz adlarında kırıntı yolu + son parça tıklanabilir üretir", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_langflow_inline_env()

  html <- env$mergen_kaynakca_marker_html(list(
    list(title = "prosedur.pdf", path = "Grup 1&&Kalite&&prosedur.pdf", page = "", type = "pdf")
  ))

  # Kırıntı yolu (soluk, tıklanamaz) parçalar " - " ile birleşir
  expect_match(html, "class='kaynakca-breadcrumb'", fixed = TRUE)
  expect_match(html, "Grup 1 - Kalite - ", fixed = TRUE)
  # Yalnızca son parça tıklanabilir
  expect_match(html, ">prosedur.pdf</span>", fixed = TRUE)
  # data-filename tam '&&' adını taşır (disk çözümlemesi için)
  expect_match(html, "data-filename='Grup 1&amp;&amp;Kalite&amp;&amp;prosedur.pdf'", fixed = TRUE)
  expect_match(html, "fa-file-pdf", fixed = TRUE)
})

test_that("mergen_kaynakca_marker_html '&&' içermeyen yolda mevcut davranışı korur (başlık tıklanabilir)", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_langflow_inline_env()

  html <- env$mergen_kaynakca_marker_html(list(
    list(title = "Kalite Prosedürü", path = "surecler/kalite/prosedur.pdf", page = "3", type = "pdf")
  ))

  expect_false(grepl("kaynakca-breadcrumb", html, fixed = TRUE))
  expect_match(html, ">Kalite Prosedürü</span>", fixed = TRUE)
  expect_match(html, "data-filename='surecler&amp;&amp;kalite&amp;&amp;prosedur.pdf'", fixed = TRUE)
})

test_that("mergen_kaynakca_marker_html kırıntı yolu değerlerini kaçışlar (XSS sınırı)", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_langflow_inline_env()

  html <- env$mergen_kaynakca_marker_html(list(
    list(title = "<img src=x>.pdf", path = "<b>oku</b>&&Kalite&&<img src=x>.pdf", page = "", type = "pdf")
  ))
  expect_false(grepl("<img", html, fixed = TRUE))
  expect_false(grepl("<b>oku</b>", html, fixed = TRUE))
  expect_match(html, "&lt;b&gt;oku&lt;/b&gt; - Kalite - ", fixed = TRUE)
})

test_that("process_message_content Langflow düzyazı yanıtını tıklanabilir kırıntı Kaynakça'ya yükseltir", {
  testthat::skip_if_not_installed("htmltools")
  testthat::skip_if_not_installed("commonmark")
  testthat::skip_if_not_installed("stringr")
  testthat::skip_if_not_installed("openssl")

  repo_root <- resolve_repo_root_for_tests()
  env <- .source_langflow_inline_env()
  env$HTML <- htmltools::HTML
  for (f in c("R/helpers_markdown_safety.R", "R/helpers_language.R", "R/helpers_messaging.R")) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  metin <- paste0(
    "İşçilik girişi günlük yapılır.<sup>(1)</sup>\n\n",
    "Kaynak:\n",
    "(1) Grup 1&&Kalite&&İşçilik Girişi Talimatı.docx\n"
  )
  final_text <- env$mergen_langflow_finalize_answer(metin, list())
  out <- env$process_message_content(final_text, "ai")

  # Üstsimge atıf metinde [1] olarak kaldı (citation_handler.js üstsimge yapar)
  expect_match(out$html, "[1]", fixed = TRUE)
  # Tıklanabilir kaynak + kırıntı yolu + Word ikonu
  expect_match(out$html, "class='source-link'", fixed = TRUE)
  expect_match(out$html, "class='kaynakca-breadcrumb'", fixed = TRUE)
  expect_match(out$html, ">İşçilik Girişi Talimatı.docx</span>", fixed = TRUE)
  expect_match(out$html, "fa-file-word", fixed = TRUE)
  # İşaretleyici görünmez; ham HTML geçmez
  expect_false(grepl("[KAYNAK", out$html, fixed = TRUE))
  expect_false(grepl("<sup>", out$html, fixed = TRUE))
})

test_that("search_file_in_folder '&&' düz dosya adını alt klasörde çözer", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)
  alt <- file.path(base_dir, "AltKlasor")
  dir.create(alt, recursive = TRUE)

  # Disk basename'i '&&' içerir (düz ad; '&&' dizin ayracı DEĞİL)
  fname <- "Grup 1&&Kalite&&prosedur.pdf"
  writeLines("ornek", file.path(alt, fname))

  found <- search_file_in_folder(base_dir, fname)
  expect_false(is.null(found))
  expect_identical(
    normalizePath(found, winslash = "/"),
    normalizePath(file.path(alt, fname), winslash = "/")
  )
})

test_that("search_file_in_folder parça içerme ile boşluk/varyant farkına dayanır", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)
  writeLines("ornek", file.path(base_dir, "Grup 1&&Kalite&&prosedur final.pdf"))

  # Model tam adı vermese bile tüm '&&' parçaları dosya adında geçtiği için bulunur
  found <- search_file_in_folder(base_dir, "Grup 1&&Kalite&&prosedur")
  expect_false(is.null(found))
  expect_identical(
    normalizePath(found, winslash = "/"),
    normalizePath(file.path(base_dir, "Grup 1&&Kalite&&prosedur final.pdf"), winslash = "/")
  )
})
