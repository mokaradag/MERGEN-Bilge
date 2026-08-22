# ==============================================================================
# Dosya Yolu: R/helpers_pk_safe_errors.R
# Açıklama: Proje ve Kaynak Analizi için kullanıcıya gösterilecek hata metninin
#           güvenli hale getirilmesi (D22).
#
#           Eski davranış: module_proje_kaynak_analizi.R, conditionMessage(e)
#           çıktısını (sürücü adı, DSN, sunucu adı, SQLSTATE, şema/sütun
#           ayrıntısı) doğrudan sohbet balonuna gömüyordu. Ortak Oturum tarafında
#           bu iş için `oo_arac_oda_guvenli_yanit()` zaten vardı; ancak o dosya
#           kaynak manifestinde ÇOK DAHA SONRA yüklenir, bu yüzden PK tarafında
#           çağrılamaz. Burada aynı yaklaşımın PK'ya ait, saf ve bağımsız
#           karşılığı bulunur.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ bağımlılığı yoktur ve her
#           iki motor (v1/v2) ile derin mod tarafından koşulsuz kullanılır.
# ==============================================================================

# Ham altyapı tanılaması sayılan kalıplar. Bunlardan biri görülürse metin
# kullanıcıya HİÇ gösterilmez; yerine genel mesaj döner.
PK_UNSAFE_ERROR_PATTERNS <- c(
  "nanodbc", "SQLSTATE", "ODBC", "odbc.cpp", "SQL Server", "sqlserver",
  "Microsoft][", "HY000", "42S02", "42S22", "42000", "IM002", "08001",
  "08S01", "28000", "Login timeout", "Login failed", "Named Pipes",
  "TCP Provider", "could not connect", "Connection refused",
  "DSN=", "Driver=", "Server=", "Database=", "Uid=", "Pwd=",
  "Error in ", "error in evaluating", "Invalid object name",
  "Incorrect syntax", "Conversion failed", "Arithmetic overflow",
  "sp_executesql", "Msg ", "Level ", "State "
)

# Kullanıcıya gösterilen genel veritabanı hatası. Sorgu adı/DSN/sütun adı gibi
# hiçbir iç ayrıntı taşımaz.
PK_GENERIC_DB_ERROR_MESSAGE <- paste0(
  "\U000026A0\U0000FE0F **Veritabanı Hatası:** Sorgu çalıştırılırken bir hata ",
  "oluştu. Teknik ayrıntılar sunucu günlüklerine kaydedildi. ",
  "Sorun sürerse lütfen sistem yöneticisiyle iletişime geçin."
)

# Kullanıcıya dönen PK hata metinlerinin ORTAK başlangıç işareti. Modül, SQL
# yürütmesinden dönen değerin veri mi yoksa hata metni mi olduğunu bu işaretle
# ayırt eder.
PK_USER_ERROR_PREFIX <- "\U000026A0\U0000FE0F"

