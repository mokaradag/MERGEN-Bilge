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
  # Tek üstsimgede birden çok parantezli sayı grubu
  expect_identical(f("X<sup>(1)(2)</sup>"), "X[1][2]")
  expect_identical(f("X<sup>(1, 2)</sup>"), "X[1][2]")
  # Büyük/küçük harf duyarsız etiket
  expect_identical(f("Y<SUP>(3)</SUP>"), "Y[3]")
  # <sup> yoksa metin değişmez
  expect_identical(f("Sade metin."), "Sade metin.")
  # CITATION-ŞEKİLLİ DEĞİL (parantezsiz bare rakam / harf): sıradan üs/dipnot
  # gösterimi olabilir (m<sup>2</sup> gibi); DOKUNULMAZ, yanlışlıkla atfa
  # dönüştürülmez veya kaybolmaz.
  expect_identical(f("A<sup>1</sup> B<sup>(2)</sup>"), "A<sup>1</sup> B[2]")
  expect_identical(f("X<sup>1, 2</sup>"), "X<sup>1, 2</sup>")
  expect_identical(f("A<sup>x</sup>B"), "A<sup>x</sup>B")
  expect_identical(f("Alan m<sup>2</sup> olarak hesaplanır."), "Alan m<sup>2</sup> olarak hesaplanır.")
  # num_map ile yeniden eşleme (orijinal numara -> pozisyon)
  expect_identical(f("A<sup>(1)</sup> C<sup>(3)</sup>", num_map = c("1" = "1", "3" = "2")), "A[1] C[2]")
  # Eşleşmeyen numara DÜŞÜRÜLÜR (etkisiz; subscript hatası da vermez)
  expect_identical(f("A<sup>(9)</sup>", num_map = c("1" = "1")), "A")
  # Kısmen eşleşen üstsimge: yalnızca eşleşen numara kalır
  expect_identical(f("A<sup>(1)(9)</sup>", num_map = c("1" = "1")), "A[1]")
  # Öznitelikli üstsimge etiketi de yakalanır (class vb.); sayılar YALNIZCA
  # etiket İÇERİĞİNDEN alınır, açılış etiketindeki öznitelik değeri değil.
  expect_identical(f('X<sup class="citation">(1)</sup>'), "X[1]")
  expect_identical(f("Y<sup data-x='1'>(2)</sup>"), "Y[2]")
  # <supper> gibi farklı etiket yakalanmaz (sözcük sınırı)
  expect_identical(f("m<supper>3</supper>"), "m<supper>3</supper>")
  # Boş güvenli
  expect_identical(f(""), "")
})

