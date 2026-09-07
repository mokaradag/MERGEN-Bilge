# ==============================================================================
# Dosya Yolu: tests/testthat/test-review-round-hardening-behavior.R
# Açıklama: Son inceleme turunda kapatılan bulguların DAVRANIŞ sözleşmesi.
#           Her blok, düzeltilen kusurun gerçek tetikleyicisini kurar ve
#           düzeltmenin yerinde kaldığını doğrular.
#
#           Kapsam: güvenli yol bileşeni kuralları (Windows geçersiz/ayrılmış
#           ad, kontrol karakteri), oturum temizliği tekilleştirme, kanonik
#           kimlik taşması, sohbet başlığı çok baytlı koruma, SSE olay
#           sonlandırıcısı, MCP tanımlayıcı tırnağı + SQL yorumu, vision
#           uzantı kapısı, dosya alım hattı reddetme durumu ve MCP taban
#           önek denetimi.
#
#           Çevrimdışı ve deterministiktir: DB, LLM, ağ, tarayıcı, SSO sunucusu
#           veya gerçek Shiny oturumu GEREKMEZ.
# ==============================================================================

.reviewHardeningEnv <- function(dosyalar, stub_fn = NULL) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  if (is.function(stub_fn)) stub_fn(env)
  kok <- resolve_repo_root_for_tests()
  for (dosya in dosyalar) {
    source(file.path(kok, dosya), encoding = "UTF-8", local = env)
  }
  env
}

# ------------------------------------------------------------------------------
# safe_join_path: Windows'ta geçersiz ad karakterleri, ayrılmış aygıt adları ve
# kontrol karakterleri. Denetim PLATFORMDAN BAĞIMSIZDIR: üretim Windows/UNC
# üzerinde çalışır ve kararın tek biçimli kalması testlerin iki platformda da
# aynı sonucu vermesini sağlar.
# ------------------------------------------------------------------------------
test_that("safe_join_path Windows geçersiz karakter ve ayrılmış adları reddeder", {
  env <- .reviewHardeningEnv("R/utils_safe_path.R")
  taban <- withr::local_tempdir()

  # Windows'ta ada giremeyen karakterler
  for (seg in c("rapor?.txt", "foo:bar", "a<b.txt", "a>b.txt",
                "a|b.txt", "a*b.txt", "a\"b.txt")) {
    expect_null(env$safe_join_path(taban, seg),
                info = sprintf("geçersiz karakter reddedilmeli: %s", seg))
  }

  # Ayrılmış aygıt adları (uzantılı biçimleri de aynı aygıta çözülür)
  for (seg in c("CON", "con.txt", "NUL.txt", "PRN", "AUX", "COM1", "lpt9.log",
                "alt/CON.txt")) {
    expect_null(env$safe_join_path(taban, seg),
                info = sprintf("ayrılmış ad reddedilmeli: %s", seg))
  }

  # Kontrol karakterleri (sekme / satır sonu)
  expect_null(env$safe_join_path(taban, "rapor\tson.txt"))
  expect_null(env$safe_join_path(taban, "rapor\nson.txt"))

  # Normal ve TÜRKÇE adlar etkilenmez
  expect_true(nzchar(env$safe_join_path(taban, "rapor.txt") %||% ""))
  expect_true(nzchar(env$safe_join_path(taban, "İstanbul/Özet-Çalışma.docx") %||% ""))
  # `CONSOLE` ayrılmış DEĞİLDİR; yalnızca tam gövde eşleşmesi reddedilir.
  expect_true(nzchar(env$safe_join_path(taban, "CONSOLE.txt") %||% ""))
})

# ------------------------------------------------------------------------------
# register_session_cleanup_on_end: AYNI ÇAĞRIDA yinelenen fonksiyon
# ------------------------------------------------------------------------------
test_that("oturum temizliği aynı çağrıdaki yinelenen fonksiyonu bir kez kaydeder", {
  env <- .reviewHardeningEnv("R/utils_session_cleanup.R")

  sayac <- 0L
  temizlik <- function() sayac <<- sayac + 1L

  kayitli <- NULL
  session <- list(
    token = "t1",
    userData = new.env(parent = emptyenv()),
    onSessionEnded = function(fn) {
      kayitli <<- fn
      invisible(TRUE)
    }
  )

  # Aynı fonksiyon İKİ KEZ verilir: defter yalnızca BİR kopya taşımalıdır.
  env$register_session_cleanup_on_end(session, extra_cleanup = list(temizlik, temizlik))
  expect_length(session$userData$mergen_session_cleanup_extra, 1L)

  kayitli()
  expect_identical(sayac, 1L)
})

