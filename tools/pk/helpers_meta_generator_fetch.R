# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_fetch.R
# Açıklama: Faz 3b metadata üreticisi -- ŞEMA GETİRME (enjekte edilmiş DB).
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# NEDEN AYRI DOSYA: envanter DÖNGÜSÜ (hangi sorgu, hangi sırayla, hangi karar)
# ile ŞEMA GETİRME (tanımlayıcı mı örnekleme mi, hata sınıfı ne) iki ayrı
# sorumluluktur; ikisi tek dosyada büyüdüğünde ne okunur ne de ayrı ayrı test
# edilebilir kalır.
#
# DB erişimi ENJEKTE EDİLİR (`describe_fn`, `sample_fn`); buradaki hiçbir kod
# gerçek bir veritabanı OLMADAN test edilemez değildir.
# ==============================================================================

# Enjekte edilen işlevler FARKLI ARİTEDE olabilir: testler `function(conn, sql)`
# geçirir, üretim enjeksiyonu zaman aşımı/tavan gibi ek argümanlar kabul eder.
# Ek argümanlar YALNIZCA hedef işlev onları beyan ettiğinde geçirilir; böylece
# hem belgelenen sade sözleşme hem de üretim sınırları çalışır.
.pkgn_call_injected <- function(fn, positional = list(), optional = list()) {
  arglar <- tryCatch(names(formals(fn)), error = function(e) NULL)
  if (is.null(arglar)) arglar <- character(0)
  if (length(optional)) {
    kabul <- if ("..." %in% arglar) {
      rep(TRUE, length(optional))
    } else {
      names(optional) %in% arglar
    }
    optional <- optional[kabul]
  }
  # `quote = TRUE`: argümanlar ZATEN değerlerdir (bağlantı nesnesi, metin, sayı).
  # Tırnaksız `do.call` bunları çağrı içine gömüp yeniden değerlendirir; bir
  # bağlantı nesnesi için bu gereksiz ve kırılgandır.
  do.call(fn, c(positional, optional), quote = TRUE)
}

# BAĞLANTI SEVİYESİNDE OLDUĞU ANLAŞILAN hata kalıpları. Böyle bir hatadan sonra
# önbelleğe alınmış tutamaç ARTIK GEÇERSİZDİR; bırakılıp yenisi açılmalıdır,
# aksi hâlde aynı hedefteki TÜM sonraki sorgular da düşer.
#
# `HYT00` BU LİSTEDE DEĞİLDİR. ODBC'de `HYT00` genel SORGU ZAMAN AŞIMI,
# `HYT01` ise BAĞLANTI zaman aşımıdır. Bu kod yolu, bağlantı ZATEN alındıktan
# sonra bir describe/sample çağrısı zaman aşımına uğradığında çalışır; `HYT00`
# bağlantı hatası sayılırsa HER olağan ifade zaman aşımı hâlâ KULLANILABİLİR bir
# tutamacı düşürür ve yavaş bir sorgu, bağlantı çalkalanmasına dönüşür.
.PKGN_CONNECTION_ERROR_PATTERN <- paste(
  "08s01", "08001", "08003", "08004", "hyt01",
  "communication link", "connection is closed", "connection was closed",
  "not connected", "server is not found", "login timeout", "broken pipe",
  sep = "|"
)

# YERELDEN BAĞIMSIZ ASCII küçük harf.
#
# Kalıplar ASCII'dir; `tolower()` ise YERELE BAĞLIDIR. Türkçe Windows VM'inde
# büyük `I` noktasız `ı` olur ve `COMMUNICATION LINK ...` / `LOGIN TIMEOUT ...`
# gibi mesajlar bu kalıpları KAÇIRIR. O durumda ölü tutamaç `baglantilar`
# içinde kalır ve o hedefteki sonraki HER sorgu aynı ölü tutamaçla düşer.
.pkgn_ascii_lower <- function(x) {
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) return(pk_ascii_lower(x))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

.pkgn_is_connection_error <- function(message) {
  ham <- as.character(message %||% "")[1]
  if (is.na(ham) || !nzchar(ham)) return(FALSE)
  grepl(.PKGN_CONNECTION_ERROR_PATTERN, .pkgn_ascii_lower(ham),
        perl = TRUE, useBytes = TRUE)
}

# Enjekte edilen `connect_fn` sözleşmesi "bağlantı nesnesi ya da NULL" der.
# Uygulamanın `get_connection()` işlevi `list(conn = , pooled = )` sarmalayıcısı
# döndürür; ham bir `DBIConnection` ise LİSTE DEĞİLDİR ve `$conn` erişimi
# üzerinde HATA verir. Bu yüzden sarmalayıcı olup olmadığı ÖNCE sınanır.
.pkgn_unwrap_connection <- function(handle) {
  if (is.null(handle)) return(NULL)
  if (inherits(handle, "DBIConnection")) return(handle)
  if (is.list(handle) && !is.null(handle$conn)) return(handle$conn)
  handle
}