test_that(".langflow_sup_is_citation_shaped yalnızca tamamen parantezli rakam gruplarını kabul eder", {
  env <- .source_langflow_inline_env()
  shaped <- env$.langflow_sup_is_citation_shaped

  expect_true(shaped("(1)"))
  expect_true(shaped("(1)(2)"))
  expect_true(shaped("(1, 2)"))
  expect_true(shaped("( 1 )"))
  expect_false(shaped("1"))
  expect_false(shaped("1, 2"))
  expect_false(shaped("2"))
  expect_false(shaped("x"))
  expect_false(shaped("(1"))
  expect_false(shaped("1)"))
  expect_false(shaped(""))
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
  expect_null(parse("Metin.\n\nKaynak:\n(1)  /kok/gizli/dosya.pdf\n"))
  expect_null(parse("Metin.\n\nKaynak:\n(1) C:/gizli/dosya.docx\n"))
  expect_null(parse("Metin.\n\nKaynak:\n(1) ust&&..&&dosya.pdf\n"))
  expect_null(parse("Metin.\n\nKaynak:\n(1) ust&&C:&&dosya.pdf\n"))
  expect_null(parse("Metin.\n\nKaynak:\n(1) ust&& &&dosya.pdf\n"))
  expect_null(parse("Metin.\n\nKaynak:\n(1) javascript:dosya.pdf\n"))
  # Kurumsal yüklenen belgeler bugün PDF; ileride Word için doc/docx tutulur.
  expect_null(parse("Metin.\n\nKaynak:\n(1) Grup&&deck.pptx\n"))
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

test_that("mergen_langflow_finalize_answer kaynak yoksa <sup> çevirmez (sıradan üstsimge korunur)", {
  env <- .source_langflow_inline_env()
  finalize <- env$mergen_langflow_finalize_answer

  # Kaynakça bloğu üretilmediyse (yapısal kaynak yok + düzyazı "Kaynak:" yok),
  # "m<sup>2</sup>" gibi matematiksel üstsimge yanlış atıf gibi görünmez.
  out <- finalize("Alan m<sup>2</sup> olarak hesaplanır.", list())
  expect_false(grepl("[2]", out, fixed = TRUE))
  expect_match(out, "m<sup>2</sup>", fixed = TRUE)
})

test_that("mergen_langflow_finalize_answer atlanan kaynak numarasında eşleşmeyen atıfı etkisiz kılar", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_inline_env()
  finalize <- env$mergen_langflow_finalize_answer

  # (1) reddedilir (URL), (2) kabul edilir -> tek yoğun giriş [1] olur.
  # <sup>(1)</sup> yanlış belgeye kaymamalı: DÜŞÜRÜLÜR. <sup>(2)</sup> -> [1].
  metin <- paste0(
    "Cümle bir.<sup>(1)</sup>\n",
    "Cümle iki.<sup>(2)</sup>\n\n",
    "Kaynak:\n",
    "(1) https://ornek.gecersiz/dis.pdf\n",
    "(2) Grup&&gecerli.pdf\n"
  )
  out <- finalize(metin, list())
  expect_match(out, "Cümle bir.\n", fixed = TRUE)
  expect_false(grepl("Cümle bir.[1]", out, fixed = TRUE))
  expect_match(out, "Cümle iki.[1]", fixed = TRUE)
  expect_match(out, "[KAYNAK 1] gecerli.pdf", fixed = TRUE)
})

test_that("mergen_langflow_finalize_answer girişlerden sonraki metni korur (sessizce düşürmez)", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_inline_env()
  finalize <- env$mergen_langflow_finalize_answer

  metin <- paste0(
    "Ana cevap metni.\n\n",
    "Kaynak:\n",
    "(1) Grup&&kilavuz.pdf\n\n",
    "Not: Belgeler kurumsal klasorde saklanir."
  )
  out <- finalize(metin, list())
  # Trailing "Not:" metni korunur (düzyazıya taşınır); Kaynakça yine en sonda.
  expect_match(out, "Not: Belgeler kurumsal klasorde saklanir.", fixed = TRUE)
  expect_match(out, "Ana cevap metni.", fixed = TRUE)
  expect_match(out, "\n\nKaynakça:\n[KAYNAK 1]", fixed = TRUE)
})

test_that("mergen_langflow_parse_prose_sources numaralı girişler arasındaki boş satırı atlar (listeyi kesmez)", {
  env <- .source_langflow_inline_env()
  parse <- env$mergen_langflow_parse_prose_sources

  metin <- paste0(
    "Metin.\n\nKaynak:\n",
    "(1) Grup&&a.pdf\n",
    "\n",
    "(2) Grup&&b.pdf\n"
  )
  res <- parse(metin)
  expect_false(is.null(res))
  expect_length(res$records, 2L)
  expect_identical(res$records[[1]]$title, "a.pdf")
  expect_identical(res$records[[2]]$title, "b.pdf")
  expect_identical(res$tail, "")
})

test_that("mergen_langflow_finalize_answer boş satırla ayrılmış girişlerdeki atıfları doğru eşler", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_inline_env()
  finalize <- env$mergen_langflow_finalize_answer

  metin <- paste0(
    "Birinci cümle.<sup>(1)</sup>\n",
    "İkinci cümle.<sup>(2)</sup>\n\n",
    "Kaynak:\n",
    "(1) Grup&&a.pdf\n",
    "\n",
    "(2) Grup&&b.pdf\n"
  )
  out <- finalize(metin, list())
  expect_match(out, "Birinci cümle.[1]", fixed = TRUE)
  expect_match(out, "İkinci cümle.[2]", fixed = TRUE)
  expect_match(out, "[KAYNAK 1] a.pdf", fixed = TRUE)
  expect_match(out, "[KAYNAK 2] b.pdf", fixed = TRUE)
})

