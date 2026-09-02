# ==============================================================================
# Dosya Yolu: R/server_handler_pk_async.R
# Faz 6: PK async ana-süreç gönderim ve callback yaşam döngüsü.
# ==============================================================================

# NOT: derin gözlemci fabrika-kapsamı sarmalayıcısı ARTIK BURADA DEĞİLDİR.
# `R/helpers_pk_worker_observers.R` içine taşındı; böylece (a) temiz bir PSOCK
# işçisi de aynı kapsamı alır ve (b) sarmalayıcı yeniden source'a karşı
# IDEMPOTENT'tir (burada her yüklemede zincir büyüyordu).

mergen_pk_analysis_execute <- function(ctx) {
  stopped <- try(ctx$stop_generation(), silent = TRUE)
  if (!inherits(stopped, "try-error") && isTRUE(stopped)) return(list(action = "stop"))

  # İSTEĞİN ORİJİNAL BAŞLANGICI. Bu andan türetilen MUTLAK son tarih, hangi
  # yola gidilirse gidilsin (işçi, degrade senkron, hazırlık sonrası senkron
  # yedek) TEK kalır: hiçbir yeniden deneme taze bir bütçe almaz.
  istek_baslangici <- Sys.time()

  # JETON SAHİPLİĞİ YALNIZCA JETONU TÜKETEN YOL İÇİN KAYDEDİLİR.
  #
  # `MERGEN_PK_ASYNC=false` (geri alma) durumunda senkron yol `stop_generation`
  # kullanır, dosya jetonunu DEĞİL. Sahiplik yine de kaydedilseydi Durdur
  # gözlemcisi bir `.flag` dosyası yazar, ama o yolda dosyayı temizleyecek bir
  # `bitir_istek()` OLMADIĞI için durdurulan her senkron PK isteği geride iptal
  # artefaktı bırakırdı.
  #
  # Yapılandırma sözleşmesi sorgu metadata'sına EN YÜKSEK önceliği verir.
  # Yönlendirme kararı `NULL` metadata ile alınırsa, `async = FALSE` işaretli
  # bir üretim sorgusu global bayrak açıkken yine işçiye gönderilirdi.
  aktif_meta <- mergen_pk_routing_query_meta(ctx)
  uygun <- pk_async_available(aktif_meta)
  if (!isTRUE(uygun$available)) {
    if (!identical(uygun$reason, "flag_off")) {
      log_info(sprintf("[PK_ASYNC] Async yok (%s); senkron yol.", uygun$reason))
    }
    # SINIRLI SQL GÜVENLİĞİ DEGRADE YOLDA DA KORUNUR: `flag_off` bilinçli geri
    # almadır (eski davranış), ama yetenek sondası başarısız olduğunda (plan
    # yok, bağımlılık eksik) standart senkron boru hattı bu PR'ın getirdiği
    # bellek/son tarih sınırlarını ATLAR. Bu yüzden o yolda sınırlı yürütücü
    # AÇIKÇA etkinleştirilir.
    if (!identical(uygun$reason, "flag_off")) {
      geri_al <- mergen_pk_force_bounded_sync(stop_check = ctx$stop_generation,
                                              started_at = istek_baslangici)
      on.exit(try(geri_al(), silent = TRUE), add = TRUE)
    }
    return(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), ctx$messages_to_process))
  }

  # JETON SAHİPLİĞİ hazırlığın SONUNDA (ve kapalı başarısız olarak) kaydedilir;
  # bkz. `mergen_pk_prepare_async_request()`. Burada ÖN kayıt yapmak, hazırlık
  # iptal olduğunda (kimlik hazır değil, anlık görüntü güvensiz) hiçbir yolun
  # temizlemediği bayat bir sahiplik bırakırdı.
  hazirlik <- mergen_pk_prepare_async_request(ctx, started_at = istek_baslangici)
  if (!isTRUE(hazirlik$ok)) {
    if (isTRUE(hazirlik$fallback_sync)) {
      # ASENKRON NİYETİ AÇIKTI: senkron yola düşülse bile Faz 6 sınırları
      # (parçalı getirim, sonuç tavanı, mutlak son tarih, Durdur kapısı)
      # KORUNUR ve bütçe orijinal başlangıçtan sayılır.
      geri_al <- mergen_pk_force_bounded_sync(stop_check = ctx$stop_generation,
                                              started_at = istek_baslangici)
      on.exit(try(geri_al(), silent = TRUE), add = TRUE)
      return(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), ctx$messages_to_process))
    }
    return(list(action = "answer", answer = hazirlik$answer, chips = list()))
  }
  mergen_pk_dispatch_async(ctx, hazirlik$request, hazirlik$cancel_token)
}

