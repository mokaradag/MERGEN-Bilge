# ==============================================================================
# Dosya Yolu: R/helpers_pk_telemetry_base.R
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

# Süreç kapsamlı telemetri durumu. `ready`: NA = henüz bilinmiyor.
#
# HAZIRLIK KARARI VERİTABANI HEDEFİNE GÖRE ANAHTARLANIR.
#
# `pk_telemetry_log_analysis()` SEÇİLEN sorgunun bağlantısını alır ve sorgu
# kütüphanesi sorgu başına `db_target` beyan eder. Tek bir süreç-küresel bit,
# İLK yoklanan hedefin kararını DİĞER TÜM hedeflere dayatıyordu: ilk hedefte
# `MB_Analiz_Log` yoksa tablosu OLAN bir hedefte denetim kaydı hiç yazılmıyor;
# ilk hedefte varsa tablosu OLMAYAN bir hedef her analizde başarısız bir
# `INSERT` tekrarlıyordu.
.pk_telemetry_state <- new.env(parent = emptyenv())
.pk_telemetry_state$ready <- NA
.pk_telemetry_state$ready_by_target <- list()
.pk_telemetry_state$warned <- FALSE
.pk_telemetry_state$write_warned <- FALSE

# Etkin telemetri hedefi: açık değer -> etkin yürütme bağlamı -> "primary".
.pk_telemetry_target_key <- function(target = NULL) {
  ad <- as.character(target %||% "")[1]
  if (is.na(ad) || !nzchar(ad)) {
    ad <- tryCatch({
      baglam <- if (exists("pk_active_exec_context", mode = "function", inherits = TRUE)) {
        pk_active_exec_context()
      } else {
        list()
      }
      as.character(baglam$query$db_target %||% "")[1]
    }, error = function(e) "")
  }
  if (length(ad) != 1L || is.na(ad) || !nzchar(ad)) "primary" else ad
}