# ------------------------------------------------------------------------------
# .normalize_user_session_id yedek yolu: tam sayı taşması
# ------------------------------------------------------------------------------
test_that("kimlik yedek yolu integer.max üstü değeri reddeder (hata fırlatmaz)", {
  env <- .reviewHardeningEnv("R/helpers_user_session_identity.R")
  # Kanonik doğrulayıcı YOK: yedek yol çalışır.
  expect_false(exists("mergen_canonical_user_id", envir = env, inherits = FALSE))

  expect_identical(env$.normalize_user_session_id(2147483648), 0L)
  expect_identical(env$.normalize_user_session_id("2147483648"), 0L)
  # Geçerli kimlik etkilenmez.
  expect_identical(env$.normalize_user_session_id(42), 42L)
  # Kayıplı dönüşüm yine reddedilir.
  expect_identical(env$.normalize_user_session_id(1.9), 0L)
})

# ------------------------------------------------------------------------------
# validate_chat_title: geçersiz çok baytlı başlık hata FIRLATMAZ, REDDEDİLİR
# ------------------------------------------------------------------------------
test_that("validate_chat_title geçersiz çok baytlı başlıkta çökmez", {
  env <- .reviewHardeningEnv("R/helpers_db_validation.R")

  bozuk <- rawToChar(as.raw(c(0x41, 0xFF, 0xFE, 0x42)))
  Encoding(bozuk) <- "UTF-8"

  # Uzunluk denetimi bayt uzunluğuna düşer; "invalid multibyte string" ATILMAZ.
  expect_true(isTRUE(env$validate_chat_title(bozuk)))

  # Uzun bozuk başlık uzunluk gerekçesiyle REDDEDİLİR (kesinti değil).
  uzun_bozuk <- paste0(strrep("a", 220), bozuk)
  expect_error(env$validate_chat_title(uzun_bozuk), "200", fixed = TRUE)

  # Geçerli Türkçe başlık kabul edilir.
  expect_true(isTRUE(env$validate_chat_title("Türkçe Söyleşi Başlığı")))
  # SQL deseni yine reddedilir.
  expect_error(env$validate_chat_title("a'; DROP TABLE x"), "invalid SQL")
})

# ------------------------------------------------------------------------------
# SSE olay sonlandırıcısı: fallback okuması boş ayırıcı satırı KORUR
# ------------------------------------------------------------------------------
test_that("akış fallback'i SSE olay sonlandırıcısını korur", {
  env <- .reviewHardeningEnv("R/helpers_streaming_io.R")

  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)
  con <- file(tmp, open = "wb")
  writeBin(charToRaw("data: birinci\n\ndata: ikinci\n\n"), con)
  close(con)

  sonuc <- env$.mergen_stream_read_full_fallback(
    tmp, env$mergen_stream_read_state_new()
  )

  # Olay sınırı (boş satır) KORUNUR: iki olay arasında boş ayırıcı görünmelidir.
  expect_true("" %in% sonuc$lines)
  expect_identical(sonuc$lines[1], "data: birinci")
  expect_identical(sonuc$lines[2], "")
  expect_identical(sonuc$lines[3], "data: ikinci")
  # Son ayraçtan SONRAKİ boş parça yine atılır (fazla boş satır üretilmez).
  expect_length(sonuc$lines, 4L)
})

