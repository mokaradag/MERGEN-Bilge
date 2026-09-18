# ==============================================================================
# Dosya Yolu: R/helpers_pk_sql_execute.R
# Faz 6: fiziksel bağlantı, duvar-saati timeout ve bellek tavanlı SQL getirimi.
# ==============================================================================

#' Kalan bütçeyle SINIRLI bloklayan DB çağrısı
#'
#' HER senkron sürücü çağrısı (checkout, kontrol ifadeleri, gönderim, getirim,
#' metadata, sonuç temizleme) bu sınırdan geçmelidir. Aksi hâlde tek bir askıda
#' kalan yardımcı çağrı, tüm analiz son tarihini ve iptali ETKİSİZ kılar:
#' istek zaman aşımına uğramış olsa bile işçi ve bağlantı meşgul kalır.
#'
#' @param budget_fn Kalan saniyeyi döndüren fonksiyon (`Inf` = bu katmanda
#'   bütçe yok).
#' @return `list(ok = TRUE, value = ) | list(ok = FALSE, status = , error = )`.
pk_sql_bounded_call <- function(fn, budget_fn, floor_sec = 0.05) {
  kalan <- tryCatch(budget_fn(), error = function(e) Inf)
  if (length(kalan) != 1L || is.na(kalan)) kalan <- Inf
  if (is.finite(kalan) && kalan <= 0) {
    return(list(ok = FALSE, status = "deadline", error = NA_character_))
  }

  deger <- tryCatch({
    if (is.finite(kalan)) {
      setTimeLimit(cpu = Inf, elapsed = max(floor_sec, kalan), transient = TRUE)
    }
    fn()
  }, error = function(e) e, finally = {
    if (is.finite(kalan)) {
      try(setTimeLimit(cpu = Inf, elapsed = Inf, transient = TRUE), silent = TRUE)
    }
  })

  if (!inherits(deger, "condition")) return(list(ok = TRUE, value = deger))
  list(ok = FALSE, status = "error", error = conditionMessage(deger))
}

.pk_sql_unicode_wrapper <- function() {
  paste("DECLARE @sql NVARCHAR(MAX);", "SET @sql = ?;", "EXEC sp_executesql @sql;", sep = "\n")
}

.pk_sql_frame_bytes <- function(df) {
  bayt <- tryCatch(as.numeric(utils::object.size(df)), error = function(e) NA_real_)
  if (length(bayt) != 1L || is.na(bayt) || !is.finite(bayt)) return(NA_real_)
  bayt
}

# NOT: eski `.pk_sql_has_unbounded_lob()` KALDIRILDI. İki ayrı kusuru vardı:
#
#   1) Sınıflandırma `dbColumnInfo()` çerçevesinin TÜM alanlarını (kolon ADI
#      dahil) düzleştirip tip adı arıyordu. Üretimdeki `odbc::OdbcResult`
#      yolunda `type` SAYISAL bir ODBC kodudur; dolayısıyla gerçek LOB'lar
#      YAKALANMIYOR, buna karşılık `text`/`xml` adlı bir kolon TAKMA ADI sonucu
#      tamamen reddedebiliyordu.
#   2) Kanıtlanamayan genişliği "kesinlikle çok büyük" sayıyordu. Kısa bir
#      `nvarchar(max)` değeri taşıyan TEK SATIRLIK sonuç da böylece
#      reddediliyordu — oysa sözleşme (§5.10) bu durumda ZORUNLU sınırlı-parça
#      getirimini seçmeyi söyler.
#
# Yerine `pk_sql_plan_chunk_rows()` (R/helpers_pk_result_size.R) kullanılır:
# metadata'dan KANITLANMIŞ satır genişliği türetilir, parça boyutu ona göre
# küçültülür ve kanıt yoksa granülarite tek satıra iner.