#' Telemetri durumunu sıfırla (yalnızca testler ve tanılama içindir)
pk_telemetry_reset_state <- function() {
  .pk_telemetry_state$ready <- NA
  .pk_telemetry_state$ready_by_target <- list()
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

# Faz 6 (§5.10): telemetri GÖZLENEBİLİRLİKTİR; iptal/son tarih garantisini
# BOZAMAZ. Bu iki senkron DB çağrısı analizin TERMİNAL yollarında çalışır;
# sınırlanmazlarsa askıda kalan bir DB/ağ, analizi bitmiş bir isteğin işçisini
# ve bağlantısını süresiz tutar. Bütçe yoksa (`Inf`) davranış DEĞİŞMEZ.
#
# BÜTÇE KAYNAĞI TEARDOWN DEĞİL, KALAN ANALİZ BÜTÇESİDİR. `.db_pk_teardown_budget_sec()`
# analiz bütçesi tükendikten SONRA bile en az 2 saniye TANIR; bu lütuf
# KAYNAKLARI BIRAKMAK içindir. Onu opsiyonel telemetriye harcamak, süresi ZATEN
# dolmuş bir isteğin (muhtemelen iki kez) yeni DB işi başlatması ve sert son
# tarihi aşarken işçiyi/bağlantıyı tutması demekti. Bütçe kalmadığında telemetri
# ATLANIR — gözlenebilirlik, son tarih garantisini bozamaz.
.pk_telemetry_bounded <- function(fn) {
  if (!exists(".db_with_elapsed_budget", mode = "function", inherits = TRUE) ||
      !exists(".db_pk_residual_budget_sec", mode = "function", inherits = TRUE)) {
    return(fn())
  }

  kalan <- tryCatch(.db_pk_residual_budget_sec(), error = function(e) Inf)
  if (length(kalan) != 1L || is.na(kalan)) kalan <- Inf
  if (is.finite(kalan) && kalan <= 0) {
    stop("PK analiz butcesi tukendi; telemetri atlandi.", call. = FALSE)
  }

  .db_with_elapsed_budget(kalan, fn)
}

# Bir telemetri hatası KALICI mı (tablo yok/kullanılamaz) yoksa GEÇİCİ mi
# (zaman aşımı/bağlantı) ?
#
# Yalnızca KALICI sonuçlar süreç-global durumda önbelleklenir: son tarihine
# yakın TEK bir istek, tablo ve DB sağlıklıyken bile telemetriyi o sürecin
# ÖMRÜ BOYUNCA kapatabilirdi.
.pk_telemetry_error_is_transient <- function(e) {
  metin <- tryCatch(conditionMessage(e), error = function(x) "")
  if (is.null(metin) || is.na(metin) || !nzchar(metin)) return(TRUE)

  isaretler <- c("butcesi tukendi", "reached elapsed time limit", "time limit",
                 "timeout", "Timeout", "connection", "Connection",
                 "Communication link", "TCP Provider")
  any(vapply(isaretler, function(p) grepl(p, metin, fixed = TRUE), logical(1)))
}

#' MB_Analiz_Log tablosunun kullanılabilirliğini süreç başına bir kez tespit et
#'
#' @return TRUE (yazılabilir) / FALSE (yok veya erişilemiyor).
pk_telemetry_table_ready <- function(conn, target = NULL) {
  hedef <- .pk_telemetry_target_key(target)
  onceki <- .pk_telemetry_state$ready_by_target[[hedef]]
  if (!is.null(onceki) && !is.na(onceki)) {
    return(isTRUE(onceki))
  }

  if (is.null(conn)) return(FALSE)

  # TAM ŞEMA doğrulanır: yalnızca `AnalizLogID` projeksiyonu, INSERT'in
  # kullandığı bir sütunu EKSİK olan eski bir tabloyu da "hazır" sayıyordu.
  # Bu durumda hazırlık TRUE önbelleklenir, her analiz aynı INSERT'i dener ve
  # başarısız olur; telemetri satırları sessizce hiç yazılmaz.
  sutunlar <- tryCatch(pk_telemetry_required_columns(), error = function(e) "AnalizLogID")
  projeksiyon <- sprintf(
    "SELECT %s FROM MB_Analiz_Log WHERE 1 = 0",
    paste(sutunlar, collapse = ", ")
  )

  gecici <- FALSE
  ready <- tryCatch({
    .pk_telemetry_bounded(function() DBI::dbGetQuery(conn, projeksiyon))
    TRUE
  }, error = function(e) {
    gecici <<- isTRUE(.pk_telemetry_error_is_transient(e))
    FALSE
  })

  # GEÇİCİ başarısızlık (zaman aşımı / bağlantı) ÖNBELLEKLENMEZ: aksi hâlde son
  # tarihine yakın TEK bir istek, tablo ve DB sonrasında sağlıklı olsa bile bu
  # sürecin/işçinin ÖMRÜ BOYUNCA telemetriyi kapatırdı. Yalnızca KESİN sonuç
  # ("tablo yok/kullanılamaz") saklanır.
  if (isTRUE(ready) || !isTRUE(gecici)) {
    .pk_telemetry_state$ready_by_target[[hedef]] <- ready
    # Geriye dönük tanılama alanı: son kesin karar.
    .pk_telemetry_state$ready <- ready
  }
  if (isTRUE(gecici)) return(FALSE)

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
#' @param db_target Hazırlık kararının anahtarlanacağı VERİTABANI HEDEFİ.
#'   Verilmezse etkin yürütme bağlamından çözülür.
#'
#'   HEDEF AÇIKÇA TAŞINIR: etkin yürütme bağlamı OLMAYAN yollarda (işçi
#'   doğrudan-çıkış telemetrisi, derin gözlem) `.pk_telemetry_target_key()`
#'   her bağlantıyı `"primary"` sayıyordu. Önbelleğe alınmış bir birincil
#'   karar, geçerli bir ikincil yazımı ATLAYABİLİYOR ya da geçersiz bir
#'   `INSERT`i ikincil bağlantıda YİNELEYEBİLİYORDU.
#' @return Görünmez TRUE (yazıldı) / FALSE (atlandı veya başarısız).
pk_telemetry_log_analysis <- function(info, conn, db_target = NULL) {
  tryCatch({
    if (!pk_telemetry_enabled()) return(invisible(FALSE))
    if (is.null(conn)) return(invisible(FALSE))
    hedef <- db_target %||% (if (is.list(info)) info$db_target else NULL)
    if (!pk_telemetry_table_ready(conn, target = hedef)) return(invisible(FALSE))

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

    .pk_telemetry_bounded(function() DBI::dbExecute(conn, sql, params = params))
    invisible(TRUE)

  }, error = function(e) {
    # KALICI bir şema hatası (eksik sütun / tablo kaybolmuş) hazırlık kararını
    # GEÇERSİZ KILAR: aksi hâlde önbellekteki TRUE yüzünden aynı geçersiz INSERT
    # her istekte yeniden denenirdi. Geçici hatalarda (zaman aşımı/bağlantı)
    # karar KORUNUR; tablo sağlıklıysa sonraki istek yine yazabilmelidir.
    if (!isTRUE(.pk_telemetry_error_is_transient(e))) {
      hedef_anahtari <- .pk_telemetry_target_key(
        db_target %||% (if (is.list(info)) info$db_target else NULL)
      )
      .pk_telemetry_state$ready_by_target[[hedef_anahtari]] <- NULL
      .pk_telemetry_state$ready <- NA
    }

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

    pk_telemetry_log_analysis(info, conn, db_target = info$db_target)

    invisible(footer)
  }, error = function(e) invisible(""))
}
