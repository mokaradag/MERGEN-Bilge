# R/helpers_file_pipeline.R

# Kalıcılaştırma sonucu için AÇIK durum kodları. `processAndSummarizeFile()`
# eskiden reddetme yollarında da `invisible(NULL)` dönüyordu; `R/server_observers_files.R`
# sonucu yok sayıp `processed_count` değerini KOŞULSUZ artırıyor ve başarı
# bildirimi gösteriyordu (reddedilen dosya "eklendi" sayılıyordu).
MERGEN_FILE_PIPELINE_ACCEPTED <- "kabul"
MERGEN_FILE_PIPELINE_REJECTED <- "red"

.file_pipeline_status <- function(status, reason = "") {
  invisible(list(status = status, reason = as.character(reason %||% "")[1]))
}

# Bir kalıcılaştırma sonucunun kabul edilip edilmediğini söyler. Eski çağıranlar
# `NULL` alıyordu; geriye dönük uyumluluk için `NULL` REDDETME sayılır.
mergen_file_pipeline_accepted <- function(result) {
  if (is.null(result)) return(FALSE)
  if (is.list(result) && !is.null(result$status)) {
    return(identical(as.character(result$status)[1], MERGEN_FILE_PIPELINE_ACCEPTED))
  }
  isTRUE(result)
}

# Oturum ve çağıran kimliğinden ETKİN kullanıcı kimliğini seçer. Oturum kimliği
# ancak KANONİK ve POZİTİF ise tercih edilir; `0L` gibi yer tutucu bir değer
# çağıranın çözümlenmiş kimliğini gölgelemez.
.file_pipeline_effective_uid <- function(session_user_id, caller_user_id) {
  kanonik <- function(x) {
    if (exists("mergen_canonical_user_id", mode = "function", inherits = TRUE)) {
      return(mergen_canonical_user_id(x %||% NA_integer_))
    }
    deger <- suppressWarnings(as.numeric(x %||% NA_integer_))
    if (length(deger) != 1L || !is.finite(deger) || deger <= 0 ||
        deger != trunc(deger) || deger > .Machine$integer.max) {
      return(0L)
    }
    as.integer(deger)
  }

  oturum <- kanonik(session_user_id)
  cagiran <- kanonik(caller_user_id)

  # KİMLİK DEĞİŞİMİ KAPALI-BAŞARISIZDIR (IDOR). Parti kullanıcı A için başlayıp
  # aynı Shiny oturumu B'ye geçtikten SONRA tamamlanabilir (`sso_auth_error`
  # yalnızca istemci token'ını temizler, oturumu kapatmaz). Oturum kimliğini
  # koşulsuz tercih etmek, A'nın kalıcılaşmış dosyasını B'nin oturum durumuna
  # bağlıyordu. İKİ kimlik de POZİTİF ve FARKLIYSA sonuç geçersizdir; çağıran
  # mevcut `effective_user_id <= 0L` reddetme yoluna düşer.
  if (oturum > 0L && cagiran > 0L && !identical(oturum, cagiran)) return(0L)

  if (oturum > 0L) return(oturum)
  cagiran
}

.file_pipeline_session_uid <- function(session) {
  .file_pipeline_effective_uid(tryCatch(session$userData$user_id, error = function(e) NULL), NULL)
}

# Arka plan özetinin sahiplik kararı: yüklemede oturum kimliği POZİTİFSE canlı
# kimlik aynı kalmalıdır (SSO süresi dolunca çağıran kimliğine düşülmez).
# Yüklemede oturum kimliği yoksa yalnız yine yokken ya da aynı kullanıcıyken
# geçerlidir; farklı pozitif kimlik her durumda reddedilir.
.file_pipeline_owner_ok <- function(yukleme_uid, canli_uid, etkin_uid) {
  if (etkin_uid <= 0L) return(FALSE)
  if (yukleme_uid > 0L) return(identical(canli_uid, etkin_uid))
  canli_uid <= 0L || identical(canli_uid, etkin_uid)
}

