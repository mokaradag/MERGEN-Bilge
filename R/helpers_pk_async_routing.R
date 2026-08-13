# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_routing.R
# Açıklama: Faz 6 (§5.10) — ASENKRON YÖNLENDİRME KARARININ iki yardımcısı:
#           yönlendirme anındaki sorgu metadata'sı ve DEGRADE senkron yolda
#           sınırlı SQL yürütücüsünün zorlanması.
#
# `R/helpers_pk_async_lifecycle.R` içinden BÖLÜNMÜŞTÜR: orası TEK bir isteğin
# sonucunun nasıl sunulduğu/temizlendiğidir ve 24-fonksiyon bakım tavanına
# dayanmıştı. Yönlendirme "bu istek işçiye GİDER Mİ ve gitmezse hangi güvenlik
# sınırlarıyla çalışır" sorusudur.
#
# SAFTIR sayılmaz (ortam sembolü değiştirir) ama Shiny/reaktif/DB DOKUNMAZ.
# ==============================================================================

# ------------------------------------------------------------------------------
# YÖNLENDİRME İÇİN SORGU MUAFİYETİ (TEK YÖNLÜ: yalnızca SIKILAŞTIRIR)
# ------------------------------------------------------------------------------
# Yönlendirme kararı sorgu SEÇİMİNDEN ÖNCE alınır: `pk_active_query_meta()` o
# anda normalde `NULL`'dur, dolayısıyla `async = FALSE` işaretli bir üretim
# sorgusu küresel bayrak açıkken YİNE işçiye gönderilirdi (per-query override
# ölü bir yapılandırma).
#
# ESKİ YAKLAŞIM (PR #703 incelemesi) YETERSİZDİ: sorgu ADI kullanıcının istemi
# içinde ALT DİZE olarak aranıyordu. Sıradan bir doğal dil istemi ("bu yılki
# bütçe aşımlarını göster") sorgu adını İÇERMEZ, dolayısıyla muafiyet normal
# semantik istemlerde HİÇ görülmüyordu.
#
# YENİ YAKLAŞIM: repoda ZATEN var olan SAF/DETERMİNİSTİK sezgisel skorlayıcı
# (`pk_compute_heuristic_query_scores()`; LLM/DB/ağ YOK) ile MAKUL ADAY kümesi
# hesaplanır. Adaylardan HERHANGİ BİRİ asenkronu kapatıyorsa muafiyet uygulanır.
#
# KASITLI OLARAK MUHAFAZAKÂRDIR: yanlış pozitif = istek SENKRON çalışır (eski
# davranış, güvenli yön). Yanlış negatif = muafiyet kaçırılır (eski hata).
# Muafiyet ASLA async'i AÇAMAZ: `pk_async_enabled()` küresel bayrağı tek yönlü
# okur (bkz. `R/helpers_pk_async_request.R`).
mergen_pk_routing_query_meta <- function(ctx) {
  aktif <- tryCatch(pk_active_query_meta(), error = function(e) NULL)
  if (!is.null(aktif)) return(aktif)

  kutuphane <- get0("query_library", inherits = TRUE)
  if (!is.list(kutuphane) || !length(kutuphane)) return(NULL)

  # ÜRETİM BAĞLAMININ GERÇEKTEN TAŞIDIĞI ALAN OKUNUR.
  #
  # `server_send_message.R` bu bağlamı `user_message_text` ile kurar;
  # `user_prompt` alanı YOKTUR. Yalnızca `user_prompt` okunduğunda istem HER
  # ZAMAN boş çıkıyor, sezgisel muafiyet taraması hiç çalışmıyor ve
  # `meta$async = FALSE` işaretli bir sorgu küresel bayrak açıkken yine işçiye
  # gönderiliyordu; yani sorgu bazlı kapatma anahtarı sessizce etkisizdi.
  istem <- tryCatch(
    as.character(ctx$user_message_text %||% ctx$user_prompt %||% "")[1],
    error = function(e) ""
  )
  if (is.na(istem) || !nzchar(istem)) return(NULL)

  adaylar <- .pk_routing_candidate_indexes(istem, kutuphane)
  if (!length(adaylar)) return(NULL)

  for (indeks in adaylar) {
    sorgu <- kutuphane[[indeks]]
    if (!is.list(sorgu) || !is.list(sorgu$meta)) next
    if (identical(.pk_routing_meta_async(sorgu$meta), FALSE)) {
      # SENTETİK muafiyet metadata'sı döndürülür: aday sorgunun DİĞER
      # ayarlarını (zaman aşımı, sonuç tavanı) yönlendirme anında uygulamak
      # YANLIŞ olurdu — hangi sorgunun seçileceği HENÜZ BİLİNMİYOR. Tek
      # taşınan bilgi "bu istek asenkrondan muaf olabilir"dir.
      return(list(async = FALSE))
    }
  }
  NULL
}