test_that("mergen_langflow_parse_prose_sources BÜYÜK harf başlıkları tanır (KAYNAK / KAYNAKÇA)", {
  env <- .source_langflow_inline_env()
  parse <- env$mergen_langflow_parse_prose_sources

  r1 <- parse("Metin.\n\nKAYNAK:\n(1) Grup&&rapor.pdf\n")
  expect_false(is.null(r1))
  expect_length(r1$records, 1L)

  r2 <- parse("Metin.\n\nKAYNAKÇA:\n(1) Grup&&kilavuz.docx\n")
  expect_false(is.null(r2))
  expect_length(r2$records, 1L)
})

test_that("search_file_in_folder pptx uzantısını indeksler ve alt klasörde çözer", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)
  alt <- file.path(base_dir, "AltKlasor")
  dir.create(alt, recursive = TRUE)

  fname <- "Grup 1&&Sunum&&tanitim.pptx"
  writeLines("ornek", file.path(alt, fname))

  found <- search_file_in_folder(base_dir, fname)
  expect_false(is.null(found))
  expect_identical(
    normalizePath(found, winslash = "/"),
    normalizePath(file.path(alt, fname), winslash = "/")
  )
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


test_that("mergen_kaynakca_marker_html tıklama ipucunda boşluklu && gezinme parçalarını taşımaz", {
  testthat::skip_if_not_installed("htmltools")
  env <- .source_langflow_inline_env()

  html <- env$mergen_kaynakca_marker_html(list(
    list(title = "secret.pdf", path = "A&& .. &&secret.pdf", page = "", type = "pdf"),
    list(title = "dosya.docx", path = "A&& C: &&dosya.docx", page = "", type = "docx")
  ))

  expect_false(grepl("data-filename='A&amp;&amp; .. &amp;&amp;secret.pdf'", html, fixed = TRUE))
  expect_false(grepl("data-filename='A&amp;&amp; C: &amp;&amp;dosya.docx'", html, fixed = TRUE))
  expect_match(html, "data-filename='A&amp;&amp;secret.pdf'", fixed = TRUE)
  expect_match(html, "data-filename='A&amp;&amp;dosya.docx'", fixed = TRUE)
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

test_that("search_file_in_folder ipucu skorlu aramadan önce TAM '&&' eşleşmesini tercih eder", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)

  # Alakasız dosya: yalnızca ipucunun SON parçasıyla aynı basename'e sahip
  # (yanlış eşleşme adayı). '.search_with_hint' bu adaya düşerse yanlış dosya
  # açılırdı.
  decoy_dir <- file.path(base_dir, "Alakasiz")
  dir.create(decoy_dir, recursive = TRUE)
  writeLines("yanlis", file.path(decoy_dir, "prosedur.pdf"))

  # Gerçek düz '&&' adı: aranan TAM hedef.
  real_dir <- file.path(base_dir, "Gercek")
  dir.create(real_dir, recursive = TRUE)
  fname <- "Grup&&Kalite&&prosedur.pdf"
  writeLines("dogru", file.path(real_dir, fname))

  found <- search_file_in_folder(base_dir, fname)
  expect_false(is.null(found))
  expect_identical(
    normalizePath(found, winslash = "/"),
    normalizePath(file.path(real_dir, fname), winslash = "/")
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

test_that("search_file_in_folder uzantılı ipucunda parça-içerme son çaresini devre dışı bırakır (yanlış dosya açmaz)", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)
  decoy_dir <- file.path(base_dir, "A", "B")
  dir.create(decoy_dir, recursive = TRUE)
  # Atıflanan gerçek dosya (A&&B&&prosedur.pdf) DİSKTE YOK; yalnızca alt-dize
  # olarak tüm parçaları içeren ALAKASIZ bir dosya var.
  writeLines("yanlis", file.path(decoy_dir, "eski-prosedur.pdf"))

  found <- search_file_in_folder(base_dir, "A&&B&&prosedur.pdf")
  expect_null(found)
})

test_that("search_file_in_folder docm uzantısını indeksler ve alt klasörde çözer", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)
  alt <- file.path(base_dir, "AltKlasor")
  dir.create(alt, recursive = TRUE)

  fname <- "Grup 1&&Makro&&otomasyon.docm"
  writeLines("ornek", file.path(alt, fname))

  found <- search_file_in_folder(base_dir, fname)
  expect_false(is.null(found))
  expect_identical(
    normalizePath(found, winslash = "/"),
    normalizePath(file.path(alt, fname), winslash = "/")
  )
})

