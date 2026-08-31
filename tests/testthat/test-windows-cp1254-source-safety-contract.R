# ==============================================================================
# Dosya Yolu: tests/testthat/test-windows-cp1254-source-safety-contract.R
# Açıklama: R kaynak dosyalarının Windows VM (Türkçe yerel, WINDOWS-1254 kod
#           sayfası) üzerinde `source(..., encoding = "UTF-8")` ile SESSİZCE
#           BOZULMADAN okunabildiğini garanti eder.
#
#           NEDEN: Windows VM'de R'nin yerel kodlaması WINDOWS-1254'tür.
#           `source(dosya, encoding = "UTF-8")` içeriği yerel kodlamaya çevirir.
#           WINDOWS-1254'te KARŞILIĞI OLMAYAN bir karakter (ör. lira işareti
#           U+20BA, kesişim U+2229, sağ ok U+2192, birleştirici işaretler,
#           emoji) çeviriyi
#           bozar: R "giriş bağlantısında geçersiz giriş bulundu" uyarısı verir
#           ve dosyayı O NOKTADA KESER. Kesilen dosya "unexpected end of input"
#           ile ayrıştırılamaz; sonrasındaki tüm fonksiyonlar tanımsız kalır ve
#           testler yüzlerce ardıl hata üretir.
#
#           Bu, Türkçe metin bütünlüğü kuralının KARŞITI DEĞİLDİR: ç ğ ı İ ö ş ü
#           gibi Türkçe karakterlerin TAMAMI WINDOWS-1254'te temsil edilir ve
#           serbestçe kullanılmaya devam eder. Yalnızca temsil EDİLEMEYEN
#           karakterler yasaktır; bunlar dizelerde `"\uXXXX"` kaçışıyla (değer
#           bayt düzeyinde AYNI kalır) ya da yorumlarda ASCII karşılığıyla
#           yazılmalıdır.
#
#           Test çevrimdışı ve deterministiktir: DB, LLM, tarayıcı, ağ yoktur.
# ==============================================================================

# DEPO TARAMALARI YALNIZCA İZLENEN DOSYALARA BAKAR (PR #705 incelemesi, P2).
#
# `list.files()` çalışma kopyasındaki HER `.R` dosyasını görür; operatörün
# Windows VM'de bıraktığı izlenmeyen deneme betikleri (`tools/debug.R` gibi)
# uygulama tarafından `source()` EDİLMEZ ve bu sözleşmenin konusu DEĞİLDİR,
# ama emoji içerirlerse tüm paketi kırmıştı. Kök dizin için ZATEN kapalı bir
# izin listesi vardı; özyinelemeli taramalar için de aynı sınır uygulanır.
#
# `git` yoksa ya da dizin bir depo değilse (dışa aktarılmış arşiv) davranış
# ESKİSİ GİBİ kalır: filtre UYGULANMAZ, yani daha AZ değil daha ÇOK dosya
# taranır. Sözleşme hiçbir durumda sessizce devre dışı kalmaz.
.cp1254_izlenen_dosyalar <- function(kok) {
  # `-z` KULLANILMAZ: NUL ayırıcı bir R karakter dizesinde taşınamaz. Satır
  # tabanlı çıktı yeterlidir. `core.quotepath=false` Türkçe adların kaçışsız
  # (ham UTF-8) gelmesini sağlar; aksi hâlde yollar eşleşmezdi.
  cikti <- tryCatch(
    suppressWarnings(system2(
      # PATHSPEC'LER DE `shQuote()` EDİLİR: `system2()` Unix'te komutu KABUK
      # üzerinden çalıştırır, tırnaksız `*.R` YEREL DİZİNDE glob olarak
      # genişler ve git yalnızca kökteki birkaç dosyayı görürdü.
      "git", c("-C", shQuote(kok), "-c", "core.quotepath=false",
               "ls-files", "--", shQuote("*.R"), shQuote("*.r")),
      stdout = TRUE, stderr = FALSE
    )),
    error = function(e) NULL
  )
  if (is.null(cikti) || !length(cikti) || !is.null(attr(cikti, "status"))) return(NULL)

  yollar <- enc2utf8(cikti[nzchar(cikti)])
  if (!length(yollar)) return(NULL)
  normalizePath(file.path(kok, yollar), winslash = "/", mustWork = FALSE)
}