# `describe` çağrısını yap ve SONUCU ile HATASINI AYIR.
#
# Üretim tanımlayıcı işlevi hataları yutup `NULL` döndürebildiği için varsayılan
# enjeksiyon (helpers_meta_generator_db.R) gerçek hatayı YÜKSELTİR; böylece
# "bu sorgu tanımlanamıyor" ile "sonda BAŞARISIZ oldu" ayrı kalır.
.pkgn_describe <- function(query, config, conn, describe_fn) {
  tryCatch(
    .pkgn_call_injected(
      describe_fn,
      positional = list(conn, query$sql),
      optional = list(timeout_sec = config$sql_timeout_sec)
    ),
    error = function(e) e
  )
}

#' Şema getir (kip bazlı)
#'
#' @param connect_error Bağlantı EDİNİMİ sırasında yakalanmış güvenli hata
#'   özeti. `connect_fn()` düştüğünde çağıran yalnızca `NULL` bağlantı görür;
#'   kimlik doğrulama hatası, eksik ODBC sürücüsü, oturum açma zaman aşımı ve
#'   havuz checkout hatası bu bilgi olmadan `health.json` içinde AYIRT
#'   EDİLEMEZ hâle gelirdi.
pkgn_fetch_schema <- function(query, config, conn, describe_fn, sample_fn,
                              connect_error = NULL) {
  hata_sonucu <- function(code, detail, error = NULL, connection_error = FALSE) {
    list(ok = FALSE, code = code, detail = detail,
         error = if (is.null(error)) NULL else pkgh_db_error_summary(error),
         connection_error = isTRUE(connection_error))
  }

  if (is.null(conn)) {
    return(list(
      ok = FALSE, code = "no_connection",
      detail = sprintf("'%s' hedefi icin DB baglantisi kurulamadi; sorgu Tier-0 kaldi.",
                       as.character(query$db_target %||% "primary")[1]),
      # Edinim hatası ZATEN güvenli özet biçimindedir; ikinci kez özetlemek
      # sınıf bilgisini kaybettirirdi.
      error = if (is.null(connect_error)) NULL else as.character(connect_error)[1],
      connection_error = FALSE
    ))
  }

  if (identical(config$mode, "describe")) {
    return(.pkgn_fetch_describe(query, config, conn, describe_fn, hata_sonucu))
  }
  .pkgn_fetch_sample(query, config, conn, describe_fn, sample_fn, hata_sonucu)
}

.pkgn_fetch_describe <- function(query, config, conn, describe_fn, hata_sonucu) {
  tanimlayici <- .pkgn_describe(query, config, conn, describe_fn)
  if (inherits(tanimlayici, "condition")) {
    return(hata_sonucu("describe_failed",
                       paste0(
                         "Sonuc kumesi tanimlayicisi ALINAMADI (sonda hatasi). ",
                         "Bu, 'bu sorgu tanimlanamiyor' ile AYNI SEY DEGILDIR."
                       ),
                       conditionMessage(tanimlayici),
                       connection_error = .pkgn_is_connection_error(
                         conditionMessage(tanimlayici))))
  }
  if (is.null(tanimlayici) || !length(tanimlayici)) {
    return(hata_sonucu(
      "describe_unavailable",
      paste0(
        "sys.dm_exec_describe_first_result_set bu sorgu icin sema donduremedi ",
        "(gecici tablo, dinamik SQL ya da belirsiz sonuc kumesi olabilir). ",
        "'sample' kipi bu sorgu icin gerekebilir."
      )
    ))
  }

  cikarim <- pkgs_schema_from_descriptor(tanimlayici)
  if (is.null(cikarim)) {
    return(hata_sonucu("describe_empty_schema",
                       "Tanimlayici bos/gecersiz sema dondurdu."))
  }
  if (!isTRUE(cikarim$ok)) {
    return(hata_sonucu("describe_invalid_schema", .pkgn_invalid_schema_detail(cikarim)))
  }

  ornek_bilgi <- list(mode = "describe", executed = FALSE)
  list(
    ok = TRUE,
    schema = cikarim$schema,
    source_types = cikarim$source_types,
    unmapped = cikarim$unmapped,
    unbounded = cikarim$unbounded,
    observations = list(),
    sample_info = ornek_bilgi,
    cache = list(mode = "describe", columns = cikarim$schema,
                 source_types = cikarim$source_types,
                 unmapped = cikarim$unmapped, unbounded = cikarim$unbounded,
                 observations = list(), sample_info = ornek_bilgi)
  )
}

.pkgn_invalid_schema_detail <- function(cikarim) {
  sprintf(paste0(
    "Tanimlayici KULLANILAMAZ sutun(lar) bildirdi: %s. Adsiz bir sonuc ",
    "sutunu dusurulup 'kismi' sema yazmak, baslangic dogrulamasini gecen ",
    "ama gercek sonucla UYUSMAYAN metadata uretirdi."
  ), paste(cikarim$invalid, collapse = ", "))
}

