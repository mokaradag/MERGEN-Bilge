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

  riskli <- any(vapply(
    PK_UNSAFE_ERROR_PATTERNS,
    function(kalip) grepl(kalip, metin, fixed = TRUE, useBytes = TRUE),
    logical(1)
  ))

  if (riskli) {
    return(PK_GENERIC_DB_ERROR_MESSAGE)
  }

  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    metin <- tryCatch(redact_sensitive_text(metin), error = function(e) metin)
  }

  metin
}

#' Ham hatayı sunucu loguna yaz, kullanıcıya güvenli metni döndür
#'
#' Ayrıntı KAYBOLMAZ; yalnızca yer değiştirir. Operatör tanılamayı sunucu
#' günlüğünden okur, kullanıcı ise genel mesajı görür.
pk_report_db_error <- function(raw_message, context_label = "PK_ANALIZ",
                               context_detail = NULL) {
  ham <- as.character(raw_message %||% "")[1]
  if (is.na(ham)) ham <- ""

  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    ham <- tryCatch(redact_sensitive_text(ham), error = function(e) ham)
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
