# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_worker.R
# Faz 6: future işçisi PK giriş noktası.
# ==============================================================================

.pk_async_log <- function(fmt, ...) {
  metin <- try(sprintf(fmt, ...), silent = TRUE)
  if (!inherits(metin, "try-error")) try(cat(metin, "\n", sep = ""), silent = TRUE)
  invisible(NULL)
}

# `helpers_pk_async_request.R` globals paketini logger tanımlanmadan önce
# tanımlar. Manifestte bu dosya request helper'ından SONRA yüklendiği için,
# paketi burada bir kez genişletmek bootstrap'ın daha source() çalışmadan hata
# verdiği PSOCK yolunda `.pk_async_log` sembolünü de açıkça taşır.
.PK_ASYNC_GLOBALS_WRAPPER_MARK <- "pk_async_globals_log_wrapper"  # KENDINI SARMALAMA ENGELLENIR. Bu dosya AYNI ortamda IKINCI kez source edilirse (bootstrap sahne ortamina yeniden yukleme) `get0()` sarmalayicinin KENDISINI bulur. Isaret hem yeniden sarmalamayi hem de `_without_log` bagininin sarmalayiciya kaydirilmasini engeller; kaydirilsaydi sarmalayicinin govdesi CAGRI aninda kendini cozer ve her cagri sonsuz ozyinelemeye girerdi.
.pk_async_globals_aday <- get0("pk_async_worker_globals", mode = "function", inherits = TRUE, ifnotfound = NULL)
if (is.function(.pk_async_globals_aday) && !isTRUE(attr(.pk_async_globals_aday, .PK_ASYNC_GLOBALS_WRAPPER_MARK, exact = TRUE))) {
  .pk_async_worker_globals_without_log <- .pk_async_globals_aday
  pk_async_worker_globals <- function(force = FALSE) { paket <- .pk_async_worker_globals_without_log(force = force); paket$.pk_async_log <- .pk_async_log; paket }
  attr(pk_async_worker_globals, .PK_ASYNC_GLOBALS_WRAPPER_MARK) <- TRUE
}

