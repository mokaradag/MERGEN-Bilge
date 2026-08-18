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
pkg_default_connect_fn <- function(target = "primary") {
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
    return(db_acquire_tx_connection(dogrulama$target))
  }

  if (!exists("get_connection", mode = "function", inherits = TRUE)) {
    stop("[PK_META_GEN] get_connection bulunamadi; uygulama bootstrap'i yuklenmedi.",
         call. = FALSE)
  }
  get_connection(dogrulama$target)
}

pkg_default_release_fn <- function(handle) {
  if (is.null(handle)) return(invisible(NULL))

  if (is.list(handle) && isTRUE(handle$checked_out) &&
      exists("db_release_tx_connection", mode = "function", inherits = TRUE)) {
    return(invisible(tryCatch(db_release_tx_connection(handle), error = function(e) NULL)))
  }

  if (exists("release_connection", mode = "function", inherits = TRUE)) {
    return(invisible(tryCatch(release_connection(handle), error = function(e) NULL)))
  }
  invisible(NULL)
}

#' Varsayılan `describe` çağrısı
#'
#' `sys.dm_exec_describe_first_result_set` sorguyu ÇALIŞTIRMAZ; metni parametre
#' olarak alır ve sonuç kümesi şemasını döndürür.
#'
#' İKİ DAVRANIŞ FARKI:
#'   1) `MERGEN_PK_RESULT_SCHEMA_PROBE` uygulamanın İSTEĞE BAĞLI çalışma zamanı
#'      sondasını kapatır. Operatör `MERGEN_PK_META_MODE=describe` dediğinde
#'      üreticinin envanteri BU BAYRAKTAN BAĞIMSIZ olarak yapması beklenir;
#'      aksi hâlde sondası kapalı bir VM'de HİÇBİR şema üretilmez.
#'   2) Tanımlayıcı işlevi hataları YUTAR ve `NULL` döner. `NULL`, "bu sorgu
#'      tanımlanamıyor" ile "sonda BAŞARISIZ oldu" arasındaki farkı siler; bu
#'      yüzden gerçek hata YAKALANIR ve YÜKSELTİLİR, çağıran ikisini ayırır.
pkg_default_describe_fn <- function(conn, sql, timeout_sec = NULL) {
  if (!exists("pk_sql_describe_result_schema", mode = "function", inherits = TRUE)) {
    stop("[PK_META_GEN] pk_sql_describe_result_schema bulunamadi.", call. = FALSE)
  }

  onceki_sonda <- Sys.getenv("MERGEN_PK_RESULT_SCHEMA_PROBE", unset = NA_character_)
  Sys.setenv(MERGEN_PK_RESULT_SCHEMA_PROBE = "true")
  on.exit({
    if (is.na(onceki_sonda)) {
      Sys.unsetenv("MERGEN_PK_RESULT_SCHEMA_PROBE")
    } else {
      Sys.setenv(MERGEN_PK_RESULT_SCHEMA_PROBE = onceki_sonda)
    }
  }, add = TRUE)

  yakalanan <- NULL
  cagri <- function(fn) {
    deger <- tryCatch(.pkgd_bounded(fn, timeout_sec), error = function(e) e)
    if (inherits(deger, "condition")) {
      yakalanan <<- deger
      return(list(ok = FALSE, value = NULL))
    }
    list(ok = TRUE, value = deger)
  }

  sonuc <- pk_sql_describe_result_schema(conn, sql, call_fn = cagri)
  if (!is.null(yakalanan)) stop(yakalanan)
  sonuc
}

# Örnek getirimini başlat. Türkçe/köşeli parantezli sütun adları içeren üretim
# SQL'i, ODBC'ye HAM BATCH olarak gönderildiğinde ayrışma/kodlama hatası
# verebilir; üretim yolu bu yüzden metni NVARCHAR(MAX) PARAMETRESİ olarak
# gönderir. Üretici aynı yolu kullanır, böylece uygulamada ÇALIŞAN bir sorgu
# yalnızca üreticide başarısız olmaz. Metin DEĞİŞTİRİLMEZ: kapıdan geçen metin
# ile parametre olarak gönderilen metin AYNIDIR.
.pkgd_send_sample_query <- function(conn, sql) {
  unicode_acik <- !identical(
    tolower(trimws(Sys.getenv("MERGEN_PK_META_SAMPLE_UNICODE", unset = "true"))),
    "false"
  )

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
#' salt-okunur kapısından GEÇEN metin ile ÇALIŞAN metni ayırır. Bunun yerine
#' imleç açılır ve yalnızca N satır çekilir; kalan sonuç sunucuda bırakılır.
#'
#' DÜRÜSTLÜK: `dbFetch(n = )` bir AKTARIM sınırdır, SUNUCU İŞ YÜKÜ sınırı
#' DEĞİLDİR. `dbSendQuery()` SELECT'i çalıştırır; büyük bir birleştirme ya da
#' `ORDER BY` bu satırlar çekilmeden ÖNCE sunucuda tamamlanabilir. Gerçek
#' koruma bu yüzden ZAMAN AŞIMI ve BAYT TAVANIDIR; ikisi de burada uygulanır ve
#' sağlık kaydında `server_bounded = FALSE` olarak BİLDİRİLİR.
pkg_default_sample_fn <- function(conn, sql, sample_rows = 500L, timeout_sec = NULL,
                                  max_result_mb = NULL) {
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

  sonuc <- .pkgd_bounded(function() .pkgd_send_sample_query(conn, sql), timeout_sec)
  # Sonuç kümesi HER DURUMDA kapatılır; aksi hâlde bağlantı kirli kalır.
  on.exit(tryCatch(DBI::dbClearResult(sonuc), error = function(e) NULL), add = TRUE)

  # BAYT TAVANI İÇİN PARÇALI GETİRİM: birkaç büyük LOB satırı, satır sayısı
  # sınırının altında kalırken yapılandırılmış bellek bütçesini kat kat aşabilir.
  parca <- max(1L, min(n, 200L))
  parcalar <- list()
  toplam_satir <- 0L
  toplam_bayt <- 0

  while (toplam_satir < n) {
    istenen <- min(parca, n - toplam_satir)
    blok <- .pkgd_bounded(function() DBI::dbFetch(sonuc, n = istenen), timeout_sec)
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
    .pkgd_bounded(function() DBI::dbFetch(sonuc, n = 0L), timeout_sec)
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