#' Ham hata metnini kullanıcıya gösterilebilir hale getir
#'
#' Metin altyapı tanılaması gibi görünüyorsa tamamen genel mesajla değiştirilir.
#' Aksi halde (örn. bizim ürettiğimiz Türkçe doğrulama mesajı) depo genelindeki
#' `redact_sensitive_text()` süzgecinden geçirilerek olduğu gibi döner.
#'
#' @param raw_message Ham hata metni (genellikle `conditionMessage(e)`).
#' @return Kullanıcıya gösterilebilir tek elemanlı karakter değer.
pk_safe_error_message <- function(raw_message) {
  metin <- as.character(raw_message %||% "")[1]
  if (is.na(metin) || !nzchar(trimws(metin))) {
    return(PK_GENERIC_DB_ERROR_MESSAGE)
  }

  # BÜYÜK/KÜÇÜK HARF DUYARSIZ eşleşme (PR #705, P4-1).
  #
  # Sürücüler aynı tanılamayı farklı harflendirmeyle üretir (`dsn=`, `Pwd=`,
  # `sql server`, `login failed`). Harfe duyarlı `fixed = TRUE` karşılaştırma
  # bunları KAÇIRIYOR ve ham altyapı metni kullanıcıya gidiyordu.
  #
  # Katlama ASCII'ye SABİTLENMİŞTİR: `tolower()` Türkçe yerelde `I` -> `ı`
  # eşlemesi yaptığı için `IM002`/`Invalid object name` gibi ASCII kalıpları
  # bozardı. `chartr()` yerelden BAĞIMSIZDIR.
  .pk_err_fold <- function(x) {
    chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", x)
  }

  katlanmis <- tryCatch(.pk_err_fold(metin), error = function(e) NULL)
  if (is.null(katlanmis) || length(katlanmis) != 1L || is.na(katlanmis)) {
    # KAPALI BAŞARISIZ: katlanamayan metin güvenli sayılmaz.
    return(PK_GENERIC_DB_ERROR_MESSAGE)
  }

  riskli <- any(vapply(
    PK_UNSAFE_ERROR_PATTERNS,
    function(kalip) {
      grepl(.pk_err_fold(kalip), katlanmis, fixed = TRUE, useBytes = TRUE)
    },
    logical(1)
  ))

  if (riskli) {
    return(PK_GENERIC_DB_ERROR_MESSAGE)
  }

  # REDAKSİYON BAŞARISIZSA HAM METNE DÖNÜLMEZ.
  #
  # Eski yedek yol (`error = function(e) metin`) tam olarak korunmak istenen
  # şeyi sızdırıyordu: redaktör bir DSN/parola/anahtar içeren metinde hata
  # verdiğinde, o ham metin kullanıcıya ve loga aynen gidiyordu. Redaksiyon
  # yapılamıyorsa doğru davranış GENEL mesaja düşmektir.
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    metin <- tryCatch(redact_sensitive_text(metin),
                      error = function(e) PK_GENERIC_DB_ERROR_MESSAGE)
  }

  metin
}

#' Kullanıcıya dönecek hata metnini TANINABİLİR biçime getir
#'
#' `pk_safe_error_message()` bilerek geçirgendir: altyapı tanılaması gibi
#' GÖRÜNMEYEN bir metin (örn. kendi ürettiğimiz Türkçe doğrulama mesajı)
#' olduğu gibi döner. Bu doğru bir redaksiyon kararıdır ama tek başına yeterli
#' değildir: çağıran modül SQL yürütmesinden dönen değerin veri mi hata metni
#' mi olduğunu ortak işaretten anlar; işaret düşerse hata metni SONUÇ KÜMESİ
#' sanılır ve akış ham bir R hatasıyla çöker. Bu yüzden kullanıcıya giden metin
#' burada her koşulda işaretlenir.
#'
#' @return `PK_USER_ERROR_PREFIX` ile başlayan tek elemanlı karakter değer.
pk_user_error_text <- function(message) {
  metin <- as.character(message %||% "")[1]
  if (is.na(metin) || !nzchar(trimws(metin))) {
    return(PK_GENERIC_DB_ERROR_MESSAGE)
  }

  if (startsWith(metin, PK_USER_ERROR_PREFIX)) {
    return(metin)
  }

  paste0(PK_USER_ERROR_PREFIX, " **Veritabanı Hatası:** ", metin)
}

#' Ham hatayı sunucu loguna yaz, kullanıcıya güvenli metni döndür
#'
#' Ayrıntı KAYBOLMAZ; yalnızca yer değiştirir. Operatör tanılamayı sunucu
#' günlüğünden okur, kullanıcı ise genel mesajı görür.
pk_report_db_error <- function(raw_message, context_label = "PK_ANALIZ",
                               context_detail = NULL) {
  ham <- as.character(raw_message %||% "")[1]
  if (is.na(ham)) ham <- ""

  # Aynı kapalı-başarısız kural sunucu logu için de geçerlidir: redaktör hata
  # verdiğinde ham metin DİSKE YAZILMAZ.
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    ham <- tryCatch(redact_sensitive_text(ham),
                    error = function(e) "[redaksiyon basarisiz - ham metin gizlendi]")
  }

  try(
    cat(sprintf(
      "[%s] VERITABANI HATASI (kullaniciya gosterilmedi)%s: %s\n",
      context_label,
      if (is.null(context_detail)) "" else sprintf(" | %s", as.character(context_detail)[1]),
      ham
    )),
    silent = TRUE
  )

  pk_safe_error_message(raw_message)
}