# ------------------------------------------------------------------------------
# MCP grafik filtresi: SQL yorumu tırnak durumunu BOZMAZ
# ------------------------------------------------------------------------------
test_that("tanımlayıcı tırnağı normalleştirmesi SQL yorumlarını izler", {
  env <- .reviewHardeningEnv(
    "R/helpers_mcp_chart_tools.R",
    stub_fn = function(e) {
      e$helpers_mcp_tools <- new.env(parent = emptyenv())
      assign("helpers_mcp_tools", e$helpers_mcp_tools, envir = globalenv())
    }
  )
  on.exit(
    suppressWarnings(rm("helpers_mcp_tools", envir = globalenv())),
    add = TRUE
  )
  normalize <- env$.mcp_chart_identifier_quotes

  # Satır yorumundaki kesme işareti tek tırnak durumunu ters çevirip sonraki
  # satırdaki `[status]` dönüşümünü engelliyordu.
  expect_identical(
    normalize("x > 0 -- user's note\nAND [status] = 'ok'"),
    "x > 0 -- user's note\nAND \"status\" = 'ok'"
  )
  # Blok yorumu için aynı kural.
  expect_identical(
    normalize("/* it's a block */ [a] = 1"),
    "/* it's a block */ \"a\" = 1"
  )
  # Dize değişmezinin içindeki `--` yorum BAŞLATMAZ.
  expect_identical(
    normalize("a = 'x -- y' AND [b] = 2"),
    "a = 'x -- y' AND \"b\" = 2"
  )
  # Köşeli parantezli ADIN içindeki `--` yorum sanılmaz.
  expect_identical(normalize("[a--b] = 1"), "\"a--b\" = 1")

  # KAÇIRILMIŞ KAPANIŞ İŞARETİ: T-SQL `]]` ve MySQL çift ters tırnak,
  # tanımlayıcı İÇİNDEKİ tek bir literal karakteri gösterir. Tarayıcı ilk
  # işareti kapanış sayıyor, `[a]]b]` (yani `a]b` sütunu) `"a""b"` oluyor ve
  # DuckDB ya BAŞKA bir tanımlayıcı sorguluyor ya da sorguyu reddediyordu.
  expect_identical(normalize("[a]]b] = 1"), "\"a]b\" = 1")
  expect_identical(normalize("`a``b` = 2"), "\"a`b\" = 2")
  # Tanımlayıcı içindeki ÇİFT TIRNAK DuckDB tanımlayıcısında `""` olarak
  # KAÇIRILMALIDIR; aksi hâlde `[a"b]` girdisi GEÇERSİZ SQL üretiyordu.
  expect_identical(normalize("[a\"b] = 4"), "\"a\"\"b\" = 4")
  # Dize değişmezindeki köşeli parantez hâlâ DOKUNULMAZ kalır.
  expect_identical(
    normalize("col LIKE '%[Rev 2]%'"),
    "col LIKE '%[Rev 2]%'"
  )
})

# ------------------------------------------------------------------------------
# Vision: OpenAI image-input sözleşmesinin kabul etmediği uzantılar
# ------------------------------------------------------------------------------
test_that("vision kodlaması bmp/svg için data-url üretmez", {
  env <- .reviewHardeningEnv("R/helpers_vision_context.R")

  expect_true(env$mergen_vision_is_encodable_image("a.png"))
  expect_true(env$mergen_vision_is_encodable_image("a.JPEG"))
  expect_true(env$mergen_vision_is_encodable_image("a.webp"))
  expect_true(env$mergen_vision_is_encodable_image("a.gif"))
  expect_false(env$mergen_vision_is_encodable_image("a.bmp"))
  expect_false(env$mergen_vision_is_encodable_image("a.svg"))

  # Dosya gerçekten var olsa bile data-url ÜRETİLMEZ.
  dizin <- withr::local_tempdir()
  for (uzanti in c("bmp", "svg")) {
    yol <- file.path(dizin, paste0("gorsel.", uzanti))
    writeBin(as.raw(c(0x01, 0x02, 0x03, 0x04)), yol)
    expect_null(env$mergen_build_image_data_url(yol),
                info = sprintf("%s data-url üretmemeli", uzanti))
  }

  # PNG normal yoldan kodlanır (regresyon koruması).
  png_yol <- file.path(dizin, "gorsel.png")
  writeBin(as.raw(c(0x89, 0x50, 0x4E, 0x47)), png_yol)
  du <- env$mergen_build_image_data_url(png_yol)
  expect_true(is.character(du) && startsWith(du, "data:image/png;base64,"))
})

