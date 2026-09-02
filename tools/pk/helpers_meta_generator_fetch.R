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

# Runtime `convert_date_columns()` çağrısını metadata kapısından ÖNCE yapar.
# Dolayısıyla query$date_columns içinde AÇIKÇA beyan edilen bir sütunun ham SQL
# tipi varchar/character olsa bile metadata kapısının gördüğü etkin sınıf Date
# olur. Üretici ham şemayı kalıcılaştırırsa çalışma zamanı sözleşmesine göre
# geçerli bir role=date küresyonunu yanlışlıkla geri çeker. Burada yalnızca
# sorguda birebir adı geçen sütunlar dönüştürülür; isimler trimlenmez/uydurulmaz.
.pkgn_apply_declared_date_schema <- function(query, schema) {
  sonuc <- schema
  if (is.null(sonuc) || !length(sonuc) || is.null(names(sonuc))) return(sonuc)

  tarih <- query$date_columns %||% character(0)
  if (!is.character(tarih) || !length(tarih)) return(sonuc)
  tarih <- tarih[!is.na(tarih) & nzchar(tarih)]

  for (sutun in intersect(tarih, names(sonuc))) {
    sonuc[[sutun]] <- "Date"
  }
  sonuc
}

# Üretim örneklemesi `dbFetch(n=...)` ile yalnızca AKTARIMI sınırlar; SQL Server
# JOIN/ORDER BY çalışmasını n satırdan önce tamamlamak zorunda değildir. Bu
# nedenle GERÇEK varsayılan sample yolu yalnızca sorgu kütüphanesinde açıkça
# güvenli olarak küratörlenmiş sorgularda çalıştırılır. Test enjeksiyonları bu
# operatör kapısından etkilenmez; onlar DB iş yükü çalıştırmaz.
.pkgn_default_sample_is_explicitly_safe <- function(query, sample_fn) {
  varsayilan <- exists("pkg_default_sample_fn", mode = "function", inherits = TRUE) &&
    identical(sample_fn, get("pkg_default_sample_fn", mode = "function", inherits = TRUE))
  !varsayilan || isTRUE(query$meta_sample_safe)
}

# SQL Server'in statik sonuc tanimlayicisi ayni batch icinde olusturulan #temp
# tablolarini cozumleyemez. D23 kapisi batch'in YALNIZCA yerel #temp staging
# yaptigini kanitladiysa metadata icin sorgu CALISTIRILMADAN esdeger bir CTE
# zinciri kurulur. Uygulama ve sample yolu her zaman ORIJINAL SQL'i kullanir.
.pkgn_local_temp_replace_token <- function(sql, token, replacement) {
  metin <- as.character(sql %||% "")[1]
  if (is.na(metin)) metin <- ""

  maske <- pk_sql_mask_literals(metin)
  if (!isTRUE(maske$ok)) {
    stop("[PK_META_GEN] Yerel #temp metadata donusumunde SQL maskelenemedi.", call. = FALSE)
  }

  kalip <- paste0(
    "(?<![A-Za-z0-9_@#$])", token,
    "(?![A-Za-z0-9_@#$])"
  )
  yerler <- gregexpr(kalip, maske$masked, ignore.case = TRUE, perl = TRUE)[[1]]
  if (length(yerler) == 1L && identical(yerler[1], -1L)) return(metin)
  uzunluklar <- attr(yerler, "match.length")

  sonuc <- metin
  for (j in rev(seq_along(yerler))) {
    bas <- as.integer(yerler[j])
    uzunluk <- as.integer(uzunluklar[j])
    if (is.na(bas) || bas < 1L || is.na(uzunluk) || uzunluk < 1L) {
      stop("[PK_META_GEN] Yerel #temp metadata token konumu belirsiz.", call. = FALSE)
    }
    son <- bas + uzunluk - 1L
    oncesi <- if (bas > 1L) substr(sonuc, 1L, bas - 1L) else ""
    sonrasi <- if (son < nchar(sonuc, type = "chars")) {
      substr(sonuc, son + 1L, nchar(sonuc, type = "chars"))
    } else {
      ""
    }
    sonuc <- paste0(oncesi, replacement, sonrasi)
  }
  sonuc
}

