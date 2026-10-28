# ==============================================================================
# Dosya Yolu: tests/testthat/test-docx-bounded-reader-behavior.R
# Açıklama: DOCX okuyucunun kaynak sınırları. Küçük ama patolojik arşivler
#           (sıkıştırma bombası, düğüm bombası, yalan beyan edilen boyut, DTD
#           varlık zinciri) XML DOM kurulmadan ve sınırlı bayt üretilerek
#           reddedilir; meşru Türkçe belge değişmeden okunur. Hem ortak dosya
#           okuyucu (readFileContentToString) hem Bilge Yolaç çıkarıcısı aynı
#           sınırlı okuyucudan geçer. Fikstürler tests/fixtures/docx altındadır
#           (en büyüğü ~55 KB).
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
    sys.source(file.path(root, "R", "helpers_files_docx_reader.R"), envir = env, keep.source = FALSE)
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
    list(dosya = "oznitelik_bombasi.docx", hata = "öznitelik sayısını"),
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

test_that("Word tarzı yoğun tablo XML'i varsayılan öğe bütçesine takılmaz", {
  env <- .docx_env()
  withr::local_envvar(MERGEN_DOCX_MAX_XML_NODES = NA, MERGEN_DOCX_MAX_XML_MB = NA)
  yol <- .docx_fikstur("yogun_tablo_gecerli.docx")
  # ~11 MB XML, ~910 bin '<' (kapanış etiketleri dahil): boyut sınırının altında
  # meşru, etiket yoğun belge (~12.5 bayt/'<') reddedilmemeli.
  baglanti <- unz(yol, "word/document.xml", open = "rb")
  baytlar <- readBin(baglanti, what = "raw", n = 25 * 1024 * 1024)
  close(baglanti)
  expect_gt(sum(baytlar == as.raw(0x3C)), 750000)
  belge <- env$mergen_docx_read_document_xml(yol)
  son <- xml2::xml_text(xml2::xml_find_first(belge, "/*/*/*[last()]"))
  expect_identical(son, enc2utf8("Tablo sonu: ğüşıöç İ"))
})

test_that("metin düğümündeki '=' karakterleri öznitelik sayılmaz", {
  env <- .docx_env()
  withr::local_envvar(MERGEN_DOCX_MAX_XML_NODES = NA, MERGEN_DOCX_MAX_XML_MB = NA)
  # Tek <w:t> içinde 5000 '=' (öznitelik yok): öğe başı ve toplam öznitelik
  # sınırının üstünde '=' taşısa da meşru belge reddedilmez.
  yol <- .docx_fikstur("esittir_metni_gecerli.docx")
  metin <- xml2::xml_text(env$mergen_docx_read_document_xml(yol, max_elements = 1000))
  expect_identical(metin, paste0(strrep("=", 5000L), " x = y"))
  expect_match(env$readFileContentToString(list(name = "x.docx", datapath = yol)), strrep("=", 5000L), fixed = TRUE)
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
  # Aynı düğüm bütçesi öznitelik ('=') sayısına ayrıca uygulanır: tek öğeli
  # belge '<' sınırının altında kalsa da öznitelik sınırına takılır.
  withr::local_envvar(MERGEN_DOCX_MAX_XML_NODES = "100")
  expect_error(env$mergen_docx_read_document_xml(.docx_fikstur("oznitelik_bombasi.docx"), max_attributes_per_element = 1e6),
               "öznitelik sayısını", fixed = TRUE)
  expect_s3_class(env$mergen_docx_read_document_xml(.docx_fikstur("gecerli_turkce.docx")), "xml_document")
  withr::local_envvar(MERGEN_DOCX_MAX_XML_NODES = "Inf", MERGEN_DOCX_MAX_XML_MB = "-1")
  expect_s3_class(env$mergen_docx_read_document_xml(.docx_fikstur("gecerli_turkce.docx")), "xml_document")
  expect_error(env$mergen_docx_read_document_xml(.docx_fikstur("boyut_bombasi.docx")), "izin verilen boyutu", fixed = TRUE)
})