# ------------------------------------------------------------------------------
# Dosya alım hattı: reddetme durumu ve kanonik kimlik seçimi
# ------------------------------------------------------------------------------
test_that("dosya alım hattı reddetmeyi AÇIK durumla bildirir", {
  env <- .reviewHardeningEnv("R/helpers_file_pipeline.R")

  kabul <- env$.file_pipeline_status(env$MERGEN_FILE_PIPELINE_ACCEPTED)
  red <- env$.file_pipeline_status(env$MERGEN_FILE_PIPELINE_REJECTED, "kimlik")

  expect_true(env$mergen_file_pipeline_accepted(kabul))
  expect_false(env$mergen_file_pipeline_accepted(red))
  expect_identical(red$reason, "kimlik")
  # Eski çağıranlar `NULL` alıyordu; geriye dönük uyumlulukta REDDETME sayılır.
  expect_false(env$mergen_file_pipeline_accepted(NULL))
})

test_that("etkin kimlik seçimi oturumdaki 0L değerini çağıranın kimliğiyle aşar", {
  env <- .reviewHardeningEnv("R/helpers_file_pipeline.R")

  # Oturum kimliği hâlâ yer tutucu: çağıranın ÇÖZÜMLENMİŞ kimliği kullanılır.
  expect_identical(env$.file_pipeline_effective_uid(0L, 42L), 42L)
  expect_identical(env$.file_pipeline_effective_uid(NULL, 42L), 42L)
  expect_identical(env$.file_pipeline_effective_uid("unknown", 42L), 42L)
  # İKİ kimlik de POZİTİF ve FARKLIYSA sonuç GEÇERSİZDİR (kapalı-başarısız IDOR
  # koruması): parti kullanıcı A için başlayıp aynı Shiny oturumu B'ye geçtikten
  # SONRA tamamlanabilir; oturum kimliğini koşulsuz tercih etmek A'nın
  # kalıcılaşmış dosyasını B'nin oturum durumuna bağlıyordu.
  expect_identical(env$.file_pipeline_effective_uid(7L, 42L), 0L)
  # Kimlikler EŞLEŞİYORSA oturum kimliği kullanılır.
  expect_identical(env$.file_pipeline_effective_uid(7L, 7L), 7L)
  # Çağıran kimliği yoksa oturum kimliği tek kaynaktır.
  expect_identical(env$.file_pipeline_effective_uid(7L, NULL), 7L)
  expect_identical(env$.file_pipeline_effective_uid(7L, 0L), 7L)
  # İkisi de geçersizse 0L döner (kapalı-başarısız).
  expect_identical(env$.file_pipeline_effective_uid(0L, NULL), 0L)
  # Kayıplı dönüşüm kabul edilmez.
  expect_identical(env$.file_pipeline_effective_uid(1.9, 0L), 0L)
})

# ------------------------------------------------------------------------------
# is_under_mcp_base: hızlı yol KÖK önekini de doğrular
# ------------------------------------------------------------------------------
test_that("is_under_mcp_base hızlı yolu farklı kökü kabul etmez", {
  env <- .reviewHardeningEnv(c("R/utils_path_helpers.R", "R/helpers_files_path.R"))

  withr::local_options(mergen.mcp_base_dir = "/data/mcp")
  withr::local_envvar(c(MCP_FILES_BASE = ""))

  # Gerçek kök altındaki kullanıcı kovası kabul edilir.
  expect_true(env$is_under_mcp_base("/data/mcp/user_42/veri.xlsx"))
  # BAŞKA bir kök altındaki aynı ad yapısı REDDEDİLİR (dosya kopyalanmadan
  # "zaten kalıcı" sayılıyordu).
  expect_false(env$is_under_mcp_base("/baska/kok/mcp/user_1/dosya.txt"))
})

