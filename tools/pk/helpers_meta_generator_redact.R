# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_redact.R
# Açıklama: Faz 3b metadata üreticisi -- GİZLİLİK MASKELEME ve HATA
#           SINIFLANDIRMA.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# NEDEN AYRI DOSYA: maskeleme, raporun TÜM yollarında (bulgu üretimi, sağlık
# kaydı, giriş betiği konsolu) kullanılan bir GÜVENLİK sınırıdır; yapısal bulgu
# kararlarıyla aynı dosyada yaşadığında hem test edilmesi hem de gözden
# geçirilmesi zorlaşır.
#
# SERT KURAL: DSN, kimlik bilgisi, jeton, bağlantı dizesi, KULLANICI ADI,
# DOSYA YOLU ve ÜRETİM SATIR DEĞERLERİ rapora GİRMEZ. Şema/sütun ADLARI
# operatörün kendi VM'inde beklenen ve gerekli bilgidir; satır İÇERİĞİ değildir.
# ==============================================================================

# Yerelden BAĞIMSIZ ASCII küçük harf.
#
# Sürücü metni ASCII İngilizce kalıplarla eşleştirilir; ama `tolower()` YERELE
# BAĞLIDIR. Türkçe Windows yerelinde büyük `I` noktasız `ı` olur ve
# `LOGIN FAILED`, `INVALID OBJECT NAME`, `COMMUNICATION LINK ...` gibi mesajlar
# kendi sınıflarını KAÇIRIR; tanı `sinif=unknown` olarak bozulur. Depo kuralı
# gereği protokol metni asla yerele bağlı katlanmaz.
.pkgh_ascii_lower <- function(x) {
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) return(pk_ascii_lower(x))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

# Bağlantı dizesi anahtarları. Değer, `;` görünene KADAR ya da süslü/tırnaklı
# bir blok olarak maskelenir: `DSN={Prod SQL};UID={DOMAIN User};` biçimi
# boşluktan kesildiğinde `SQL}` / `User}` artıkları raporda KALIRDI.
.PKGH_SECRET_KEYS <- paste(
  c("dsn", "uid", "pwd", "password", "server", "database", "driver",
    "address", "addr", "app", "user", "user id", "uid", "trusted_connection",
    "authentication", "encrypt", "token", "apikey", "api_key", "secret"),
  collapse = "|"
)

.pkgh_redact <- function(x) {
  metin <- as.character(x %||% "")[1]
  if (is.na(metin)) return("")
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    metin <- tryCatch(redact_sensitive_text(metin), error = function(e) metin)
  }
  # Yerel yedek: bağlantı dizesi değerinin TAMAMINI maskele (süslü/tırnaklı
  # bloklar dahil), sonraki anahtar/değer çiftlerine dokunmadan.
  metin <- gsub(
    sprintf("(?i)\\b(%s)\\s*=\\s*(\\{[^}]*\\}|\"[^\"]*\"|'[^']*'|[^;]*)", .PKGH_SECRET_KEYS),
    "\\1=<gizli>", metin, perl = TRUE
  )
  metin <- gsub("(?i)(https?://)[^\\s;'\"]+", "\\1<gizli>", metin, perl = TRUE)
  metin
}

# SERBEST METİNDE YAŞAYAN gizli bilgiler.
#
# `.pkgh_redact()` yalnızca `anahtar=deger` biçimini ve URL'leri kapatır.
# Bootstrap istisnası ise SERBEST NESİR olabilir:
#   "Login failed for user 'DOMAIN\\alice'", "C:/Users/Alice/...",
#   "\\\\sunucu\\pay\\..." , "[ProdSql01] erisilemedi"
# Bunların hiçbiri anahtar/değer değildir ve maskelenmeden operatör loguna
# (ve katalog bulgusu varsa `health.json` içine) YAZILIRDI.
.pkgh_redact_freeform <- function(metin) {
  # UNC ve sürücü harfli Windows yolları + POSIX mutlak yolları.
  metin <- gsub("(?i)\\\\\\\\[^\\s'\"()\\[\\]]+", "<yol>", metin, perl = TRUE)
  metin <- gsub("(?i)\\b[a-z]:[\\\\/][^\\s'\"()\\[\\]]*", "<yol>", metin, perl = TRUE)
  metin <- gsub("(?<![A-Za-z0-9_])/(?:home|root|Users|mnt|srv|opt|var)/[^\\s'\"()\\[\\]]*",
                "<yol>", metin, perl = TRUE)
  # "for user 'X'", "user \"X\"", "login 'X'".
  metin <- gsub("(?i)\\b(for\\s+user|user|login|kullanici)\\s+(['\"\\[])[^'\"\\]]*(['\"\\]])",
                "\\1 <kullanici>", metin, perl = TRUE)
  # Ters bölü ile ayrılmış alan adı\\kullanici çifti.
  metin <- gsub("(?i)(['\"\\[])[A-Za-z0-9_.-]+\\\\[A-Za-z0-9_.$-]+(['\"\\]])",
                "<kullanici>", metin, perl = TRUE)
  .pkgh_redact_bracket_hosts(metin)
}

