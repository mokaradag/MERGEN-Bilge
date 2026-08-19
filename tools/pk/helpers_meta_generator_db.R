# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_db.R
# Açıklama: Faz 3b metadata üreticisi -- VARSAYILAN DB ENJEKSİYONLARI.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# Envanter koşusu DB erişimini ENJEKTE EDER; bu dosya yalnızca VM'de kullanılan
# GERÇEK enjeksiyonları tanımlar. Çevrimdışı testler kendi sahte işlevlerini
# geçirir, dolayısıyla buradaki kod bir DB olmadan ÇALIŞTIRILMAZ.
#
# SERT KURALLAR:
#   * SALT OKUNUR. Veri değiştiren tek bir DBI çağrısı (dbExecute/dbWriteTable/
#     dbRemoveTable/DDL) yoktur. Tek `EXEC`, üretimin de kullandığı
#     `sp_executesql` UNICODE PARAMETRE sarmalayıcısıdır: KAPIDAN GEÇEN SQL
#     metni NVARCHAR(MAX) PARAMETRESİ olarak gönderilir, batch olarak DEĞİL.
#   * BİRİNCİL DSN AÇIKÇA YAPILANDIRILMIŞ OLMALIDIR. Uygulamanın geliştirme
#     yedeği (`TestConnection`) DEVRALINMAZ.
#   * HER BLOKLAYAN ÇAĞRI zaman aşımı ile sınırlanır.
#   * ÖRNEKLEME sonucu BAYT TAVANINA tabidir.
# ==============================================================================

# Bloklayan sürücü çağrısını yapılandırılmış zaman aşımı ile sınırla. Üretimin
# `pk_sql_bounded_call()` sarmalayıcısı varsa o kullanılır (aynı davranış),
# yoksa yerel `setTimeLimit()` yedeği devreye girer.
.pkgd_bounded <- function(fn, timeout_sec = NULL) {
  sinir <- suppressWarnings(as.numeric(timeout_sec)[1])
  if (length(sinir) != 1L || is.na(sinir) || !is.finite(sinir) || sinir <= 0) {
    return(fn())
  }

  if (exists("pk_sql_bounded_call", mode = "function", inherits = TRUE)) {
    sonuc <- pk_sql_bounded_call(fn, budget_fn = function() sinir)
    if (isTRUE(sonuc$ok)) return(sonuc$value)
    stop(sprintf("[PK_META_GEN] DB cagrisi sinirlandi (durum=%s): %s",
                 as.character(sonuc$status)[1],
                 as.character(sonuc$error %||% NA_character_)[1]), call. = FALSE)
  }

  on.exit(try(setTimeLimit(cpu = Inf, elapsed = Inf, transient = TRUE), silent = TRUE),
          add = TRUE)
  setTimeLimit(cpu = Inf, elapsed = sinir, transient = TRUE)
  fn()
}

# SORGU BAŞINA MUTLAK SON TARİH.
#
# `MERGEN_PK_META_SQL_TIMEOUT_SEC` SORGU BAŞINA bir tavandır. Her `dbFetch()`
# çağrısına TAM bütçeyi vermek, `dbSendQuery()` zaten aynı tam bütçeyi almışken,
# tek bir örneklemenin (varsayılan 500 satır / 200'lük parça) yaklaşık DÖRT
# zaman aşımı penceresi tüketmesine yol açar; `sample_rows` büyüdükçe bu katsayı
# da büyür. Bu yüzden bütçe koşunun BAŞINDA mutlak bir son tarihe çevrilir ve
# her bloklayan çağrıya YALNIZCA KALAN süre verilir.
.pkgd_deadline <- function(timeout_sec) {
  sinir <- suppressWarnings(as.numeric(timeout_sec)[1])
  if (length(sinir) != 1L || is.na(sinir) || !is.finite(sinir) || sinir <= 0) {
    return(NULL)
  }
  Sys.time() + sinir
}