test_that("is_under_mcp_base mojibake bozulmuş kökü hâlâ tanır", {
  # Mojibake toleransı artık deponun TEK KAYNAKLI onarım yardımcısına dayanır
  # (kayıplı ASCII iskeleti `Şube` ile `Çube` köklerini aynı sayıyordu), bu
  # yüzden izole ortam `R/utils_text_encoding.R` dosyasını da yükler.
  env <- .reviewHardeningEnv(c(
    "R/utils_text_encoding.R", "R/utils_path_helpers.R", "R/helpers_files_path.R"
  ))

  # Taban adı ASCII, ÜST dizin Türkçe: mojibake yalnızca üst dizini bozar.
  withr::local_options(mergen.mcp_base_dir = "/rehisds/Geliştirme/mcp")
  withr::local_envvar(c(MCP_FILES_BASE = ""))

  # Mojibake fikstürü TÜMÜYLE KAÇIŞLA yazılır: U+017F (uzun s) WINDOWS-1254'te
  # KARŞILIĞI YOKTUR ve literal biçimi Windows VM'de dosyayı o baytta kesip
  # sonraki her tanımı yok ederdi (CLAUDE.md 1G). Aynı dizede kaçış ile literal
  # Türkçe KARIŞTIRILMAZ, bu yüzden `Å` de kaçışla yazılır; değer bayt-aynıdır.
  # `ş` (U+015F) UTF-8 baytları `C5 9F`; WINDOWS-1254 olarak okunduğunda
  # `Å` (U+00C5) + `Ÿ` (U+0178) olur. Fikstür bu GERÇEK mojibake çiftini
  # kullanır: onarım yardımcısı bunu çözer ve iki yol aynı köke indirgenir.
  # İkisi de CP1254'te temsil edilebilir (CLAUDE.md 1G); kaçış biçimi yazılır.
  bozuk <- "/rehisds/Geli\u00C5\u0178tirme/mcp/user_42/x.xlsx"
  expect_true(env$is_under_mcp_base(bozuk))

  # FARKLI bir Türkçe kök artık eşleşmez: kayıplı iskelet bunu aynı sayıyordu.
  farkli <- "/rehisds/Geli\u00E7tirme/mcp/user_42/x.xlsx"
  expect_false(env$is_under_mcp_base(farkli))
})

# ------------------------------------------------------------------------------
# Dosya sistemi fallback listelemesi YÜKLEME ARA ÜRÜNLERİNİ göstermez
# ------------------------------------------------------------------------------
test_that("gevşek listeleme .mergen-part ve rezervasyon adlarını ayıklar", {
  env <- .reviewHardeningEnv("R/config_file_store_listing_helpers.R")

  kova <- withr::local_tempdir()
  writeLines("veri", file.path(kova, "rapor.xlsx"))
  # Terfi sonrası Windows/UNC kilidinde silinemeyen aşamalı kopya.
  writeLines("yarim", file.path(kova, "rapor.xlsx.mergen-part"))
  writeLines("yarim", file.path(kova, "baska.pdf.mergen-part"))
  # Rezervasyon adları `dir.create()` ile üretilen DİZİNLERDİR; listeleme
  # API'lerinin kendisi dizinleri dışlar (`include.dirs = FALSE` /
  # `fs::dir_ls(type = "file")`). Üretim şekliyle DİZİN olarak kurulur.
  dir.create(file.path(kova, "index.json.aw-rsv"))
  dir.create(file.path(kova, "kopya.docx.oo-rsv"))
  dir.create(file.path(kova, "rapor.xlsx.mergen-rsv"))

  sonuc <- env$.file_store_list_user_files_relaxed(kova)
  expect_identical(basename(sonuc), "rapor.xlsx")
})

test_that("rezervasyon soneki taşıyan GEÇERLİ dosya listelemede kalır", {
  env <- .reviewHardeningEnv("R/config_file_store_listing_helpers.R")

  kova <- withr::local_tempdir()
  # Rezervasyon sonekleri yalnızca DİZİNLERE aittir; aynı sonekle adlandırılmış
  # gerçek bir dosya kullanıcının dosyasıdır ve düşürülmemelidir.
  writeLines("veri", file.path(kova, "rapor.oo-rsv"))

  sonuc <- env$.file_store_list_user_files_relaxed(kova)
  expect_identical(basename(sonuc), "rapor.oo-rsv")
})

