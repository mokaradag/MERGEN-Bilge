# ==============================================================================
# Dosya Yolu: R/helpers_pk_telemetry.R
# Açıklama: Proje ve Kaynak Analizi kullanım/bozulma telemetrisi
#           (MB_Analiz_Log yazımı).
#
# EN ÖNEMLİ SÖZLEŞME - YAZIMLAR "FAIL-SOFT" OLMAK ZORUNDADIR:
#   MB_Analiz_Log DDL'i DBA tarafından ELLE uygulanır (docs/sql/...), telemetri
#   ise varsayılan olarak AÇIKTIR. Uygulama güncellemesi DDL'den önce sahaya
#   inerse, tablo yokken her analizde yazım denenir. Bu durum gözlem amaçlı bir
#   özelliği, ÇALIŞAN v1 analizlerini de bozan bir arızaya çevirirdi. Bu yüzden:
#     * tablo hazırlığı SÜREÇ BAŞINA BİR KEZ tespit edilir,
#     * tablo yoksa telemetri TEK bir log satırıyla devre dışı bırakılır,
#     * her yazım tryCatch ile sarılır; hiçbir hata kullanıcı isteğine sızmaz.
#   Bu, MB_Ortak* / MB_Game_* ailelerindeki "tablo yoksa özellik yine çalışır"
#   kuralının aynısıdır.
#
# GİZLİLİK:
#   MERGEN_PK_LOG_QUESTION_TEXT=false (varsayılan) iken ham soru metni YAZILMAZ.
#   Onun yerine sunucu anahtarlı (HMAC-SHA256) bir parmak izi saklanır. Düz
#   (anahtarsız) özet yeterli DEĞİLDİR: sorular sonlu bir proje sözlüğünden
#   geldiği için düşük entropilidir ve tabloyu okuyabilen biri aday soruları
#   özetleyip eşleştirebilir. Anahtar yoksa parmak izi de YAZILMAZ.
#   Bu dosya hiçbir koşulda API anahtarı, token, DSN, bağlantı dizesi veya
#   HMAC anahtarının kendisini loglamaz.
#
# KISITLI ALAN:
#   SatirRlsOncesi (RLS öncesi satır sayısı) yalnızca bu tabloda yaşar. Bu
#   değer kullanıcıya görünen alt bilgiye, ek dosyalara veya modele giden
#   pakete ASLA konulmaz.
#
# DOSYA SINIRI:
#   Kaydın SAF katmanı (soru normalizasyonu, anahtarlı parmak izi, alan kırpma,
#   satır kurulumu, kodlama normalizasyonu) R/helpers_pk_telemetry_record.R
#   içindedir ve bu dosyadan ÖNCE yüklenir. Burası yalnızca DB'ye dokunan
#   katmandır: hazırlık tespiti, yazım ve gözlem giriş noktası. Saf yardımcıları
#   buraya geri taşımayın; bölme hem gizlilik kararının DB'siz test
#   edilebilmesini hem de sürdürülebilirlik bütçesini korur.
# ==============================================================================

# Süreç kapsamlı telemetri durumu. ready: NA = henüz bilinmiyor.
.pk_telemetry_state <- new.env(parent = emptyenv())
.pk_telemetry_state$ready <- NA
.pk_telemetry_state$warned <- FALSE
.pk_telemetry_state$write_warned <- FALSE

#' Telemetri durumunu sıfırla (yalnızca testler ve tanılama içindir)
pk_telemetry_reset_state <- function() {
  .pk_telemetry_state$ready <- NA
  .pk_telemetry_state$warned <- FALSE
  .pk_telemetry_state$write_warned <- FALSE
  invisible(TRUE)
}

pk_telemetry_enabled <- function() {
  isTRUE(tryCatch(pk_config_resolve("MERGEN_PK_TELEMETRY"), error = function(e) FALSE))
}

# Logger yoksa (izole test/worker) sessizce yut; telemetri asla akışı bozmaz.
.pk_telemetry_log <- function(level, message) {
  tryCatch({
    fn_name <- if (identical(level, "warn")) "log_warn" else "log_info"
    if (exists(fn_name, mode = "function", inherits = TRUE)) {
      get(fn_name, mode = "function", inherits = TRUE)(message)
    }
    invisible(NULL)
  }, error = function(e) invisible(NULL))
}

