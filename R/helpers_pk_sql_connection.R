# ==============================================================================
# Dosya Yolu: R/helpers_pk_sql_connection.R
# Açıklama: Faz 6 (§5.10) — SINIRLI SQL yürütmesinin BAĞLANTI OTURUM DURUMU
#           yardımcıları: ifade zaman aşımı uygulama/geri yükleme ve temizliği
#           tamamlanmamış bir havuz bağlantısını geçersiz kılma.
#
# `R/helpers_pk_sql_execute.R` içinden BÖLÜNMÜŞTÜR: orası GETİRİM boru hattıdır
# (parça planı, bayt kapısı, tipli sonuç) ve 24-fonksiyon bakım tavanına
# dayanmıştı. Oturum durumu ayrı bir sorumluluktur: "bu fiziksel bağlantıyı
# istekten SONRA kim, hangi hâlde devralır".
#
# `pk_sql_bounded_call()` bu dosyadan ÖNCE yüklenen `helpers_pk_sql_execute.R`
# içindedir; manifest sırası bu yüzden ZORUNLUDUR.
# ==============================================================================


# SQL Server oturum durumu olan LOCK_TIMEOUT, havuzdan alınan FİZİKSEL bir
# bağlantıda kalıcıdır. Eski kod temizlikte koşulsuz `-1` yazıyordu; bu, havuza
# iade edilen bağlantının ÖNCEKİ kilit-bekleme politikasını yok eder ve sonraki
# ilgisiz istekler sonsuza kadar bekleyebilir. Bu yüzden önceki değer okunur.
.pk_sql_read_lock_timeout <- function(conn, budget_fn) {
  okuma <- pk_sql_bounded_call(
    function() DBI::dbGetQuery(conn, "SELECT @@LOCK_TIMEOUT AS lt"), budget_fn
  )
  if (!isTRUE(okuma$ok) || !is.data.frame(okuma$value) || nrow(okuma$value) < 1L) {
    return(NA_integer_)
  }
  deger <- suppressWarnings(as.integer(okuma$value[[1]][1]))
  if (length(deger) != 1L || is.na(deger)) return(NA_integer_)
  deger
}

pk_sql_apply_statement_timeout <- function(conn, timeout_sec, budget_fn = NULL) {
  saniye <- suppressWarnings(as.integer(timeout_sec)[1])
  if (length(saniye) != 1L || is.na(saniye) || saniye <= 0L) {
    return(list(mechanism = "none", applied = FALSE, timeout_sec = 0L,
                previous = NA_integer_))
  }
  if (inherits(conn, "Pool")) {
    return(list(mechanism = "deferred_pool", applied = FALSE, timeout_sec = saniye,
                previous = NA_integer_))
  }
  if (is.null(conn) || !requireNamespace("DBI", quietly = TRUE)) {
    return(list(mechanism = "none", applied = FALSE, timeout_sec = saniye,
                previous = NA_integer_))
  }

  butce <- if (is.function(budget_fn)) budget_fn else function() Inf
  onceki <- .pk_sql_read_lock_timeout(conn, butce)

  # ÖNCEKİ DEĞER OKUNAMADIYSA ZAMAN AŞIMI HİÇ UYGULANMAZ.
  #
  # Okuma başarısızsa `onceki` `NA_integer_` olur; eskiden `SET LOCK_TIMEOUT`
  # yine çalıştırılıyor ve `applied = TRUE` raporlanıyordu. Temizlikte
  # `.pk_sql_restore_lock_timeout()` `dirty = TRUE` döndüğü için çağıran
  # havuzdaki fiziksel bağlantıyı EMEKLİYE AYIRIYORDU: bu durumdaki HER istek
  # bir havuz bağlantısını yok ediyordu. Zaman aşımını atlamak oturumu TEMİZ
  # bırakır ve yalnızca kilit bekleme sınırından vazgeçer.
  if (length(onceki) != 1L || is.na(onceki)) {
    return(list(mechanism = "none", applied = FALSE, timeout_sec = saniye,
                previous = NA_integer_))
  }

  # MİLİSANİYE ÇARPIMI TAM SAYI TAŞMASINA UĞRAMAZ: `MERGEN_PK_SQL_TIMEOUT_SEC` üst sınır BEYAN ETMEZ; 2147483 saniyenin üzerinde `saniye * 1000L` `NA_integer_` üretiyor, ifade `SET LOCK_TIMEOUT NA` olarak gidiyor, deyim düşüyor ve kilit bekleme sınırı operatör aksini sanırken SESSİZCE uygulanmıyordu. Üst sınır SQL Server'ın kabul ettiği azami değerdir.
  ms <- min(as.numeric(saniye) * 1000, 2147483647)

  uygulama <- pk_sql_bounded_call(
    function() DBI::dbExecute(conn, sprintf("SET LOCK_TIMEOUT %.0f", ms)),
    butce
  )
  if (isTRUE(uygulama$ok)) {
    return(list(mechanism = "lock_timeout", applied = TRUE, timeout_sec = saniye,
                previous = onceki))
  }
  list(mechanism = "none", applied = FALSE, timeout_sec = saniye, previous = onceki)
}