.pkgn_local_temp_strip_into <- function(stage_sql, temp_name) {
  metin <- as.character(stage_sql %||% "")[1]
  if (is.na(metin) || !nzchar(trimws(metin))) {
    stop("[PK_META_GEN] Yerel #temp staging SQL bos.", call. = FALSE)
  }

  maske <- pk_sql_mask_literals(metin)
  if (!isTRUE(maske$ok)) {
    stop("[PK_META_GEN] Yerel #temp staging SQL maskelenemedi.", call. = FALSE)
  }

  kalip <- paste0(
    "(?<![A-Za-z0-9_@#$])INTO[ \\t\\r\\n]+",
    temp_name,
    "(?![A-Za-z0-9_@#$])"
  )
  yerler <- gregexpr(kalip, maske$masked, ignore.case = TRUE, perl = TRUE)[[1]]
  if (length(yerler) != 1L || identical(yerler[1], -1L)) {
    stop("[PK_META_GEN] Yerel #temp staging INTO hedefi tekil degil.", call. = FALSE)
  }
  uzunluk <- as.integer(attr(yerler, "match.length")[1])
  bas <- as.integer(yerler[1])
  son <- bas + uzunluk - 1L

  oncesi <- if (bas > 1L) substr(metin, 1L, bas - 1L) else ""
  sonrasi <- if (son < nchar(metin, type = "chars")) {
    substr(metin, son + 1L, nchar(metin, type = "chars"))
  } else {
    ""
  }
  trimws(paste0(oncesi, " ", sonrasi))
}

.pkgn_local_temp_describe_sql <- function(sql) {
  if (!exists("pk_sql_analyze_local_temp_batch", mode = "function", inherits = TRUE)) {
    return(sql)
  }

  plan <- pk_sql_analyze_local_temp_batch(sql)
  if (!is.list(plan) || !isTRUE(plan$ok)) return(sql)
  if (!length(plan$temp_names) || length(plan$temp_names) != length(plan$staging_sql)) {
    stop("[PK_META_GEN] Yerel #temp metadata plani tutarsiz.", call. = FALSE)
  }

  sonuc_turu <- if (.pk_sql_starts_with_word(plan$result_sql, "SELECT")) {
    "select"
  } else if (.pk_sql_starts_with_word(plan$result_sql, "WITH")) {
    "cte"
  } else {
    stop("[PK_META_GEN] Yerel #temp metadata donusumu final SELECT/CTE gerektirir.",
         call. = FALSE)
  }

  # CTE adlari sabittir ama SQL'de zaten kullaniliyorsa semantigi degistirmemek
  # icin fail-closed. Arama literal/yorum disindaki maskelenmis kodda yapilir.
  tum_sql <- paste(c(plan$staging_sql, plan$result_sql), collapse = "\n")
  tum_maske <- pk_sql_mask_literals(tum_sql)
  if (!isTRUE(tum_maske$ok)) {
    stop("[PK_META_GEN] Yerel #temp metadata plani maskelenemedi.", call. = FALSE)
  }

  cte_adlari <- sprintf("__pk_meta_local_temp_%03d", seq_along(plan$temp_names))
  for (ad in cte_adlari) {
    if (.pk_sql_has_word(tum_maske$masked, ad)) {
      stop("[PK_META_GEN] Yerel #temp metadata CTE adi sorguyla cakisti.", call. = FALSE)
    }
  }

  staging <- character(length(plan$staging_sql))
  for (i in seq_along(plan$staging_sql)) {
    parca <- .pkgn_local_temp_strip_into(plan$staging_sql[[i]], plan$temp_names[[i]])
    for (j in seq_along(plan$temp_names)) {
      parca <- .pkgn_local_temp_replace_token(parca, plan$temp_names[[j]], cte_adlari[[j]])
    }
    staging[[i]] <- parca
  }

  sonuc <- plan$result_sql
  for (j in seq_along(plan$temp_names)) {
    sonuc <- .pkgn_local_temp_replace_token(sonuc, plan$temp_names[[j]], cte_adlari[[j]])
  }

  cte <- vapply(seq_along(staging), function(i) {
    paste0(cte_adlari[[i]], " AS (\n", staging[[i]], "\n)")
  }, character(1))

  if (identical(sonuc_turu, "select")) {
    return(paste0("WITH ", paste(cte, collapse = ",\n"), "\n", sonuc))
  }

  # Final sorgu zaten WITH ile basliyorsa ikinci bir WITH yazmak T-SQL'i bozar.
  # Staging CTE'leri mevcut CTE zincirinin BASINA virgulle eklenir. Bu yalnizca
  # describe metnidir; runtime ve sample orijinal batch'i kullanmaya devam eder.
  # BASTAKI BOSLUK TOLERE EDILIR. Siniflandirma (`.pk_sql_starts_with_word()`)
  # bastaki bosluk/yeni satiri tolere ediyor; bu degistirme etmiyordu. Yeni
  # satirla ya da bosluklarla baslayan bir `result_sql` "cte" siniflandirilip
  # ardindan "final CTE govdesi ayristirilamadi" ile REDDEDILIYOR ve sorgu
  # yalnizca BICIMLENDIRME nedeniyle describe metadata'sini kaybediyordu.
  sonuc_cte <- sub("^[ \\t\\r\\n]*WITH[ \\t\\r\\n]+", "", sonuc,
                   ignore.case = TRUE, perl = TRUE)
  if (!nzchar(trimws(sonuc_cte)) || identical(sonuc_cte, sonuc)) {
    stop("[PK_META_GEN] Yerel #temp final CTE govdesi ayristirilamadi.", call. = FALSE)
  }
  paste0("WITH ", paste(cte, collapse = ",\n"), ",\n", sonuc_cte)
}