processAndSummarizeFile <- function(file_info,
                                    current_user_id,
                                    session,
                                    settings,
                                    file_manager_data,
                                    session_files_reactive,
                                    update_manager_ui = TRUE,
                                    show_toast = TRUE,
                                    auto_attach = FALSE,
                                    already_persisted = FALSE,
                                    get_user_upload_dir_fn = NULL) {
  note_id <- showNotification(sprintf("İşlem başlatıldı: %s", file_info$name),
                              duration = NULL, type = "message")

  # SSO modunda başlangıçta gelen 0L yerine oturumdaki gerçek kullanıcıyı kullan.
  # `%||%` YALNIZCA NULL'u değiştirir: oturum kimliği hâlâ `0L` iken çağıranın
  # ÇÖZÜMLENMİŞ kimliği yok sayılıyor ve geçerli yükleme reddediliyordu.
  effective_user_id <- .file_pipeline_effective_uid(
    session$userData$user_id,
    current_user_id
  )

  # KİMLİK ÇÖZÜLEMEZSE KALICILAŞTIRMA DURUR (kapalı-başarısız). Yalnızca log
  # yazmak dosyayı `user_0` klasörüne kopyalıyor ve indeksi `user_id = 0` ile
  # güncelliyordu; bu kova daha sonra kimliği doğrulanmış BAŞKA bir kullanıcıya
  # da görünebiliyordu (IDOR).
  if (effective_user_id <= 0L) {
    cat(sprintf("[FILE PIPELINE] UYARI: effective_user_id=%d (session=%s, param=%s) - dosya: %s\n",
                effective_user_id,
                as.character(session$userData$user_id %||% "NULL"),
                as.character(current_user_id %||% "NULL"),
                file_info$name))
    try(removeNotification(note_id), silent = TRUE)
    if (isTRUE(show_toast)) {
      showToast(
        session,
        "Kimlik doğrulama tamamlanmadan dosya kalıcı klasöre kaydedilemez.",
        "warning"
      )
    }
    return(.file_pipeline_status(MERGEN_FILE_PIPELINE_REJECTED, "kimlik"))
  }

  # Kalıcılaştırma TEK yerde yapılır. Dosya alım hattı (veya Dosya Yönetimi)
  # tarafından zaten kopyalanıp indekslenmiş dosya için burada ikinci kez
  # kopyalama/indeks yazımı YAPILMAZ; kayıt tam olarak bir kez gerçekleşir.
  dest <- file_info$datapath
  zaten_kalici <- isTRUE(already_persisted) || is_under_mcp_base(dest)

  if (!zaten_kalici) {
    # Kalıcılaştırma hatası bildirimi açık bırakmaz ve partiyi yarıda kesmez.
    dest <- tryCatch(
      copy_to_mcp_base(list(name = file_info$name, datapath = file_info$datapath), effective_user_id),
      error = function(e) {
        cat("[FILE PIPELINE] Kalıcılaştırma başarısız:", conditionMessage(e), "\n")
        NULL
      }
    )
    if (is.null(dest)) {
      try(removeNotification(note_id), silent = TRUE)
      if (isTRUE(show_toast)) {
        showToast(session, paste(file_info$name, "kalıcı klasöre kaydedilemedi."), "error")
      }
      return(.file_pipeline_status(MERGEN_FILE_PIPELINE_REJECTED, "kopya"))
    }

    # İNDEKS KAYDI BAŞARISIZSA YÜKLEME DURUR. Hata yutulduğunda dosya oturum
    # durumuna ekleniyor, arayüz "yüklendi" raporluyor ancak kalıcı indeks
    # dosyayı HİÇ içermiyordu (yeniden başlatmada kayıp). Kopya da geri alınır:
    # işlem ya tam başarılı olur ya da diskte iz bırakmaz.
    indekslendi <- tryCatch({
      global_register_file(
        dest, file_info$name,
        user_id = effective_user_id,
        persist_under_mcp_base = TRUE
      )
      cat("[FILE PIPELINE] Dosya indekse kaydedildi:", file_info$name, "\n")
      TRUE
    }, error = function(e) {
      cat("[FILE PIPELINE] İndeks kaydı başarısız:", conditionMessage(e), "\n")
      FALSE
    })

    if (!isTRUE(indekslendi)) {
      # Yetim kopya yalnızca DOĞRULANMIŞ kullanıcı kökü altındaysa kaldırılır.
      # Çözümleyici AÇIKÇA geçilir: `fm_cleanup_orphan_upload()` ad ile arama
      # yaptığında modül closure'ındaki `get_user_upload_dir` bulunamıyor,
      # yardımcı "çözümleyici yok" diyerek FALSE dönüyor ve indekslenmemiş kopya
      # kalıcı depoda kalıyordu.
      # VARSAYILAN ÇÖZÜMLEYİCİ KÖKÜ `dest`TEN türetir: `copy_to_mcp_base()` etkin
      # tabanı `mergen.mcp_base_dir` -> `MCP_FILES_BASE` -> `<getwd()>/mergen_uploads`
      # sırasıyla seçer; `mergen_user_upload_dir()` ise `resolve_mcp_base_dir()`
      # üzerinden gider ve son yedeği `MERGEN_UPLOADS_DIR`dir. İki taban
      # AYRIŞTIĞINDA `mergen_path_inside_root()` FALSE dönüyor, temizlik "kök
      # dışında" diyerek vazgeçiyor ve İNDEKSLENMEMİŞ kopya kalıcı depoda
      # kalıyordu. `dest` zaten kopyanın ÜRETİLDİĞİ yoldur, bu yüzden
      # `dirname(dest)` kullanıcı kökünün KESİN karşılığıdır.
      kok_cozumleyici <- if (is.function(get_user_upload_dir_fn)) {
        get_user_upload_dir_fn
      } else {
        function() {
          aday <- as.character(dirname(as.character(dest %||% "")[1]))[1]
          if (length(aday) == 1L && !is.na(aday) && nzchar(aday) && aday != ".") {
            return(aday)
          }
          mergen_user_upload_dir(effective_user_id)
        }
      }
      temiz <- if (exists("fm_cleanup_orphan_upload", mode = "function", inherits = TRUE)) {
        try(fm_cleanup_orphan_upload(dest, get_user_upload_dir_fn = kok_cozumleyici),
            silent = TRUE)
      } else {
        FALSE
      }
      # BELİRSİZ sonuç (NA) da başarı sayılmaz; yetim kopya sessizce kalmamalı.
      if (inherits(temiz, "try-error") || !isTRUE(temiz)) {
        cat("[FILE PIPELINE] UYARI: Yetim kopya kaldırılamadı:", as.character(dest), "\n")
      }
      try(removeNotification(note_id), silent = TRUE)
      if (isTRUE(show_toast)) {
        showToast(session, paste(file_info$name, "kalıcı indekse kaydedilemedi."), "error")
      }
      return(.file_pipeline_status(MERGEN_FILE_PIPELINE_REJECTED, "indeks"))
    }
  }

  # MCP araçları için oturum dosya kayıt defterini merkezi helper ile güncelle
  session_user_data_put_list_item(
    session,
    "current_session_files",
    file_info$name,
    list(name = file_info$name, datapath = dest, path = dest)
  )

  # Ayar anlık görüntüsü: reactiveValues VE düz liste için aynı yardımcı.
  settings_snapshot <- tryCatch(as_llm_settings_list(settings), error = function(e) list())
  settings_snapshot$shiny_session <- NULL

  # Encoding-safe path for worker (UTF-8 dönüşümü)
  dest_safe <- tryCatch(enc2utf8(as.character(dest)), error = function(e) as.character(dest))
  file_name_safe <- tryCatch(enc2utf8(as.character(file_info$name)), error = function(e) as.character(file_info$name))

  # Özet sırada/işçide beklerken aynı Shiny oturumu başka kullanıcıya geçebilir
  # (SSO yeniden kimlik) ya da kimlik süresi dolabilir (0). Başlatmadan ve sonuç
  # işlenmeden önce CANLI oturum kimliği yükleyenle uyumlu olmalıdır; A'nın dosya
  # özeti B'nin ya da kimliği düşmüş oturumun durumuna yazılmaz.
  yukleme_oturum_uid <- .file_pipeline_session_uid(session)
  sahip_gecerli <- function() {
    .file_pipeline_owner_ok(yukleme_oturum_uid, .file_pipeline_session_uid(session), effective_user_id)
  }
  # Her özet işi dosya adına bağlı bir iş jetonu taşır: aynı adla yeniden
  # yükleme ya da dosyanın bağlamdan çıkarılması eski işin sonucunu geçersiz kılar.
  is_jetonu <- basename(tempfile("ozet_"))
  .file_summary_job_token(session, file_info$name, is_jetonu)
  ozet_hata <- function(e) {
    try(removeNotification(note_id), silent = TRUE)
    # Dosya zaten indekse kaydedildi, sadece özetleme başarısız oldu
    msg <- tryCatch(enc2utf8(conditionMessage(e)), error = function(err) conditionMessage(e))
    cat("[FILE PIPELINE] Özetleme hatası:", msg, "\n")
    if (sahip_gecerli() && .file_pipeline_session_uid(session) > 0L) {
      showToast(session, paste(file_info$name, "yüklendi ancak özet çıkarılamadı."), "warning")
    }
  }
  ozet_baslat <- function() {
    if (!sahip_gecerli()) {
      try(removeNotification(note_id), silent = TRUE)
      cat("[FILE PIPELINE] Oturum kimliği değişti, kuyruktaki özet başlatılmadı.\n")
      # Kimlik düştüyse (başka kullanıcıya geçmediyse) iptal söylenir; dosya adı verilmez.
      if (.file_pipeline_session_uid(session) <= 0L && isTRUE(show_toast)) {
        showToast(session, "Oturum kimliği doğrulanamadığı için bir dosya özeti iptal edildi.", "warning")
      }
      return(invisible(NULL))
    }
    # Oturum kapanırsa ya da kimliği değişir/düşerse işçi durdurma dosyasını görür
    # ve dosyayı okumadan/LLM çağrısı yapmadan durur.
    durdurma_dosyasi <- tempfile("mergen_ozet_dur_")
    durdur <- function(...) try(file.create(durdurma_dosyasi), silent = TRUE)
    durdurma_kaydi <- if (is.function(session$onSessionEnded)) {
      try(session$onSessionEnded(durdur), silent = TRUE)
    }
    kimlik_kaydi <- if (exists("mergen_session_on_owner_change", mode = "function")) {
      mergen_session_on_owner_change(session, durdur)
    }
    ozet_gorevi <- file_summary_task_fn(file_name_safe, dest_safe, settings_snapshot, durdurma_dosyasi)
    # Bağımlılıklar süreç başına bir kez taranır (açılışta ısıtılır) ve görev İZOLE
    # ortamla gönderilir: otomatik kip oturumu taşıyan çerçeveyi serileştiriyordu.
    # Başarısız tarama otomatik kipe düşürülmez (aynı tarama tekrar ederdi); özet
    # reddedilir ve ortak hata yolundan bildirilir.
    bagimlilik <- if (exists("worker_monitor_auto_globals", mode = "function")) {
      try(worker_monitor_auto_globals("file_summary", ozet_gorevi), silent = TRUE)
    }
    tarama_basarisiz <- !is.null(bagimlilik) &&
      (inherits(bagimlilik, "try-error") || !isTRUE(bagimlilik$ok))
    # Eşzamanlı gönderim hatası reddedilmiş söze çevrilir: bildirim kapanır,
    # uyarı ve günlük aşağıdaki ortak hata yolundan verilir.
    gonderim <- if (tarama_basarisiz) {
      simpleError("Özet görevinin bağımlılık taraması başarısız oldu.")
    } else {
      try(tracked_future_promise(
        task_fn = ozet_gorevi,
        task_type = "file_summary",
        session_token = session$token,
        dependency_mode = if (is.null(bagimlilik)) "auto" else "explicit",
        globals = bagimlilik$globals,
        packages = bagimlilik$packages
      ), silent = TRUE)
    }
    if (inherits(gonderim, "try-error")) gonderim <- attr(gonderim, "condition")
    if (inherits(gonderim, "condition")) gonderim <- promises::promise_reject(gonderim)
    if (promises::is.promising(gonderim)) {
      gonderim <- promises::finally(gonderim, function() {
        if (is.function(durdurma_kaydi)) try(durdurma_kaydi(), silent = TRUE)
        if (is.function(kimlik_kaydi)) try(kimlik_kaydi(), silent = TRUE)
        unlink(durdurma_dosyasi)
      })
    }
    gonderim %...>%
    (function(res) {
      removeNotification(note_id)
      if (!sahip_gecerli()) {
        cat("[FILE PIPELINE] Oturum kimliği değişti, özet sonucu uygulanmadı.\n")
        return(invisible(NULL))
      }
      # Dosya bağlamdan çıkarıldı, silindi ya da aynı adla yeniden yüklendiyse
      # eski işin sonucu yeni durumu ezmez.
      if (!.file_summary_result_current(session, file_info$name, is_jetonu, res$dest)) {
        cat("[FILE PIPELINE] Dosya değişti ya da çıkarıldı; eski özet sonucu uygulanmadı.\n")
        return(invisible(NULL))
      }
      if (isTRUE(auto_attach)) {
        current_files <- session_files_reactive() %||% list()
        current_files[[file_info$name]] <- list(
          name = file_info$name,
          summary = res$summary,
          size = file.info(res$dest)$size,
          type = res$ext
        )
        session_files_reactive(current_files)
      }

      session_user_data_put_list_item(
        session,
        "file_summaries",
        file_info$name,
        res$summary
      )

      if (!is.null(file_manager_data$sync_file_to_context)) {
        file_manager_data$sync_file_to_context(
          file_info$name,
          summary = res$summary,
          persisted_path = res$dest
        )
      }

      if (isTRUE(show_toast)) showToast(session, paste(file_info$name, "özetlendi."), "success")
    }) %...!% ozet_hata
  }

  ozet_kuyrukta <- if (exists("file_summary_schedule", mode = "function")) {
    file_summary_schedule(ozet_baslat, session = session, sahip = effective_user_id, on_drop = ozet_hata)
  } else {
    ozet_baslat()
    TRUE
  }
  # Özet kuyruğu doluysa ya da arka plan özet kapasitesi yoksa dosya yine kabul
  # edilir; özet atlanır ve gerçek neden söylenir. Bildirim göstermeyen toplu
  # çağıran nedeni sonuçtan okur.
  if (identical(as.logical(ozet_kuyrukta), FALSE)) {
    try(removeNotification(note_id), silent = TRUE)
    isci_yok <- identical(attr(ozet_kuyrukta, "neden"), "isci_yok")
    cat(if (isci_yok) "[FILE PIPELINE] Arka plan özet işçisi yok, özet atlandı:" else
      "[FILE PIPELINE] Özet kuyruğu dolu, özet atlandı:", file_name_safe, "\n")
    if (isTRUE(show_toast)) {
      showToast(session, paste(file_info$name, if (isci_yok) {
        "yüklendi; arka plan özet kapasitesi olmadığından özet çıkarılmadı."
      } else {
        "yüklendi; özet kuyruğu dolu olduğundan özet çıkarılmadı."
      }), "warning")
    }
    return(.file_pipeline_status(MERGEN_FILE_PIPELINE_ACCEPTED,
                                 if (isci_yok) "ozet_atlandi_isci" else "ozet_atlandi"))
  }

  # Dosya KABUL edildi: kalıcılaştırma ve indeks kaydı tamamlandı. Özetleme
  # asenkron sürer; sayaç/başarı bildirimi bu karara göre verilir.
  .file_pipeline_status(MERGEN_FILE_PIPELINE_ACCEPTED)
}