# KÖŞELİ PARANTEZLİ İÇ SUNUCU/HOST ADLARI MASKELENİR.
#
# ODBC hata metinleri `[Microsoft][ODBC Driver 17 for SQL Server][ProdSql01]`
# gibi zincirler taşır. İlk iki belirteç STANDART sürücü önekidir ve tanılama
# için gereklidir; sonuncusu ise İÇ SUNUCU ADIDIR. `pkgh_sanitize_bootstrap_error()`
# çıktısı operatör konsoluna ve `health.json` içine gidebildiğinden, hassas iç
# uç nokta adı orada YER ALMAMALIDIR. Bilinen sürücü/protokol belirteçleri ve
# SQLSTATE benzeri kodlar korunur; geri kalan köşeli belirteçler maskelenir.
.PKGH_BRACKET_SAFE <- c(
  "microsoft", "odbc", "sql server", "sql native client", "unixodbc",
  "freetds", "driver manager", "iodbc", "sqlserver", "db2", "oracle"
)

.pkgh_redact_bracket_hosts <- function(metin) {
  if (!is.character(metin) || length(metin) != 1L || is.na(metin)) return(metin)

  konumlar <- gregexpr("\\[[^\\[\\]]+\\]", metin, perl = TRUE)
  parcalar <- regmatches(metin, konumlar)[[1]]
  if (!length(parcalar)) return(metin)

  yeni <- vapply(parcalar, function(p) {
    icerik <- trimws(substr(p, 2L, nchar(p) - 1L))
    # PROTOKOL BELIRTECI YERELE BAGLI KATLANMAZ (Turkce noktasiz `i` tuzagi).
    #
    # `tolower("I")` Turkce `LC_CTYPE` altinda noktasiz `ı` uretir:
    # `[iODBC]`/`[Microsoft]` gibi STANDART surucu onekleri izin listesiyle
    # eslesmeyip `[<sunucu>]` diye maskeleniyor ve operator surucu kanitini
    # KAYBEDIYORDU.
    kucuk <- .pkgh_ascii_lower(icerik)
    # SQLSTATE BICIMI KORUNUR, SERBEST BES KARAKTER DEGIL.
    #
    # Eski `^[0-9A-Za-z]{5}$` muafiyeti HERHANGI bir bes karakterlik
    # alfanumerik icerigi gecirdigi icin `[Prod1]` / `[Sql01]` gibi KISA IC
    # SUNUCU adlari maskesiz kaliyor ve `pkgh_sanitize_bootstrap_error()`
    # bunlari operator konsoluna ve `health.json` icine yaziyordu.
    # SQLSTATE ya iki rakam + uc alfanumeriktir (`42S02`, `08S01`) ya da
    # `HY`/`IM` sinif onekini tasir (`HYT00`, `IM002`).
    if (grepl("^[0-9]{2}[0-9A-Za-z]{3}$", icerik) ||
        grepl("^(hy|im)[0-9a-z]{3}$", kucuk) ||
        grepl("^[0-9]+$", icerik)) {
      return(p)
    }
    # IZIN LISTESI ALT DIZGE DEGIL, BELIRTEC ESLESMESIDIR.
    #
    # Eski `grepl(g, kucuk, fixed = TRUE)` alt dizge kontroluydu; izin verilen
    # bir belirteci ICEREN her ic sunucu adi maskesiz gecyordu
    # (`[odbc-gw-prod-07]`, `[SQLSERVER-FIN-01]`, `[oracle-dw-prod.intra]`).
    # Gercek surucu onekleri belirtecin KENDISIDIR ya da belirtecten sonra
    # BOSLUK ile devam eder (`[ODBC Driver 17 for SQL Server]`); sunucu adlari
    # ise `-`/`_`/`.` ile birlesir. Bu yuzden yalnizca tam esitlik ya da
    # "belirtec + bosluk" oneki guvenli sayilir.
    if (any(vapply(.PKGH_BRACKET_SAFE,
                   function(g) identical(kucuk, g) || startsWith(kucuk, paste0(g, " ")),
                   logical(1)))) {
      return(p)
    }
    "[<sunucu>]"
  }, character(1), USE.NAMES = FALSE)

  regmatches(metin, konumlar) <- list(yeni)
  metin
}