pk_async_run_analysis <- function(request) {
  basladi <- Sys.time()
  tanilama <- list(bootstrap_cached = NA, bootstrap_loaded = 0L,
                   bootstrap_failed = character(0), entry_missing = character(0),
                   duration_ms = 0)

  bitir <- function(status, result = NULL, session_writes = list(), error = NA_character_) {
    tanilama$duration_ms <- as.numeric(difftime(Sys.time(), basladi, units = "secs")) * 1000
    # TERMİNAL YOL ARTIFACT KAPSAMINI KAPATIR. Başarı yolu kaydı ZATEN
    # `pk_artifact_release_tracked()` ile devreder; başarısız/iptal yollarının
    # bir kısmı da açıkça `discard` çağırır. Buradaki güvenlik ağı, ERKEN
    # dönüşlerin (bootstrap/config arızası) kapsamı AÇIK bırakmasını önler:
    # açık kalan bir kapsam sonraki isteğin dosyalarını izlemeye başlardı.
    if (!identical(status, "ok") &&
        exists("pk_artifact_discard_tracked", mode = "function", inherits = TRUE)) {
      try(pk_artifact_discard_tracked(), silent = TRUE)
    }
    list(status = status, result = result, session_writes = session_writes,
         error = error, diagnostics = tanilama)
  }
  if (!is.list(request)) return(bitir("error", error = "Gecersiz istek anlik goruntusu."))

  # ARTIFACT KAYIT KAPSAMI BU İSTEĞE AİTTİR (PR #703 incelemesi).
  #
  # Kapsam açılmadıkça `pk_artifact_track()` NO-OP'tur; böylece senkron/geri
  # alma yolundaki başarılı dışa aktarımlar süreç-global bir deftere BİRİKMEZ
  # ve sonraki bir isteğin `pk_artifact_discard_tracked()` çağrısı onları
  # SİLEMEZ. Kapsam her terminal yolda (release/discard) kapanır.
  if (exists("pk_artifact_scope_begin", mode = "function", inherits = TRUE)) {
    try(pk_artifact_scope_begin(request$request_id), silent = TRUE)
  }

  # Token/son tarih BOOTSTRAP'TAN ÖNCE türetilir. Temiz bir işçide bootstrap
  # manifest kaynaklarını ve SQL kütüphanesini yükler; yavaş/askıda bir repo
  # yolu, ilk kapı bootstrap'tan SONRA olsaydı Durdur'u yok sayar ve işçiyi
  # `MERGEN_PK_ANALYSIS_DEADLINE_SEC` ötesine taşırdı.
  jeton <- as.character(request$cancel_token %||% "")[1]
  if (!nzchar(jeton)) jeton <- NULL
  baslangic <- tryCatch(
    as.POSIXct(as.numeric(request$started_at_epoch %||% NA_real_), origin = "1970-01-01"),
    error = function(e) basladi
  )
  if (length(baslangic) != 1L || is.na(baslangic)) baslangic <- basladi
  son_tarih <- pk_deadline_at(baslangic, request$deadline_sec)

  # İşçinin KENDİ kapısı da GÜNCEL (per-query override uygulanmış) son tarihi
  # okur; aksi hâlde daha büyük bir sorgu bütçesi iç aşamalarda geçerli olur
  # ama dış kapı yine küresel değerde keserdi. Seçim öncesi override olamaz,
  # bu yüzden erken kapılarda dondurulmuş değere eşittir.
  etkin_son_tarih <- function() {
    aday <- getOption("mergen.pk.async.deadline_at", NULL)
    if (inherits(aday, "POSIXct") && length(aday) == 1L && !is.na(aday)) aday else son_tarih
  }

  bootstrap_oncesi <- pk_async_stage_gate(jeton, son_tarih)
  if (isTRUE(bootstrap_oncesi$halt)) return(bitir(bootstrap_oncesi$status))

  # Bootstrap'ın KENDİSİ de iptal/son tarih farkındadır: kaynak yükleme veya
  # havuz kurulumu askıda kalırsa tek bir ön kapı yeterli olmazdı.
  boot <- tryCatch(
    pk_async_worker_bootstrap(
      request$repo_root, request$bootstrap_files,
      stage_gate = function() pk_async_stage_gate(jeton, son_tarih),
      workers = request$worker_count,
      db_pool_options = request$db_pool_options,
      # Bootstrap'ın KENDİ dosya sistemi çağrıları da bu son tarihle sınırlanır.
      deadline_at = son_tarih
    ),
    error = function(e) list(ok = FALSE, loaded = 0L, failed = conditionMessage(e), cached = FALSE)
  )
  tanilama$bootstrap_cached <- isTRUE(boot$cached)
  tanilama$bootstrap_loaded <- as.integer(boot$loaded %||% 0L)
  tanilama$bootstrap_failed <- as.character(boot$failed %||% character(0))
  # Bootstrap içinde gözlenen iptal/son tarih, "altyapı arızası" DEĞİLDİR:
  # senkron yeniden denemeye düşmek kullanıcının Durdur'unu yok saymak olurdu.
  if (isTRUE(boot$halted)) {
    return(bitir(as.character(boot$halt_status %||% "cancelled")[1]))
  }
  if (!isTRUE(boot$ok)) {
    .pk_async_log("[PK_ASYNC] Isci bootstrap basarisiz: %s",
                  paste(utils::head(tanilama$bootstrap_failed, 5L), collapse = ", "))
    return(bitir("bootstrap_failed", error = "Isci yardimcilari yuklenemedi."))
  }

  hazir <- try(pk_async_worker_ready(), silent = TRUE)
  if (inherits(hazir, "try-error")) hazir <- list(ready = FALSE, missing = "unknown")
  if (!isTRUE(hazir$ready)) {
    tanilama$entry_missing <- as.character(hazir$missing %||% character(0))
    return(bitir("bootstrap_failed", error = "Isci giris noktalari eksik."))
  }

  # Ana süreçte çözülmüş yapılandırma (options() basamağı) işçide kurulur;
  # aksi hâlde kalıcı PSOCK işçisi ana süreçten FARKLI güvenlik sınırlarıyla
  # (ör. daha gevşek MERGEN_PK_MAX_RESULT_MB) çalışırdı.
  if (is.list(request$pk_config) && length(request$pk_config) > 0L) {
    eski_config <- tryCatch(pk_async_config_install(request$pk_config), error = function(e) NULL)
    # BOŞ dönüş, anlık görüntünün UYGULANAMADIĞI anlamına gelir (ör. option
    # anahtarı çözücüsü eksik). Devam etmek, işçinin gönderenin sınırları yerine
    # BAYAT ortam değerleriyle veya köprünün 512 MB / 5000 satır yerleşik
    # varsayılanlarıyla çalışması demektir; bu bir yapılandırma ARIZASIDIR.
    if (!is.list(eski_config) || length(eski_config) == 0L) {
      return(bitir("bootstrap_failed", error = "Istek yapilandirmasi iscide kurulamadi."))
    }
    on.exit(try(do.call(options, eski_config), silent = TRUE), add = TRUE)

    # ORTAM basamağı da eşitlenir: `pk_config_resolve()` ortamı options'tan
    # ÖNCE okur ve kalıcı bir işçinin BAYAT ortamı taze isteğin sınırlarını
    # yenerdi (ör. sıkılaştırılmış `MERGEN_PK_MAX_RESULT_MB` yok sayılırdı).
    ortam_geri <- tryCatch(pk_async_config_install_env(request$pk_config),
                           error = function(e) NULL)
    # ORTAM BASAMAĞI DA KAPALI BAŞARISIZDIR (PR #703 incelemesi).
    #
    # `pk_config_resolve()` ORTAMI options'tan ÖNCE okur. Ortam eşitlemesi
    # sessizce başarısız olursa, options anlık görüntüsü doğru kurulmuş olsa
    # bile SICAK bir işçinin ESKİ ve daha GEVŞEK ortam değeri isteği yönetirdi.
    if (!is.function(ortam_geri)) {
      return(bitir("bootstrap_failed",
                   error = "Istek yapilandirmasi isci ortamina kurulamadi."))
    }
    on.exit(try(ortam_geri(), silent = TRUE), add = TRUE)
  }

  # Sözde-anonim soru korelasyonu için taşınan TEK sır; hiçbir yere yazılmaz.
  if (is.list(request$pk_secrets) && length(request$pk_secrets) > 0L) {  # SENTINEL TASIYAN GORUNTU DE KURULUR: yalnizca KALDIRMA iceren bir goruntu atlanirsa SICAK isci silinmis anahtari omru boyunca korurdu.
    sir_geri <- tryCatch(pk_async_secret_install(request$pk_secrets), error = function(e) NULL)
    if (is.function(sir_geri)) on.exit(try(sir_geri(), silent = TRUE), add = TRUE)
  }

  stop_check <- function() isTRUE(pk_async_stage_gate(jeton, etkin_son_tarih())$halt)
  ilk_kapi <- pk_async_stage_gate(jeton, son_tarih)
  if (isTRUE(ilk_kapi$halt)) return(bitir(ilk_kapi$status))

  # Mutlak son tarih ve iptal jetonu, imzaları değişmeyen ara katmanların
  # (v1/v2 seçici, filtre LLM'i, telemetri) BLOKLAYAN çağrılarını kalan bütçeyle
  # sınırlayabilmesi için option olarak yayınlanır.
  eski_deadline_option <- getOption("mergen.pk.async.deadline_at", NULL)
  eski_token_option <- getOption("mergen.pk.async.cancel_token", NULL)
  eski_start_option <- getOption("mergen.pk.async.started_at", NULL)
  # `started_at` da yayınlanır: sorgu SEÇİLDİKTEN sonra `pk_set_exec_context()`
  # per-query `analysis_deadline_sec` override'ını uygularken geçen süreyi
  # SIFIRLAMAMALIDIR; mutlak son tarih hep AYNI başlangıçtan hesaplanır.
  options(mergen.pk.async.deadline_at = son_tarih,
          mergen.pk.async.cancel_token = jeton,
          mergen.pk.async.started_at = baslangic)
  on.exit(options(mergen.pk.async.deadline_at = eski_deadline_option,
                  mergen.pk.async.cancel_token = eski_token_option,
                  mergen.pk.async.started_at = eski_start_option), add = TRUE)


  vekil <- tryCatch(pk_async_worker_session(request), error = function(e) NULL)
  if (is.null(vekil)) return(bitir("error", error = "Oturum vekili kurulamadi."))

  motor <- as.character(request$engine %||% "")[1]
  if (motor %in% c("v1", "v2")) {
    eski_motor <- getOption("mergen.pk.engine", NULL)
    options(mergen.pk.engine = motor)
    on.exit(options(mergen.pk.engine = eski_motor), add = TRUE)
    eski_motor_env <- Sys.getenv("MERGEN_PK_ENGINE", unset = NA_character_)  # ORTAM BASAMAGI options'TAN ONCE OKUNUR (`pk_config_resolve()`) ve `pk_async_config_snapshot()` MERGEN_PK_ENGINE'i BILINCLI olarak DISLAR: SICAK bir PSOCK iscisinde kalan BAYAT deger istek anlik goruntusunu YENIYOR ve v2 gonderimi v1 hattinda kosuyordu.
    Sys.setenv(MERGEN_PK_ENGINE = motor)
    on.exit({ if (is.na(eski_motor_env)) Sys.unsetenv("MERGEN_PK_ENGINE") else Sys.setenv(MERGEN_PK_ENGINE = eski_motor_env) }, add = TRUE)
  }

  # Bootstrap edilen gerçek PK giriş noktası kendi lexical ortamında global
  # yardımcıları çözer. Override'lar async wrapper'ın değil BU pipeline ortamına
  # yazılmalıdır; PSOCK'ta ikisi aynı olmak zorunda değildir.
  # HEDEF ORTAM CEKIRDEGINDIR, SARMALAYICININ DEGIL: tek-cikis kancasi (`pk_hook_single_exit_fix_install()`) kuruldugunda `environment(pk_analiz_process_request)` OMURSUZ kurucu cercevesidir ve oraya yazilan sinirli yurutucuyu cekirdek HIC gormez (sinirsiz materyalizasyon kalir, Durdur/son tarih kapisi uygulanmazdi). `mergen_pk_force_bounded_sync()` ile AYNI cozumleme kullanilir.
  .pk_cekirdek_ad <- ".pk_analiz_process_request_without_exit_observer"
  target_env <- environment(if (exists(.pk_cekirdek_ad, mode = "function", inherits = TRUE)) get(.pk_cekirdek_ad, mode = "function", inherits = TRUE) else pk_analiz_process_request)
  if (!is.environment(target_env)) target_env <- environment(pk_analiz_process_request)
  eski_unicode <- get0("execute_pk_sql_unicode", envir = target_env,
                       inherits = TRUE, ifnotfound = NULL)

  # SQL sınırları SEÇİLEN SORGU metadata'sıyla, yani seçimden SONRA çözülür.
  # Tipli sonuç (timeout/too_large) modül sınırında karakter metne dönüştüğü
  # için ayrı bir kutuya not edilir; nihai durum ondan üretilir.
  sql_durum <- pk_async_sql_status_box()
  bounded_unicode <- pk_async_bounded_sql_executor(
    stage_gate = function() pk_async_stage_gate(jeton, etkin_son_tarih()),
    deadline_at = etkin_son_tarih,
    status_box = sql_durum
  )
  assign("execute_pk_sql_unicode", bounded_unicode, envir = target_env)
  on.exit({
    # ÖNCEKİ BAĞLAMA YOKSA GEÇİCİ BAĞLAMA KALDIRILIR.
    #
    # `get0()` önceki değer bulunmadığında `NULL` döner. Eski `on.exit`
    # yalnızca fonksiyon durumunda geri yazıyor, aksi hâlde SINIRLI
    # sarmalayıcıyı `target_env` içinde BIRAKIYORDU; aynı kalıcı PSOCK
    # işçisindeki BİR SONRAKİ istek o zaman ÖNCEKİ isteğin kapısı/son tarihiyle
    # çalışırdı.
    if (is.function(eski_unicode)) {
      assign("execute_pk_sql_unicode", eski_unicode, envir = target_env)
    } else if (exists("execute_pk_sql_unicode", envir = target_env, inherits = FALSE)) {
      rm("execute_pk_sql_unicode", envir = target_env)
    }
  }, add = TRUE)

  # Deep orkestratörün içeride türettiği iki kurucu dispatch bağlamına sabitlenir.
  if (isTRUE(request$deep_thinking)) {
    eski_deadline_fn <- get0("pk_deadline_at", envir = target_env, inherits = TRUE)
    eski_token_fn <- get0("pk_cancel_token_path", envir = target_env, inherits = TRUE)
    assign("pk_deadline_at", function(started_at, deadline_sec) etkin_son_tarih(), envir = target_env)
    assign("pk_cancel_token_path", function(request_id, base_dir = NULL) jeton, envir = target_env)
    on.exit({
      # Aynı gerekçe: önceki değer yoksa `NULL` ATANMAZ, bağlama KALDIRILIR.
      .pk_worker_restore <- function(ad, eski) {
        if (is.function(eski)) {
          assign(ad, eski, envir = target_env)
        } else if (exists(ad, envir = target_env, inherits = FALSE)) {
          rm(list = ad, envir = target_env)
        }
      }
      .pk_worker_restore("pk_deadline_at", eski_deadline_fn)
      .pk_worker_restore("pk_cancel_token_path", eski_token_fn)
    }, add = TRUE)
  }

  # Derin istek için giriş noktası YOKSA standart boru hattına SESSİZCE düşmek
  # yasaktır: kullanıcı istemediği bir analizi alırdı. Bootstrap doğrulaması
  # bunu zaten yakalar; bu ikinci kapı kısmi dağıtımlara karşı savunmadır.
  if (isTRUE(request$deep_thinking) &&
      !exists("pk_deep_analysis_process", mode = "function", inherits = TRUE)) {
    return(bitir("bootstrap_failed", error = "Derin analiz giris noktasi eksik."))
  }

  sonuc <- tryCatch({
    if (isTRUE(request$deep_thinking)) {
      pk_deep_analysis_process(
        request$user_prompt, request$chat_history, vekil,
        detail_level = request$detail_level, stop_check = stop_check
      )
    } else {
      pk_analiz_process_request(
        request$user_prompt, request$chat_history, vekil, stop_check = stop_check
      )
    }
  }, error = function(e) {
    .pk_async_log("[PK_ASYNC] Boru hatti hatasi: %s",
                  .pk_async_redact_for_log(conditionMessage(e)))
    structure(list(message = conditionMessage(e)), class = "pk_async_pipeline_error")
  })

  yazimlar <- tryCatch(pk_async_harvest_session(vekil), error = function(e) list())

  # KISMİ DERİN SONUÇ: `pk_deep_analysis_process()` bazı sorgular tamamlandıktan
  # sonra iptal/son tarih gördüğünde bağlamı `pk_partial_halt_status` ile
  # işaretleyip DÖNDÜRÜR. Aynı jeton/son tarih burada da hâlâ aktif olduğu için
  # koşulsuz bir son kapı bu kısmi sonucu ATAR ve yeni kısmi-sonuç yolu asenkron
  # kipte kullanıcıya HİÇ ULAŞAMAZDI. Zaten ELE ALINMIŞ bir halt tekrar
  # cezalandırılmaz.
  kismi <- is.list(sonuc) &&
    nzchar(as.character(sonuc$pk_partial_halt_status %||% "")[1])

  son_kapi <- pk_async_stage_gate(jeton, etkin_son_tarih())
  if (isTRUE(son_kapi$halt) && !isTRUE(kismi)) {
    # Boru hattı iptal/son tarih GÖZLENMEDEN önce büyük bir XLSX/CSV artifact'i
    # üretmiş olabilir. `sonuc` burada DÜŞÜRÜLDÜĞÜ için ana sürecin temizleyecek
    # bir yol listesi kalmazdı; dosyalar işçinin kalıcı temp dizininde ÖKSÜZ
    # kalırdı. Bu yüzden yerelde silinirler.
    try(pk_async_discard_worker_artifact(sonuc), silent = TRUE)
    # `sonuc` üzerinden ERİŞİLEMEYEN artifact'ler de vardır: `.pk_result_v2()`
    # dışa aktarımı ürettikten HEMEN SONRA Durdur gelirse `list(type =
    # "pk_stopped")` döner ve yollar kaybolur. Bu yüzden üretim anında
    # KAYDEDİLEN artifact kaydı da boşaltılır.
    try(pk_artifact_discard_tracked(), silent = TRUE)
    return(bitir(son_kapi$status, session_writes = yazimlar))
  }
  if (inherits(sonuc, "pk_async_pipeline_error")) {
    try(pk_artifact_discard_tracked(), silent = TRUE)
    return(bitir("error", session_writes = yazimlar,
                 error = .pk_async_safe_error_text(sonuc$message)))
  }

  # Modül sınırı tipli SQL sonucunu karakter metne dönüştürür; gerçek durum
  # kutudan geri alınır. Aksi hâlde bir SQL zaman aşımı `status = "ok"` olarak
  # raporlanır ve tipli-sonuç sözleşmesi (§5.11) sessizce bozulurdu.
  if (!is.na(sql_durum$status) && is.character(sonuc)) {
    try(pk_async_discard_worker_artifact(sonuc), silent = TRUE)
    try(pk_artifact_discard_tracked(), silent = TRUE)
    return(bitir(sql_durum$status, session_writes = yazimlar,
                 error = as.character(sonuc)[1]))
  }

  # BAŞARILI yolda artifact ana sürece TESLİM EDİLİR; kayıt yalnızca sahiplik
  # devri olarak boşaltılır (dosyalar SİLİNMEZ).
  try(pk_artifact_release_tracked(), silent = TRUE)

  # Ana süreç data'yı tüketmez; büyük frame future IPC'den önce bırakılır.
  if (is.list(sonuc) && !is.null(sonuc$data)) sonuc$data <- NULL
  bitir("ok", result = sonuc, session_writes = yazimlar)
}