.pkgd_remaining <- function(deadline) {
  if (is.null(deadline)) return(NULL)
  kalan <- suppressWarnings(as.numeric(difftime(deadline, Sys.time(), units = "secs")))
  if (length(kalan) != 1L || is.na(kalan)) return(NULL)
  # Bütçe tükendiyse çağrı BAŞLATILMAZ; sıfır/negatif bir sınır `setTimeLimit()`
  # için anlamsızdır ve "sınırsız" gibi davranırdı.
  if (kalan <= 0) {
    stop(paste0(
      "[PK_META_GEN] Sorgu basina zaman butcesi TUKENDI ",
      "(MERGEN_PK_META_SQL_TIMEOUT_SEC). Kalan surucu cagrisi BASLATILMADI."
    ), call. = FALSE)
  }
  kalan
}

# Kalan bütçeyle sınırlı çağrı.
.pkgd_bounded_until <- function(fn, deadline) {
  .pkgd_bounded(fn, .pkgd_remaining(deadline))
}

# Sonuç temizliği için TABAN süre. Bütçe tükenmiş olsa bile açık bir ODBC
# sonucunu iptal etmeye kısa bir şans tanınır; aksi hâlde bağlantı kirli kalır.
.PKGD_CLEANUP_MIN_SEC <- 5

.pkgd_is_sql_server <- function(conn) {
  inherits(conn, "OdbcConnection") || inherits(conn, "Microsoft SQL Server")
}

#' Varsayılan bağlantı açıcı
#'
#' HEDEF DOĞRULANMIŞ OLARAK GELİR (bkz. `pkg_meta_validate_db_target()`).
#' Burada ayrıca DSN'in GERÇEKTEN yapılandırılmış olduğu doğrulanır: uygulamanın
#' `.DEFAULT_DSN = Sys.getenv("DB_DSN", "TestConnection")` geliştirme yedeği,
#' `DB_DSN` tanımsızken üreticiyi YANLIŞ bir veritabanını envanterlemeye
#' götürebilirdi. Üretimden türetilmiş metadata için bu KAPALI BAŞARISIZ olur.
#' @param timeout_sec Yapılandırılmış üretici zaman aşımı. BAĞLANTI EDİNİMİ DE
#'   SINIRLANIR: `get_connection()` / `db_acquire_tx_connection()` bir PK isteği
#'   dışında üreticinin bütçesini BİLMEZ ve kendi sürücü/oturum açma/havuz
#'   bekleme politikasını uygular. Erişilemeyen bir DSN ya da tıkanmış bir havuz
#'   checkout'u, sınırlı hiçbir describe/fetch çağrısı BAŞLAMADAN koşuyu
#'   kilitleyebilirdi -- oysa operatör sözleşmesi "her bloklayan sürücü çağrısı
#'   sınırlıdır" der.
pkg_default_connect_fn <- function(target = "primary", timeout_sec = NULL) {
  dogrulama <- pkg_meta_validate_db_target(target)
  if (!isTRUE(dogrulama$ok)) {
    stop(sprintf("[PK_META_GEN] %s", dogrulama$detail), call. = FALSE)
  }

  dsn_degiskeni <- dogrulama$env_var
  dsn <- trimws(Sys.getenv(dsn_degiskeni, unset = ""))
  if (!nzchar(dsn)) {
    stop(sprintf(paste0(
      "[PK_META_GEN] '%s' hedefi icin %s tanimli degil. Uretici uygulamanin ",
      "gelistirme yedegini DEVRALMAZ; uretim metadata'si yanlis bir ",
      "veritabanindan uretilemez. .Renviron dosyasina %s ekleyin."
    ), dogrulama$target, dsn_degiskeni, dsn_degiskeni), call. = FALSE)
  }

  # HAVUZ AKTİFSE GERÇEK BİR BAĞLANTI ÖDÜNÇ ALINIR.
  #
  # `get_connection("primary")` havuz açıkken canlı `Pool` NESNESİNİ döndürür;
  # `pk_sql_describe_result_schema()` ise Pool'u OdbcConnection saymadığı için
  # doğrudan NULL döner ve TÜM birincil sorgular "describe_unavailable" olurdu.
  if (exists("db_acquire_tx_connection", mode = "function", inherits = TRUE) &&
      exists("is_db_pool_enabled", mode = "function", inherits = TRUE) &&
      isTRUE(tryCatch(is_db_pool_enabled(), error = function(e) FALSE))) {
    return(.pkgd_bounded(function() db_acquire_tx_connection(dogrulama$target), timeout_sec))
  }

  if (!exists("get_connection", mode = "function", inherits = TRUE)) {
    stop("[PK_META_GEN] get_connection bulunamadi; uygulama bootstrap'i yuklenmedi.",
         call. = FALSE)
  }
  .pkgd_bounded(function() get_connection(dogrulama$target), timeout_sec)
}

