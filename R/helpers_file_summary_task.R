# ==============================================================================
# Dosya Yolu: R/helpers_file_summary_task.R
# Açıklama: Dosya özeti işçi görevi: ayar anlık görüntüsü, LLM özet çağrısı,
#           işçide çalışan görev fabrikası ve özet iş jetonları
#           (R/helpers_file_pipeline.R kullanır).
# ==============================================================================

as_llm_settings_list <- function(settings) {
  if (is.null(settings)) return(list())

  # reaktif değerler (reactiveValues) is.list() kontrolünde TRUE döndürür; bu
  # nedenle düz liste kontrolünden ÖNCE yakalanmalıdır. Aksi halde canlı reaktif
  # nesne, anlık görüntüye çevrilmeden worker/arka plan bağlamına sızabilir ve
  # "reactive value outside consumer" hatasına yol açabilir
  # (CLAUDE.md: worker'a canlı reaktif nesne geçirme, önce düz değer yakala).
  # isolate ile reaktif olmayan bağlamda da güvenli anlık görüntü alınır.
  if (shiny::is.reactivevalues(settings)) {
    return(tryCatch(
      shiny::isolate(shiny::reactiveValuesToList(settings)),
      error = function(e) list()
    ))
  }

  if (is.list(settings)) return(settings)

  tryCatch(
    shiny::isolate(shiny::reactiveValuesToList(settings)),
    error = function(e) list()
  )
}

summarize_file_with_llm <- function(file_text, filename, settings) {
  snippet <- substr(file_text %||% "", 1, 60000)
  settings_list <- as_llm_settings_list(settings)
  chat <- list(
    list(type = "system",
         content = "Türkçe yanıtla. ÖNEMLİ: Bu bir 'özet' görevi DEĞİLDİR. Görevin, dosyanın içeriğini kapsamlı bir şekilde 'ÇIKARTMAK' ve raporlamaktır. \
Asla yüzeysel geçme. Dosyadaki her ana başlığı, alt başlığı, istatistiksel veriyi, sayısal değerleri ve teknik detayları koruyarak uzun ve ayrıntılı bir içerik dökümü hazırla. \
Kullanıcı 'özet' dese bile, sen 'Ayrıntılı İçerik Analizi' formatında yanıt ver. \
Eksik bilgi bırakma. İçeriği maddeler halinde, hiyerarşik ve okunabilir şekilde sun."),
    list(type = "user",
         content = paste0("Dosya adı: ", filename,
                          "\nİçerik (kısaltılmış olabilir):\n", snippet))
  )
  tryCatch({
    warn_msgs <- character(0)
	res <- withCallingHandlers(
	  call_llm_with_retry(chat, settings_list, max_retries = 2),
      warning = function(w) {
        warn_msgs <<- c(warn_msgs, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    if (is.list(res) && !is.null(res$content)) {
      res <- res$content
    }
    if (!is.character(res) || length(res) == 0 || is.na(res[1])) {
      res <- ""
    } else {
      res <- as.character(res)[1]
    }
    if (!nzchar(res)) {
      paste("Özet çıkarılamadı. İçerikten bir parça:\n", substr(snippet, 1, 1000))
    } else {
      res
    }
  }, error = function(e) {
    paste("Özet çıkarılamadı. İçerikten bir parça:\n", substr(snippet, 1, 1000))
  })
}

# Özet görevi üst düzey fabrikadan üretilir: gövde her dosyada aynı olduğundan
# bağımlılık taraması açılışta bir kez ısıtılabilir (file_summary_warm_dependencies).
# `stop_file` oturum kapanınca ya da oturumun kimliği değişince/düşünce ana
# süreçte oluşturulur; işçi okuma ve LLM çağrısından önce bakar ve artık yetkili
# olmayan sahibin işini sürdürmez.
file_summary_task_fn <- function(file_name_safe, dest_safe, settings_snapshot, stop_file = "") {
  force(file_name_safe)
  force(dest_safe)
  force(settings_snapshot)
  force(stop_file)
  function() {
    if (nzchar(stop_file) && file.exists(stop_file)) stop("Oturum kapandı ya da kimlik değişti; dosya özeti iptal edildi.")
    file_ext <- tolower(tools::file_ext(file_name_safe))

    # Özet çıkarma - hata durumunda basit bilgi döndür
    digest <- tryCatch({
      switch(file_ext,
        "xlsx" = , "xls" = build_excel_digest_json(dest_safe, top_levels = 12),
        {
          txt <- readFileContentToString(list(name = file_name_safe, datapath = dest_safe, size = file.info(dest_safe)$size))
          substr(txt, 1, 50000)
        }
      )
    }, error = function(e) {
      sprintf("Dosya: %s\nBoyut: %s bayt\nTip: %s\n(Detaylı içerik okunamadı: %s)",
              file_name_safe,
              file.info(dest_safe)$size %||% "bilinmiyor",
              file_ext,
              conditionMessage(e))
    })

    if (nzchar(stop_file) && file.exists(stop_file)) stop("Oturum kapandı ya da kimlik değişti; dosya özeti iptal edildi.")
    summary_text <- summarize_file_with_llm(digest, file_name_safe, settings_snapshot)
    list(summary = summary_text, dest = dest_safe, ext = file_ext)
  }
}

# Dosya adına bağlı özet iş jetonu (oturum userData ortamında). `jeton` verilirse
# yazar, `NULL` ile çağrılırsa siler; ortam yoksa (test çiftleri) sessizce geçer.
.file_summary_job_token <- function(session, ad, jeton) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (!is.environment(ud) || is.null(ad) || !nzchar(as.character(ad)[1])) return(invisible(NULL))
  isler <- if (is.list(ud$file_summary_jobs)) ud$file_summary_jobs else list()
  isler[[as.character(ad)[1]]] <- jeton
  ud$file_summary_jobs <- isler
  invisible(NULL)
}

# Özet sonucu yalnız iş jetonu hâlâ bu işe aitse ve dosya kayıt defterinde aynı
# yolla duruyorsa uygulanır.
.file_summary_result_current <- function(session, ad, jeton, dest) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (!is.environment(ud)) return(TRUE)
  if (!identical(ud$file_summary_jobs[[ad]], jeton)) return(FALSE)
  kayit <- ud$current_session_files
  if (!is.list(kayit)) return(TRUE)
  yol <- kayit[[ad]]$path %||% kayit[[ad]]$datapath
  !is.null(yol) && identical(as.character(yol)[1], as.character(dest)[1])
}