# Beklenmeyen işçi istisnaları KULLANICIYA HİÇBİR ZAMAN ham dönmez. Bir
# allowlist ("DB gibi görünen metinleri genelleştir") yetersizdi: dışa aktarım/
# dosya yolları, ana bilgisayar adları ve uygulama iç ayrıntıları o listeye
# uymadıkları için olduğu gibi sohbete sızabiliyordu. Redakte edilmiş ORİJİNAL
# yalnızca SUNUCU LOGUNA yazılır.
PK_ASYNC_GENERIC_ERROR_MESSAGE <- "Analiz sirasinda beklenmeyen bir hata olustu."

.pk_async_redact_for_log <- function(message) {
  ham <- tryCatch(as.character(message)[1], error = function(e) NA_character_)
  if (is.null(ham) || !length(ham) || is.na(ham) || !nzchar(ham)) {
    return("Bilinmeyen analiz hatasi.")
  }
  # PR #705 (P1): LOG sinirinda BAGLANTI TANIMLAYICILARI da maskelenir.
  #
  # Genel `redact_sensitive_text()` KIMLIK BILGISI alanlarini maskeler ama
  # `DSN=PrivateProd`, `UID=alice`, `Server=corp-internal\SQL01` degerlerini
  # BILEREK korur (kullanici adi tek basina sir degildir). Burada metin KALICI
  # sunucu log'una yazilir ve depo sozlesmesi ozel DSN'lerin log'lanmasini
  # ACIKCA yasaklar; bu alanlar iç altyapiyi yeniden kurmaya yeter.
  # GENEL REDAKTORE GERI DUSULMEZ: `redact_sensitive_text()` tam da yukarida sayilan alanlari KORUR; geri dusmek bu korumayi tamamen kaldirirdi.
  if (exists("redact_connection_identifiers", mode = "function", inherits = TRUE)) {
    ham <- tryCatch(redact_connection_identifiers(ham),
                    error = function(e) "[redaksiyon basarisiz - ham metin gizlendi]")
  } else {
    # KAPALI BASARISIZ: redaktor hic yuklenmemisse ham metin LOG'A YAZILMAZ.
    return("[redaktor yuklenmedi - ham metin gizlendi]")
  }
  substr(ham, 1L, 400L)
}