mergen_pk_dispatch_async <- function(ctx, request, cancel_token) {
  req_id <- as.character(ctx$req_id %||% "")[1]
  mesajlar <- ctx$messages_to_process
  oturum <- ctx$session

  # Kaydedilmemiş sohbetler için `NULL` TEK bir sentinel'e katlanıyordu; bu
  # yüzden "kaydedilmemiş sohbet A" ile "Yeni Sohbet'ten sonraki kaydedilmemiş
  # sohbet B" ayırt EDİLEMİYORDU ve eski işçi sonucu taze sohbete düşebiliyordu.
  # Kaydedilmemiş sohbet artık oturum-yerel bir NESİL sayacıyla etiketlenir.
  kaynak_chat_key <- mergen_pk_chat_identity(oturum, ctx$values)

  request_done <- FALSE
  bekci_iptal <- NULL
  # BAYAT JETON SÜPÜRÜCÜSÜ (sızıntı önleme; en iyi çaba, SINIRLI).
  #
  # Kayıp bir işçinin jetonu artık zamanlayıcıyla silinmez (aşağıdaki bekçi
  # notu). Yaş tabanlı süpürücü yalnızca varsayılan analiz son tarihinin çok
  # ötesindeki dosyalara dokunur, bu yüzden AKTİF bir isteğin jetonunu asla
  # kaldırmaz. Süreç çökmesinden kalan dosyalar da böyle toplanır.
  if (exists("pk_cancel_token_cleanup_stale", mode = "function", inherits = TRUE)) {
    try(pk_cancel_token_cleanup_stale(), silent = TRUE)
  }
  # Jeton YALNIZCA işçi future'ı yerleştiğinde temizlenir (bkz. bekçi notu).
  jeton_yerlesmede_temizle <- function() {
    try(pk_cancel_token_clear(cancel_token), silent = TRUE)
  }

  butce_birak <- function() {
    try(shiny::isolate(
      mergen_send_message_release_values_token(ctx$values, req_id = req_id)
    ), silent = TRUE)
  }

  bitir_istek <- function() {
    request_done <<- TRUE
    # Son tarih bekçisi ARTIK GEREKSİZ: istek terminal duruma ulaştı.
    if (is.function(bekci_iptal)) {
      try(bekci_iptal(), silent = TRUE)
      bekci_iptal <<- NULL
    }
    # JETON TEMİZLİĞİ FAIL-SOFT'TUR: dosya (ör. Windows'ta kilitliyken) kaldırılamazsa yardımcı hata sinyaller; terminal temizlik (`is_sending`, yazıyor sarmalayıcısı, backpressure) YİNE tamamlanmalıdır. Aksi hâlde `bitir_istek()` fırlatıyor, `promises::catch()` içindeki ikinci çağrı da fırlatıyor ve sohbet oturum sonuna kadar KİLİTLİ kalıyordu.
    try(pk_cancel_token_clear(cancel_token), silent = TRUE)
    try(mergen_pk_unregister_active_request(oturum, req_id), silent = TRUE)
    # SAHİPLİK DE KALDIRILIR. Bu fonksiyon başarılı analizde `devam_et()`'in
    # nihai LLM'i AYNI istek kimliğiyle başlatmasından ÖNCE çalışır; sahiplik
    # kalırsa o sırada basılan Durdur `mergen_pk_request_has_cancel_token()`
    # denetimini geçer ve işçi ÇOKTAN bittiği hâlde yeni bir `.flag` dosyası
    # yazılır. O dosyayı temizleyecek bir PK yolu artık yoktur.
    try(mergen_pk_unregister_cancel_token(oturum, req_id), silent = TRUE)
  }

  # SENKRON YEDEK: SADECE GÖNDERİM ÖNCESİ yollarda kullanılır (kayıt defteri
  # hatası, dispatch hatası). Orada henüz bir promise geri çağrısında değiliz ve
  # çağıran zaten senkron akıştadır.
  #
  # İKİ SÖZLEŞME BİRDEN korunur:
  #   1) ORİJİNAL BÜTÇE: gönderim hatası zaten süre harcadı; taze bir son tarih
  #      vermek toplam duvar saatini ikiye katlar.
  #   2) SINIRLI SQL: asenkron niyeti AÇIKTI, bu yüzden parçalı getirim/sonuç
  #      tavanı/Durdur kapısı senkron yolda da uygulanır (aksi hâlde bir gönderim
  #      hatası tam `dbGetQuery()` materyalizasyonuna geri dönerdi).
  sinirli_senkron <- function(etiket) shiny::isolate({
    kalan <- mergen_pk_residual_budget_sec(request)
    if (is.finite(kalan) && kalan <= 0) {
      log_warn(sprintf("[PK_ASYNC] %s: kalan butce yok; senkron yeniden deneme YAPILMADI.", etiket))
      return(list(action = "answer", answer = pk_async_halt_message("deadline"),
                  messages_to_process = mesajlar, chips = list()))
    }
    geri_al <- mergen_pk_force_bounded_sync(
      stop_check = ctx$stop_generation,
      started_at = mergen_pk_request_started_at(request) %||% Sys.time(),
      deadline_at = mergen_pk_request_deadline_at(request)
    )
    on.exit(try(geri_al(), silent = TRUE), add = TRUE)
    mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), mesajlar)
  })

  # Oturum-sonu kancası OTURUM BAŞINA TEKTİR (bkz. helpers_pk_async_lifecycle.R):
  # istek başına bir kapanış kaydetmek, tamamlanan HER isteğin gönderim
  # çerçevesini oturum ömrü boyunca canlı tutuyordu. Kanca, kayıt defterindeki
  # AKTİF istekleri iptal eder ve backpressure yuvalarını bırakır — bir kopma
  # fırtınası aksi hâlde sağlıklı oturumlara dakikalarca "sunucu meşgul" derdi.
  # KAYIT SONUCU KORUNUR. Eskiden `try` bloğu koşulsuz `TRUE` üretiyordu; kayıt
  # defteri `FALSE` dönse (ör. `session$userData` alınamadı) bile gönderim
  # yapılıyor ve oturum-sonu iptali/backpressure bırakma o isteği BULAMIYORDU.
  kayit <- try(
    isTRUE(mergen_pk_register_active_request(oturum, req_id, cancel_token, butce_birak)),
    silent = TRUE
  )
  if (!identical(kayit, TRUE)) {
    log_warn("[PK_ASYNC] Aktif istek kaydi yapilamadi; senkron yola donuluyor.")
    # Yaşam döngüsü koruması KURULAMADIYSA asenkron gönderim yapılmaz: iptal
    # edilemeyen ve backpressure'ı bırakılamayan bir işçi bırakmak, senkron
    # yolun bloklamasından daha kötüdür.
    # JETON TEMİZLİĞİ FAIL-SOFT'TUR: dosya (ör. Windows'ta kilitliyken) kaldırılamazsa yardımcı hata sinyaller; terminal temizlik (`is_sending`, yazıyor sarmalayıcısı, backpressure) YİNE tamamlanmalıdır. Aksi hâlde `bitir_istek()` fırlatıyor, `promises::catch()` içindeki ikinci çağrı da fırlatıyor ve sohbet oturum sonuna kadar KİLİTLİ kalıyordu.
    try(pk_cancel_token_clear(cancel_token), silent = TRUE)
    try(mergen_pk_unregister_cancel_token(oturum, req_id), silent = TRUE)
    return(sinirli_senkron("active_registry_failed"))
  }

  # continuation ve message insertion alt çağrıları da reactive okuyabildiği için
  # callback'teki tüm gövde isolate edilir.
  devam_et <- function(uygulama) shiny::isolate({
    if (identical(uygulama$action, "answer")) {
      ctx$cleanup_send_message()
      # KÖKEN ALT BİLGİSİ: `add_message_fn` (çalışma zamanı `add_message()`)
      # AI mesajlarında `pk_provenance_decorate()` çağırdığı için terminal
      # yanıtlar da alt bilgiyi ALIR. Mesaj kimliği ise çipler için ZORUNLUDUR
      # (aşağıya bakınız).
      # `add_message_fn()` MESAJ LİSTESİ döndürür; çip tüketicisi seçicisini bu
      # değerden kurduğu için hiçbir DOM düğümünün taşımadığı bir sarmalayıcı
      # kimliği arıyor ve terminal yanıtın çipleri KAYBOLUYORDU. `id` alanı
      # alınır; eski davranışa (düz kimlik) da uyumlu kalınır.
      eklenen <- ctx$add_message_fn(uygulama$answer, "ai")
      mesaj_kimligi <- if (is.list(eklenen)) {
        as.character(eklenen$id %||% "")[1]
      } else {
        as.character(eklenen %||% "")[1]
      }
      if (length(mesaj_kimligi) != 1L || is.na(mesaj_kimligi)) mesaj_kimligi <- ""
      if (exists("mergen_pk_emit_chips", mode = "function", inherits = TRUE)) {
        try(mergen_pk_emit_chips(ctx, uygulama$chips, message_id = mesaj_kimligi),
            silent = TRUE)
      }
      return(invisible(NULL))
    }
    ctx$continue_fn(uygulama$messages_to_process, uygulama$max_output_tokens)
  })

  koruma_gecti <- function(etiket, result = NULL) {
    # Oturum KAPANDIYSA hiçbir geri çağrı uygulanamaz. Yalnızca jetonu
    # işaretlemek yetmez: future zaten tamamlanmışsa jeton geç kalır ve
    # istek kimliği/stop bayrağı/sohbet kimliği değişmediği için koruma
    # geçebilirdi (kapalı bir oturumda export sunmak, oturum yazımı uygulamak
    # ve nihai LLM'i tetiklemek demek olurdu).
    if (!isTRUE(mergen_pk_session_open(oturum))) {
      log_info(sprintf("[PK_ASYNC] Callback yok sayildi (%s, sebep=session_ended).", etiket))
      bitir_istek()
      try(mergen_pk_cleanup_worker_artifact(result), silent = TRUE)
      butce_birak()
      return(FALSE)
    }

    aktif <- try(shiny::isolate(ctx$active_request_id()), silent = TRUE)
    if (inherits(aktif, "try-error")) aktif <- NULL
    stopped <- try(shiny::isolate(ctx$stop_generation()), silent = TRUE)
    stopped <- !inherits(stopped, "try-error") && isTRUE(stopped)
    # AÇIKÇA TERK EDİLMİŞ istek: kullanıcı A -> B -> A gezindiğinde istek
    # kimliği ve sohbet kimliği yeniden EŞLEŞEBİLİR; terk işareti olmadan bu
    # sonuç kabul edilir ve bayat yanıt/oturum yazımları uygulanırdı.
    if (isTRUE(try(mergen_pk_request_abandoned(oturum, req_id), silent = TRUE))) {
      stopped <- TRUE
    }
    karar <- pk_async_should_apply(aktif, req_id, stopped = stopped)

    simdiki <- mergen_pk_chat_identity(oturum, ctx$values)
    ayni_chat <- identical(simdiki, kaynak_chat_key)
    if (isTRUE(karar$apply) && isTRUE(ayni_chat)) return(TRUE)

    sebep <- if (!isTRUE(karar$apply)) karar$reason else "chat_changed"
    log_info(sprintf("[PK_ASYNC] Callback yok sayildi (%s, sebep=%s).", etiket, sebep))
    bitir_istek()
    try(mergen_pk_cleanup_worker_artifact(result), silent = TRUE)
    butce_birak()

    # SOHBET DEĞİŞTİ ama istek kimliği HÂLÂ BU İSTEK: kullanıcı yeni bir istek
    # başlatmadı, yalnızca gezindi. Gönderim durumu (`is_sending`) burada
    # temizlenmezse yeni sohbet eski isteğin durdur/gönder kilidinde takılı
    # kalırdı. Gerçekten BAYAT kimlikler için davranış değişmez (no-op).
    #
    # KAPI `karar$apply` DEĞİL, İSTEK KİMLİĞİDİR. Terk işareti (`abandoned`)
    # `stopped = TRUE` yapar ve `pk_async_should_apply()` `apply = FALSE`
    # döndürür; sohbet gezinmesi tam da bu işareti koyduğu için temizlik dalı
    # HİÇ çalışmıyor, `values$is_sending` ve yazma sarmalayıcısı yeni açılan
    # sohbette TAKILI kalıyordu. Gerçekten BAYAT bir kimlik için davranış
    # değişmez: `aktif` başka bir isteği gösterdiğinde koşul zaten FALSE'tur.
    if (identical(aktif, req_id) && !isTRUE(ayni_chat)) {
      try(shiny::isolate(ctx$cleanup_send_message()), silent = TRUE)
    }
    FALSE
  }

  # ALTYAPI ARIZASI PROMISE GERİ ÇAĞRISINDA SENKRON OLARAK TEKRAR OYNATILMAZ.
  #
  # `then()` geri çağrısı ANA SHINY SÜRECİNDE çalışır: orada `mergen_pk_run_sync()`
  # çağırmak uzun bir SQL/LLM turunu olay döngüsüne taşır ve o R sürecindeki
  # HER oturumu dondurur — üstelik geri çağrı bloklandığı sürece kullanıcının
  # Durdur olayı da işlenemez. Bu tam olarak Faz 6'nın ortadan kaldırdığı D15
  # donmasıdır. Bu yüzden geri çağrı yolunda TİPLİ bir altyapı hatası döndürülür.
  altyapi_hatasi <- function(etiket) {
    log_warn(sprintf("[PK_ASYNC] %s: senkron tekrar oynatma YAPILMADI (olay dongusu korunuyor).",
                     etiket))
    list(action = "answer",
         answer = mergen_pk_worker_outcome_text("infrastructure"),
         messages_to_process = mesajlar, chips = list())
  }

  # SUNULMUŞ artifact temizlik kapsamında tutulur: devam kapanışı hata verirse
  # (LLM kesintisi, mesaj ekleme hatası) bağlantısını içeren bir yanıt HİÇ
  # işlenmez ve işçinin ürettiği XLSX/CSV oturum sonuna kadar erişilemez biçimde
  # diskte kalırdı. Tekrarlanan kesintilerde bu, uzun ömürlü oturumlarda
  # birikir.
  sunulan_sonuc <- NULL

  session_token <- try(oturum$token, silent = TRUE)
  if (inherits(session_token, "try-error")) session_token <- NULL
  vaat <- try(
    tracked_future_promise(
      # `pk_async_run_analysis()` ANA SÜREÇTE tanımlanmış bir kapanıştır:
      # serileştirildiğinde lexical ortamı İŞÇİNİN `globalenv()`'i olur ve
      # explicit-mode'un izole globals ortamını GÖREMEZ. Bootstrap henüz
      # çalışmadığı için o `globalenv()` boştur; bu yüzden bootstrap ÖNCESİ
      # yardımcılar analiz başlamadan oraya kurulur.
      task_fn = function() {
        # Paket, görev fonksiyonunun KAPSAYAN ortamındadır (explicit-mode onu
        # `environment(task_fn)` olarak bağlar); çağrı çerçevesinde değil.
        pk_async_worker_install_globals(parent.env(environment()))
        pk_async_run_analysis(request)
      },
      task_type = if (isTRUE(request$deep_thinking)) "pk_deep_analysis" else "pk_analysis",
      session_token = session_token,
      dependency_mode = "explicit",
      globals = c(pk_async_worker_globals(), list(request = request)),
      packages = c("DBI", "jsonlite")
    ),
    silent = TRUE
  )
  if (inherits(vaat, "try-error")) {
    bitir_istek()
    log_warn("[PK_ASYNC] Gonderim basarisiz; senkron yol.")
    return(sinirli_senkron("dispatch_failed"))
  }

  # ------------------------------------------------------------------------
  # MUTLAK SON TARİH BEKÇİSİ (ANA SÜREÇTE)
  # ------------------------------------------------------------------------
  # İşçi TARAFINDAKİ aşama kapısı yalnızca İKİ AŞAMA ARASINDA yoklanabilir.
  # Bloklayan bir yerli çağrı (askıda UNC/NFS üzerinde bootstrap dosya okuması,
  # sürücü içinde asılı bir ODBC login/disconnect) dönene kadar ne Durdur ne de
  # son tarih GÖRÜLEBİLİR. Bu yüzden "sert son tarih" iddiası, ANA SÜREÇTE
  # bekleyen bir bekçi olmadan DOĞRU DEĞİLDİR (PR #703 incelemesi).
  #
  # Bekçi işçiyi ÖLDÜRMEZ (PSOCK işçisi güvenilir biçimde sonlandırılamaz); ama:
  #   * iptal jetonunu İŞARETLER (işçi bir sonraki kapıda kendi kendine durur),
  #   * isteği AÇIKÇA TERK EDİLMİŞ işaretler (geç gelen sonuç UYGULANMAZ),
  #   * backpressure yuvasını BIRAKIR ve kullanıcıya TİPLİ son tarih mesajı verir.
  # Böylece kullanıcı ve oturum, bloklayan yerli çağrının insafına kalmaz.
  # SONLULUK DENETLENIR: mutlak son tarih kurulmamissa `pk_deadline_at()` `NA` doner ve `!is.null(NA)` TRUE'dur; `pk_deadline_remaining_sec(NA)` ise `Inf` verir, yani `later::later(delay = Inf)` ile bekci HIC ATESLENMEZ. Gecikme SONLU olmadan zamanlanmaz.
  son_tarih_ani <- mergen_pk_request_deadline_at(request)
  son_tarih_sonlu <- isTRUE(is.finite(suppressWarnings(as.numeric(son_tarih_ani))[1]))
  if (son_tarih_sonlu && requireNamespace("later", quietly = TRUE)) {
    # Küçük bir tolerans: işçinin KENDİ tipli son tarih sonucu normalde önce
    # gelir ve daha iyi bir mesaj üretir; bekçi yalnızca o gelmediğinde konuşur.
    kalan_bekci <- suppressWarnings(as.numeric(pk_deadline_remaining_sec(son_tarih_ani))[1])
    if (!isTRUE(is.finite(kalan_bekci))) kalan_bekci <- 0
    gecikme <- max(1, kalan_bekci + 3)
    bekci_govde <- function() {
      if (isTRUE(request_done)) return(invisible(NULL))

      # SON TARİH YENİDEN OKUNMAZ; İŞÇİ ONU UZATAMAZ (PR #705 inceleme, P2).
      #
      # Burada `getOption("mergen.pk.async.deadline_at")` yeniden okunuyor ve
      # "işçi seçimden sonra son tarihi uzatmış olabilir" gerekçesiyle bekçi
      # yeniden zamanlanıyordu. Bu ÖLÜ bir daldı ve iki ayrı nedenle YANLIŞTI:
      #   1) Analiz AYRI bir PSOCK sürecinde koşar ve `options()` SÜREÇ
      #      YERELİDİR; işçinin yazdığı değer ANA sürece hiç ulaşmaz, yani okuma
      #      her zaman seçim ÖNCESİ değeri (ya da `NULL`) döndürürdü.
      #   2) Sorgu bazlı `analysis_deadline_sec` zaten YALNIZCA SIKILAŞTIRABİLİR:
      #      `.pk_exec_query_deadline_at()` bütçeyi küresel tavana kelepçeler ve
      #      yürürlükteki son tarihi İLERİ ALMAYI açıkça reddeder. Dolayısıyla
      #      işçinin bekçiden DAHA UZUN bir bütçesi hiçbir durumda olamaz.
      # Sonuç olarak bekçinin ilk gecikmesi (kalan + 3 sn) üst sınırdır ve
      # yeniden zamanlama gerekmez.

      # BEKÇİ DE PROMISE GERİ ÇAĞRILARIYLA AYNI KORUMADAN GEÇER: takılı bir
      # işçide `request_done` FALSE kalır, bu yüzden terk edilmiş/bayat bir
      # istek ESKİ son tarihte BAŞKA bir sohbetin arayüzünü bozabiliyordu.
      # Durum temizliği yine yapılır; ARAYÜZ yalnızca istek hâlâ bizimse.
      terk <- isTRUE(try(mergen_pk_request_abandoned(oturum, req_id), silent = TRUE))
      aktif_id <- try(shiny::isolate(ctx$active_request_id()), silent = TRUE)
      if (inherits(aktif_id, "try-error")) aktif_id <- NULL
      karar_bekci <- pk_async_should_apply(aktif_id, req_id, stopped = terk)
      ayni_chat_bekci <- identical(mergen_pk_chat_identity(oturum, ctx$values),
                                   kaynak_chat_key)
      arayuz_bizim <- isTRUE(karar_bekci$apply) && isTRUE(ayni_chat_bekci) &&
        isTRUE(mergen_pk_session_open(oturum))

      log_warn("[PK_ASYNC] Mutlak son tarih asildi; istek terk ediliyor (isci yaniti beklenmiyor).")
      try(pk_cancel_token_signal(cancel_token), silent = TRUE)
      # Geç gelen işçi sonucu UYGULANAMAZ.
      try(mergen_pk_invalidate_requests(oturum, req_id), silent = TRUE)
      request_done <<- TRUE
      try(mergen_pk_unregister_active_request(oturum, req_id), silent = TRUE)
      try(mergen_pk_unregister_cancel_token(oturum, req_id), silent = TRUE)
      butce_birak()
      # JETON, İŞÇİ FUTURE'I YERLEŞENE KADAR ASSERT EDİLİR (SÜRE SINIRI YOK).
      #
      # Burada SABİT GECİKMELİ bir `pk_cancel_token_clear()` zamanlayıcısı
      # vardı. Yerli bir çağrıda bloklanmış bir işçi o gecikmeden SONRA
      # dönebilir; jeton ÇOKTAN silinmiş olduğu için `pk_async_stage_gate()`
      # "iptal yok" okur ve terk edilmiş istek SQL/analiz/dışa aktarım işine
      # DEVAM eder — işçi yuvasını ve bir DB bağlantısını tutarak, üstelik ana
      # süreç sonucu attıktan sonra. "İşçi kaç saniye bloklanabilir" sorusunun
      # üst sınırı YOKTUR, dolayısıyla güvenli bir sabit gecikme de yoktur.
      #
      # Jeton artık YALNIZCA yerleşme yolunda temizlenir
      # (`jeton_yerlesmede_temizle()`; onFulfilled / onRejected / catch).
      # Promise'in HİÇ yerleşmediği (işçi kayıp) durumda dosya kalır; sızıntıyı
      # gönderim başındaki YAŞ TABANLI süpürücü toplar (bkz. dispatch girişi).
      if (isTRUE(arayuz_bizim)) {
        try(shiny::isolate({ ctx$cleanup_send_message()
          ctx$add_message_fn(mergen_pk_worker_outcome_text("deadline"), "ai") }), silent = TRUE)
      } else if (isTRUE(karar_bekci$apply) && !isTRUE(ayni_chat_bekci)) {  # SOHBET DEGISTI, istek kimligi HALA BU ISTEK: `koruma_gecti()` bunu temizler, bekci temizlemiyordu; yeni sohbet eski istegin gonderim kilidinde TAKILI kaliyordu. Mesaj EKLENMEZ.
        try(shiny::isolate(ctx$cleanup_send_message()), silent = TRUE) }
      invisible(NULL)
    }
    bekci_iptal <- try(later::later(bekci_govde, delay = gecikme), silent = TRUE)
    if (inherits(bekci_iptal, "try-error")) bekci_iptal <- NULL
  }

  # BAYAT KÖKEN KAYDI HER TERMİNAL HATA YOLUNDA TÜKETİLİR: yalnızca genel `!ok` dalı temizliyordu; `bootstrap_failed`, reddedilen future ve devam kapanışı hatası temizlemeyince ÖNCEKİ isteğin bekleyen otoriter alt bilgisi, ilgisiz bir altyapı hatası mesajına `add_message()` içindeki dekorasyonla iliştiriliyordu.
  bayat_kokeni_tuket <- function() {
    if (exists("pk_provenance_take", mode = "function", inherits = TRUE)) {
      try(pk_provenance_take(oturum, request_id = req_id), silent = TRUE)
    }
    invisible(NULL)
  }

  # TANIM `promises::then()` ÖNCESİNE ALINDI: geri çağrılar bu işlevi çağırır ve
  # bugün yalnızca promise'lerin olay döngüsünde çalışması sayesinde bağlanır.
  # `tracked_future_promise()` yerine geri çağrıyı EŞ ZAMANLI çalıştıran bir test
  # ikizi kullanıldığında "could not find function" doğardı.
  tamamlandi <- promises::then(
    vaat,
    onFulfilled = function(worker_result) {
      jeton_yerlesmede_temizle()
      if (!isTRUE(koruma_gecti("fulfilled", worker_result$result))) return(invisible(NULL))
      bitir_istek()
      durum <- as.character(worker_result$status %||% "error")[1]

      if (identical(durum, "ok")) {
        # `pk_analiz_process_request()` sıradan terminal yanıtları KARAKTER
        # olarak döndürebilir ("eşleşen sorgu yok", yetki/ön koşul mesajları).
        # Artifact/provenance yeniden yazımı YALNIZCA liste sonuçlar içindir;
        # aksi hâlde atomik vektörde `$` ile "invalid for atomic vectors"
        # hatası alınır ve yanıt tamamen kaybolurdu.
        eski_sonuc <- worker_result$result
        if (!is.list(eski_sonuc)) {
          try(pk_async_apply_session_writes(oturum, worker_result$session_writes), silent = TRUE)
          return(devam_et(mergen_pk_apply_analysis_result(eski_sonuc, mesajlar)))
        }

        sunum <- mergen_pk_serve_worker_artifact(eski_sonuc, oturum)
        if (!isTRUE(sunum$ok)) {
          # Servis edilemeyen bir ek, çalışmayan indirme bağlantısı olarak
          # sunulmaz; artifact temizlenir ve durum AÇIKÇA hata olur.
          try(mergen_pk_cleanup_worker_artifact(eski_sonuc), silent = TRUE)
          shiny::isolate({
            ctx$cleanup_send_message()
            ctx$add_message_fn(mergen_pk_worker_outcome_text("export_failed"), "ai")
          })
          return(invisible(NULL))
        }
        sonuc <- sunum$result
        # Artifact SUNULDU: devam kapanışı hata verirse temizlenebilmesi için
        # dış kapsamda tutulur.
        sunulan_sonuc <<- sonuc

        pending <- worker_result$session_writes$pk_provenance_pending
        eski_blok <- as.character(eski_sonuc$pk_answer_block %||% "")[1]
        yeni_blok <- as.character(sonuc$pk_answer_block %||% "")[1]
        if (is.list(pending) && is.character(pending$footer) && length(pending$footer) == 1L &&
            nzchar(eski_blok) && nzchar(yeni_blok) && !identical(eski_blok, yeni_blok) &&
            grepl(eski_blok, pending$footer, fixed = TRUE)) {
          pending$footer <- sub(eski_blok, yeni_blok, pending$footer, fixed = TRUE)
          worker_result$session_writes$pk_provenance_pending <- pending
        }
        try(pk_async_apply_session_writes(oturum, worker_result$session_writes), silent = TRUE)
        uygulama <- mergen_pk_apply_analysis_result(sonuc, mesajlar)
        devam_et(uygulama)
        # SAHİPLİK DEVRİ AÇIKÇA YAPILIR: bu noktadan sonra artifact'in sahibi
        # `pk_export_serve()` tarafından kurulan OTURUM-SONU defteridir.
        #
        # `devam_et()` FIRLATIRSA bu satıra hiç gelinmez; `sunulan_sonuc` set
        # kalır ve aşağıdaki `promises::catch()` teslim EDİLEMEMİŞ dosyayı
        # hemen siler. Normal dönüşte ise dosya SİLİNMEZ: `answer` yolunda
        # mesaj eklenmiştir, `continue` yolunda ise bağlantıyı taşıyan nihai
        # LLM yanıtı akmaktadır ve kullanıcı indirmeyi SONRADAN tıklar —
        # devam isteğinin tamamlanmasında silmek, tam da kullanıcının ihtiyaç
        # duyduğu dosyayı yok ederdi. Bayrağı burada düşürmek, hiçbir geri
        # çağrının artık sahiplenmediği bir "asılı sahip" durumunu önler.
        sunulan_sonuc <<- NULL
        return(invisible(NULL))
      }

      # KABUL EDİLMEYEN sonuçların oturum yazımları UYGULANMAZ. İşçi bu
      # yazımları son kapıdan ÖNCE topluyor; iptal/son tarih/hata ile atılan
      # bir istek, canlı oturumun seçim durumunu ve köken alt bilgisini
      # EZEMEMELİDİR (sonraki istek oradan tohumlanıyor).
      if (identical(durum, "bootstrap_failed")) {
        bayat_kokeni_tuket()
        return(devam_et(altyapi_hatasi("bootstrap_failed")))
      }
      shiny::isolate({
        ctx$cleanup_send_message()
        # BEKLEYEN KÖKEN KAYDI BURADA TÜKETİLİR. Kabul edilmeyen sonucun
        # oturum yazımları uygulanmaz, ama ÖNCEKİ bir isteğin bekleyen kaydı
        # oturumda durabilir; `add_message()` içindeki dekorasyon o BAYAT alt
        # bilgiyi bu ilgisiz hata mesajına iliştirirdi.
        if (exists("pk_provenance_take", mode = "function", inherits = TRUE)) {
          try(pk_provenance_take(oturum, request_id = req_id), silent = TRUE)  # kimlik zorunlu
        }
        ctx$add_message_fn(mergen_pk_worker_outcome_text(durum, worker_result$error), "ai")
      })
      invisible(NULL)
    },
    onRejected = function(error) {
      # REDDEDİLEN future de YERLEŞMİŞTİR: jeton ertelemesi burada da biter,
      # aksi hâlde altyapı hatasıyla ölen bir istek `.flag` dosyasını gereksiz
      # yere bir saate kadar canlı tutardı.
      jeton_yerlesmede_temizle()
      if (!isTRUE(koruma_gecti("rejected"))) return(invisible(NULL))
      bitir_istek()
      bayat_kokeni_tuket()
      # Buraya yalnızca ALTYAPI hataları düşer (serileştirme/işçi kaybı):
      # boru hattı hataları işçide tipli pakete dönüştürülür. Bu geri çağrı ANA
      # SÜREÇTE çalıştığı için senkron tekrar oynatma YAPILMAZ (bkz. yukarıdaki
      # `altyapi_hatasi()` gerekçesi); kullanıcıya tipli bir altyapı mesajı
      # verilir ve olay döngüsü serbest kalır.
      devam_et(altyapi_hatasi("worker_rejected"))
      invisible(NULL)
    }
  )

  # `then()` içindeki onFulfilled/onRejected KENDİLERİ de hata atabilir
  # (`mergen_pk_apply_analysis_result`, `continue_fn`, nihai LLM hazırlığı).
  # Bu istisna, kardeş onRejected'a DEĞİL, `then()`'in DÖNDÜRDÜĞÜ çocuk
  # promise'e düşer. Yakalanmazsa `is_sending`/backpressure takılı kalır ve
  # yanıt sessizce kaybolur.
  try(promises::catch(tamamlandi, function(hata) {
    jeton_yerlesmede_temizle()
    log_warn("[PK_ASYNC] Devam kapanisi hata verdi; istek temizleniyor.")
    bitir_istek()
    butce_birak()
    # SUNULMUŞ ama TESLİM EDİLMEMİŞ artifact temizlenir: bağlantısını içeren
    # bir yanıt hiç işlenmediği için dosya artık ERİŞİLEMEZ; oturum sonuna
    # kadar tutmak, tekrarlanan kesintilerde büyük dosyaların birikmesi demektir.
    if (!is.null(sunulan_sonuc)) {
      try(mergen_pk_cleanup_worker_artifact(sunulan_sonuc), silent = TRUE)
      sunulan_sonuc <<- NULL
    }
    bayat_kokeni_tuket()
    try(shiny::isolate({
      ctx$cleanup_send_message()
      ctx$add_message_fn(mergen_pk_worker_outcome_text("error"), "ai")
    }), silent = TRUE)
    invisible(NULL)
  }), silent = TRUE)

  list(action = "deferred")
}

mergen_pk_signal_cancel <- function(request_id, session = NULL) {
  kimlik <- try(as.character(request_id)[1], silent = TRUE)
  if (inherits(kimlik, "try-error") || is.null(kimlik) || !length(kimlik) ||
      is.na(kimlik) || !nzchar(kimlik)) return(invisible(FALSE))
  pk_cancel_token_signal(mergen_pk_cancel_token_for_session(session, kimlik))
}
