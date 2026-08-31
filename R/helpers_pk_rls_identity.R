# ==============================================================================
# Dosya Yolu: R/helpers_pk_rls_identity.R
# Açıklama: RLS kimlik/izin okuma yardımcıları (§5.4 sertleştirme).
#
#           `R/helpers_pk_analysis_security_summary.R` bilinçli olarak KÜÇÜK
#           bir yardımcı dosyadır ve bakım ratchet'i ile kilitlidir. Bu dosya
#           oradan ÇIKARILAN dört odaklı yardımcıyı barındırır:
#             * kanonik kullanıcı adı anahtarı (SQL collation ile R `==`
#               ayrışmasını kapatır),
#             * sunucu log'una gidecek tanı metninin KAPALI BAŞARISIZ
#               redaksiyonu,
#             * izin okumasının SQL tarafında kullanıcıya daraltılması,
#             * izin satırlarının kanonik kullanıcı anahtarıyla seçilmesi.
#
#           `.pk_rls_bounded_query()` / `.pk_rls_halt_error()` çağrı ANINDA
#           çözülür; bu dosya onları TANIMLAMAZ ve manifest sırası (bu dosya
#           güvenlik özeti dosyasından ÖNCE) yalnızca okunabilirlik içindir.
#
#           Dosya SAFTIR: Shiny/reactive bağımlılığı yoktur; yalnızca çağıranın
#           verdiği DBI bağlantısını kullanır.
# ==============================================================================

# KULLANICI ADI KANONİK BİÇİMİ (YETKİLENDİRME SINIRI).
#
# Temel kimlik araması SQL'de yapılır (`WHERE KullaniciAdi = ?`) ve SQL Server
# COLLATION'ına uyar (normalde büyük/küçük harf duyarsız). İzin satırları ise
# R'de `==` ile karşılaştırılıyordu; yani temel aramadan GEÇEN bir kullanıcı,
# izin tablosundaki yazımı farklı diye HİÇBİR PY/EPS satırını eşleştiremeyip
# boş kapsama (erişim reddi) düşebiliyordu. Katlama yerelden BAĞIMSIZDIR:
# Türkçe yerelde `tolower("I")` noktasız `ı` üretir ve iki taraf ayrışır.
#
# NOKTALI/NOKTASIZ I AİLESİ KATLANMAZ (PR #705/#714 incelemesi).
#
# Önceki biçim `İ` ve `I` harflerinin İKİSİNİ de `i` yapıyordu. Bu bir
# TRANSLİTERASYONdur ve yetkilendirmede kullanılamaz: `Ipek` ile `İpek`
# BİRBİRİNDEN FARKLI hesaplardır, hiçbir SQL Server collation'ı (ne
# `Turkish_CI_AS` ne `Latin1_General_CI_AS`) bu ikisini eşit saymaz. Katlama
# sonucu `.pk_rls_rows_for_user()` iki hesabın izin satırlarını BİRLEŞTİRİP
# kullanıcıya kendi kapsamı dışında proje/EPS kodu verebiliyordu.
#
# Katlama artık yalnızca AYNI HARFİN büyük/küçük biçimlerini birleştirir:
#   * ASCII A-Z -> a-z (`I` -> `i` dâhil; bu, dağıtımın kullandığı
#     büyük/küçük harf duyarsız collation davranışıdır ve korunur),
#   * Türkçe Ç/Ğ/Ö/Ş/Ü -> ç/ğ/ö/ş/ü.
#
# `İ` (U+0130) ve `ı` (U+0131) HİÇ katlanmaz. Bunlar ASCII `i`/`I`'dan AYRI
# harflerdir; onları ASCII i-ailesine indirmek `İpek` ile `Ipek` hesaplarını
# BİRLEŞTİRİYORDU. İki taraf gerçekten farklı harf kullanıyorsa satır
# EŞLEŞMEZ ve karar KAPALI BAŞARISIZ (kapsam boş) olur; yanlış hesabın
# kapsamını devralmaktansa erişimi reddetmek doğrudur.
.PK_RLS_FOLD_FROM <- "ABCDEFGHIJKLMNOPQRSTUVWXYZÇĞÖŞÜ"
.PK_RLS_FOLD_TO   <- "abcdefghijklmnopqrstuvwxyzçğöşü"