.pk_async_safe_error_text <- function(message) {
  redakte <- .pk_async_redact_for_log(message)
  .pk_async_log("[PK_ASYNC] Isci hatasi (redakte): %s", redakte)

  # SINIFLANDIRMA HAM METINDEN, KAYIT REDAKTE METINDEN.
  #
  # Sinif tespiti redakte edilmis metne bakarsa, redaksiyon ne kadar guclu
  # olursa tespit o kadar korlesir: `DSN=<redacted>` gibi maskelenmis bir
  # deger, altyapi imzasini SILEBILIR ve gercek bir DB hatasi "genel hata"
  # olarak raporlanir. Ham metin YALNIZCA bellekte, siniflandirma icin
  # okunur; ASLA log'a ya da kullaniciya TASINMAZ.
  ham <- tryCatch(as.character(message)[1], error = function(e) NA_character_)
  if (is.null(ham) || !length(ham) || is.na(ham)) ham <- ""

  # D22 sözleşmesi korunur: DB/sürücü kaynaklı hatalar kullanıcıya "teknik bir
  # hata" olarak bildirilir (ham DSN/nanodbc/SQLSTATE metni ASLA taşınmaz).
  # IMZA ESLESMESI BUYUK/KUCUK HARFTEN BAGIMSIZDIR (`dsn=`, `odbc`, `sqlstate`). Katlama YEREL `chartr()` iledir: `tolower()` Turkce yerelde `I` -> noktasiz `i` uretir, `pk_ascii_lower()` ise iscide yuklu olmayabilir.
  .AZ <- "ABCDEFGHIJKLMNOPQRSTUVWXYZ"; .az <- "abcdefghijklmnopqrstuvwxyz"
  ham_duz <- chartr(.AZ, .az, ham); redakte_duz <- chartr(.AZ, .az, redakte)
  altyapi <- chartr(.AZ, .az, c("nanodbc", "SQLSTATE", "DSN=", "ODBC", "Driver", "sp_executesql", "TCP Provider", "SQL Server"))
  if (any(vapply(altyapi, function(p) {
        grepl(p, ham_duz, fixed = TRUE) || grepl(p, redakte_duz, fixed = TRUE)
      }, logical(1)))) {
    return("Veritabani erisiminde teknik bir hata olustu.")
  }

  # Diğer HER istisna GENEL mesaja indirgenir. Yalnızca DB-benzeri metinleri
  # genelleştiren eski allowlist yetersizdi: dışa aktarım/dosya yolu, ana
  # bilgisayar adı veya uygulama iç ayrıntısı taşıyan bir hata metni o listeye
  # uymadığı için olduğu gibi sohbete sızabiliyordu.
  PK_ASYNC_GENERIC_ERROR_MESSAGE
}