test_that("yalnızca ara ürün içeren klasör BOŞ listelenir", {
  env <- .reviewHardeningEnv("R/config_file_store_listing_helpers.R")

  kova <- withr::local_tempdir()
  writeLines("yarim", file.path(kova, "rapor.xlsx.mergen-part"))

  # Ayıklama listeleme BAŞARISI denetiminden ÖNCE yapılır; aksi hâlde klasör
  # "dosya var" sayılıp yarım dosya geçerli bir yükleme gibi dönüyordu.
  expect_identical(env$.file_store_list_user_files_relaxed(kova), character(0))
})

test_that("ara ürün soneki listesi merkezî sabitlerden türetilir", {
  env <- .reviewHardeningEnv(c(
    "R/utils_path_reservation.R",
    "R/helpers_files_promote_probe.R",
    "R/helpers_files_promote_target.R",
    "R/helpers_files_staging_copy.R",
    "R/helpers_files_copy_promote.R",
    "R/config_file_store_listing_helpers.R"
  ))

  sonekler <- env$.file_store_artifact_suffixes()
  expect_true(env$MERGEN_UPLOAD_STAGING_SUFFIX %in% sonekler)
  # REZERVASYON sonekleri DOSYA filtresinde YER ALMAZ: yalnızca dizinlere
  # aittir ve dizinler listelemede ayrıca ayıklanır. Sonek filtresine alınmaları
  # aynı sonekli GEÇERLİ bir dosyayı düşürüyordu.
  expect_false(env$MERGEN_PROMOTE_RESERVATION_SUFFIX %in% sonekler)

  # Geçersiz yapılandırma (NA / boş) varsayılana düşer, `NA` sonek üretmez.
  env$MERGEN_UPLOAD_STAGING_SUFFIX <- NA_character_
  expect_identical(env$.file_store_artifact_suffixes(), ".mergen-part")
  env$MERGEN_UPLOAD_STAGING_SUFFIX <- character(0)
  expect_identical(env$.file_store_artifact_suffixes(), ".mergen-part")
})

# ------------------------------------------------------------------------------
# Shiny boot smoke gövde taraması BAYT GÜVENLİDİR
# ------------------------------------------------------------------------------
test_that("kesilmiş UTF-8 gövdesinde ASCII çapa hâlâ bulunur", {
  # 256 KB okuma sınırı çok baytlı bir diziyi ORTADAN kesebilir. `enc2utf8()`
  # baytları UTF-8 olarak İŞARETLER ama GEÇERLİ kılmaz; geniş karakter çevirisi
  # başarısız olur ve sağlıklı bir sayfa "boot smoke failed" sayılırdı.
  #
  # FİKSTÜR DETERMİNİSTİK KURULUR: bu test BAYT UZUNLUĞUNA dayanır ve Windows'ta
  # test dosyası yerel kod sayfasıyla ayrıştırıldığı için literal bir Türkçe
  # karakter TEK bayt olabilir (CP1254'te `ş` = 0xFE). `intToUtf8()` her iki
  # platformda da iki baytlık (0xC5 0x9F) dizi üretir.
  cok_baytli <- intToUtf8(as.integer(0x015F))
  expect_identical(length(charToRaw(cok_baytli)), 2L)

  govde <- paste0(
    "<!DOCTYPE html>\n<html><head><title>MERGEN Bilge</title></head><body>",
    strrep(paste0("icerik ", cok_baytli, " "), 50), cok_baytli
  )
  ham <- charToRaw(govde)
  # Son baytı düşürmek kapanış dizisini tam ortasından keser.
  kesik <- rawToChar(ham[seq_len(length(ham) - 1L)])
  expect_false(validUTF8(kesik))

  # Bayt güvenli normalleştirme + BAYT taraması: çapa hâlâ bulunur.
  # (`enc2utf8()` sonucu YEREL BAĞIMLIDIR — yerel kod sayfası baytları geçerli
  # sayabilir — bu yüzden eski yolun çıktısı burada iddia edilmez.)
  normalize <- iconv(kesik, from = "UTF-8", to = "UTF-8", sub = "?")
  expect_true(validUTF8(normalize))
  expect_true(grepl("<!DOCTYPE", normalize, ignore.case = TRUE, useBytes = TRUE))
})