#' @param timeout_sec Bırakma da SINIRLIDIR: havuza iade ya da `dbDisconnect()`
#'   kirli/ölü bir tutamaçta bloklayabilir. Bütçe verilmediğinde taban temizlik
#'   süresi uygulanır; sonsuza dek beklemek koşuyu kilitlerdi.
pkg_default_release_fn <- function(handle, timeout_sec = NULL) {
  if (is.null(handle)) return(invisible(NULL))

  sinir <- suppressWarnings(as.numeric(timeout_sec)[1])
  if (length(sinir) != 1L || is.na(sinir) || !is.finite(sinir) || sinir <= 0) {
    sinir <- .PKGD_CLEANUP_MIN_SEC
  }

  if (is.list(handle) && isTRUE(handle$checked_out) &&
      exists("db_release_tx_connection", mode = "function", inherits = TRUE)) {
    return(invisible(tryCatch(
      .pkgd_bounded(function() db_release_tx_connection(handle), sinir),
      error = function(e) NULL
    )))
  }

  if (exists("release_connection", mode = "function", inherits = TRUE)) {
    return(invisible(tryCatch(
      .pkgd_bounded(function() release_connection(handle), sinir),
      error = function(e) NULL
    )))
  }
  invisible(NULL)
}

.pkgd_descriptor_params <- function(sql) {
  if (exists("normalize_db_params", mode = "function", inherits = TRUE)) {
    return(tryCatch(normalize_db_params(list(sql)), error = function(e) list(sql)))
  }
  list(sql)
}

.pkgd_descriptor_error_detail <- function(cerceve) {
  if (!is.data.frame(cerceve) || !nrow(cerceve) || !("error_number" %in% names(cerceve))) {
    return(NULL)
  }
  idx <- which(!is.na(cerceve$error_number))
  if (!length(idx)) return(NULL)
  i <- idx[[1L]]
  no <- suppressWarnings(as.integer(cerceve$error_number[i]))
  tur <- if ("error_type_desc" %in% names(cerceve)) as.character(cerceve$error_type_desc[i]) else NA_character_
  mesaj <- if ("error_message" %in% names(cerceve)) as.character(cerceve$error_message[i]) else NA_character_
  paste0(
    "SQL Server sonuc tanimlayicisi hata bildirdi",
    if (!is.na(no)) sprintf(" (hata_no=%d)", no) else "",
    if (!is.na(tur) && nzchar(tur)) sprintf(" (tur=%s)", tur) else "",
    if (!is.na(mesaj) && nzchar(mesaj)) paste0(": ", mesaj) else "."
  )
}

.pkgd_repair_descriptor_names <- function(cerceve, runtime_names) {
  if (!is.data.frame(cerceve) || !nrow(cerceve) || !("name" %in% names(cerceve))) {
    stop("[PK_META_GEN] Tanimlayici ad onarimi icin gecerli bir cerceve yok.", call. = FALSE)
  }
  adlar <- as.character(cerceve$name)
  eksik <- is.na(adlar) | !nzchar(adlar)
  if (!any(eksik)) return(cerceve)

  runtime_names <- as.character(runtime_names)
  if (length(runtime_names) != nrow(cerceve)) {
    stop(sprintf(
      paste0(
        "[PK_META_GEN] Runtime kolon metadata'si tanimlayici ile AYNI sayida sutun ",
        "dondurmedi (tanimlayici=%d, runtime=%d); sema uydurulmadi."
      ),
      nrow(cerceve), length(runtime_names)
    ), call. = FALSE)
  }
  if (any(is.na(runtime_names[eksik]) | !nzchar(runtime_names[eksik]))) {
    stop(paste0(
      "[PK_META_GEN] SQL Server statik tanimlayicisinin adini belirleyemedigi ",
      "sutunlar runtime sonuc metadata'sinda da ADSIZ; sema uydurulmadi."
    ), call. = FALSE)
  }

  cerceve$name[eksik] <- runtime_names[eksik]
  cerceve
}