test_that("UTF-16 belge denetimlerden önce UTF-8'e çevrilir; DTD UTF-16 ile gizlenemez", {
  env <- .docx_env()
  metin <- xml2::xml_text(env$mergen_docx_read_document_xml(.docx_fikstur("utf16_gecerli.docx")))
  expect_identical(metin, enc2utf8("UTF-16 Türkçe ğüşıöç"))

  testthat::local_mocked_bindings(read_xml = function(...) stop("DOM kurulmamalıydı"), .package = "xml2")
  expect_error(env$mergen_docx_read_document_xml(.docx_fikstur("utf16_dtd_varlik.docx")), "DTD", fixed = TRUE)
  # Çevrilemeyen çok baytlı kodlama (UCS-4) taramayı atlatamaz: reddedilir.
  expect_error(env$mergen_docx_read_document_xml(.docx_fikstur("utf32_desteklenmez.docx")),
               "kodlaması desteklenmiyor", fixed = TRUE)
})

test_that("UTF-8'e çevrilince büyüyen UTF-16 belge bayt sınırını aşamaz", {
  env <- .docx_env()
  yol <- .docx_fikstur("utf16_genisleyen.docx")
  liste <- utils::unzip(yol, list = TRUE)
  ham <- as.numeric(liste$Length[liste$Name == "word/document.xml"])
  expect_identical(ham, 6094)
  # Ham UTF-16 (6094 bayt) sınırın altında, UTF-8 karşılığı (9046 bayt) üstünde.
  testthat::local_mocked_bindings(read_xml = function(...) stop("DOM kurulmamalıydı"), .package = "xml2")
  expect_error(env$mergen_docx_read_document_xml(yol, max_xml_bytes = ham + 100),
               "izin verilen boyutu", fixed = TRUE)
})

test_that("bildirilen başka kodlama (EBCDIC) DTD'yi tarama dışında bırakıp ayrıştırıcıya ulaştıramaz", {
  env <- .docx_env()
  # Bildirim yok sayılır (IGNORE_ENC): EBCDIC baytları UTF-8 olarak ayrıştırılır
  # ve belge ayrıştırıcıda reddedilir; DTD içeriği hiçbir yoldan metne ulaşmaz.
  expect_error(env$mergen_docx_read_document_xml(.docx_fikstur("ebcdic_dtd.docx")),
               "Start tag expected", fixed = TRUE)
  expect_match(env$readFileContentToString(list(name = "x.docx", datapath = .docx_fikstur("ebcdic_dtd.docx"))),
               "Dosya okunurken bir hata", fixed = TRUE)
})

test_that("DTD yalnız prologda aranır: gövdedeki yorum/CDATA metni reddedilmez, prolog hilesi reddedilir", {
  env <- .docx_env()
  metin <- xml2::xml_text(env$mergen_docx_read_document_xml(.docx_fikstur("dtd_metni_govdede.docx")))
  expect_identical(metin, enc2utf8("Örnek: <!DOCTYPE html> ğüş"))
  expect_match(env$readFileContentToString(list(name = "x.docx", datapath = .docx_fikstur("dtd_metni_govdede.docx"))),
               "<!DOCTYPE html>", fixed = TRUE)

  # Prolog yorumundaki "<a" taramayı bitiremez; arkasındaki DTD DOM'dan önce reddedilir.
  testthat::local_mocked_bindings(read_xml = function(...) stop("DOM kurulmamalıydı"), .package = "xml2")
  expect_error(env$mergen_docx_read_document_xml(.docx_fikstur("dtd_yorum_hilesi.docx")), "DTD", fixed = TRUE)
  b <- function(x) charToRaw(enc2utf8(x))
  expect_false(env$mergen_docx_prolog_has_dtd(b("\ufeff<?xml version='1.0'?>\n<!-- <!DOCTYPE --> <r/>")))
  expect_true(env$mergen_docx_prolog_has_dtd(b("<?xml version='1.0'?><!--x--><!DOCTYPE r><r/>")))
  expect_true(env$mergen_docx_prolog_has_dtd(b("<!ELEMENT r ANY><r/>")))
})