.pk_rls_user_key <- function(x) {
  ham <- as.character(x %||% "")
  ham <- trimws(ham)
  chartr(.PK_RLS_FOLD_FROM, .PK_RLS_FOLD_TO, ham)
}

# DB TARAFI DARALTILMIŞ SATIRLAR İÇİN AKSAN DUYARLI KİMLİK ANAHTARI.
#
# `WHERE KullaniciAdi = ?` yüklemi VERİTABANI collation'ıyla çözülür. AKSAN
# DUYARSIZ (`_CI_AI`) bir collation'da `Oz` sorgusu HEM `Oz` HEM `Öz` satırını
# döndürür ve `get_user_rls_info()` iki kullanıcının proje/EPS kodlarını
# çağıranın kapsamına ekler. Bu anahtar yalnızca BÜYÜK/KÜÇÜK harf farkını
# katlar; `Ç/Ğ/Ö/Ş/Ü` ile `C/G/O/S/U` AYRI kalır, yani aksan farkı satırı
# DÜŞÜRÜR. Noktalı/noktasız `I` ailesi burada BİLEREK birleştirilir: dağıtım
# collation'ı (`Turkish_CI_AS`) `i` ile `İ`yi zaten eşit sayar; ayırmak
# YETKİLİ bir kullanıcının kapsamını boşaltırdı (yedek yol bunları hâlâ ayrı
# tutar, orada DB kararı YOKTUR).
.PK_RLS_DB_FOLD_FROM <- "\u0130\u0131"
.PK_RLS_DB_FOLD_TO   <- "ii"

.pk_rls_db_match_key <- function(x) {
  chartr(.PK_RLS_DB_FOLD_FROM, .PK_RLS_DB_FOLD_TO, .pk_rls_user_key(x))
}

# SUNUCU LOG'UNA GİDECEK HER TANI METNİ REDAKTE EDİLİR (kapalı başarısız).
#
# Ham ODBC/sürücü metni DSN, sunucu/veritabanı adı, kullanıcı adı ve zaman
# zaman bağlantı dizesi kimlik bilgisi taşır. `cat()` uygulamanın redakte eden
# `log_*()` sınırını ATLAR; bu yardımcı o sınırı geri getirir.
.pk_rls_safe_detail <- function(text) {
  metin <- as.character(text %||% "")[1]
  if (is.na(metin) || !nzchar(metin)) return("")
  # Bu metin KALICI sunucu log'una gider: baglanti TANIMLAYICILARI (DSN/UID/
  # Server/Database) da maskelenir. Genel redaktor bunlari BILEREK korur.
  #
  # GENEL REDAKTÖRE GERİ DÜŞÜLMEZ. `redact_sensitive_text()` sözleşmesi gereği
  # `Server=`, `Database=`, `DSN=`, `UID=` alanlarını BİLEREK korur; geri
  # düşmek, bağlantı altyapısını kalıcı log'a yazmak demekti. Bağlantıya özgü
  # redaktör yoksa tanı metni HİÇ yazılmaz.
  redaktor <- if (exists("redact_connection_identifiers", mode = "function", inherits = TRUE)) {
    redact_connection_identifiers
  } else {
    NULL
  }
  if (is.null(redaktor)) return("(redaktor yuklenmedi)")
  temiz <- tryCatch(redaktor(metin), error = function(e) NULL)
  if (!is.character(temiz) || length(temiz) != 1L || is.na(temiz)) {
    return("(redaksiyon uygulanamadi)")
  }
  temiz <- gsub("[[:cntrl:]]+", " ", temiz, perl = TRUE)
  temiz <- gsub("[[:space:]]+", " ", trimws(temiz), perl = TRUE)
  if (nchar(temiz) > 300L) temiz <- paste0(substr(temiz, 1L, 299L), "…")
  temiz
}