# Metadata'daki `async` alanının ÜÇ DURUMLU okunuşu: `TRUE`/`FALSE`/`NULL`.
# `pk_config_resolve()` kullanılmaz: o, metadata yoksa küresel değere düşer ve
# "bu sorgu bir şey söylemiyor" ile "bu sorgu açıkça açıyor" ayrımını kaybeder.
.pk_routing_meta_async <- function(meta) {
  if (!is.list(meta)) return(NULL)
  ham <- meta[[pk_config_meta_key("MERGEN_PK_ASYNC")]]
  if (is.null(ham)) return(NULL)
  if (!exists(".pk_config_as_logical", mode = "function", inherits = TRUE)) {
    return(if (isTRUE(ham)) TRUE else if (identical(ham, FALSE)) FALSE else NULL)
  }
  tryCatch(.pk_config_as_logical(ham), error = function(e) NULL)
}

# Sezgisel skorlayıcıdan MAKUL aday indeksleri. Skorlayıcı yoksa/başarısızsa
# davranış eski hâline döner: yalnızca KESİN ad eşleşmesi.
.pk_routing_candidate_indexes <- function(prompt, library) {
  if (exists("pk_compute_heuristic_query_scores", mode = "function", inherits = TRUE)) {
    skorlar <- tryCatch(pk_compute_heuristic_query_scores(prompt, library),
                        error = function(e) NULL)
    if (is.list(skorlar) && is.data.frame(skorlar$all_scores) &&
        nrow(skorlar$all_scores) == length(library)) {
      yuzde <- suppressWarnings(as.numeric(skorlar$all_scores$heuristic_score))
      yuzde[is.na(yuzde)] <- 0
      # `pk_compute_heuristic_query_scores()` içindeki `THRESHOLD_PCT` ile AYNI
      # eşik; orası tek kaynaktır ve burada yeniden tanımlanmaz.
      indeksler <- which(yuzde >= 30)
      en_iyi <- suppressWarnings(as.integer(skorlar$best_idx)[1])
      if (isTRUE(skorlar$passes_threshold) && !is.na(en_iyi)) {
        indeksler <- unique(c(indeksler, en_iyi))
      }

      # SENKRON-ONLY SORGULAR İÇİN EŞİK DAHA GENİŞTİR.
      #
      # 30 puanlık yönlendirme eşiği, sezgisel ile semantik seçicinin AYRIŞTIĞI
      # durumda sorgu bazlı kapatma anahtarını atlıyordu: `async = FALSE`
      # işaretli bir sorgu eşiğin altında kalıp adaylardan düşüyor, ama AI
      # seçici onu seçiyordu. Muafiyet yönü tek taraflı GÜVENLİDİR (yanlış
      # pozitif = istek senkron çalışır, eski davranış), bu yüzden HERHANGİ bir
      # sözlüksel sinyali olan senkron-only sorgu aday kabul edilir. Sinyali
      # SIFIR olan sorgu yine dışarıda kalır; aksi hâlde tek bir senkron-only
      # kayıt tüm kütüphane için asenkronu kapatırdı.
      senkron_only <- which(vapply(seq_along(library), function(i) {
        meta <- tryCatch(library[[i]]$meta, error = function(e) NULL)
        identical(.pk_routing_meta_async(meta), FALSE)
      }, logical(1)))

      if (length(senkron_only)) {
        indeksler <- unique(c(indeksler, senkron_only[yuzde[senkron_only] > 0]))
      }
      if (length(indeksler)) return(indeksler)
      return(integer(0))
    }
  }
  .pk_routing_exact_name_indexes(prompt, library)
}

.pk_routing_exact_name_indexes <- function(prompt, library) {
  katla <- function(x) {
    metin <- tryCatch(enc2utf8(as.character(x)[1]), error = function(e) "")
    if (is.na(metin)) return("")
    if (exists("pk_tr_fold", mode = "function", inherits = TRUE)) {
      return(tryCatch(pk_tr_fold(metin), error = function(e) metin))
    }
    chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", metin)
  }
  istem_katli <- katla(prompt)
  bulunan <- integer(0)
  for (i in seq_along(library)) {
    sorgu <- library[[i]]
    if (!is.list(sorgu)) next
    ad <- katla(sorgu$name %||% "")
    if (nzchar(ad) && grepl(ad, istem_katli, fixed = TRUE)) bulunan <- c(bulunan, i)
  }
  bulunan
}