# Statik SQL Server tanımlayıcısı bazen çalışan bir SELECT'in sonuç adını NULL
# bırakabilir. Bu durumda 170 sorgu tanımına tek tek özel metadata eklemek yerine
# yalnızca sorunlu sorgu için GERÇEK sonuç imleci açılır, HİÇ SATIR ÇEKİLMEDEN
# `dbColumnInfo()` ile sürücünün gördüğü kolon adları alınır ve imleç kapatılır.
# Bu yol yalnızca eksik ad onarımıdır: tip/genişlik kanıtı hâlâ SQL Server'ın
# statik tanımlayıcısından gelir ve kolon sayısı birebir uyuşmazsa fail-closed.
.pkgd_runtime_column_names <- function(conn, sql, timeout_sec = NULL) {
  son_tarih <- .pkgd_deadline(timeout_sec)
  sonuc <- .pkgd_bounded_until(
    function() .pkgd_send_sample_query(conn, sql, unicode = TRUE),
    son_tarih
  )
  on.exit({
    temizlik_sinir <- tryCatch(.pkgd_remaining(son_tarih), error = function(e) NULL)
    if (is.null(temizlik_sinir)) temizlik_sinir <- .PKGD_CLEANUP_MIN_SEC
    temizlik_sinir <- max(as.numeric(temizlik_sinir), .PKGD_CLEANUP_MIN_SEC)
    tryCatch(.pkgd_bounded(function() DBI::dbClearResult(sonuc), temizlik_sinir),
             error = function(e) NULL)
  }, add = TRUE)

  bilgi <- .pkgd_bounded_until(function() DBI::dbColumnInfo(sonuc), son_tarih)
  if (!is.data.frame(bilgi) || !("name" %in% names(bilgi))) {
    stop("[PK_META_GEN] Runtime sonuc metadata'si kolon adlarini dondurmedi.", call. = FALSE)
  }
  as.character(bilgi$name)
}

#' Varsayılan `describe` çağrısı
#'
#' Normal yol `sys.dm_exec_describe_first_result_set` ile sorguyu çalıştırmadan
#' şemayı çıkarır. SQL Server statik analizinin yalnızca KOLON ADINI
#' belirleyemediği istisnada, gerçek SQL aynı Unicode yoldan açılır ve HİÇ SATIR
#' çekilmeden `dbColumnInfo()` ile yalnızca eksik adlar doğrulanır. Böylece çalışan
#' sql_file sorguları yanlış "adsiz sonuc sutunu" diye reddedilmez; kolon sayısı
#' veya adlar runtime ile doğrulanamazsa sistem yine fail-closed kalır.
pkg_default_describe_fn <- function(conn, sql, timeout_sec = NULL) {
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("[PK_META_GEN] DBI paketi gerekli.", call. = FALSE)
  }
  if (!.pkgd_is_sql_server(conn)) {
    if (!exists("pk_sql_describe_result_schema", mode = "function", inherits = TRUE)) {
      stop("[PK_META_GEN] pk_sql_describe_result_schema bulunamadi.", call. = FALSE)
    }
    return(pk_sql_describe_result_schema(conn, sql))
  }

  tanim_sql <- paste(
    paste0(
      "SELECT column_ordinal, name, system_type_name, max_length, ",
      "error_number, error_type, error_type_desc, error_message"
    ),
    "FROM sys.dm_exec_describe_first_result_set(CAST(? AS NVARCHAR(MAX)), NULL, 0)",
    "ORDER BY column_ordinal"
  )

  cerceve <- .pkgd_bounded(
    function() DBI::dbGetQuery(conn, tanim_sql, params = .pkgd_descriptor_params(sql)),
    timeout_sec
  )
  if (!is.data.frame(cerceve) || nrow(cerceve) == 0L) return(NULL)

  descriptor_error <- .pkgd_descriptor_error_detail(cerceve)
  if (!is.null(descriptor_error)) {
    stop(paste0("[PK_META_GEN] ", descriptor_error), call. = FALSE)
  }

  adlar <- as.character(cerceve$name)
  eksik <- is.na(adlar) | !nzchar(adlar)
  if (any(eksik)) {
    runtime_adlari <- .pkgd_runtime_column_names(conn, sql, timeout_sec)
    cerceve <- .pkgd_repair_descriptor_names(cerceve, runtime_adlari)
    cat(sprintf(
      "[PK_META_GEN] BILGI: statik tanimlayicinin belirleyemedigi %d kolon adi runtime metadata ile dogrulandi.\n",
      sum(eksik)
    ))
  }

  lapply(seq_len(nrow(cerceve)), function(i) {
    list(
      name = as.character(cerceve$name[i]),
      system_type_name = as.character(cerceve$system_type_name[i]),
      max_length = suppressWarnings(as.numeric(cerceve$max_length[i]))
    )
  })
}

