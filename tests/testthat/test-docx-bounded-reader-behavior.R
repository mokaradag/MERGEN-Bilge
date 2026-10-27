# ==============================================================================
# Dosya Yolu: tests/testthat/test-docx-bounded-reader-behavior.R
# Açıklama: DOCX okuyucunun kaynak sınırları. Küçük ama patolojik arşivler
#           (sıkıştırma bombası, düğüm bombası, yalan beyan edilen boyut, DTD
#           varlık zinciri) XML DOM kurulmadan ve sınırlı bayt üretilerek
#           reddedilir; meşru Türkçe belge değişmeden okunur. Hem ortak dosya
#           okuyucu (readFileContentToString) hem Bilge Yolaç çıkarıcısı aynı
#           sınırlı okuyucudan geçer. Fikstürler tests/fixtures/docx altındadır
#           (en büyüğü ~41 KB).
# ==============================================================================

.docx_env <- local({
  env <- NULL
  function() {
    if (!is.null(env)) return(env)
    env <<- new.env(parent = globalenv())
    root <- resolve_repo_root_for_tests()
    env$`%||%` <- function(x, y) if (is.null(x)) y else x
    env$path_exists_relaxed <- function(p) file.exists(p)
    env$resolve_readable_path <- function(p) p
    sys.source(file.path(root, "R", "helpers_files.R"), envir = env, keep.source = FALSE)
    sys.source(file.path(root, "R", "helpers_claude_code_document_extractors.R"),
               envir = env, keep.source = FALSE)
    env
  }
})

.docx_fikstur <- function(ad) file.path(resolve_repo_root_for_tests(), "tests", "fixtures", "docx", ad)

test_that("meşru Türkçe DOCX iki okuyucuda da okunur", {
  env <- .docx_env()
  beklenen <- enc2utf8("Türkçe çalışma ğüşıöç İ")
  metin <- env$readFileContentToString(list(name = "belge.docx", datapath = .docx_fikstur("gecerli_turkce.docx")))
  expect_match(metin, beklenen, fixed = TRUE)
  expect_match(metin, "ikinci paragraf", fixed = TRUE)
  cc <- env$extract_docx_text_for_claude(.docx_fikstur("gecerli_turkce.docx"))
  expect_match(cc, beklenen, fixed = TRUE)
})

test_that("patolojik DOCX, XML DOM kurulmadan reddedilir", {
  env <- .docx_env()
  # read_xml çağrılırsa test düşer: ret DOM'dan ÖNCE olmalıdır.
  testthat::local_mocked_bindings(read_xml = function(...) stop("DOM kurulmamalıydı"), .package = "xml2")

  vakalar <- list(
    list(dosya = "boyut_bombasi.docx", hata = "izin verilen boyutu"),
    list(dosya = "dugum_bombasi.docx", hata = "öğe sayısını"),
    list(dosya = "dtd_varlik.docx", hata = "DTD")
  )
  for (v in vakalar) {
    expect_error(env$mergen_docx_read_document_xml(.docx_fikstur(v$dosya)), v$hata, fixed = TRUE,
                 info = v$dosya)
    # Ortak okuyucu hatayı metin sonucuna çevirir; Bilge Yolaç çıkarıcısı hata verir.
    sonuc <- env$readFileContentToString(list(name = "x.docx", datapath = .docx_fikstur(v$dosya)))
    expect_match(sonuc, "Dosya okunurken bir hata", fixed = TRUE, info = v$dosya)
    expect_false(grepl("DOM kurulmamal", sonuc, fixed = TRUE), info = v$dosya)
    expect_error(env$extract_docx_text_for_claude(.docx_fikstur(v$dosya)), v$hata, fixed = TRUE,
                 info = v$dosya)
  }
})

test_that("merkez dizinde yalan beyan edilen boyut açma bütçesini aşamaz", {
  env <- .docx_env()
  yol <- .docx_fikstur("yalanci_boyut.docx")
  liste <- utils::unzip(yol, list = TRUE)
  expect_identical(as.numeric(liste$Length[liste$Name == "word/document.xml"]), 1000)
  # Açıcı beyan edilen boyutta durur (gerçek akış 40 MB); okuyucunun kendi
  # bütçe + 1 bayt sınırı ikinci savunma hattıdır.
  baglanti <- unz(yol, "word/document.xml", open = "rb")
  uretilen <- length(readBin(baglanti, what = "raw", n = 2 * 1024 * 1024 + 1))
  close(baglanti)
  expect_lte(uretilen, 1000)
  # Kesik XML ayrıştırılamaz: belge reddedilir, büyük içerik hiç üretilmez.
  expect_error(env$mergen_docx_read_document_xml(yol, max_xml_bytes = 2 * 1024 * 1024))
  expect_match(env$readFileContentToString(list(name = "x.docx", datapath = yol)),
               "Dosya okunurken bir hata", fixed = TRUE)
})

test_that("sınırlar ortam değişkeniyle ayarlanabilir; geçersiz değer güvenli varsayılana döner", {
  env <- .docx_env()
  withr::local_envvar(MERGEN_DOCX_MAX_XML_NODES = "3")
  expect_error(env$mergen_docx_read_document_xml(.docx_fikstur("gecerli_turkce.docx")), "öğe sayısını", fixed = TRUE)
  withr::local_envvar(MERGEN_DOCX_MAX_XML_NODES = "Inf", MERGEN_DOCX_MAX_XML_MB = "-1")
  expect_s3_class(env$mergen_docx_read_document_xml(.docx_fikstur("gecerli_turkce.docx")), "xml_document")
  expect_error(env$mergen_docx_read_document_xml(.docx_fikstur("boyut_bombasi.docx")), "izin verilen boyutu", fixed = TRUE)
})