# ------------------------------------------------------------------------------
# DEGRADE YOLDA SINIRLI SENKRON YÜRÜTÜCÜ
# ------------------------------------------------------------------------------
# `MERGEN_PK_ASYNC=true` iken yetenek sondası başarısız olduğunda (plan yok,
# bağımlılık eksik) senkron boru hattı `execute_pk_sql_unicode()` üzerinden TAM
# `DBI::dbGetQuery()` materyalizasyonu yapar: yeni parça/bellek/son tarih
# denetimleri DEVREYE GİRMEZ ve tek bir geniş sorgu Shiny sürecini bloklayıp
# belleği tüketebilir. Operatör asenkronu AÇIK bıraktığına göre yeni sınırların
# geçerli olmasını bekler; bu yüzden sınırlı yürütücü zorlanır.
#
# `flag_off` (BİLİNÇLİ geri alma) bu yoldan GEÇMEZ: orada eski davranış aynen
# korunur.
#
# GERÇEK BÜTÇE VE GERÇEK KAPI (PR #703 incelemesi): eskiden aşama kapısı SABİT
# `halt = FALSE` idi ve son tarih normalde `NULL` olan bir option'dan okunuyordu.
# Sonuç: parçalama korunuyor ama İLAN EDİLEN duvar-saati son tarihi ve Durdur
# KORUNMUYORDU. Artık istek başlangıcı/son tarihi AÇIKÇA yayınlanır ve kapı
# `stop_check` + son tarihi gerçekten yoklar.
#
# @param stop_check Kullanıcı Durdur kapanışı (reaktif; senkron yolda çağrılır).
# @param started_at İSTEĞİN ORİJİNAL başlangıcı (yeniden başlatılmaz).
# @param deadline_at Mutlak son tarih; `NULL` ise `started_at` + yapılandırma.
# @return Önceki durumu geri yükleyen fonksiyon.
mergen_pk_force_bounded_sync <- function(stop_check = NULL,
                                         started_at = Sys.time(),
                                         deadline_at = NULL) {
  bos <- function() invisible(FALSE)
  if (!exists("pk_async_bounded_sql_executor", mode = "function", inherits = TRUE)) return(bos)
  if (!exists("pk_analiz_process_request", mode = "function", inherits = TRUE)) return(bos)

  hedef <- environment(pk_analiz_process_request)
  if (!is.environment(hedef)) return(bos)

  baslangic <- tryCatch(as.POSIXct(started_at), error = function(e) Sys.time())
  if (length(baslangic) != 1L || is.na(baslangic)) baslangic <- Sys.time()

  son_tarih <- deadline_at
  if (is.null(son_tarih)) {
    butce <- tryCatch(pk_config_resolve("MERGEN_PK_ANALYSIS_DEADLINE_SEC"),
                      error = function(e) NA_real_)
    son_tarih <- pk_deadline_at(baslangic, butce)
  }
  if (length(son_tarih) != 1L || is.na(son_tarih)) son_tarih <- NULL

  # GERÇEK aşama kapısı: Durdur + mutlak son tarih. Son tarih her çağrıda
  # OPTION'dan okunur ki sorgu seçildikten sonraki per-query override (yalnızca
  # SIKILAŞTIRAN) bu kapıya da ulaşsın.
  kapi <- function() {
    durdu <- FALSE
    if (is.function(stop_check)) {
      durdu <- isTRUE(tryCatch(stop_check(), error = function(e) FALSE))
    }
    if (isTRUE(durdu)) return(list(halt = TRUE, status = "cancelled"))
    guncel <- getOption("mergen.pk.async.deadline_at", NULL)
    if (!is.null(guncel) && isTRUE(tryCatch(pk_deadline_expired(guncel), error = function(e) FALSE))) {
      return(list(halt = TRUE, status = "deadline"))
    }
    list(halt = FALSE, status = "ok")
  }

  eski <- get0("execute_pk_sql_unicode", envir = hedef, inherits = TRUE)
  eski_son_tarih <- getOption("mergen.pk.async.deadline_at", NULL)
  eski_baslangic <- getOption("mergen.pk.async.started_at", NULL)
  kutu <- pk_async_sql_status_box()
  sinirli <- pk_async_bounded_sql_executor(
    stage_gate = kapi,
    deadline_at = function() getOption("mergen.pk.async.deadline_at", NULL),
    status_box = kutu
  )

  ok <- isTRUE(tryCatch({
    assign("execute_pk_sql_unicode", sinirli, envir = hedef)
    TRUE
  }, error = function(e) FALSE))
  if (!isTRUE(ok)) return(bos)

  # İSTEK BÜTÇESİ YAYINLANIR: `pk_set_exec_context()` per-query override'ı bu
  # başlangıçtan türetir ve `pk_active_stage_halt()` yoklamaları gerçek bir
  # son tarih görür. Senkron yeniden deneme bütçeyi SIFIRLAMAZ.
  options(mergen.pk.async.started_at = baslangic,
          mergen.pk.async.deadline_at = son_tarih)

  function() {
    if (is.function(eski)) {
      try(assign("execute_pk_sql_unicode", eski, envir = hedef), silent = TRUE)
    }
    options(mergen.pk.async.started_at = eski_baslangic,
            mergen.pk.async.deadline_at = eski_son_tarih)
    invisible(TRUE)
  }
}