# Örnek getirimini başlat. Türkçe/köşeli parantezli sütun adları içeren üretim
# SQL'i, ODBC'ye HAM BATCH olarak gönderildiğinde ayrışma/kodlama hatası
# verebilir; üretim yolu bu yüzden metni NVARCHAR(MAX) PARAMETRESİ olarak
# gönderir. Üretici aynı yolu kullanır, böylece uygulamada ÇALIŞAN bir sorgu
# yalnızca üreticide başarısız olmaz. Metin DEĞİŞTİRİLMEZ: kapıdan geçen metin
# ile parametre olarak gönderilen metin AYNIDIR.
.pkgd_send_sample_query <- function(conn, sql, unicode = TRUE) {
  unicode_acik <- isTRUE(unicode)

  if (unicode_acik && .pkgd_is_sql_server(conn)) {
    sarmalayici <- paste(
      "DECLARE @sql NVARCHAR(MAX);", "SET @sql = ?;", "EXEC sp_executesql @sql;",
      sep = "\n"
    )
    parametre <- if (exists("normalize_db_params", mode = "function", inherits = TRUE)) {
      tryCatch(normalize_db_params(list(sql)), error = function(e) list(sql))
    } else {
      list(sql)
    }
    return(DBI::dbSendQuery(conn, sarmalayici, params = parametre))
  }

  DBI::dbSendQuery(conn, sql)
}