test_that(".langflow_strip_page_suffix parantezli/virgüllü sayfa eklerini uzantıdan sonra ayırır", {
  env <- .source_langflow_inline_env()
  strip <- env$.langflow_strip_page_suffix

  r1 <- strip("Grup&&dosya.pdf (Sayfa 3)")
  expect_identical(r1$name, "Grup&&dosya.pdf")
  expect_identical(r1$page, "3")

  r2 <- strip("dosya.pdf, s. 5")
  expect_identical(r2$name, "dosya.pdf")
  expect_identical(r2$page, "5")

  r3 <- strip("Grup&&dosya.docx (Page 2)")
  expect_identical(r3$name, "Grup&&dosya.docx")
  expect_identical(r3$page, "2")

  # Sayfa eki yoksa ad değişmeden kalır.
  r4 <- strip("Grup&&kilavuz.pdf")
  expect_identical(r4$name, "Grup&&kilavuz.pdf")
  expect_identical(r4$page, "")

  # Uzantıdan ÖNCE gelen benzer metin (ör. dosya adının kendi parçası) yanlışlıkla
  # sayfa eki sayılmaz; uzantı en sonda olduğundan ad değişmeden kalır.
  r5 <- strip("Analiz (Sayfa 3).pdf")
  expect_identical(r5$name, "Analiz (Sayfa 3).pdf")
  expect_identical(r5$page, "")
})

test_that(".langflow_prose_source_record sayfa açıklaması eklenmiş kaynak adlarını doğru ayrıştırır", {
  env <- .source_langflow_inline_env()
  rec_fn <- env$.langflow_prose_source_record

  r1 <- rec_fn("Grup&&dosya.pdf (Sayfa 3)")
  expect_false(is.null(r1))
  expect_identical(r1$path, "Grup&&dosya.pdf")
  expect_identical(r1$title, "dosya.pdf")
  expect_identical(r1$type, "pdf")
  expect_identical(r1$page, "3")

  r2 <- rec_fn("Grup&&dosya.pdf, s. 5")
  expect_false(is.null(r2))
  expect_identical(r2$path, "Grup&&dosya.pdf")
  expect_identical(r2$page, "5")

  # Sayfa eki yoksa mevcut davranış korunur (page = "").
  r3 <- rec_fn("Grup&&kilavuz.pdf")
  expect_false(is.null(r3))
  expect_identical(r3$page, "")
})

test_that("mergen_langflow_parse_prose_sources sayfa açıklamalı kaynak satırlarını reddetmez", {
  env <- .source_langflow_inline_env()
  parse <- env$mergen_langflow_parse_prose_sources

  metin <- paste0(
    "Metin.\n\nKaynak:\n",
    "(1) Grup&&dosya.pdf (Sayfa 3)\n",
    "(2) Grup&&kilavuz.docx, s. 7\n"
  )
  res <- parse(metin)
  expect_false(is.null(res))
  expect_length(res$records, 2L)
  expect_identical(res$records[[1]]$path, "Grup&&dosya.pdf")
  expect_identical(res$records[[1]]$page, "3")
  expect_identical(res$records[[2]]$path, "Grup&&kilavuz.docx")
  expect_identical(res$records[[2]]$page, "7")
})