#' @param query_meta AÇIK sorgu metadata'sı. Derin analiz per-query yürütme
#'   bağlamı KURMAZ; örtük `pk_active_query_meta()` orada `NULL` döner ve
#'   `MERGEN_PK_RESULT_OVERHEAD_FACTOR` / `MERGEN_PK_ALLOW_UNBOUNDED_LOB` gibi
#'   sorgu override'ları ÖLÜ kalırdı. Verilmezse eski örtük davranış korunur.
pk_sql_execute_bounded <- function(conn, sql_text, unicode_param = TRUE,
                                   chunk_rows = 5000L, max_result_mb = 512,
                                   stop_check = NULL, stage_gate = NULL,
                                   timeout_sec = NULL, deadline_at = NULL,
                                   expected_rows = NA_real_,
                                   overhead_factor = NULL, query_meta = NULL) {
  etkin_meta <- query_meta %||% tryCatch(pk_active_query_meta(), error = function(e) NULL)
  bos <- function(status, error = NA_character_, data = NULL, rows = 0L,
                  bytes = 0, chunks = 0L, timeout_mechanism = "none") {
    list(status = status, data = data, rows = rows, bytes = bytes, chunks = chunks,
         error = error, timeout_mechanism = timeout_mechanism)
  }
  if (is.null(sql_text) || !nzchar(trimws(as.character(sql_text)[1]))) {
    return(bos("error", error = "Bos SQL metni gonderilemez."))
  }
  if (is.null(conn) || !requireNamespace("DBI", quietly = TRUE)) {
    return(bos("error", error = "DB baglantisi kullanilamiyor."))
  }

  beklenen_satir <- suppressWarnings(as.numeric(expected_rows)[1])
  if (length(beklenen_satir) != 1L) beklenen_satir <- NA_real_
  yuk_carpani <- suppressWarnings(as.numeric(
    overhead_factor %||% tryCatch(
      pk_config_resolve("MERGEN_PK_RESULT_OVERHEAD_FACTOR", etkin_meta),
      error = function(e) 2.5
    )
  )[1])
  if (length(yuk_carpani) != 1L || is.na(yuk_carpani) || !is.finite(yuk_carpani) ||
      yuk_carpani < 1) {
    yuk_carpani <- 2.5
  }

  parca_satir <- suppressWarnings(as.integer(chunk_rows)[1])
  if (length(parca_satir) != 1L || is.na(parca_satir) || parca_satir < 1L) parca_satir <- 5000L
  tavan_mb <- suppressWarnings(as.numeric(max_result_mb)[1])
  if (length(tavan_mb) != 1L || is.na(tavan_mb) || !is.finite(tavan_mb) || tavan_mb <= 0) {
    return(bos("too_large", error = "ceiling_unresolved"))
  }
  if (is.null(deadline_at)) deadline_at <- getOption("mergen.pk.async.deadline_at", NULL)
  if (is.null(timeout_sec)) {
    timeout_sec <- if (exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
      tryCatch(pk_config_resolve("MERGEN_PK_SQL_TIMEOUT_SEC"), error = function(e) 120L)
    } else 120L
  }

  plan <- pk_sql_timeout_plan(
    timeout_sec, if (is.null(deadline_at)) Inf else pk_deadline_remaining_sec(deadline_at)
  )
  if (!isTRUE(plan$dispatch)) return(bos("deadline", error = plan$reason))
  etkin_timeout <- suppressWarnings(as.numeric(plan$timeout_sec)[1])
  if (length(etkin_timeout) != 1L || is.na(etkin_timeout) || etkin_timeout < 0) etkin_timeout <- 0

  kapi <- function() {
    if (is.function(stage_gate)) {
      x <- tryCatch(stage_gate(), error = function(e) NULL)
      if (is.list(x) && isTRUE(x$halt)) return(as.character(x$status %||% "cancelled")[1])
      return("ok")
    }
    if (is.function(stop_check) &&
        isTRUE(tryCatch(stop_check(), error = function(e) FALSE))) return("cancelled")
    "ok"
  }
  ilk <- kapi()
  if (!identical(ilk, "ok")) return(bos(ilk))

  # Analiz bütçesi: kurulum/temizlik ÇAĞRILARI da bu bütçeden geçer.
  analiz_kalan <- function() {
    if (is.null(deadline_at)) Inf else pk_deadline_remaining_sec(deadline_at)
  }

  query_conn <- conn
  checked_out <- FALSE
  if (inherits(conn, "Pool")) {
    if (!requireNamespace("pool", quietly = TRUE)) {
      return(bos("error", error = "Pool baglantisi icin 'pool' paketi gerekli."))
    }
    # Checkout tek başına yeni bir FİZİKSEL ODBC bağlantısı kurabilir; yavaş bir
    # DSN/login burada kalan bütçeyi aşabilirdi.
    alim <- pk_sql_bounded_call(function() pool::poolCheckout(conn), analiz_kalan)
    if (!isTRUE(alim$ok)) {
      # `pk_sql_bounded_call()` yalnızca bütçe çağrıdan ÖNCE tükenmişse
      # `"deadline"` üretir; checkout SIRASINDA dolan bütçe genel bir hata
      # gibi görünür ve tipli son tarih sonucu KAYBOLURDU. Kalan bütçe burada
      # YENİDEN yoklanır.
      kalan <- analiz_kalan()
      durum <- if (identical(alim$status, "deadline") ||
                   (is.finite(kalan) && kalan <= 0)) "deadline" else "error"
      return(bos(durum, error = alim$error))
    }
    query_conn <- alim$value
    checked_out <- TRUE
  }

  # TEMİZLİK KAYDI CHECKOUT'TAN HEMEN SONRA GELİR: `pool::poolCheckout()` başarılı olup `checked_out <- TRUE` yazıldıktan SONRA, `on.exit()` kaydına kadar geçen HER satır korumasızdı. `pk_sql_apply_statement_timeout()` bir hata sinyalledi mi (kısmi bootstrap'ta "could not find function" yeter) fonksiyon `poolReturn()` de `.pk_sql_invalidate_connection()` de çalıştırmadan çıkıyor, checkout KALICI olarak sızıyordu; tekrarı havuzu tüketip sonraki istekleri checkout'ta blokluyordu.
  timeout_state <- list(mechanism = "none", applied = FALSE,
                        timeout_sec = 0L, previous = NA_integer_)

  # Sonuç kümesi temizliği de başarısız olabilir; o durumda bağlantı KİRLİDİR.
  sonuc_temiz <- new.env(parent = emptyenv())
  sonuc_temiz$dirty <- FALSE

  on.exit({
    # Temizlik de SINIRLIDIR: askıda kalan bir geri yükleme/iade çağrısı,
    # zaman aşımına uğramış bir isteğin işçisini ve bağlantısını tutmaya devam
    # ederdi. Temizliğin kendi tabanı vardır (bütçe tükense bile denenmelidir).
    temizlik_butce <- function() max(2, min(10, analiz_kalan()))
    geri_yukleme <- .pk_sql_restore_lock_timeout(query_conn, timeout_state, temizlik_butce)

    if (isTRUE(checked_out)) {
      # İSTEK BAŞINA TEMİZLİĞİ TAMAMLANMAMIŞ bağlantı havuza İADE EDİLMEZ:
      # sonraki ödünç alan bu isteğin `LOCK_TIMEOUT` değerini veya
      # temizlenmemiş bir sonuç kümesini devralırdı. Böyle bir bağlantı
      # geçersiz kılınır (fiziksel olarak kapatılır).
      kirli <- isTRUE(geri_yukleme$dirty) || isTRUE(sonuc_temiz$dirty)
      if (kirli) {
        .pk_sql_invalidate_connection(query_conn, temizlik_butce)
      } else {
        # `poolReturn()` SONUCU DENETLENİR (PR #703 incelemesi): `pk_sql_bounded_call()`
        # hata ATMAZ, `list(ok = FALSE, ...)` DÖNER. Eskiden `try()` bunu yutuyor
        # ve iade edilememiş checkout SESSİZCE kayboluyordu; tekrarı havuz
        # yuvalarını tüketip sonraki istekleri checkout'ta bloklardı.
        iade <- try(pk_sql_bounded_call(function() pool::poolReturn(query_conn),
                                        temizlik_butce), silent = TRUE)
        if (inherits(iade, "try-error") || !isTRUE(iade$ok)) {
          # İade edilemedi: bağlantı belirsiz durumda ve HÂLÂ ödünç alınmış
          # sayılıyor. Açıkça emekliye ayrılır (fiziksel kapatma) ve loglanır.
          .pk_sql_invalidate_connection(query_conn, temizlik_butce)
          if (exists("log_warn", mode = "function", inherits = TRUE)) {
            try(log_warn("[PK_SQL] Havuz iadesi basarisiz; checkout emekliye ayrildi."),
                silent = TRUE)
          }
        }
      }
    }
  }, add = TRUE)

  # ZAMAN AŞIMI UYGULAMASI ÖLÜMCÜL DEĞİLDİR: hata durumunda kilit bekleme
  # sınırından vazgeçilir, bağlantı temiz kalır ve temizlik kaydı ZATEN kuruludur.
  uygulanan_zaman_asimi <- try(
    pk_sql_apply_statement_timeout(query_conn, etkin_timeout, analiz_kalan),
    silent = TRUE
  )
  if (is.list(uygulanan_zaman_asimi) &&
      !inherits(uygulanan_zaman_asimi, "try-error")) {
    timeout_state <- uygulanan_zaman_asimi
  }
  mekanizma <- paste(c(
    if (inherits(query_conn, "OdbcConnection")) "odbc_interrupt" else character(0),
    if (isTRUE(timeout_state$applied)) "lock_timeout" else character(0)
  ), collapse = "+")
  if (!nzchar(mekanizma)) mekanizma <- timeout_state$mechanism %||% "none"


  ifade_son_tarihi <- if (is.finite(etkin_timeout) && etkin_timeout > 0) {
    Sys.time() + etkin_timeout
  } else as.POSIXct(NA)

  ifade_kalan <- function() {
    if (!is.na(ifade_son_tarihi)) {
      as.numeric(difftime(ifade_son_tarihi, Sys.time(), units = "secs"))
    } else Inf
  }

  bloklayan <- function(fn) {
    # HİÇBİR YENİ BLOKLAYAN ÇAĞRI DURDUR/SON TARİH SONRASINDA BAŞLATILMAZ.
    #
    # Yürütme birden çok bloklayan sürücü çağrısından oluşur (gönderim, kolon
    # metadata'sı, tanımlayıcı sondası, her parça getirimi). Kapı yalnızca
    # getirim döngüsünde yoklanıyordu; Durdur bir çağrının HEMEN ÖNCESİNDE
    # geldiğinde o çağrı yine de başlatılıyor ve işçi + DB oturumu tam bir
    # zaman aşımı süresi daha meşgul kalıyordu.
    #
    # DÜRÜSTLÜK NOTU: bu, ZATEN ÇALIŞAN bir ifadeyi kesmez. Uçuştaki bir ODBC
    # ifadesi için tek gerçek sınır `min(SQL zaman aşımı, kalan analiz bütçesi)`
    # elapsed sınırıdır (`interruptible = TRUE` ile odbc R kesmesini SQLCancel'a
    # çevirir). Kullanıcının BEKLEMEMESİ ise ana süreçteki son tarih bekçisiyle
    # garanti edilir (bkz. `server_handler_pk_async.R`).
    on_kapi <- kapi()
    if (!identical(on_kapi, "ok")) {
      return(list(ok = FALSE, status = on_kapi, error = NA_character_))
    }

    kalan_analiz <- analiz_kalan()
    kalan_ifade <- ifade_kalan()
    kalan <- min(kalan_analiz, kalan_ifade)
    if (is.finite(kalan) && kalan <= 0) {
      return(list(ok = FALSE,
                  status = if (is.finite(kalan_analiz) && kalan_analiz <= 0) "deadline" else "timeout",
                  error = NA_character_))
    }

    sonuc <- pk_sql_bounded_call(fn, function() kalan)
    if (isTRUE(sonuc$ok)) return(sonuc)

    ka <- analiz_kalan()
    ki <- ifade_kalan()
    durum <- if (is.finite(ka) && ka <= 0) "deadline" else if (is.finite(ki) && ki <= 0) "timeout" else "error"
    list(ok = FALSE, status = durum, error = sonuc$error)
  }

  metin <- enc2utf8(trimws(as.character(sql_text)[1]))

  # SÜRÜCÜ TANIMLAYICI SONDASI — `dbSendQuery()`'DEN ÖNCE.
  #
  # `dbColumnInfo()` üretimde yalnızca sayısal ODBC kodları verir ve orada
  # `varchar(max)` ile `varchar(200)` AYIRT EDİLEMEZ. SQL Server'ın kendi
  # tanımlayıcısı (`sys.dm_exec_describe_first_result_set`) hem GÜVENLİĞİ
  # (MAX sütunu materyalizasyondan ÖNCE yakalanır) hem PERFORMANSI (sıradan
  # metin sütunları tek satırlık getirime düşmez) sağlar.
  #
  # SIRA ZORUNLUDUR: aynı bağlantıda AÇIK bir sonuç kümesi varken ikinci bir
  # ifade çalıştırılamaz (MARS kapalı); bu yüzden sonda gönderimden ÖNCEDİR.
  sema <- if (exists("pk_sql_describe_result_schema", mode = "function", inherits = TRUE)) {
    tryCatch(pk_sql_describe_result_schema(query_conn, metin, call_fn = bloklayan),
             error = function(e) NULL)
  } else {
    NULL
  }

  gonderim <- bloklayan(function() {
    if (isTRUE(unicode_param)) {
      params <- if (exists("normalize_db_params", mode = "function", inherits = TRUE)) {
        normalize_db_params(list(metin))
      } else list(metin)
      DBI::dbSendQuery(query_conn, .pk_sql_unicode_wrapper(), params = params)
    } else DBI::dbSendQuery(query_conn, metin)
  })
  if (!isTRUE(gonderim$ok)) {
    return(bos(gonderim$status, error = gonderim$error, timeout_mechanism = mekanizma))
  }
  res <- gonderim$value
  on.exit({
    temizleme <- try(pk_sql_bounded_call(
      function() DBI::dbClearResult(res),
      function() max(2, min(10, analiz_kalan()))
    ), silent = TRUE)
    # Sonuç kümesi temizlenemediyse bağlantı KİRLİDİR; havuza iade edilmemelidir.
    if (inherits(temizleme, "try-error") || !isTRUE(temizleme$ok)) {
      sonuc_temiz$dirty <- TRUE
    }
  }, add = TRUE, after = FALSE)

  # Metadata dbFetch()'ten ÖNCE okunur ve GÜVENLİ PARÇA BOYUTUNU belirler.
  # Sınırsız/bilinmeyen tip sonucu REDDETMEZ; yalnızca materyalizasyon
  # granülaritesini düşürür (bkz. pk_sql_plan_chunk_rows).
  meta_okuma <- bloklayan(function() DBI::dbColumnInfo(res))
  kolon_bilgisi <- if (isTRUE(meta_okuma$ok)) meta_okuma$value else NULL
  # HER TERMİNAL DURUM AYNEN KORUNUR.
  #
  # Eskiden yalnızca `deadline`/`timeout` erken dönüyordu; kapı `dbColumnInfo()`
  # çağrısının HEMEN ÖNÜNDE `cancelled` verdiğinde durum DÜŞÜYOR, akış
  # metadata'sız devam ediyor ve iptal, bir sonraki kapı yoklamasına kadar
  # görünmüyordu. Metadata'sız plan artık kapalı-başarısız reddettiği için bu
  # yol iptali `too_large` diye raporlardı: TİPLİ SONUÇ KAYBOLURDU.
  if (!isTRUE(meta_okuma$ok) && !identical(meta_okuma$status, "ok")) {
    return(bos(meta_okuma$status, error = meta_okuma$error, timeout_mechanism = mekanizma))
  }

  parca_plani <- tryCatch(
    pk_sql_plan_chunk_rows(kolon_bilgisi, chunk_rows = parca_satir,
                           max_result_mb = tavan_mb,
                           schema = sema,
                           query_meta = etkin_meta,
                           # Yapılandırılmış yük çarpanı planlamaya da GİRER;
                           # aksi hâlde `MERGEN_PK_RESULT_OVERHEAD_FACTOR`
                           # override'ı sıradan getirimlerde ÖLÜ kalırdı
                           # (`expected_rows` normalde bilinmez).
                           overhead_factor = yuk_carpani),
    # PLANLAYICI HATASI güvenlik arızasıdır: çağıranın istediği parçaya
    # (normalde 5.000) dönmek, güvenli granülarite kurulamamışken büyük bir ilk
    # `dbFetch()` yapmak olurdu. Kapalı başarısız: tek satır.
    error = function(e) list(rows = 1L, bounded = FALSE,
                             reason = "plan_failed")
  )

  # Sınırsız LOB sütunu materyalizasyondan ÖNCE reddedilir: satır granülaritesi
  # tek bir LOB HÜCRESİNİ kesemez.
  if (isTRUE(parca_plani$refuse)) {
    return(bos("too_large",
               error = as.character(parca_plani$reason %||% "unbounded_lob_column")[1],
               timeout_mechanism = mekanizma))
  }

  parca_satir <- max(1L, suppressWarnings(as.integer(parca_plani$rows)[1]))
  if (is.na(parca_satir)) parca_satir <- 1L

  # ÖN DENETİM (preflight): satır sayısı ÖNCEDEN biliniyorsa (çağıran bir
  # `COUNT(*)`/katalog tahmini verdiyse) ve genişlik KANITLANMIŞ üst sınırlıysa,
  # tek bir parça bile getirmeden reddedilebilir. Bu, `MERGEN_PK_MAX_RESULT_MB`
  # ile `MERGEN_PK_RESULT_OVERHEAD_FACTOR` denetimlerine GERÇEK çalışma zamanı
  # etkisi kazandırır; öncesinde ikisi de yalnızca saf yardımcıda yaşıyordu.
  # Satır sayısı BİLİNMİYORSA hiçbir şey değişmez: parçalı yol zaten tavanı
  # parça parça uygular (ön denetim bir OPTİMİZASYONDUR, tek savunma değil).
  if (is.finite(beklenen_satir) && beklenen_satir >= 0 &&
      exists("pk_result_size_preflight", mode = "function", inherits = TRUE)) {
    genislik <- tryCatch(
      pk_result_width_upper_bound(pk_sql_columns_from_metadata(kolon_bilgisi, schema = sema)),
      error = function(e) NULL
    )
    on_denetim <- tryCatch(
      pk_result_size_preflight(beklenen_satir, genislik, tavan_mb,
                               overhead_factor = yuk_carpani),
      error = function(e) NULL
    )
    if (is.list(on_denetim) && identical(on_denetim$decision, "refuse")) {
      return(bos("too_large", error = on_denetim$reason %||% "preflight_refused",
                 timeout_mechanism = mekanizma))
    }
  }

  parcalar <- list()
  toplam_bayt <- 0
  toplam_satir <- 0L
  parca_sayisi <- 0L
  son_parca_bayt <- 0
  repeat {
    durum <- kapi()
    if (!identical(durum, "ok")) return(bos(durum, chunks = parca_sayisi,
                                             timeout_mechanism = mekanizma))

    # BİR SONRAKİ PARÇA, TEPE KULLANIMI TAVANI AŞACAKSA HİÇ GETİRİLMEZ.
    #
    # Getirim SONRASI bayt kapısı, parça ZATEN bellekte olduktan sonra çalışır.
    # Genişlik bilinmediğinde planlayıcı tek satırlık parça seçer; ilk satır
    # büyük ama tavanın altındaysa kabul edilir ve döngü HEMEN bir sonraki tam
    # satırı getirir. 512 MB tavan altında iki adet 300 MB'lık satır bu yüzden
    # `pk_chunk_accumulate_decision()` `too_large` diyemeden AYNI ANDA bellekte
    # olabiliyor ve işçi tipli reddi üretmek yerine OOM ile ölebiliyordu.
    #
    # Muhafazakâr tepe tahmini: birikmiş baytlar + BİR ÖNCEKİ parçanın boyutu
    # (bilinmiyorsa birikmiş toplam). Tavanın YARISINI aşan bir tepe beklentisi
    # varsa getirim BAŞLATILMAZ ve tipli `too_large` döner.
    # Sonuç TAMAMLANDIYSA projeksiyon anlamsızdır: sonraki getirim SIFIR
    # satırdır. Cevap alınamıyorsa karar ESKİSİ GİBİ reddetmektir (kapalı
    # başarısız).
    # EŞİK, HEMEN ALTINDAKİ BİRİKTİRME KARARIYLA AYNIDIR: `pk_chunk_accumulate_decision()` ilk parçadan SONRA `tavan_mb / 2` uygular; ön getirim kapısı tam tavanla karşılaştırınca ARDINDAN gelen karardan DAHA ZAYIF kalıyor ve açıklamayla çelişiyordu.
    if (parca_sayisi > 0L &&
        (toplam_bayt + son_parca_bayt) > (tavan_mb / 2 * .PK_RESULT_MB)) {
      # TAMAMLANMA DENETİMİ DE `bloklayan()` ÜZERİNDEN GEÇER.
      #
      # Doğrudan çağrı, sürücü tamamlanma denetiminde bloklarsa kalan analiz ve
      # ifade bütçelerini ATLIYORDU; asılı bir denetim getirimin kendisi kadar
      # etkili biçimde işçiyi tutar. Tipli zaman aşımı/durdurma durumu aynen
      # yukarı taşınır; denetim cevap veremezse karar ESKİSİ GİBİ reddetmektir.
      # İÇ `try()` KALDIRILDI: geri çağrı hiçbir koşul SİNYALLEMİYOR, bu yüzden
      # `pk_sql_bounded_call()` içindeki `setTimeLimit()` kesmesi de sürücü
      # hatası da `ok = TRUE` + `try-error` değeri olarak dönüyordu. Aşağıdaki
      # `!isTRUE(tamamlandi$value)` dalı o durumda `too_large` üretiyor ve zaman
      # aşımına uğramış/iptal edilmiş bir istek kullanıcıya "sonuç çok büyük"
      # diye raporlanıyordu. Sınıflandırma artık `bloklayan()` sorumluluğudur.
      tamamlandi <- bloklayan(function() isTRUE(DBI::dbHasCompleted(res)))
      if (!isTRUE(tamamlandi$ok)) {
        rm(parcalar)
        return(bos(tamamlandi$status, error = tamamlandi$error,
                   chunks = parca_sayisi, timeout_mechanism = mekanizma))
      }
      if (!isTRUE(tamamlandi$value)) {
        rm(parcalar)
        return(bos("too_large", error = "projected_peak_exceeds_ceiling",
                   chunks = parca_sayisi, timeout_mechanism = mekanizma))
      }
    }

    getirim <- bloklayan(function() DBI::dbFetch(res, n = parca_satir))
    if (!isTRUE(getirim$ok)) {
      return(bos(getirim$status, error = getirim$error, chunks = parca_sayisi,
                 timeout_mechanism = mekanizma))
    }
    parca <- getirim$value
    if (!is.data.frame(parca) || nrow(parca) == 0L) break

    parca_bayt <- .pk_sql_frame_bytes(parca)
    karar <- pk_chunk_accumulate_decision(
      toplam_bayt, parca_bayt, if (parca_sayisi == 0L) tavan_mb else tavan_mb / 2
    )
    if (!identical(karar$action, "accept")) {
      rm(parcalar)
      return(bos("too_large", error = karar$reason, chunks = parca_sayisi,
                 timeout_mechanism = mekanizma))
    }
    parca_sayisi <- parca_sayisi + 1L
    parcalar[[parca_sayisi]] <- parca
    son_parca_bayt <- parca_bayt
    toplam_bayt <- karar$total_bytes
    toplam_satir <- toplam_satir + nrow(parca)
    if (nrow(parca) < parca_satir) break
  }

  if (parca_sayisi == 0L) {
    bos_fetch <- bloklayan(function() DBI::dbFetch(res, n = 0L))
    if (!isTRUE(bos_fetch$ok)) return(bos(bos_fetch$status, error = bos_fetch$error,
                                          timeout_mechanism = mekanizma))
    veri <- bos_fetch$value
  } else if (parca_sayisi == 1L) {
    veri <- parcalar[[1]]
  } else {
    # BİRLEŞTİRME de pahalı bir aşamadır: `rbind` bir an için parçaların TAMAMI
    # ile birleşik frame'i AYNI ANDA tutar. Bu yüzden (a) hemen önce kapı tekrar
    # yoklanır ve (b) ikili tepe kullanımı tavana karşı kontrol edilir.
    durum <- kapi()
    if (!identical(durum, "ok")) {
      return(bos(durum, chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }
    if (is.finite(toplam_bayt) && (toplam_bayt * 2) > tavan_mb * 1024 * 1024) {
      rm(parcalar)
      return(bos("too_large", error = "assembly_would_exceed_max_result_mb",
                 chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }

    birlestirme <- bloklayan(function() do.call(rbind, parcalar))
    if (!isTRUE(birlestirme$ok)) {
      return(bos(birlestirme$status, error = birlestirme$error,
                 chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }
    veri <- birlestirme$value

    # Birleştirmeden SONRA da kapı yoklanır: durdurulan bir istek buradan
    # `ok` ile çıkmamalıdır.
    durum <- kapi()
    if (!identical(durum, "ok")) {
      return(bos(durum, chunks = parca_sayisi, timeout_mechanism = mekanizma))
    }
  }

  son_bayt <- .pk_sql_frame_bytes(veri)
  if (!is.data.frame(veri)) return(bos("error", error = "SQL sonucu data.frame degil.",
                                       chunks = parca_sayisi, timeout_mechanism = mekanizma))
  if (is.na(son_bayt) || son_bayt > tavan_mb * 1024 * 1024) {
    rm(veri)
    return(bos("too_large", error = "would_exceed_max_result_mb",
               chunks = parca_sayisi, timeout_mechanism = mekanizma))
  }
  list(status = "ok", data = veri, rows = nrow(veri), bytes = son_bayt,
       chunks = parca_sayisi, error = NA_character_, timeout_mechanism = mekanizma)
}