# Ana Söyleşi yüklemesinin ANA SÜREÇ commit'i: kopyalama/indeksleme bittikten
# sonra dosyayı sohbet bağlamına ekler ve özetlemeyi kuyruğa alır.
# Promise geri çağrısı reaktif bağlam içinde olmadığı için isolate kullanılır.
chat_upload_commit_results <- function(results, ctx, batch_id = NULL) {
  if (!is.null(batch_id)) try(removeNotification(batch_id), silent = TRUE)

  # Parti A için başlayıp oturum B'ye geçtiyse (ya da kimlik düştüyse) dosyalar
  # B'nin sohbet bağlamına HİÇ eklenmez; kalıcı kopya A'nın kovasında kalır.
  if (!.file_pipeline_owner_ok(ctx$session_uid %||% .file_pipeline_session_uid(ctx$session),
                               .file_pipeline_session_uid(ctx$session),
                               .file_pipeline_effective_uid(NULL, ctx$user_id))) {
    cat("[UPLOAD BATCH] Oturum kimliği değişti; parti sohbet bağlamına eklenmedi.\n")
    return(invisible(NULL))
  }

  shiny::isolate({
    for (sonuc in results %||% list()) {
      if (!isTRUE(sonuc$ok)) {
        showToast(
          ctx$session,
          sprintf("'%s' kalıcı klasöre kaydedilemedi: %s", sonuc$name, sonuc$error %||% "bilinmeyen hata"),
          "warning"
        )
        next
      }

      uf <- list(
        name = sonuc$name,
        datapath = sonuc$dest,
        size = sonuc$size,
        type = sonuc$type
      )

      ctx$file_to_add_reactive(uf)

      processAndSummarizeFile(
        uf,
        current_user_id = ctx$user_id,
        session = ctx$session,
        settings = ctx$settings_data,
        file_manager_data = ctx$file_manager_data,
        session_files_reactive = ctx$session_files_reactive,
        update_manager_ui = TRUE,
        show_toast = TRUE,
        auto_attach = FALSE,
        already_persisted = TRUE
      )
    }
  })

  invisible(NULL)
}