# `describe` çağrısını yap ve SONUCU ile HATASINI AYIR.
#
# Üretim tanımlayıcı işlevi hataları yutup `NULL` döndürebildiği için varsayılan
# enjeksiyon (helpers_meta_generator_db.R) gerçek hatayı YÜKSELTİR; böylece
# "bu sorgu tanımlanamıyor" ile "sonda BAŞARISIZ oldu" ayrı kalır.
# Yerel #temp batch'lerde yalnızca TANIMLAMA metni esdeger CTE'ye donusturulur;
# DB'de #temp olusturulmaz ve örnekleme/çalışma zamanı SQL'i değiştirilmez.
.pkgn_describe <- function(query, config, conn, describe_fn) {
  describe_sql <- tryCatch(.pkgn_local_temp_describe_sql(query$sql), error = function(e) e)
  if (inherits(describe_sql, "condition")) {
    # YEREL YENIDEN YAZIM HATASI SONDA HATASI DEGILDIR: bu kosul DB'ye HIC
    # gitmeden olusur (or. yerel `#temp` metadata CTE adi sorguyla cakisir).
    # Isaretlenmezse `describe_failed` olarak raporlaniyor ve operator
    # `health.json` uzerinden sorgu metni yerine BAGLANTI/sonda sorunu ariyordu.
    class(describe_sql) <- c("pkgn_describe_rewrite_error", class(describe_sql))
    return(describe_sql)
  }

  tryCatch(
    .pkgn_call_injected(
      describe_fn,
      positional = list(conn, describe_sql),
      optional = list(
        timeout_sec = config$sql_timeout_sec,
        # Ad kurtarma GERÇEK sorguyu açar; örnek yoluyla AYNI operatör kapısı.
        allow_runtime_names = isTRUE(query$meta_sample_safe)
      )
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
  if (inherits(tanimlayici, "pkgn_describe_rewrite_error")) {
    # YEREL YENIDEN YAZIM HATASI BIR SURUCU HATASI DEGILDIR (PR #705 inceleme, P3).
    #
    # `hata_sonucu()` her `error` argumanini `pkgh_db_error_summary()` icinden
    # gecirir; bu metin ise DB'ye hic ulasmadan `.pkgn_local_temp_describe_sql()`
    # tarafindan URETILIR. Ozetleyici hicbir surucu sinifina eslemedigi icin
    # "DB hatasi (sinif=unknown)" yaziyor ve operatorun TEK ipucu olan yapisal
    # sebep (`Yerel #temp metadata CTE adi sorguyla cakisti.`) SILINIYORDU --
    # ustelik yukaridaki `detail` metni "bulgu sorgu metnindedir" diyordu.
    # Metin ureticinin KENDI yazdigi yapisal aciklamadir ve uretim satir degeri
    # TASIMAZ; `.pkgh_redact()` bu yuzden yeterlidir.
    return(list(
      ok = FALSE, code = "describe_rewrite_failed",
      detail = paste0(
        "Yerel `#temp` describe donusumu BASARISIZ; DB'ye sorgu GONDERILMEDI. ",
        "Bulgu SORGU METNINDEDIR, baglantida DEGIL."
      ),
      error = .pkgh_redact(conditionMessage(tanimlayici)),
      connection_error = FALSE
    ))
  }
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

  etkin_sema <- .pkgn_apply_declared_date_schema(query, cikarim$schema)
  ornek_bilgi <- list(mode = "describe", executed = FALSE)
  list(
    ok = TRUE,
    schema = etkin_sema,
    source_types = cikarim$source_types,
    unmapped = cikarim$unmapped,
    unbounded = cikarim$unbounded,
    duplicate_columns = cikarim$duplicate_columns,  # TEKRAR EDEN SONUC SUTUNU: semayi gecersiz kilmaz (guvenlik yolu korunur), envanter dongusunde AYRI bir bulguya donusur.
    observations = list(),
    sample_info = ornek_bilgi,
    cache = list(mode = "describe", columns = etkin_sema,
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

  # Gerçek üretim sample yolu, sunucu iş yükü açıkça güvenli olarak
  # küratörlenmedikçe ÇALIŞTIRILMAZ. `sample_rows` yalnızca dbFetch aktarım
  # tavanıdır; bunu iş yükü sınırı gibi yorumlamak güvenli değildir.
  if (!.pkgn_default_sample_is_explicitly_safe(query, sample_fn)) {
    return(hata_sonucu(
      "sample_not_server_bounded",
      paste0(
        "Sample kipi bu sorgu icin CALISTIRILMADI: dbFetch(n) yalnizca aktarimi ",
        "sinirlar; tam SELECT sunucuda buyuk JOIN/ORDER BY calismasi yapabilir. ",
        "Yalnizca query$meta_sample_safe = TRUE olarak ACIKCA kure edilmis ",
        "sorgular uretim veritabaninda orneklenebilir."
      )
    ))
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

  etkin_sema <- .pkgn_apply_declared_date_schema(query, cikarim$schema)
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
    # Satır sayısı hâlâ AKTARIM sınırıdır; güvenlik, üretim sample yolunun
    # yalnızca açıkça güvenli diye küratörlenmiş sorgularda çalışmasıdır.
    server_bounded = FALSE,
    bound_kind = "explicit_safe_query_gate",
    explicitly_sample_safe = isTRUE(query$meta_sample_safe),
    # 500 satırlık bir örnek 501 satırlık sonucu 5 milyondan AYIRT EDEMEZ.
    # Bu yüzden satır sayısı tavana değdiğinde yalnızca ALT SINIR bildirilir
    # ve row_cap geçti/kaldı iddiası ÜRETİLMEZ.
    row_count_is_lower_bound = satir >= config$sample_rows,
    cardinality_claim = "unknown"
  )

  list(
    ok = TRUE,
    schema = etkin_sema,
    source_types = cikarim$source_types,
    unmapped = cikarim$unmapped,
    unbounded = cikarim$unbounded,
    observations = gozlemler,
    sample_info = ornek_bilgi,
    cache = list(mode = "sample", columns = etkin_sema,
                 source_types = cikarim$source_types, rows_seen = satir,
                 unmapped = cikarim$unmapped, unbounded = cikarim$unbounded,
                 observations = gozlemler, sample_info = ornek_bilgi)
  )
}