.cp1254_izlenene_indirge <- function(dosyalar, kok) {
  izlenen <- .cp1254_izlenen_dosyalar(kok)
  if (is.null(izlenen)) return(dosyalar)
  dosyalar[normalizePath(dosyalar, winslash = "/", mustWork = FALSE) %in% izlenen]
}

testthat::test_that("R kaynak dosyaları WINDOWS-1254 yerelinde bozulmadan okunabilir", {
  # Repo kökü çözümü, repo genelindeki test sözleşmesiyle aynıdır
  # (bkz. tests/testthat/helper_bootstrap.R); ek paket bağımlılığı yoktur.
  kok <- if (exists("repo_root_for_tests", inherits = TRUE)) {
    get("repo_root_for_tests", inherits = TRUE)
  } else {
    aday <- c(".", "..", "../..")
    uygun <- aday[vapply(
      aday,
      function(p) file.exists(file.path(p, "app.R")) && dir.exists(file.path(p, "R")),
      logical(1)
    )]
    testthat::skip_if(length(uygun) == 0L, "Repo kökü bulunamadı")
    normalizePath(uygun[1], winslash = "/", mustWork = TRUE)
  }

  dizinler <- file.path(kok, c("R", "tests/testthat", "tests/scripts", "tools"))
  dizinler <- dizinler[dir.exists(dizinler)]

  dosyalar <- unlist(lapply(
    dizinler,
    function(d) list.files(d, pattern = "\\.[Rr]$", full.names = TRUE, recursive = TRUE)
  ), use.names = FALSE)
  dosyalar <- .cp1254_izlenene_indirge(dosyalar, kok)

  # KÖK DİZİNDE YALNIZCA DEPOYA AİT GİRİŞ DOSYALARI taranır.
  #
  # `list.files(kok)` çalışma kopyasındaki HER `.R` dosyasını görür; Windows
  # VM'de operatörün kök dizinde tuttuğu deneme betikleri (izlenmeyen, depoya
  # ait olmayan dosyalar) de buna dâhildir. Bunlar uygulama tarafından hiç
  # `source()` edilmez, dolayısıyla bu sözleşmenin konusu DEĞİLDİR; taranırlarsa
  # depo kodu kusursuz olduğu hâlde suite kırmızıya döner. Kök dizindeki
  # çalışma zamanı dosyaları kapalı bir kümedir (seam kaydı `extra_runtime_files`
  # ile aynı sınır); yeni bir kök dosyası eklendiğinde bu liste de bilinçli
  # olarak güncellenir.
  kok_calisma_zamani <- c(
    "app.R", "global.R", "server.R", "ui.R",
    "welcome_screen.R", "run_mergen_prod.R"
  )

  # KÖK DOSYALARI İZLENEN KÜMEDEN TÜRETİLİR: sabit liste, DEPOYA EKLENMİŞ yeni
  # bir kök `.R` dosyasını taramanın DIŞINDA bırakıyordu; o dosya
  # WINDOWS-1254'e çevrilemeyen bir karakter taşısa bile sözleşme YEŞİL
  # kalırdı. İzlenen kümeden türetmek, yukarıdaki gerekçeyi (operatörün
  # İZLENMEYEN deneme betikleri taranmaz) AYNEN korur; git yoksa kapalı listeye
  # geri düşülür.
  kok_izlenen <- .cp1254_izlenen_dosyalar(kok)
  kok_dosyalar <- if (is.null(kok_izlenen)) {
    file.path(kok, kok_calisma_zamani)
  } else {
    kok_norm <- normalizePath(kok, winslash = "/", mustWork = FALSE)
    goreli <- sub(paste0("^", gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", kok_norm), "/"),
                  "", kok_izlenen)
    kok_izlenen[!grepl("/", goreli, fixed = TRUE)]
  }
  kok_dosyalar <- kok_dosyalar[file.exists(kok_dosyalar)]
  dosyalar <- unique(c(dosyalar, kok_dosyalar))

  testthat::expect_gt(length(dosyalar), 0L)

  # Her dosya BAYT olarak okunur (kesilme riski olmadan), sonra WINDOWS-1254'e
  # çevrilebilirliği sınanır. `iconv()` çevrilemeyen ögeler için NA döndürür.
  kirik <- vapply(dosyalar, function(f) {
    satirlar <- tryCatch(
      readLines(f, encoding = "UTF-8", warn = FALSE),
      error = function(e) NA_character_
    )
    # OKUNAMAYAN DOSYA "GEÇTİ" SAYILMAZ (PR #705 incelemesi, P3).
    #
    # `readLines()` hata verdiğinde `NA_character_` dönüyor ve fonksiyon
    # `NA_integer_` ile dosyayı SORUNSUZ işaretliyordu: izin hatası, kilitli
    # dosya veya bozuk bayt dizisi durumunda sözleşme dosya HİÇ denetlenmediği
    # hâlde yeşil kalırdı. `0L` "okunamadı" nöbetçisidir (satır numaraları
    # her zaman >= 1) ve aşağıda AYRI bir bulgu olarak raporlanır.
    if (length(satirlar) == 1L && is.na(satirlar[1])) return(0L)
    # BOM İLK SATIRDA KALABİLİR.
    #
    # `readLines(encoding = "UTF-8")` yalnızca kodlamayı ETİKETLER; BOM'u
    # ayıklamaz. U+FEFF'in CP1254 karşılığı YOKTUR, dolayısıyla BOM'lu ama
    # tamamen geçerli bir kaynak dosya ilk satırında `NA` üretir ve test onu
    # HATALI olarak reddederdi.
    if (length(satirlar)) {
      satirlar[1] <- sub("^\ufeff", "", satirlar[1], useBytes = FALSE)
    }
    cevrilen <- suppressWarnings(iconv(satirlar, from = "UTF-8", to = "WINDOWS-1254"))
    kotu <- which(is.na(cevrilen) & !is.na(satirlar))
    if (length(kotu)) kotu[1] else NA_integer_
  }, integer(1))

  sorunlu <- which(!is.na(kirik))

  # Hata mesajı doğrudan eyleme dönüştürülebilir olsun: dosya + ilk kırık satır.
  ayrinti <- if (length(sorunlu)) {
    paste0(
      "\n  - ",
      vapply(names(kirik)[sorunlu], function(yol) {
        onek <- paste0(kok, "/")
        if (startsWith(yol, onek)) substring(yol, nchar(onek) + 1L) else yol
      }, character(1)),
      ifelse(kirik[sorunlu] == 0L, " (DOSYA OKUNAMADI)",
             paste0(" (satır ", kirik[sorunlu], ")")),
      collapse = ""
    )
  } else ""

  testthat::expect_identical(
    length(sorunlu), 0L,
    info = paste0(
      "Aşağıdaki R dosyaları WINDOWS-1254'e çevrilemeyen karakter içeriyor ",
      "(ya da HİÇ OKUNAMADI) ve Windows VM'de `source(..., encoding = \"UTF-8\")` ",
      "sırasında KESİLİR. Dizelerde \"\\uXXXX\" kaçışı, yorumlarda ASCII ",
      "karşılık kullanın:",
      ayrinti
    )
  )
})

# ==============================================================================
# KAÇIŞ + LİTERAL KARIŞIMI (test kaynaklarında)
# ==============================================================================
#
# NEDEN: `source(dosya, encoding = "UTF-8")` ayrıştırıcıya kaynağın UTF-8
# olduğunu BİLDİRİR; çalışma zamanı `R/` dosyaları bu yoldan yüklendiği için
# güvenlidir. Test dosyaları ise testthat tarafından bu bildirim OLMADAN
# ayrıştırılabilir. Böyle bir ayrıştırmada bir dize sabiti `\u`/`\U` kaçışı
# içeriyorsa R o sabiti UTF-8'e YÜKSELTMEK zorunda kalır ve AYNI sabitteki
# LİTERAL Türkçe baytları YEREL kodlama sanarak bir kez daha çevirir. Sonuç
# sessiz çift kodlamadır: `Veritabanı Hatası` -> `VeritabanÄ± HatasÄ±`. Emoji
# doğru görünmeye devam ettiği için kusur gözden kaçar; yalnızca Türkçe kısmı
# karşılaştıran sözleşme başarısız olur ve neden Windows VM'e özgüdür.
#
# ÇÖZÜM: kaçış ile literal Türkçe AYNI sabitte birleştirilmez; `paste0()` ile
# iki ayrı sabit olarak yazılır. Değer bayt düzeyinde AYNI kalır.
testthat::test_that("test kaynaklarında kaçış ve literal Türkçe aynı dizede birleşmez", {
  kok <- if (exists("repo_root_for_tests", inherits = TRUE)) {
    get("repo_root_for_tests", inherits = TRUE)
  } else {
    aday <- c(".", "..", "../..")
    uygun <- aday[vapply(
      aday,
      function(p) file.exists(file.path(p, "app.R")) && dir.exists(file.path(p, "R")),
      logical(1)
    )]
    testthat::skip_if(length(uygun) == 0L, "Repo kökü bulunamadı")
    normalizePath(uygun[1], winslash = "/", mustWork = TRUE)
  }

  dosyalar <- list.files(
    file.path(kok, "tests", "testthat"),
    pattern = "\\.[Rr]$", full.names = TRUE
  )
  dosyalar <- .cp1254_izlenene_indirge(dosyalar, kok)
  testthat::expect_gt(length(dosyalar), 0L)

  # DİZE SABİTLERİ R'NİN KENDİ AYRIŞTIRICISIYLA BULUNUR.
  #
  # Önceki tarama satırları düzenli ifadeyle eşliyordu ve İKİ yönde de
  # yanılıyordu: (a) satır içi yorumdaki tırnaklı metin (`x <- 1 # 'ç Türkçe'`)
  # gerçek bir dize sabiti sanılıp HATALI bulgu üretiyor, (b) ters bölü
  # eşliğini takip edemediği için sınırları yanlış kesebiliyordu. `parse()` +
  # `utils::getParseData()` R'nin KENDİ sözcük çözümleyicisidir: yalnızca
  # gerçek `STR_CONST` belirteçlerini döndürür ve yorumları hiç vermez.
  # YALNIZCA ETKIN KACIS SAYILIR: onceki desen `\\u00e7` (KACIRILMIS ters bolu
  # + duz `u00e7` metni) icindeki IKINCI ters bolueyi de kacis saniyor,
  # `gsub()` sonrasi geriye `Turkce` kaliyor ve GECERLI bir literal
  # REDDEDILIYORDU. Ters bolu sayisi TEK oldugunda kacis etkindir:
  # `(?<!\\)` onunde ters bolu olmamasini, `(?:\\\\)*` cift (kacirilmis)
  # ters bolu ciftlerini tuketmeyi saglar.
  kacis_deseni <- "(?<!\\\\)(?:\\\\\\\\)*\\\\[uU]\\{?[0-9A-Fa-f]{1,8}\\}?"

  # KARIŞIK DİZE TESPİTİ TEK YERDE: hem dosya taraması hem aşağıdaki
  # POZİTİF/NEGATİF kontrol AYNI mantığı kullanır, böylece tarama sessizce
  # etkisizleşemez.
  .karisik_dizeler <- function(satirlar) {
    ifade <- tryCatch(parse(text = satirlar, keep.source = TRUE),
                      error = function(e) NULL)
    if (is.null(ifade)) return(NA_character_)
    veri <- utils::getParseData(ifade)
    if (!is.data.frame(veri) || !nrow(veri)) return(character(0))
    dizeler <- veri[veri$token == "STR_CONST", , drop = FALSE]
    if (!nrow(dizeler)) return(character(0))
    tutulan <- character(0)
    for (j in seq_len(nrow(dizeler))) {
      dize <- dizeler$text[j]
      if (!grepl(kacis_deseni, dize, perl = TRUE)) next
      kalan <- gsub(kacis_deseni, "", dize, perl = TRUE)
      if (grepl("[^\001-\177]", kalan, perl = TRUE)) {
        tutulan <- c(tutulan, sprintf("satır %d: %s", dizeler$line1[j],
                                      substr(dize, 1L, 90L)))
      }
    }
    tutulan
  }

  # POZİTİF KONTROL: kaçış + LİTERAL Türkçe AYNI dizede -> bulgu ÜRETİLMELİ.
  # NEGATİF KONTROL: `paste0()` ile AYRILMIŞ hâli -> bulgu ÜRETİLMEMELİ.
  # Bunlar olmadan tarayıcı bozulduğunda sözleşme sessizce yeşil kalırdı.
  .pozitif <- paste0("x <- \"", "\\", "u00e7 Türkçe\"")
  .negatif <- paste0("x <- paste0(\"", "\\", "u00e7\", \" Türkçe\")")
  # IKINCI NEGATIF KONTROL: CIFT ters bolu ETKIN kacis DEGILDIR; `\\u00e7`
  # duz metindir ve Turkce harflerle ayni literalde bulunmasi serbesttir.
  .negatif_cift <- paste0("x <- \"", "\\\\", "u00e7 Türkçe\"")
  # NA = AYRIŞTIRMA HATASI, BULGU DEĞİLDİR (PR #705 incelemesi, P2).
  #
  # `.karisik_dizeler()` `parse()` düştüğünde `NA_character_` döndürür ve bu
  # değerin uzunluğu da 1'dir; salt uzunluk iddiası pozitif kontrolü tarayıcı
  # BOZULSA bile geçiriyordu. Negatif kontroller `0L` beklediği için etkilenmez.
  .pozitif_bulgu <- .karisik_dizeler(.pozitif)
  testthat::expect_false(anyNA(.pozitif_bulgu))
  testthat::expect_length(.pozitif_bulgu, 1L)
  testthat::expect_length(.karisik_dizeler(.negatif), 0L)
  testthat::expect_length(.karisik_dizeler(.negatif_cift), 0L)

  bulgular <- character(0)
  for (yol in dosyalar) {
    ham <- readBin(yol, "raw", file.info(yol)$size)
    metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

    # SATIR SONLARI NORMALLEŞTİRİLİR: `.gitattributes` yalnızca TAZE bir
    # checkout'u LF yapar; VM çalışma kopyasındaki dosya CRLF kalabilir ve
    # `parse(text = <tek dize>)` CR karakterinde "unexpected invalid token"
    # verirdi.
    satirlar <- strsplit(gsub("\r\n?", "\n", metin), "\n", fixed = TRUE)[[1]]

    dosya_bulgulari <- .karisik_dizeler(satirlar)
    if (length(dosya_bulgulari) == 1L && is.na(dosya_bulgulari)) {
      # Ayrıştırılamayan dosya `tests/scripts/parse_sanity_check.R` kapısının
      # işidir; burada SESSİZCE atlanmaz, açık bulgu üretilir.
      bulgular <- c(bulgular, sprintf("%s: ayrıştırılamadı", basename(yol)))
      next
    }
    if (length(dosya_bulgulari)) {
      bulgular <- c(bulgular, sprintf("%s (%s)", basename(yol), dosya_bulgulari))
    }
  }

  testthat::expect_identical(
    length(bulgular), 0L,
    info = paste0(
      "Aşağıdaki dize sabitleri hem \\u/\\U kaçışı hem LİTERAL Türkçe içeriyor; ",
      "Windows VM'de Türkçe kısım SESSİZCE çift kodlanır. `paste0()` ile ikiye ",
      "ayırın:\n  - ",
      paste(bulgular, collapse = "\n  - ")
    )
  )
})