test_that("mergen_langflow_kaynakca_marker_block && ipucunda gezinme/sürücü parçalarını imzalamaz", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_inline_env()
  block <- env$mergen_langflow_kaynakca_marker_block(list(
    list(title = "dosya.pdf", path = "ust&&..&&dosya.pdf", page = "", type = "pdf"),
    list(title = "dosya.pdf", path = "ust&& .. &&dosya.pdf", page = "", type = "pdf"),
    list(title = "dosya.pdf", path = "ust/..&&dosya.pdf", page = "", type = "pdf"),
    list(title = "dosya.pdf", path = "ust&&../dosya.pdf", page = "", type = "pdf"),
    list(title = "dosya.pdf", path = "ust&&C:&&dosya.pdf", page = "", type = "pdf"),
    list(title = "dosya.pdf", path = "ust&& &&dosya.pdf", page = "", type = "pdf"),
    list(title = "dosya.pdf", path = " /kok/gizli/dosya.pdf", page = "", type = "pdf"),
    list(title = "dosya.pdf", path = "https://ornek.gecersiz/dosya.pdf", page = "", type = "pdf"),
    list(title = "guvenli.pdf", path = "ust&&guvenli.pdf", page = "", type = "pdf")
  ))

  expect_match(block, "[KAYNAK 1] guvenli.pdf", fixed = TRUE)
  expect_false(grepl("ust&&..&&dosya.pdf", block, fixed = TRUE))
  expect_false(grepl("ust&& .. &&dosya.pdf", block, fixed = TRUE))
  expect_false(grepl("ust/..&&dosya.pdf", block, fixed = TRUE))
  expect_false(grepl("ust&&../dosya.pdf", block, fixed = TRUE))
  expect_false(grepl("ust&&C:&&dosya.pdf", block, fixed = TRUE))
  expect_false(grepl("ust&& &&dosya.pdf", block, fixed = TRUE))
  expect_false(grepl("/kok/gizli/dosya.pdf", block, fixed = TRUE))
  expect_false(grepl("https://ornek.gecersiz/dosya.pdf", block, fixed = TRUE))
})

test_that("mergen_kaynakca_marker_split eski imzalı güvensiz && ipuçlarını render'a taşımaz", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_inline_env()

  unsafe_marker <- function(unsafe_path) {
    code <- env$.kaynakca_marker_code("dosya.pdf", unsafe_path, "", "pdf")
    paste0(
      "Metin\n\nKaynakça:\n",
      "[KAYNAK 1] dosya.pdf | yol=", unsafe_path, " | kod=", code, " | tur=pdf\n"
    )
  }

  expect_null(env$mergen_kaynakca_marker_split(unsafe_marker("ust/..&&dosya.pdf")))
  expect_null(env$mergen_kaynakca_marker_split(unsafe_marker("ust&& .. &&dosya.pdf")))
  expect_null(env$mergen_kaynakca_marker_split(unsafe_marker("ust&& &&dosya.pdf")))
  expect_null(env$mergen_kaynakca_marker_split(unsafe_marker(" /kok/gizli/dosya.pdf")))
})
test_that("mergen_langflow_finalize_answer yapısal kaynak varken yinelenen düzyazı Kaynak bloğunu söker", {
  testthat::skip_if_not_installed("openssl")
  env <- .source_langflow_inline_env()
  finalize <- env$mergen_langflow_finalize_answer

  structured <- list(list(title = "prosedur.pdf", path = "Grup&&prosedur.pdf", page = "", type = "pdf"))
  metin <- paste0(
    "Cevap.<sup>(1)</sup>\n\n",
    "Kaynak:\n",
    "(1) Grup&&prosedur.pdf\n"
  )
  out <- finalize(metin, structured)

  expect_match(out, "Cevap.[1]", fixed = TRUE)
  expect_false(grepl("\nKaynak:\n", out, fixed = TRUE))
  expect_match(out, "[KAYNAK 1] prosedur.pdf", fixed = TRUE)
})

test_that("search_file_in_folder ipucu sol parçaları eşleşmeyen aynı-basename adayı döndürmez", {
  base_dir <- tempfile()
  dir.create(base_dir, recursive = TRUE)
  decoy_dir <- file.path(base_dir, "Alakasiz")
  dir.create(decoy_dir, recursive = TRUE)
  writeLines("yanlis", file.path(decoy_dir, "prosedur.pdf"))

  found <- search_file_in_folder(base_dir, "Grup&&Kalite&&prosedur.pdf")
  expect_null(found)
})

test_that("search_file_in_folder ipucu skorunda taban klasör adındaki parçaları saymaz", {
  parent_dir <- tempfile("Grup-Kalite-")
  base_dir <- file.path(parent_dir, "belgeler")
  dir.create(base_dir, recursive = TRUE)
  decoy_dir <- file.path(base_dir, "Alakasiz")
  dir.create(decoy_dir, recursive = TRUE)
  writeLines("yanlis", file.path(decoy_dir, "prosedur.pdf"))

  found <- search_file_in_folder(base_dir, "Grup&&Kalite&&prosedur.pdf")
  expect_null(found)
})