# İZİN OKUMASI KULLANICIYA GÖRE SQL TARAFINDA DARALTILIR.
#
# Küratörlü izin sorguları TÜM kullanıcıları seçer; eskiden tüm yetkilendirme
# haritası R'ye aktarılıp orada filtreleniyordu. Bu, her istekte tüm izin
# tablosunu taşımak, diğer kullanıcıların eşlemelerini işçiye açmak ve istek
# bütçesini bu aktarımda tüketmek demektir. Operatör SQL'i tek bir SELECT
# sözleşmesindedir (salt-okunur kapısı bunu zorlar), bu yüzden türetilmiş
# tablo olarak sarılıp parametreli bir yüklem eklenir.
#
# GERİ DÜŞME KORUNUR: sarma çalışmazsa (ör. sondaki `ORDER BY`) eski davranışa
# dönülür ve R tarafındaki kanonik eşleştirme yine uygulanır; yalnızca DB
# tarafı daraltma kaybolur ve bu durum log'lanır.
#
# GERİ DÜŞME YALNIZCA SÖZDİZİMİ SINIFI HATALARDA ÇALIŞIR.
#
# Sarmalama başarısız olduğunda daraltılmamış sorgu TÜM izin tablosunu taşır.
# Bunu HER hatada yapmak, geçici bir sürücü/ağ arızasında aynı isteğin iki tam
# tablo okuması yapmasına ve kalan bütçenin ARDIŞIK olarak tüketilmesine yol
# açardı. Türetilmiş tablo sarmalamasının gerçekten desteklenmediği durumlar
# SQL sözdizimi/nesne hatalarıdır; geçici arızalar bu sınıfta değildir ve
# yukarı YAYILIR (çağıran onu `db_error` olarak TİPLİ raporlar).
# KALIPLAR KATLANMIŞ METİNLE KARŞILAŞTIRILIR; bu yüzden hepsi KÜÇÜK harftir.
# `"42S22"` / `"42S02"` büyük `S` taşıdığı için katlanmış metinle ASLA
# eşleşmiyordu: sürücü hatayı yalnızca SQLSTATE koduyla bildirdiğinde
# `.pk_rls_syntax_class_error()` `FALSE` dönüyor, belgelenen R-tarafı yedeği hiç
# çalışmıyor ve kullanıcı yetkili satırlar yerine tipli bir `db_error` alıyordu.
.PK_RLS_SYNTAX_SIGNS <- c(
  "42000", "42s22", "42s02",
  "incorrect syntax", "syntax error", "invalid column name",
  "invalid object name", "must be the first statement",
  "sozdizimi"
)

.pk_rls_syntax_class_error <- function(e) {
  metin <- tryCatch(conditionMessage(e), error = function(x) "")
  if (is.null(metin) || !length(metin) || is.na(metin[1]) || !nzchar(metin[1])) return(FALSE)
  # Katlama yerelden BAĞIMSIZ olmalıdır: Türkçe yerelde `tolower("I")` noktasız
  # `ı` üretir ve "INCORRECT SYNTAX" eşleşmezdi.
  duz <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", metin[1])
  any(vapply(.PK_RLS_SYNTAX_SIGNS, function(p) grepl(p, duz, fixed = TRUE), logical(1)))
}

# TÜRETİLMİŞ TABLO GÖVDESİNDE SONDAKİ `;` BULUNAMAZ.
#
# SQL Server `... FROM (SELECT ...;) AS t` yazımını REDDEDER: noktalı virgül
# ifadeyi kapatır. Küratörlü izin SQL'i sonda `;` taşıyorsa sarmalama HER
# ZAMAN sözdizimi hatası verir ve daraltma sessizce kaybolurdu. Yalnızca
# SONDAKİ ayırıcı (ve ardındaki boşluk) kırpılır; gövde içindeki noktalı
# virgüllere dokunulmaz.
.pk_rls_strip_terminal_semicolon <- function(statement) {
  metin <- as.character(statement %||% "")[1]
  if (is.na(metin)) return("")
  sub("[[:space:];]+$", "", metin, perl = TRUE)
}