# Sürücü hatası metni SATIR DEĞERİ TAŞIYABİLİR.
#
# Salt-okunur bir SQL Server sorgusu bile "Conversion failed when converting
# the nvarchar value 'Ahmet Yilmaz' to data type int" gibi bir hata verebilir;
# bu metin ÜRETİM SATIR DEĞERİ içerir ve `.pkgh_redact()` yalnızca gizli anahtar
# kalıplarını temizler. Bu yüzden ham sürücü metni ASLA rapora yazılmaz;
# yerine KARARLI bir sınıflandırma kodu ve (varsa) SQLSTATE yazılır.
#
# SINIF SIRASI ANLAMLIDIR: ilk eşleşen kazanır.
#   * `object_missing` SQLSTATE 42S02 (tablo/gorunum yok) ve 42S22 (sutun yok)
#     durumlarini TASIR. Bunlari `syntax_error` altina koymak, yerellestirilmis
#     bir surucu mesajinda nesne/sema kaymasini SOZDIZIMI hatasi gibi gosterir.
#   * `driver_unavailable` YALNIZCA surucu/DSN KESFI imzalariyla sinirlidir.
#     Yalin `driver` kelimesi, `[ODBC Driver 18 for SQL Server]` gibi STANDART
#     bir onek tasiyan HER sunucu hatasini (ornegin bir deadlock) surucu sorunu
#     gibi siniflandirirdi.
.PKGH_ERROR_CLASSES <- list(
  timeout             = "timeout|zaman asimi|query timeout|hywat|hyt00|hyt01",
  connection_lost     = "08s01|08001|08003|08004|communication link|connection is closed|connection was closed|not connected|baglanti",
  permission_denied   = "permission|denied|unauthorized|login failed|28000|42000.*permission",
  object_missing      = "invalid object name|invalid column name|could not find|does not exist|42s02|42s22",
  conversion_failed   = "conversion failed|arithmetic overflow|cannot convert|out-of-range",
  syntax_error        = "incorrect syntax|syntax error|42000",
  driver_unavailable  = "im002|im003|im004|data source name|specified driver could not be loaded|driver not found|can't open lib|architecture mismatch"
)

# SQLSTATE: TAM köşeli belirteci eşle ve YAKALAMAYI çıkar.
#
# `[0-9A-Za-z]{5}(?=\])` kalıbı yalnızca `]` ÖNCESİNDE beş alfanümerik ister; bu
# yüzden standart ODBC öneki `[Microsoft][ODBC Driver ...][22018]` içinde ÖNCE
# `[Microsoft]` sonundaki `osoft` ile eşleşir ve rapora `sqlstate=osoft` yazardı.
# BICIM, KOSELI IZIN LISTESIYLE AYNIDIR: iki rakam + uc alfanumerik ya da
# `HY`/`IM` sinif oneki. Serbest bes karakterli bir bracket belirteci
# (`[Microsoft][ODBC Driver 17 for SQL Server][SQL01]` zincirindeki IC SUNUCU
# adi gibi) `sqlstate=` alanina YAZILMAZ; bu fonksiyonun ciktisi bracket
# redaksiyonundan GECMEZ ve deger operator konsoluna/`health.json`a giderdi.
.PKGH_SQLSTATE_PATTERN <- "\\[((?:[0-9]{2}|HY|IM)[0-9A-Z]{3})\\]"

# SÜRÜCÜ HATA NUMARASI YALNIZCA YAPISAL OLARAK ÇAPALANMIŞ BİÇİMDEN OKUNUR.
#
# Serbest metinde `error NNN` aramak, ham mesajın SATIR DEĞERİ taşıyabildiği
# gerçeğiyle çelişir: değeri `error 12345` olan bir dönüşüm hatası, ham metin
# bastırılmış olsa bile `hata_no=12345` biçiminde satır değerinin bir parçasını
# sızdırırdı. T-SQL'in `Msg <n>, Level <k>` başlığı ise yapısal bir çapadır.
.PKGH_ERROR_NUMBER_PATTERN <- "(?i)\\bMsg[ \\t]+([0-9]{1,6})[ \\t]*,[ \\t]*Level[ \\t]+[0-9]"

.pkgh_first_capture <- function(text, pattern) {
  eslesme <- regmatches(text, regexec(pattern, text, perl = TRUE))[[1]]
  if (length(eslesme) < 2L) return(NA_character_)
  yakalanan <- eslesme[2]
  if (is.na(yakalanan) || !nzchar(yakalanan)) return(NA_character_)
  yakalanan
}