# ------------------------------------------------------------------------------
# UNICODE ÜSTSİMGE ATIFLARI (Langflow istemi `<sup>` etiketini KALDIRDI)
#
# Karakterler `intToUtf8()` ile kurulur: kaynak dosya ASCII/CP1254 güvenli kalır
# ve Windows konsol kod sayfası fixture'ı bozamaz.
# ------------------------------------------------------------------------------

.langflow_ust <- function(kod) intToUtf8(as.integer(kod))

test_that("üstsimge KARAKTERİ atıfları [n]'e çevrilir", {
  env <- .source_langflow_inline_env()
  harita <- stats::setNames(as.character(1:4), as.character(1:4))

  metin <- paste0("baslatilir", .langflow_ust(0x00B9), "; onay alinir",
                  .langflow_ust(0x00B3), " ve rapor (EK-C)",
                  .langflow_ust(0x2074), " hazirlanir.")
  out <- env$.langflow_unicode_sup_to_citation(metin, harita)

  expect_true(grepl("baslatilir[1];", out, fixed = TRUE))
  expect_true(grepl("alinir[3]", out, fixed = TRUE))
  expect_true(grepl("(EK-C)[4]", out, fixed = TRUE))
})

test_that("ÜS ifadeleri atıf sayılmaz", {
  env <- .source_langflow_inline_env()
  harita <- stats::setNames(as.character(1:6), as.character(1:6))

  # Ölçü birimi ve sayı ardından gelen üstsimge bir üstür, atıf değildir.
  for (metin in c(paste0("alan 25 m", .langflow_ust(0x00B2)),
                  paste0("hacim 3 cm", .langflow_ust(0x00B3)),
                  paste0("deger 10", .langflow_ust(0x2076)))) {
    expect_identical(env$.langflow_unicode_sup_to_citation(metin, harita), metin)
  }
})

test_that("yan yana üstsimgeler KAYNAKÇA'ya sorularak çözülür", {
  env <- .source_langflow_inline_env()

  metin <- paste0("dayanir", .langflow_ust(0x00B9), .langflow_ust(0x00B2), ".")

  # 4 kaynak: "12" geçerli bir giriş DEĞİLDİR -> iki ayrı atıf.
  dar <- stats::setNames(as.character(1:4), as.character(1:4))
  expect_true(grepl("dayanir[1][2].", env$.langflow_unicode_sup_to_citation(metin, dar),
                    fixed = TRUE))

  # 12 kaynak: "12" geçerli bir giriştir -> TEK atıf.
  genis <- stats::setNames(as.character(1:12), as.character(1:12))
  expect_true(grepl("dayanir[12].", env$.langflow_unicode_sup_to_citation(metin, genis),
                    fixed = TRUE))
})

test_that("KAYNAKÇA yokken üstsimge DEĞİŞMEZ", {
  env <- .source_langflow_inline_env()
  metin <- paste0("baslatilir", .langflow_ust(0x00B9), ".")

  # Harita yok: doğrulanamayan atıf düşürülmez, metin korunur.
  expect_identical(env$.langflow_unicode_sup_to_citation(metin, NULL), metin)
  # Aralık dışı numara da etkisizdir.
  expect_identical(
    env$.langflow_unicode_sup_to_citation(paste0("x", .langflow_ust(0x2079)),
                                          stats::setNames("1", "1")),
    paste0("x", .langflow_ust(0x2079))
  )
})

test_that("finalize üstsimge KARAKTERLERİNİ de tıklanabilir hâle getirir", {
  env <- .source_langflow_inline_env()
  kaynaklar <- list(
    list(title = "Belge A", path = "belge_a.pdf"),
    list(title = "Belge B", path = "Grup&&belge_b.pdf")
  )
  metin <- paste0("Ilk madde", .langflow_ust(0x00B9), " ve ikinci madde",
                  .langflow_ust(0x00B2), ".")

  out <- env$mergen_langflow_finalize_answer(metin, kaynaklar)
  expect_true(grepl("Ilk madde[1]", out, fixed = TRUE))
  expect_true(grepl("ikinci madde[2]", out, fixed = TRUE))
  expect_true(grepl("[KAYNAK 1]", out, fixed = TRUE))
  expect_true(grepl("[KAYNAK 2]", out, fixed = TRUE))
})