.pk_rls_permission_rows <- function(conn, statement, username) {
  # ÇÖZÜLEMEYEN KİMLİK SORGULANMAZ: DB tarafı daraltma başarılı olduğunda
  # satırlar `pk_rls_db_narrowed = TRUE` ile döner; boş/NA kimlik burada
  # reddedilmezse `KullaniciAdi = ''` satırları çağıranın kapsamı sayılırdı
  # (R tarafı yedeği yalnızca daraltma BAŞARISIZKEN korur).
  kimlik <- .pk_rls_user_key(username)
  kimlik <- kimlik[!is.na(kimlik) & nzchar(kimlik)]
  if (!length(kimlik)) {
    stop("RLS izin okumasi icin cozulmus bir kullanici kimligi gerekir.",
         call. = FALSE)
  }

  sarmalanmis <- sprintf(
    "SELECT mb_izin.* FROM (\n%s\n) AS mb_izin WHERE mb_izin.KullaniciAdi = ?",
    .pk_rls_strip_terminal_semicolon(statement)
  )

  sonuc <- tryCatch(
    .pk_rls_bounded_query(conn, sarmalanmis, params = list(username)),
    error = function(e) {
      if (isTRUE(.pk_rls_halt_error(e))) stop(e)
      if (!isTRUE(.pk_rls_syntax_class_error(e))) stop(e)
      e
    }
  )

  if (inherits(sonuc, "condition")) {
    cat(sprintf(
      "[PK_ANALIZ] UYARI: izin sorgusu DB tarafinda daraltilamadi; R tarafinda filtrelenecek. Ayrinti: %s\n",
      .pk_rls_safe_detail(conditionMessage(sonuc))
    ))
    ham <- .pk_rls_bounded_query(conn, statement)
    # DARALTMA YAPILMADI: R tarafı kanonik eşleştirmesi ZORUNLUDUR (kapalı
    # başarısız; tam izin tablosu yedeğe düştüğünde başkasının satırı alınmaz).
    if (is.data.frame(ham)) attr(ham, "pk_rls_db_narrowed") <- FALSE
    return(ham)
  }

  # DB TARAFI DARALTMA BAŞARILI: satırlar `WHERE mb_izin.KullaniciAdi = ?` ile
  # VERİTABANI COLLATION'ına göre ZATEN bu kullanıcıya aittir. İkinci ve DAHA
  # DAR bir R karşılaştırması yalnızca ONAYLI satırları DÜŞÜREBİLİR: Türkçe
  # collation (`Turkish_CI_AS`) `i` ile `İ`yi, aksan duyarsız collation ise
  # `Ö` ile `O`yu EŞİT sayar; `.pk_rls_user_key()` bunları bilinçli olarak
  # ayrı tutar. Yetkili bir PY/KY-P/DIR-P kullanıcısı bu yüzden BOŞ kapsam
  # alıp teşhissiz bir sonuç görüyordu.
  if (is.data.frame(sonuc)) attr(sonuc, "pk_rls_db_narrowed") <- TRUE
  sonuc
}