#' MB_Analiz_Log tablosunun kullanılabilirliğini süreç başına bir kez tespit et
#'
#' @return TRUE (yazılabilir) / FALSE (yok veya erişilemiyor).
pk_telemetry_table_ready <- function(conn) {
  if (!is.na(.pk_telemetry_state$ready)) {
    return(isTRUE(.pk_telemetry_state$ready))
  }

  if (is.null(conn)) return(FALSE)

  ready <- tryCatch({
    DBI::dbGetQuery(conn, "SELECT AnalizLogID FROM MB_Analiz_Log WHERE 1 = 0")
    TRUE
  }, error = function(e) FALSE)

  .pk_telemetry_state$ready <- ready

  if (!ready && !isTRUE(.pk_telemetry_state$warned)) {
    .pk_telemetry_state$warned <- TRUE
    .pk_telemetry_log(
      "warn",
      paste0(
        "[PK_TELEMETRY] MB_Analiz_Log tablosu bulunamadi; telemetri bu surec icin ",
        "devre disi birakildi. Proje ve Kaynak Analizi normal calismaya devam eder. ",
        "DDL: docs/sql/2026-08-pk-analiz-log.sql (DBA tarafindan elle uygulanir)."
      )
    )
  }

  isTRUE(ready)
}

#' Bir analiz isteğini MB_Analiz_Log tablosuna yaz (FAIL-SOFT)
#'
#' @param info Telemetri girdisi (bkz. pk_telemetry_build_record).
#' @param conn Açık DBI bağlantısı. Çağıran akışın bağlantısı kullanılır;
#'   telemetri kendi başına bağlantı AÇMAZ.
#' @return Görünmez TRUE (yazıldı) / FALSE (atlandı veya başarısız).
pk_telemetry_log_analysis <- function(info, conn) {
  tryCatch({
    if (!pk_telemetry_enabled()) return(invisible(FALSE))
    if (is.null(conn)) return(invisible(FALSE))
    if (!pk_telemetry_table_ready(conn)) return(invisible(FALSE))

    record <- .pk_telemetry_normalize_record(pk_telemetry_build_record(info))

    columns <- names(record)
    placeholders <- paste(rep("?", length(columns)), collapse = ", ")
    sql <- sprintf(
      "INSERT INTO MB_Analiz_Log (%s) VALUES (%s)",
      paste(columns, collapse = ", "),
      placeholders
    )

    params <- unname(as.list(record))
    if (exists("normalize_db_params", mode = "function", inherits = TRUE)) {
      params <- tryCatch(normalize_db_params(params), error = function(e) params)
    }

    DBI::dbExecute(conn, sql, params = params)
    invisible(TRUE)

  }, error = function(e) {
    # Yazım hatası hiçbir zaman kullanıcı isteğine sızmaz. İlk hata loglanır,
    # sonrasında sessiz kalınır ki kalıcı bir sorun logu boğmasın.
    if (!isTRUE(.pk_telemetry_state$write_warned)) {
      .pk_telemetry_state$write_warned <- TRUE
      .pk_telemetry_log(
        "warn",
        sprintf(
          "[PK_TELEMETRY] MB_Analiz_Log yazimi basarisiz; telemetri atlaniyor (tur: %s).",
          class(e)[1]
        )
      )
    }
    invisible(FALSE)
  })
}

#' Bir analiz isteğini gözlemle: alt bilgiyi hazırla + telemetriyi yaz
#'
#' Faz 0'ın tek giriş noktası. Modül tarafındaki çağrı yerlerini kısa tutmak
#' ve "gözlem" mantığını tek yerde toplamak için vardır. Hiçbir koşulda hata
#' fırlatmaz; başarısızlıkta analiz akışı etkilenmez.
#'
#' @param info Gözlem girdisi. `pre_rls_rows` YALNIZCA telemetriye gider;
#'   kullanıcıya görünen alt bilgiye asla konulmaz.
#' @return Görünmez biçimde üretilen alt bilgi metni (veya "").
pk_analysis_observe <- function(session, conn, info) {
  tryCatch({
    info <- if (is.list(info)) info else list()

    status <- pk_filter_status_normalize(info$filter_status)
    degradations <- pk_degradations_from_filter_status(status)

    footer <- pk_build_provenance_footer(list(
      query_id        = info$query_id,
      query_name      = info$query_name,
      filter_status   = status,
      filters         = info$filters %||% list(),
      authorized_rows = info$authorized_rows,
      filtered_rows   = info$filtered_rows,
      degradations    = degradations
    ))

    if (nzchar(footer)) {
      pk_provenance_stash(session, footer, request_id = info$request_id)
    }

    # Düz atama kullanılır: utils::modifyList() liste değerli alanları ada göre
    # özyinelemeli birleştirdiği için burada beklenmedik iç içe geçmelere yol
    # açabilirdi.
    info$filter_status <- status
    info$filter_count <- length(info$filters %||% list())
    info$degradation_codes <- vapply(
      degradations,
      function(d) as.character(d$code)[1],
      character(1)
    )

    pk_telemetry_log_analysis(info, conn)

    invisible(footer)
  }, error = function(e) invisible(""))
}