#' Varsayılan `sample` çağrısı -- SINIRLI ve SQL'i DEĞİŞTİRMEYEN
#'
#' SQL SARMALANMAZ (`SELECT TOP n FROM (...)` YOK): üretim sorguları `ORDER BY`,
#' CTE ve `OPTION(...)` içerebilir; sarmalamak hem sorguyu bozar hem de
#' salt-okunur kapısından GEÇEN metin ile çalışan metni ayırır. Bunun yerine
#' imleç açılır ve yalnızca N satır çekilir; kalan sonuç sunucuda bırakılır.
#'
#' DÜRÜSTLÜK: `dbFetch(n = )` bir AKTARIM sınırdır, SUNUCU İŞ YÜKÜ sınırı
#' DEĞİLDİR. `dbSendQuery()` SELECT'i çalıştırır; büyük bir birleştirme ya da
#' `ORDER BY` bu satırlar çekilmeden ÖNCE sunucuda tamamlanabilir. Gerçek
#' koruma bu yüzden ZAMAN AŞIMI ve BAYT TAVANIDIR; ikisi de burada uygulanır ve
#' sağlık kaydında `server_bounded = FALSE` olarak BİLDİRİLİR.
pkg_default_sample_fn <- function(conn, sql, sample_rows = 500L, timeout_sec = NULL,
                                  max_result_mb = NULL, sample_unicode = TRUE) {
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("[PK_META_GEN] DBI paketi gerekli.", call. = FALSE)
  }

  n <- suppressWarnings(as.integer(sample_rows)[1])
  if (length(n) != 1L || is.na(n) || n < 1L) n <- 500L

  tavan_mb <- suppressWarnings(as.numeric(max_result_mb)[1])
  if (length(tavan_mb) != 1L || is.na(tavan_mb) || !is.finite(tavan_mb) || tavan_mb <= 0) {
    tavan_mb <- Inf
  }
  tavan_bayt <- tavan_mb * 1024 * 1024

  son_tarih <- .pkgd_deadline(timeout_sec)

  sonuc <- .pkgd_bounded_until(function() .pkgd_send_sample_query(conn, sql, unicode = sample_unicode),
                               son_tarih)
  # Sonuç kümesi HER DURUMDA kapatılır; aksi hâlde bağlantı kirli kalır.
  #
  # TEMİZLİK DE SINIRLIDIR. `dbClearResult()` tamamlanmamış bir ODBC sonucunu
  # iptal ederken KENDİSİ bloklayabilir -- özellikle zaman aşımına uğramış ya da
  # bayt tavanı yüzünden erken kesilmiş bir getirimden sonra. Sınırsız bırakılan
  # bu çağrı, "her bloklayan sürücü çağrısı sınırlıdır" sözünü çürütürdü.
  #
  # Bütçe tükenmiş olabileceği için temizliğe HER ZAMAN kısa bir taban süre
  # tanınır: sıfır bütçeyle temizliği hiç denememek sonucu açık bırakırdı.
  on.exit({
    temizlik_sinir <- tryCatch(.pkgd_remaining(son_tarih), error = function(e) NULL)
    if (is.null(temizlik_sinir)) temizlik_sinir <- .PKGD_CLEANUP_MIN_SEC
    temizlik_sinir <- max(as.numeric(temizlik_sinir), .PKGD_CLEANUP_MIN_SEC)
    tryCatch(.pkgd_bounded(function() DBI::dbClearResult(sonuc), temizlik_sinir),
             error = function(e) NULL)
  }, add = TRUE)

  # BAYT TAVANI İÇİN PARÇALI GETİRİM: birkaç büyük LOB satırı, satır sayısı
  # sınırının altında kalırken yapılandırılmış bellek bütçesini kat kat aşabilir.
  parca <- max(1L, min(n, 200L))
  parcalar <- list()
  toplam_satir <- 0L
  toplam_bayt <- 0

  while (toplam_satir < n) {
    istenen <- min(parca, n - toplam_satir)
    blok <- .pkgd_bounded_until(function() DBI::dbFetch(sonuc, n = istenen), son_tarih)
    if (!is.data.frame(blok) || nrow(blok) == 0L) break

    toplam_bayt <- toplam_bayt + suppressWarnings(as.numeric(utils::object.size(blok)))
    if (is.finite(tavan_bayt) && toplam_bayt > tavan_bayt) {
      stop(sprintf(paste0(
        "[PK_META_GEN] Ornek sonucu yapilandirilmis bayt tavanini asti ",
        "(MERGEN_PK_META_MAX_RESULT_MB = %s). Getirim durduruldu."
      ), format(tavan_mb)), call. = FALSE)
    }

    parcalar[[length(parcalar) + 1L]] <- blok
    toplam_satir <- toplam_satir + nrow(blok)
    if (nrow(blok) < istenen) break
  }

  cerceve <- if (!length(parcalar)) {
    # Sütun yapısını korumak için boş bir getirim yine de yapılır.
    .pkgd_bounded_until(function() DBI::dbFetch(sonuc, n = 0L), son_tarih)
  } else if (length(parcalar) == 1L) {
    parcalar[[1]]
  } else {
    do.call(rbind, parcalar)
  }

  # UTF-8 NORMALİZASYONU ZORUNLUDUR. Başarısız olursa ham çerçeveye SESSİZCE
  # dönmek, Türkçe VM'de mojibake sütun adları ve yanlış farklı-değer kanıtı
  # üretir; bu yüzden sorgu BAŞARISIZ sayılır.
  if (exists("normalize_pk_dataframe_utf8", mode = "function", inherits = TRUE)) {
    cerceve <- tryCatch(normalize_pk_dataframe_utf8(cerceve), error = function(e) {
      stop("[PK_META_GEN] Ornek sonucu UTF-8'e normallestirilemedi; sorgu geri cekildi.",
           call. = FALSE)
    })
  }

  cerceve
}