# İZİN SATIRLARINI KANONİK KULLANICI ADIYLA SEÇ
.pk_rls_rows_for_user <- function(rows, username) {
  if (!is.data.frame(rows) || !nrow(rows)) return(rows)
  # DB TARAFINDA DARALTILMIŞ SATIRLAR OTORİTERDİR (bkz. `.pk_rls_permission_rows()`).
  # İşaret YOKSA (test kurgusu, eski çağıran) filtre yine uygulanır: varsayılan
  # KAPALI BAŞARISIZDIR.
  if (isTRUE(attr(rows, "pk_rls_db_narrowed"))) {
    # Satırlar yetkilidir AMA collation aksan duyarsız olabilir; aksan farkı
    # taşıyan BAŞKA bir hesabın satırı düşürülür (bkz. `.pk_rls_db_match_key`).
    if (!("KullaniciAdi" %in% names(rows))) return(rows)
    db_anahtar <- .pk_rls_db_match_key(username)
    db_anahtar <- db_anahtar[!is.na(db_anahtar) & nzchar(db_anahtar)]
    if (!length(db_anahtar)) return(rows[0, , drop = FALSE])
    db_satir <- .pk_rls_db_match_key(rows$KullaniciAdi)
    return(rows[!is.na(db_satir) & nzchar(db_satir) & db_satir %in% db_anahtar,
                , drop = FALSE])
  }
  if (!("KullaniciAdi" %in% names(rows))) return(rows[0, , drop = FALSE])
  # ÇÖZÜLEMEYEN KİMLİK KAPSAM ALMAZ. `.pk_rls_user_key()` NA kullanıcı adı için
  # `NA_character_`, boş için `""` döndürür ve `%in%` NA'yı EŞLEŞEBİLİR sayar
  # (`NA %in% NA` TRUE'dur). DB tarafı daraltma başarısız olup tam izin tablosu
  # yedeğe düştüğünde, `KullaniciAdi` alanı NULL/boş olan satırlar çağıranın
  # kapsamı gibi seçilirdi: kimliği çözülemeyen kullanıcı proje/EPS kodlarını
  # DEVRALIRDI. Kullanılamayan kimlik ÖNCE reddedilir.
  anahtar <- .pk_rls_user_key(username)
  anahtar <- anahtar[!is.na(anahtar) & nzchar(anahtar)]
  if (!length(anahtar)) return(rows[0, , drop = FALSE])

  satir_anahtari <- .pk_rls_user_key(rows$KullaniciAdi)
  eslesme <- !is.na(satir_anahtari) & nzchar(satir_anahtari) &
    satir_anahtari %in% anahtar
  rows[eslesme, , drop = FALSE]
}

#' Yetkisiz RLS sonucundan kullanıcıya görünen TİPLİ mesaj
#'
#' `get_user_rls_info()` yetki verilmediğinde ÜÇ AYRI durumu ayırt eder:
#' `db_error` (altyapı arızası), `ambiguous` (mükerrer yetki kaydı) ve
#' kullanıcının gerçekten bulunamaması. Çağıranlar bunların hepsini
#' "Sistemde kullanıcı kaydınız bulunamadı" diye raporlarsa, geçici bir
#' DC01 kesintisi HER kullanıcıya YANLIŞ bir yetki teşhisi olarak görünür ve
#' gerçek arıza gizlenir.
#'
#' Karar her hâlde KAPALI BAŞARISIZ kalır (yetki verilmez); değişen yalnızca
#' TEŞHİStir. Ham sürücü/SQL metni buradan geçmez: yalnızca
#' `get_user_rls_info()` içinde ÜRETİLEN sabit Türkçe gerekçeler kullanılır.
#'
#' @param rls_info `get_user_rls_info()` çıktısı.
#' @return Tek elemanlı karakter; kullanıcıya gösterilecek mesaj.
pk_rls_denied_message <- function(rls_info) {
  gerekce <- NULL
  if (is.list(rls_info)) {
    ham <- rls_info$reason
    if (is.character(ham) && length(ham) >= 1L && !is.na(ham[1]) && nzchar(ham[1])) {
      gerekce <- ham[1]
    }
  }

  if (is.list(rls_info) && isTRUE(rls_info$db_error)) {
    return(paste0(
      "\U000026A0\U0000FE0F **Yetki Bilgisi Okunamadı:** ",
      gerekce %||% paste0(
        "Yetki bilgisi okunamadı (veritabanı erişim hatası). Bu bir yetki ",
        "kararı değildir; lütfen daha sonra tekrar deneyin."
      )
    ))
  }

  if (is.list(rls_info) && isTRUE(rls_info$ambiguous)) {
    return(paste0(
      "\U000026A0\U0000FE0F **Yetki Kaydı Belirsiz:** ",
      gerekce %||% paste0(
        "Yetki kaydınız benzersiz değil (birden fazla kayıt bulundu). Yanlış ",
        "bir kapsamla analiz çalıştırmamak için işlem durduruldu."
      )
    ))
  }

  # İÇ KAYNAK ADI (tablo/görünüm) KULLANICIYA GÖSTERİLMEZ: kurtarmaya yardımı
  # yoktur, iç şema adını sızdırır. Ayrıntı sunucu log'unda kalır.
  paste0(
    "\U000026A0\U0000FE0F **Yetki Hatası:** Sistemde kullanıcı kaydınız ",
    "bulunamadı. Lütfen yönetici ile iletişime geçin."
  )
}