# Temizlikte ÖNCEKİ değeri geri yükle.
#
# ÖNCEKİ DEĞER OKUNAMADIYSA TAHMİN EDİLMEZ: `-1` yazmak, bu bağlantıda ZATEN
# yapılandırılmış olabilecek özel bir zaman aşımını sessizce ezer ve o
# DEĞİŞTİRİLMİŞ oturum durumu sonraki isteklere devredilirdi. Bu durumda oturum
# ayarına DOKUNULMAZ ve bağlantı "kirli" işaretlenir; çağıran onu havuza iade
# etmek yerine emekliye ayırır.
#
# @return `list(restored = TRUE/FALSE, dirty = TRUE/FALSE)`.
.pk_sql_restore_lock_timeout <- function(conn, timeout_state, budget_fn) {
  if (!isTRUE(timeout_state$applied)) return(list(restored = TRUE, dirty = FALSE))

  onceki <- suppressWarnings(as.integer(timeout_state$previous)[1])
  if (length(onceki) != 1L || is.na(onceki)) {
    return(list(restored = FALSE, dirty = TRUE))
  }

  sonuc <- try(pk_sql_bounded_call(
    function() DBI::dbExecute(conn, sprintf("SET LOCK_TIMEOUT %d", onceki)),
    budget_fn
  ), silent = TRUE)

  ok <- !inherits(sonuc, "try-error") && isTRUE(sonuc$ok)
  list(restored = ok, dirty = !ok)
}

# Temizliği tamamlanmamış bir havuz bağlantısını GEÇERSİZ KIL.
#
# `pool::poolReturn()` bağlantıyı havuza geri koyar; kirli oturum durumu
# (geri yüklenememiş `LOCK_TIMEOUT`, temizlenmemiş sonuç kümesi) bir sonraki
# ödünç alana devredilirdi. `pool::poolClose()` bir havuz nesnesi içindir;
# TEK bir checkout'u emekliye ayırmanın doğru yolu fiziksel bağlantıyı
# kapatmaktır — havuz eksik bağlantıyı gerektiğinde yeniden kurar.
#' @return `TRUE` yalnızca fiziksel bağlantının KAPATILDIĞI doğrulandıysa VE
#'   havuz muhasebesi (`pool::poolReturn()`) da serbest bırakıldıysa. İki
#'   koşulun BİRLEŞİK sonucudur: kapatma doğrulanmış ama iade başarısız olduğunda
#'   `FALSE` döner, çünkü checkout yuvası kaybedilmiştir ve çağıran bunu bir
#'   tam temizlik gibi raporlamamalıdır. Fark log'lanır (aşağıdaki uyarı).
.pk_sql_invalidate_connection <- function(conn, budget_fn) {
  kapatildi <- try(pk_sql_bounded_call(
    function() DBI::dbDisconnect(conn), budget_fn
  ), silent = TRUE)
  # SINIRLI ÇAĞRI SONUCU DENETLENİR: `pk_sql_bounded_call()` hata ATMAZ,
  # `list(ok = FALSE, ...)` DÖNER. Eskiden yalnızca `try-error` bakılıyordu, bu
  # yüzden zaman aşımına uğramış bir kapatma BAŞARI raporlanıyordu.
  ok <- !inherits(kapatildi, "try-error") && isTRUE(kapatildi$ok)

  if (isTRUE(ok)) {
    # Bağlantı GERÇEKTEN kapandı: `poolReturn()` yalnızca havuzun muhasebesini
    # düzeltir; kapalı bağlantı havuzun checkout doğrulamasında elenir.
    #
    # İADE SONUCU DA DENETLENİR. Eskiden dönüş atılıyor ve fonksiyon KOŞULSUZ
    # `TRUE` raporluyordu; `poolReturn()` zaman aşımına uğrar ya da hata verirse
    # checkout muhasebesi HİÇ serbest bırakılmıyor ve tekrarlanan kirli-bağlantı
    # temizlikleri işçi havuzu kapasitesini kalıcı olarak tüketiyordu.
    iade <- try(pk_sql_bounded_call(function() pool::poolReturn(conn), budget_fn),
                silent = TRUE)
    iade_ok <- !inherits(iade, "try-error") && isTRUE(iade$ok)
    if (!isTRUE(iade_ok) && exists("log_warn", mode = "function", inherits = TRUE)) {
      try(log_warn(paste0(
        "[PK_SQL] Fiziksel baglanti kapatildi ama havuz muhasebesi serbest ",
        "birakilamadi; checkout yuvasi kaybedildi."
      )), silent = TRUE)
    }
    return(invisible(isTRUE(iade_ok)))
  }

  # KAPATMA DOĞRULANAMADI => bağlantı HÂLÂ CANLI ve KİRLİ olabilir.
  #
  # `poolReturn()` ÇAĞRILMAZ (PR #703 incelemesi): iade edilen canlı bağlantı,
  # geri yüklenememiş `LOCK_TIMEOUT` / temizlenmemiş sonuç kümesi ile bir
  # sonraki isteğe devredilirdi. Yuvayı kaybetmek (havuz onu idle timeout /
  # finalizer ile toplar) KİRLİ durumu yaymaktan iyidir.
  if (exists("log_warn", mode = "function", inherits = TRUE)) {
    try(log_warn(paste0(
      "[PK_SQL] Kirli baglanti emekliye ayrilamadi; havuza IADE EDILMEDI ",
      "(checkout yuvasi kaybedildi, kirli oturum durumu yayilmadi)."
    )), silent = TRUE)
  }
  invisible(FALSE)
}
