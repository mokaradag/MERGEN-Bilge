# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-document-builders-behavior.R
# Açıklama: Bilge Yolaç doküman bağlamı saf kurucu (builder) fonksiyonlarının
#           davranışını doğrular: çalışma prompt'u, inline metin yükü, özet
#           mesajları ve rehber (manifest) dosyası. Çevrimdışı/deterministik;
#           gerçek LLM/Claude CLI/ağ yok.
# ==============================================================================

repo_root_ccd <- resolve_repo_root_for_tests()

.ccd_env <- new.env(parent = globalenv())
suppressWarnings(source(
  file.path(repo_root_ccd, "R/helpers_claude_code_documents.R"),
  encoding = "UTF-8", local = .ccd_env
))
# Özet mesaj/orkestrasyon yardımcıları document_summary.R'ye ayrıldı.
suppressWarnings(source(
  file.path(repo_root_ccd, "R/helpers_claude_code_document_summary.R"),
  encoding = "UTF-8", local = .ccd_env
))

# Bir dosyayı bayt-güvenli okuyup ASCII çapalarla aramak için yardımcı
# (Windows/VM yerel ayarlarında geçersiz UTF-8 uyarısı üretmemek için).
.ccd_read_bytes <- function(path) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
  iconv(rawToChar(raw), from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("build_claude_code_document_prompt sistem notu + kullanıcı isteğini içerir", {
  out <- .ccd_env$build_claude_code_document_prompt("Bu dosyaları özetle")
  expect_true(is.character(out) && length(out) == 1L)
  expect_true(grepl("SİSTEM ÇALIŞMA NOTU:", out, fixed = TRUE))
  expect_true(grepl("KULLANICININ ASIL İSTEĞİ:", out, fixed = TRUE))
  expect_true(grepl("Bu dosyaları özetle", out, fixed = TRUE))
  # Opsiyonel bölümler verilmediğinde eklenmez
  expect_false(grepl("Önce şu rehberi oku:", out, fixed = TRUE))
  expect_false(grepl("HAZIR METIN CIKARIMLARI:", out, fixed = TRUE))
})

test_that("build_claude_code_document_prompt opsiyonel bölümleri doğru ekler", {
  out <- .ccd_env$build_claude_code_document_prompt(
    "soru",
    manifest_path = "/tmp/rehber.md",
    reader_template_path = "/tmp/reader.R",
    unsupported_files = c("a.doc", "a.doc", "b.doc"),
    inline_payload = "HAZIR-METIN-BLOK"
  )
  expect_true(grepl("Önce şu rehberi oku: /tmp/rehber.md", out, fixed = TRUE))
  expect_true(grepl("yerel yardımcıyı kullan: /tmp/reader.R", out, fixed = TRUE))
  # Desteklenmeyen dosyalar benzersizleştirilir
  expect_true(grepl("a.doc, b.doc", out, fixed = TRUE))
  expect_false(grepl("a.doc, a.doc", out, fixed = TRUE))
  expect_true(grepl("HAZIR METIN CIKARIMLARI:", out, fixed = TRUE))
  expect_true(grepl("HAZIR-METIN-BLOK", out, fixed = TRUE))
})

test_that("build_claude_code_document_inline_payload metin bloklarını birleştirir", {
  tf1 <- tempfile(fileext = ".txt"); writeLines("birinci dosya metni", tf1)
  tf2 <- tempfile(fileext = ".txt"); writeLines("ikinci dosya metni", tf2)
  on.exit(unlink(c(tf1, tf2)), add = TRUE)

  files <- list(
    list(text_path = tf1, source_path = "rapor1.pdf"),
    list(text_path = tf2, source_path = "rapor2.pdf")
  )
  out <- .ccd_env$build_claude_code_document_inline_payload(files)
  expect_true(grepl("ÖNCEDEN ÇIKARILMIŞ METİNLER", out, fixed = TRUE))
  expect_true(grepl("DOSYA: rapor1.pdf", out, fixed = TRUE))
  expect_true(grepl("birinci dosya metni", out, fixed = TRUE))
  expect_true(grepl("DOSYA: rapor2.pdf", out, fixed = TRUE))
  expect_true(grepl("ikinci dosya metni", out, fixed = TRUE))
})

test_that("build_claude_code_document_inline_payload boş liste için '' döner", {
  expect_identical(.ccd_env$build_claude_code_document_inline_payload(list()), "")
})

test_that("build_claude_code_document_inline_payload bütçe aşılınca kısaltır", {
  tf <- tempfile(fileext = ".txt")
  writeLines(paste(rep("uzun metin parcasi", 50), collapse = " "), tf)
  on.exit(unlink(tf), add = TRUE)
  files <- list(list(text_path = tf, source_path = "buyuk.pdf"))
  out <- .ccd_env$build_claude_code_document_inline_payload(files, max_toplam_karakter = 40L)
  expect_true(grepl("METIN KISALTILDI", out, fixed = TRUE))
})

test_that("build_claude_code_document_summary_messages system+user mesajı üretir", {
  msgs <- .ccd_env$build_claude_code_document_summary_messages(
    list(prompt = "Bu raporları özetle")
  )
  expect_length(msgs, 2L)
  expect_identical(msgs[[1]]$role, "system")
  expect_identical(msgs[[2]]$role, "user")
  expect_identical(msgs[[2]]$content, "Bu raporları özetle")
  expect_true(grepl("Bilge Yolaç doküman özetleme", msgs[[1]]$content, fixed = TRUE))
  expect_true(grepl("Yanıtını Türkçe ver", msgs[[1]]$content, fixed = TRUE))
})

test_that("build_claude_code_document_summary_messages detay seviyesine göre yönerge değişir", {
  detayli <- .ccd_env$build_claude_code_document_summary_messages(
    list(prompt = "Lütfen çok ayrıntılı ve kapsamlı bir özet ver")
  )
  kisa <- .ccd_env$build_claude_code_document_summary_messages(
    list(prompt = "Kısaca özetle")
  )
  # Detaylı istek için 'kapsamlı' yönergesi, kısa istek için 'yoğun' yönergesi
  expect_true(grepl("kapsamlı ve açıklayıcı", detayli[[1]]$content, fixed = TRUE))
  expect_true(grepl("Kısa ve yoğun bir özet", kisa[[1]]$content, fixed = TRUE))
})

test_that("write_claude_code_document_manifest rehber dosyası yazar", {
  hedef <- tempfile(fileext = ".md")
  on.exit(unlink(hedef), add = TRUE)
  files <- list(
    list(source_path = "rapor1.pdf", text_path = "/tmp/rapor1.txt", status = "hazır"),
    list(source_path = "rapor2.xlsx", text_path = "/tmp/rapor2.txt")
  )
  ret <- .ccd_env$write_claude_code_document_manifest(
    hedef, files,
    orijinal_prompt = "ozet-istegi-ABC",
    reader_template_path = "/tmp/reader.R"
  )
  expect_true(file.exists(hedef))
  expect_true(is.character(ret) && nzchar(ret))

  content <- .ccd_read_bytes(hedef)
  # ASCII çapalar (Windows/VM bayt-güvenli)
  expect_true(grepl("Bilge Yola", content, fixed = TRUE))
  expect_true(grepl("ozet-istegi-ABC", content, fixed = TRUE))
  expect_true(grepl("rapor1.pdf", content, fixed = TRUE))
  expect_true(grepl("/tmp/rapor1.txt", content, fixed = TRUE))
  expect_true(grepl("rapor2.xlsx", content, fixed = TRUE))
  expect_true(grepl("/tmp/reader.R", content, fixed = TRUE))
})

test_that("write_claude_code_document_manifest boş dosya listesinde uyarı satırı yazar", {
  hedef <- tempfile(fileext = ".md")
  on.exit(unlink(hedef), add = TRUE)
  .ccd_env$write_claude_code_document_manifest(hedef, list(), orijinal_prompt = "x")
  content <- .ccd_read_bytes(hedef)
  expect_true(grepl("Hazir metin", content, fixed = TRUE) ||
                grepl("metin", content, fixed = TRUE))
})