.pkgn_fetch_sample <- function(query, config, conn, describe_fn, sample_fn, hata_sonucu) {
  # NATİF TİPLER: R sınıfı `nvarchar(max)`, `xml` ya da eşlenmeyen bir tipi
  # AYIRT EDEMEZ. Tanımlayıcı (sorguyu ÇALIŞTIRMAYAN) bu bilgiyi verir; bu
  # yüzden önce denenir.
  natif <- NULL
  genislikler <- NULL
  tanimlayici <- .pkgn_describe(query, config, conn, describe_fn)

  if (!inherits(tanimlayici, "condition") && is.list(tanimlayici) && length(tanimlayici)) {
    aday <- pkgs_schema_from_descriptor(tanimlayici)

    # YAPISAL OLARAK GEÇERSİZ BİR TANIMLAYICI, "NATİF BİLGİ YOK" İLE AYNI ŞEY
    # DEĞİLDİR.
    #
    # `ok = FALSE`, tanımlayıcının KULLANILAMAZ bir sonuç şekli (örneğin ADSIZ
    # bir sonuç sütunu) POZİTİF olarak kanıtladığı durumdur; `describe` kipi
    # bunu bilerek REDDEDER. Sessizce örneklemeye düşmek, DBI'ın uydurduğu
    # `V1`/`NA.` gibi adlarla o yapısal reddi ATLAYAN bir şema yayımlardı.
    if (!is.null(aday) && !isTRUE(aday$ok)) {
      return(hata_sonucu("describe_invalid_schema", .pkgn_invalid_schema_detail(aday)))
    }
    if (!is.null(aday) && isTRUE(aday$ok)) {
      natif <- aday$source_types
      genislikler <- aday$widths
    }
  }

  cerceve <- tryCatch(
    .pkgn_call_injected(
      sample_fn,
      positional = list(conn, query$sql, config$sample_rows),
      optional = list(timeout_sec = config$sql_timeout_sec,
                      max_result_mb = config$max_result_mb,
                      sample_unicode = isTRUE(config$sample_unicode))
    ),
    error = function(e) e
  )

  if (inherits(cerceve, "condition")) {
    return(hata_sonucu("sample_failed", "Sorgu orneklenemedi.",
                       conditionMessage(cerceve),
                       connection_error = .pkgn_is_connection_error(
                         conditionMessage(cerceve))))
  }
  if (!is.data.frame(cerceve)) {
    return(hata_sonucu("sample_not_dataframe", "Ornekleme data.frame dondurmedi."))
  }
  if (!ncol(cerceve)) {
    return(hata_sonucu("sample_no_columns", "Ornek sonucunda sutun yok."))
  }

  cikarim <- pkgs_schema_from_dataframe(cerceve, column_types = natif,
                                        column_widths = genislikler)
  if (is.null(cikarim)) {
    return(hata_sonucu("sample_invalid_schema", "Ornek sonucundan gecerli sema cikarilamadi."))
  }

  gozlemler <- pkgs_sample_observations(
    cerceve, config$high_cardinality_threshold, method = "prefix"
  )

  satir <- nrow(cerceve)
  ornek_bilgi <- list(
    mode = "sample",
    executed = TRUE,
    method = "prefix",
    rows_seen = satir,
    native_types_available = !is.null(natif),
    # DÜRÜSTLÜK: `dbFetch(n = )` bir AKTARIM sınırdır. `dbSendQuery()` SELECT'i
    # çalıştırır; büyük bir birleştirme/ORDER BY bu satırlar çekilmeden ÖNCE
    # sunucuda tamamlanabilir. Gerçek koruma zaman aşımı ve bayt tavanıdır.
    server_bounded = FALSE,
    bound_kind = "transfer_only",
    # 500 satırlık bir örnek 501 satırlık sonucu 5 milyondan AYIRT EDEMEZ.
    # Bu yüzden satır sayısı tavana değdiğinde yalnızca ALT SINIR bildirilir
    # ve row_cap geçti/kaldı iddiası ÜRETİLMEZ.
    row_count_is_lower_bound = satir >= config$sample_rows,
    cardinality_claim = "unknown"
  )

  list(
    ok = TRUE,
    schema = cikarim$schema,
    source_types = cikarim$source_types,
    unmapped = cikarim$unmapped,
    unbounded = cikarim$unbounded,
    observations = gozlemler,
    sample_info = ornek_bilgi,
    cache = list(mode = "sample", columns = cikarim$schema,
                 source_types = cikarim$source_types, rows_seen = satir,
                 unmapped = cikarim$unmapped, unbounded = cikarim$unbounded,
                 observations = gozlemler, sample_info = ornek_bilgi)
  )
}