# fileInput/sürükle-bırak toplu yüklemesini ortak dosya alım hattına gönderir.
# Doğrulama, kopyalama ve bütünlük denetimi arka planda çalışır; bu fonksiyon
# olay döngüsünü bloklamadan hemen döner.
handle_file_upload_batch <- function(uploads_df,
                                     current_user_id,
                                     session,
                                     settings_data,
                                     file_manager_data,
                                     session_files_reactive,
                                     file_to_add_reactive) {
  if (is.null(uploads_df)) return(invisible(NULL))

  if (is.data.frame(uploads_df)) {
    if (nrow(uploads_df) == 0) return(invisible(NULL))
  } else if (!(is.list(uploads_df) && !is.null(uploads_df$name))) {
    showToast(session, "Dosya yükleme bilgisi okunamadı.", "error")
    return(invisible(NULL))
  }

  # SSO modunda başlangıçta gelen 0L yerine oturumdaki gerçek kullanıcıyı kullan.
  # `%||%` YALNIZCA NULL'u değiştirir: oturum kimliği hâlâ `0L` iken çağıranın
  # ÇÖZÜMLENMİŞ kimliği yok sayılıyor ve geçerli yükleme reddediliyordu.
  effective_user_id <- .file_pipeline_effective_uid(
    session$userData$user_id,
    current_user_id
  )

  if (effective_user_id <= 0L) {
    cat(sprintf("[UPLOAD BATCH] UYARI: effective_user_id=%d, session$userData$user_id=%s, current_user_id=%s\n",
                effective_user_id,
                as.character(session$userData$user_id %||% "NULL"),
                as.character(current_user_id %||% "NULL")))
    # Kimlik hazır değilken yükleme kullanıcı kovasına yazılamaz; reddedilir.
    showToast(session, "Kullanıcı kimliği henüz hazır değil; dosya yüklemesi reddedildi. Lütfen tekrar deneyin.", "error")
    return(invisible(NULL))
  }

  # İzin verilen uzantılar tek kaynaktan (fm_normal_allowed_extensions) gelir;
  # böylece Ana Söyleşi ve Dosya Yönetimi yükleme yolları tutarlı kalır.
  allowed_exts <- if (exists("fm_normal_allowed_extensions", mode = "function", inherits = TRUE)) {
    fm_normal_allowed_extensions()
  } else {
    c("txt","pdf","docx","xlsx","xls","csv","json","r","py","md","log","xml","html",
      "jpg","jpeg","png","gif","webp","bmp","svg")
  }

  batch_id <- file_ingestion_new_batch_id("chat")
  plan <- file_ingestion_plan_batch(
    uploads = uploads_df,
    existing_names = character(),
    user_id = effective_user_id,
    allowed_ext = allowed_exts,
    max_size_mb = if (exists("fm_upload_limit_mb", mode = "function", inherits = TRUE)) {
      fm_upload_limit_mb()
    } else {
      getOption("mergen.upload_max_mb", 25L)
    },
    batch_id = batch_id
  )

  for (red in plan$rejected %||% list()) {
    showToast(
      session,
      sprintf("'%s' dosyası işlenemedi: %s", red$name, red$error %||% "desteklenmiyor"),
      "warning"
    )
  }

  if (!length(plan$tasks)) return(invisible(NULL))

  cat(sprintf("[UPLOAD] %d dosya alındı ve alım hattına gönderiliyor.\n", length(plan$tasks)))

  showNotification(
    sprintf("%d dosya arka planda işleniyor\U2026", length(plan$tasks)),
    duration = NULL,
    type = "message",
    id = batch_id
  )

  commit_ctx <- list(
    session = session,
    session_uid = .file_pipeline_session_uid(session),
    user_id = effective_user_id,
    settings_data = settings_data,
    file_manager_data = file_manager_data,
    session_files_reactive = session_files_reactive,
    file_to_add_reactive = file_to_add_reactive
  )

  outcome <- file_ingestion_submit_batch(
    controller = file_ingestion_session_controller(session),
    tasks = plan$tasks,
    user_id = effective_user_id,
    on_complete = function(results, ctx) chat_upload_commit_results(results, commit_ctx, ctx$batch_id),
    on_failure = function(message, tasks) {
      try(removeNotification(batch_id), silent = TRUE)
      showToast(session, "Dosyalar işlenemedi. Lütfen tekrar deneyin.", "error")
    },
    batch_id = batch_id
  )

  if (identical(outcome$status, "rejected")) {
    try(removeNotification(batch_id), silent = TRUE)
    showToast(session, "Yükleme kuyruğu dolu. Lütfen biraz sonra tekrar deneyin.", "warning")
  }

  invisible(outcome)
}