#' Sürücü/DB hatasını GÜVENLİ bir özet metnine indir
#'
#' @return Rapora yazılabilir, satır değeri TAŞIMAYAN metin.
pkgh_db_error_summary <- function(message) {
  ham <- as.character(message %||% "")[1]
  if (is.na(ham) || !nzchar(trimws(ham))) {
    return("DB hatasi (sinif=unknown). Ham surucu metni rapora GIRMEZ.")
  }

  kucuk <- .pkgh_ascii_lower(ham)
  sinif <- "unknown"
  for (ad in names(.PKGH_ERROR_CLASSES)) {
    if (grepl(.PKGH_ERROR_CLASSES[[ad]], kucuk, perl = TRUE, useBytes = TRUE)) {
      sinif <- ad
      break
    }
  }

  durum <- .pkgh_first_capture(ham, .PKGH_SQLSTATE_PATTERN)
  numara <- .pkgh_first_capture(ham, .PKGH_ERROR_NUMBER_PATTERN)

  parcalar <- c(
    sprintf("sinif=%s", sinif),
    if (!is.na(durum)) sprintf("sqlstate=%s", durum),
    if (!is.na(numara)) sprintf("hata_no=%s", numara)
  )

  sprintf(paste0(
    "DB hatasi (%s). Ham surucu metni URETIM SATIR DEGERI tasiyabildigi icin ",
    "rapora YAZILMAZ; tam metin yalnizca operatorun kendi oturum konsolundadir."
  ), paste(parcalar, collapse = ", "))
}

#' Başlangıç doğrulama hatasını rapora GÜVENLİ biçimde hazırla
#'
#' `pk_query_meta_attach()` çıktısı, üretimden türetilmiş
#' `R/library_query_aliases_local.R` bindirmesini de uygular; alias hataları
#' KANONİK HEDEF değerleri (gerçek proje/program adları) taşıyabilir. Bu yüzden
#' alias ile ilgili satırlar sabit bir metne indirgenir; sorgu kimliği
#' (kararlı tanımlayıcı) korunur.
pkgh_sanitize_validation_error <- function(message) {
  ham <- as.character(message %||% "")[1]
  if (is.na(ham) || !nzchar(ham)) return(NA_character_)

  satirlar <- strsplit(ham, "\n", fixed = TRUE)[[1]]
  temiz <- vapply(satirlar, function(satir) {
    if (grepl("alias", satir, ignore.case = TRUE, useBytes = TRUE)) {
      kimlik <- regmatches(satir, regexpr("^\\s*-?\\s*\\[[^]]+\\]", satir))
      # KIMLIK KOSELI PARANTEZ OLMADAN YAZILIR.
      #
      # `pkgh_sanitize_bootstrap_error()` bu ciktiyi `.pkgh_redact_freeform()`
      # icinden gecirir; koseli parantezli STANDART OLMAYAN bir sorgu kimligi
      # (`[q_planned_labour]`) surucu oneki sanilip `[<sunucu>]` diye
      # maskelenebiliyor ve operator BASARISIZ sorgunun kimligini KAYBEDIYORDU.
      onek <- if (length(kimlik) == 1L) {
        paste0("- ", gsub("^[^\\[]*\\[|\\].*$", "", trimws(kimlik)), ":")
      } else {
        "-"
      }
      return(paste0(
        onek, " alias bindirmesi dogrulamasi basarisiz. Ayrinti operator ",
        "oturumundadir; kanonik hedef degerleri (uretim proje/program adlari) ",
        "rapora YAZILMAZ."
      ))
    }
    satir
  }, character(1), USE.NAMES = FALSE)

  .pkgh_redact(paste(temiz, collapse = "\n"))
}

#' BOOTSTRAP istisnasını operatör loguna GÜVENLİ hazırla
#'
#' Bootstrap hatası KEYFİ bir R/sürücü koşul mesajıdır: bağlantı dizesi
#' biçiminde OLMAYAN kullanıcı adı, mutlak yol ve DSN adı taşıyabilir. Bu yol
#' hem konsola basılır hem de katalog bulgusu varsa `health.json` içine yazılır;
#' bu yüzden serbest metin maskelemesi de uygulanır ve uzunluk sınırlanır.
pkgh_sanitize_bootstrap_error <- function(message, max_chars = 600L) {
  temiz <- pkgh_sanitize_validation_error(message)
  if (is.na(temiz)) return(NA_character_)

  temiz <- .pkgh_redact_freeform(temiz)

  sinir <- suppressWarnings(as.integer(max_chars)[1])
  if (!is.na(sinir) && sinir > 0L && nchar(temiz) > sinir) {
    temiz <- paste0(substr(temiz, 1L, sinir), " ... [kisaltildi]")
  }
  temiz
}
