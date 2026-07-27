# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-workdir-scan-behavior.R
# Açıklama: R/helpers_claude_code_workdir_scan.R saf yardımcılarının DAVRANIŞSAL
#           testleri. Bu fonksiyonlar mevcut testlerde HİÇ çağrılmıyordu:
#             - prompt_requests_binary_document_creation (üretim niyeti tespiti)
#             - prompt_requests_existing_document_reading (okuma/özet niyeti)
#             - canonicalize_claude_code_file_path (yol kanonikleştirme)
#             - deduplicate_claude_code_file_paths (büyük/küçük harf duyarsız tekille)
#           Saf base R; ağ/DB/Shiny/CLI GEREKMEZ. Yol testleri yalnızca yerel
#           geçici dizin/dosya kullanır (sentetik fixture).
# ==============================================================================

.ccscan_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("prompt_requests_binary_document_creation",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_workdir_scan.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# prompt_requests_binary_document_creation / prompt_requests_existing_document_reading
#
# DİKKAT (mevcut davranış karakterizasyonu): Bu iki fonksiyonun boş-olmayan
# prompt eşleştirme mantığı, üretim kaynağında perl=TRUE deseni içine yazılmış
# literal "\\u00f6" / "\\u015f" gibi çift-ters-bölü Unicode kaçışları yüzünden
# PCRE2 ile UYUMSUZDUR (PCRE2 "\u" desteklemez). Bu yüzden boş-olmayan bir
# prompt ile çağrı, grepl(perl=TRUE) tarafında önce UYARI sonra HATA üretir.
# Çağıranlar bunu tryCatch(error=FALSE) ile sarmaladığından üretimde niyet
# tespiti sessizce FALSE'a düşer (degrade). Strict runner stop_on_warning=TRUE
# olduğundan, bu testler yalnızca grepl'e ULAŞMAYAN, doğru çalışan erken-çıkış
# (boş/NULL) yolunu doğrular. Eşleştirme mantığı, kaynak düzeltilene kadar
# bilinçli olarak burada doğrulanmaz (bkz. nihai rapor / olası hata kaydı).
# ------------------------------------------------------------------------------
testthat::test_that("prompt_requests_binary_document_creation boş/NULL girdide güvenli FALSE döner", {
  .ccscan_source_once()
  # Erken-çıkış (!nzchar) grepl'den önce gerçekleşir; uyarı/hata üretmez.
  testthat::expect_false(prompt_requests_binary_document_creation(""))
  testthat::expect_false(prompt_requests_binary_document_creation(NULL))
})

testthat::test_that("prompt_requests_existing_document_reading boş/NULL girdide güvenli FALSE döner", {
  .ccscan_source_once()
  testthat::expect_false(prompt_requests_existing_document_reading(""))
  testthat::expect_false(prompt_requests_existing_document_reading(NULL))
})

# ------------------------------------------------------------------------------
# NİYET TESPİTİ EŞLEŞTİRME MANTIĞI
#
# REGRESYON: Desenler perl = TRUE içinde ÇİFT ters-bölülü ("\\u00f6") Unicode
# kaçışlarıyla yazılmıştı. PCRE2 "\u" desteklemez, bu yüzden BOŞ OLMAYAN her
# prompt için grepl() önce uyarı sonra hata üretiyordu. Çağıranlar bunu
# tryCatch(error = FALSE) ile sardığı için niyet tespiti ÜRETİMDE SESSİZCE
# her zaman FALSE'a düşüyordu.
#
# Sonucu Bilge Yolaç'ta görünürdü: doküman görevi hiç algılanmadığı için metin
# çıkarımı çalışmıyor, CLI çalışma dizini izole runtime kökü olarak kalıyor ve
# ajan input/ altındaki HAM PDF'i kendi Read aracıyla okuyordu. Claude CLI
# PDF okumasını base64 bir `document` içerik bloğuna çeviriyor; on-prem
# Anthropic-uyumlu proxy bu blok tipini kabul etmediği için istek
# "Input should be 'text', 'image', 'tool_use', ..." diyerek 400 dönüyordu.
#
# Desenler tek ters-bölülü ("ö") gerçek Unicode kaçışlarına çevrildi:
# kaynak ASCII kalır, R parse anında gerçek karakteri üretir ve PCRE2 sorunu
# ortadan kalkar.
# ------------------------------------------------------------------------------

testthat::test_that("niyet tespiti desenleri uyarı/hata üretmeden derlenir", {
  .ccscan_source_once()

  # Uyarı da hata da olmamalı: strict runner stop_on_warning = TRUE ile çalışır.
  testthat::expect_no_warning(prompt_requests_existing_document_reading("test"))
  testthat::expect_no_warning(prompt_requests_binary_document_creation("test"))
  testthat::expect_no_error(prompt_requests_existing_document_reading("test"))
  testthat::expect_no_error(prompt_requests_binary_document_creation("test"))
})

testthat::test_that("okuma niyeti Türkçe ve ASCII yazımda tespit edilir", {
  .ccscan_source_once()

  # Konsol/parser bağımsızlığı için Türkçe fixture kod noktalarından kurulur.
  ozetle_tr <- paste0(
    "dizindeki dosyalar", intToUtf8(0x0131), " ", intToUtf8(0x00F6), "zetle"
  )

  testthat::expect_true(prompt_requests_existing_document_reading(ozetle_tr))
  testthat::expect_true(prompt_requests_existing_document_reading("dizindeki dosyalari ozetle"))
  testthat::expect_true(prompt_requests_existing_document_reading("bu dosyayi incele"))
  testthat::expect_true(prompt_requests_existing_document_reading("summarize the pdf"))

  # Okuma niyeti olmayan prompt FALSE kalmalıdır.
  testthat::expect_false(prompt_requests_existing_document_reading("merhaba"))
})

testthat::test_that("üretme niyeti ikili doküman uzantısıyla birlikte tespit edilir", {
  .ccscan_source_once()

  olustur_tr <- paste0("bir word belgesi olu", intToUtf8(0x015F), "tur")

  testthat::expect_true(prompt_requests_binary_document_creation(olustur_tr))
  testthat::expect_true(prompt_requests_binary_document_creation("create a docx report"))

  # Üretme fiili var ama ikili doküman hedefi yok -> FALSE.
  testthat::expect_false(prompt_requests_binary_document_creation("bir fonksiyon olustur"))
  testthat::expect_false(prompt_requests_binary_document_creation("merhaba"))
})

# ------------------------------------------------------------------------------
# canonicalize_claude_code_file_path
# ------------------------------------------------------------------------------
testthat::test_that("canonicalize_claude_code_file_path boş girdi için boş dize döndürür", {
  .ccscan_source_once()
  testthat::expect_identical(canonicalize_claude_code_file_path(""), "")
  testthat::expect_identical(canonicalize_claude_code_file_path(NULL), "")
})

testthat::test_that("canonicalize_claude_code_file_path mevcut dosyayı kanonik mutlak yola çevirir", {
  .ccscan_source_once()
  tmp <- tempfile(fileext = ".txt")
  writeLines("icerik", tmp)
  on.exit(unlink(tmp), add = TRUE)

  beklenen <- normalizePath(tmp, winslash = "/", mustWork = TRUE)
  testthat::expect_identical(canonicalize_claude_code_file_path(tmp), beklenen)
  # İleri eğik çizgi kullanılır (Windows uyumluluğu).
  testthat::expect_false(grepl("\\\\", canonicalize_claude_code_file_path(tmp)))
})

testthat::test_that("canonicalize_claude_code_file_path vektör girdide yalnızca ilk öğeyi kullanır", {
  .ccscan_source_once()
  f1 <- tempfile(fileext = ".txt"); writeLines("a", f1)
  f2 <- tempfile(fileext = ".txt"); writeLines("b", f2)
  on.exit(unlink(c(f1, f2)), add = TRUE)

  testthat::expect_identical(
    canonicalize_claude_code_file_path(c(f1, f2)),
    canonicalize_claude_code_file_path(f1)
  )
})

# ------------------------------------------------------------------------------
# deduplicate_claude_code_file_paths
# ------------------------------------------------------------------------------
testthat::test_that("deduplicate_claude_code_file_paths boş/NULL girdide character(0) döndürür", {
  .ccscan_source_once()
  testthat::expect_identical(deduplicate_claude_code_file_paths(NULL), character(0))
  testthat::expect_identical(deduplicate_claude_code_file_paths(character(0)), character(0))
  testthat::expect_identical(deduplicate_claude_code_file_paths(c("", "")), character(0))
})

testthat::test_that("deduplicate_claude_code_file_paths aynı dosyayı ve boşları tekille", {
  .ccscan_source_once()
  f1 <- tempfile(fileext = ".txt"); writeLines("a", f1)
  on.exit(unlink(f1), add = TRUE)

  donen <- deduplicate_claude_code_file_paths(c(f1, f1, ""))
  testthat::expect_length(donen, 1L)
  testthat::expect_identical(donen, canonicalize_claude_code_file_path(f1))
})

testthat::test_that("deduplicate_claude_code_file_paths harf büyüklüğünü platforma göre ele alır", {
  .ccscan_source_once()
  # Var olan kanonik bir taban dizin altında, yalnızca harf büyüklüğüyle ayrışan
  # iki var-olmayan yol; canonicalize üst dizin mevcut olduğu için yolu olduğu
  # gibi döndürür.
  #
  # SÖZLEŞME: tekilleştirme PLATFORMA DUYARLIDIR. Windows'ta dosya sistemi harf
  # büyüklüğünü yok saydığı için iki yol aynı dosyadır ve katlanır. Unix'te
  # "Rapor.TXT" ile "rapor.txt" GERÇEKTEN farklı iki dosyadır; koşulsuz
  # tolower() ile katlamak üretilen bir çıktı dosyasını sessizce düşürürdü
  # (indirme kartı/çıktı senkronizasyonu kaybı). Bu davranış PR #672 Codex
  # sertleştirmesiyle düzeltildi; sertleştirme dosyaları manifest dışı
  # kaldığı sürece ölü kod olduğu için bu ayrım fark edilmiyordu.
  base <- normalizePath(tempfile(pattern = "ccdedup"), winslash = "/", mustWork = FALSE)
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(base, recursive = TRUE), add = TRUE)

  p_upper <- paste0(base, "/Rapor.TXT")
  p_lower <- paste0(base, "/rapor.txt")

  donen <- deduplicate_claude_code_file_paths(c(p_upper, p_lower))

  if (identical(.Platform$OS.type, "windows")) {
    testthat::expect_length(donen, 1L)
    # İlk görünüm (büyük harfli) korunur.
    testthat::expect_identical(donen, canonicalize_claude_code_file_path(p_upper))
  } else {
    testthat::expect_length(donen, 2L)
    testthat::expect_identical(
      donen,
      c(
        canonicalize_claude_code_file_path(p_upper),
        canonicalize_claude_code_file_path(p_lower)
      )
    )
  }

  # Gerçekten aynı olan yol her platformda tekilleştirilir.
  testthat::expect_length(
    deduplicate_claude_code_file_paths(c(p_upper, p_upper)),
    1L
  )
})
