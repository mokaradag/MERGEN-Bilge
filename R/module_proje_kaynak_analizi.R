# R/module_proje_kaynak_analizi.R

# Proje/Kaynak Analizi helper'ları büyük modül dışında tutulur.
pk_required_helpers <- list(
  list(
    functions = c("summarize_columns_for_ai", "normalize_sql_server_identifiers"),
    path = file.path("R", "helpers_pk_analysis_core.R")
  ),
  list(
    functions = c(
      "resolve_pk_analysis_username",
      "get_user_rls_info",
      "apply_rls_to_data",
      "generate_statistical_summary"
    ),
    path = file.path("R", c("helpers_pk_rls_identity.R", "helpers_pk_analysis_security_summary.R", "helpers_pk_statistical_summary.R"))  # kimlik/izin ONCE, sonra ozet
  ),
  list(
    functions = c("extract_filter_criteria_from_prompt", "apply_smart_filters"),
    path = file.path("R", "helpers_pk_analysis_filters.R")
  ),
  list(
    functions = c(
      "pk_init_query_score_table",
      "pk_score_query_relevance",
      "pk_compute_heuristic_query_scores",
      "print_score_table"
    ),
    path = file.path("R", "helpers_pk_analysis_query_selection.R")
  ),
  # Faz 5 (§5.2) iki geçişli seçim zinciri. İZOLE/DOĞRUDAN yüklemede bu zincir
  # yoksa `pk_select_query_v2` tanımsız kalır, aşağıdaki `exists()` kapısı
  # sessizce FALSE olur ve `MERGEN_PK_ENGINE=v2` istenmiş olsa bile istek
  # KAPILARI OLMAYAN v1 seçicisine düşerdi. Sıra bağımlılık sırasıdır ve
  # `R/config_source_manifest.R` ile BİREBİR aynıdır.
  list(
    functions = c("pk_select_query_v2", "pk_select_run", "pk_select_decide"),
    path = c(
      file.path("R", "helpers_pk_query_retrieval.R"),
      file.path("R", "helpers_pk_query_selection_json.R"),
      file.path("R", "helpers_pk_query_selection_config.R"),
      file.path("R", "helpers_pk_query_selection_payload.R"),
      file.path("R", "helpers_pk_query_selection_prompt.R"),
      file.path("R", "helpers_pk_query_selection_requirements.R"),
      file.path("R", "helpers_pk_query_selection_parse.R"),
      file.path("R", "helpers_pk_query_selection_decide.R"),
      file.path("R", "helpers_pk_query_selection_degraded.R"),
      file.path("R", "helpers_pk_query_selection_history.R"),
      file.path("R", "helpers_pk_query_selection_session.R"),
      file.path("R", "helpers_pk_query_selection_seed.R"),
      file.path("R", "helpers_pk_query_selection_ai.R"),
      file.path("R", "helpers_pk_query_selection_deep.R"),
      file.path("R", "helpers_pk_query_selection_apply.R")
    )
  )
)

for (helper_spec in pk_required_helpers) {
  missing_helpers <- vapply(
    helper_spec$functions,
    function(fn) !exists(fn, mode = "function", inherits = TRUE),
    logical(1)
  )

  if (!any(missing_helpers)) {
    next
  }

  eksik_dosya <- helper_spec$path[!file.exists(helper_spec$path)]
  if (length(eksik_dosya)) {
    stop(
      sprintf(
        "%s bulunamadı; module_proje_kaynak_analizi.R yüklenemiyor.",
        paste(eksik_dosya, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  # Zincir BAĞIMLILIK SIRASINDA yüklenir; tek dosyalı girdiler de aynı yoldan
  # geçer (vektör uzunluğu 1'dir).
  for (yol in helper_spec$path) source(yol, encoding = "UTF-8", local = globalenv())
}

rm(list = intersect(
  c("pk_required_helpers", "helper_spec", "missing_helpers", "eksik_dosya", "yol"),
  ls(all.names = FALSE)
))

# ==============================================================================
# 1. RLS, KİMLİK VE ÖZET YARDIMCILARI
# ==============================================================================
# Bu sorumluluklar R/helpers_pk_analysis_security_summary.R içinde tutulur.

# ==============================================================================
# 2. SORGULAMA MOTORU (EXECUTION ENGINE)
# ==============================================================================

pk_analiz_process_request <- function(user_prompt, chat_history, session, stop_check = NULL) {
  cat("\n[PK_ANALIZ] >>> pk_analiz_process_request BASLATILDI <<<\n")

  # Faz 0 gözlemi: köken alt bilgisi + telemetri. Analiz akışını DEĞİŞTİRMEZ.
  pk_started_at <- Sys.time()
  pk_request_id <- if (exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
    pk_provenance_current_request_id(session)
  } else {
    NULL
  }
  # NOT: Kapanış `conn` ve `username` değerlerini ÇAĞRI ANINDA çözer; bu yüzden
  # yalnızca o değişkenler tanımlandıktan sonraki çıkışlarda çağrılır.
  # Seçim bozulma açıklamaları: kapanış tanımlanmadan ÖNCE ilklenir (aşağıda
  # gerçek değerle güncellenir); `pk_observe()` bunu sözlüksel kapsamla okur.
  pk_selection_disclosures <- character(0)

  pk_observe <- function(...) {
    if (!exists("pk_analysis_observe", mode = "function", inherits = TRUE)) return(invisible(NULL))

    # Düz atama kullanılır; utils::modifyList() liste değerli alanları
    # (ör. filters) ada göre özyinelemeli birleştirir ve geçersiz kılmayı bozar.
    pk_info <- list(
      request_id  = pk_request_id,
      question    = user_prompt,
      username    = username,
      engine      = "v1",
      # Faz 5: secim asamasinda olusan bozulmalar (varsa) alt bilgiye ve
      # telemetriye tasinir. Yalnizca loglara yazilan bir zayiflatma,
      # kullanici acisindan hic olmamis demektir.
      # `exists(..., inherits = FALSE)` YALNIZCA `pk_observe()` çerçevesine
      # bakar; değişken KAPSAYAN çerçevede (`pk_analiz_process_request`)
      # atanır, dolayısıyla koşul HER ZAMAN FALSE'tu ve seçim bozulmaları
      # telemetriye/alt bilgiye HİÇ ulaşmıyordu. Değişken artık kapanış
      # tanımlanmadan ÖNCE ilklenir ve sözlüksel kapsamla okunur.
      extra_degradations = pk_selection_disclosures,
      duration_ms = as.numeric(difftime(Sys.time(), pk_started_at, units = "secs")) * 1000
    )
    pk_over <- list(...)
    if (length(pk_over) > 0) pk_info[names(pk_over)] <- pk_over

    try(pk_analysis_observe(session, conn, pk_info), silent = TRUE)
    invisible(NULL)
  }

  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (baslangic)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
  cat(sprintf("[PK_ANALIZ] Kullanici Prompt: '%s'\n", user_prompt))

  username_state <- resolve_pk_analysis_username(session)
  if (!isTRUE(username_state$ready)) {
    cat(sprintf(
      "[PK_ANALIZ] Kullanici kimligi hazir degil. Sebep: %s\n",
      username_state$reason %||% "unknown"
    ))

    return(paste0(
      "\U000023F3 **Kimlik Doğrulama Hazırlanıyor:** ",
      "Proje ve Kaynak Analizi için kullanıcı kimliğiniz henüz hazır değil. ",
      "Lütfen SSO oturumunuz tamamlandıktan sonra tekrar deneyin."
    ))
  }

  username <- username_state$username

  # A. Bağlantı Kur
  cat("[PK_ANALIZ] DB Baglantisi aliniyor...\n")
  conn_list <- get_connection()
  conn <- conn_list$conn
  on.exit({
    cat("[PK_ANALIZ] DB Baglantisi serbest birakiliyor.\n")
    release_connection(conn_list)
  })
  
  # B. Kullanıcı RLS Bilgisini Çek
  rls_info <- get_user_rls_info(username, conn)
  # PR #703: TİPLİ Durdur/son tarih, `authorized`'dan ÖNCE ele alınmalıdır.
  if (isTRUE(rls_info$halted)) return(pk_rls_halt_message(rls_info))
  if (!isTRUE(rls_info$authorized)) {
    cat(sprintf("[PK_ANALIZ] Yetki verilmedi (tur=%s).\n", if (isTRUE(rls_info$db_error)) "db_error" else if (isTRUE(rls_info$ambiguous)) "ambiguous" else "not_found"))
    return(pk_rls_denied_message(rls_info))  # PR #705: db_error/ambiguous/not_found TIPLI ayrilir; hepsi KAPALI BASARISIZ, ayrilan yalnizca TESHIS
  }
  
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (RLS sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
  cat("[PK_ANALIZ] Akilli sorgu secimi yapiliyor (select_smart_query)...\n")
  # Oturum ACIKCA gecirilir: Ortak Oturum koprusu soruyu soran kullanici icin
  # sentetik bir oturum kurar ve varsayilan reaktif alan adi BASKA bir
  # kullaniciya aittir. Varsayilan alani okumak, baska kullanicinin onceki
  # sorgusunu tohumlar ve API anahtarini yanlis kullaniciyla cozerdi.
  selected_query <- select_smart_query(
    user_prompt, query_library, chat_history,
    session = session, stop_check = stop_check
  )

  if (is.null(selected_query) || (!is.null(selected_query$all_scores) && is.null(selected_query$id))) {
    cat("[PK_ANALIZ] UYARI: Uygun bir sorgu ESLESMESI BULUNAMADI.\n")

    # Faz 5 (§5.2 / D10): v2 secim hatti ACIKCA "bilmiyorum" dediyse v1'in
    # dusuk-esik geri donusu DEVREYE GIRMEZ. Yanlis bir finansal sorguyu
    # calistirmaktansa kullaniciya sormak yeglenir.
    if (!is.null(selected_query$refusal_message)) {
      # Iptal semantigi tutarli kalmalidir: secici calisirken gelen bir
      # durdurma istegi, netlestirme mesajini normal bir yanit gibi
      # gondermemelidir.
      if (is.function(stop_check) && isTRUE(stop_check())) {
        cat("[PK_ANALIZ] Durdurma talebi alindi (v2 reddi oncesi)\n")
        return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
      }

      # Reddetme/netlestirme sonuclari da TELEMETRIYE yazilir. Aksi halde
      # low_confidence/close_margin/timeout gibi sonuclar kalici olcumden
      # tamamen dusuyor ve yayilim metrikleri yalnizca basarili calistirmalari
      # gorup esik ayarini olcemez hale geliyordu.
      pk_karar <- selected_query$pk_selection
      pk_observe(
        outcome = "Reddedildi",
        engine = "v2",
        selection_status = pk_karar$status %||% "unknown",
        query_id = pk_karar$query_id %||% NA_character_,
        selection_confidence = pk_karar$effective_confidence %||% pk_karar$confidence,
        selection_margin = pk_karar$margin,
        capability_status = pk_karar$capability_status %||% "not_asserted"
      )

      # Yapisal netlestirme secenekleri (chips) KORUNUR. Tasiyici sekil
      # bilinerek `error_message`dir: hem send_message hem Ortak Oturum
      # koprusu bu sekli dogrudan yanit olarak isler, boylece metin gosterimi
      # bozulmadan yapisal veri de birlikte tasinir.
      return(list(
        type = "error_message",
        content = as.character(selected_query$refusal_message)[1],
        pk_selection_status = pk_karar$status %||% "unknown",
        pk_chips = selected_query$pk_chips %||% list()
      ))
    }

    if (!is.null(selected_query$all_scores)) {
      best_score <- max(selected_query$all_scores$final_score, na.rm = TRUE)
      best_idx <- which.max(selected_query$all_scores$final_score)
      best_name <- if (length(best_idx) > 0) selected_query$all_scores$query_name[best_idx] else "?"
      cat(sprintf("[PK_ANALIZ] En yuksek skor: %.1f%% - '%s' (Esik altinda kaldi)\n", best_score, best_name))
      
      if (best_score >= 20) {
        cat("[PK_ANALIZ] Dusuk guvenle en yakin sorgu seciliyor (fallback)...\n")
        fallback_query <- query_library[[best_idx]]
        fallback_query$relevance_score <- best_score
        fallback_query$selection_method <- "fallback"
        fallback_query$selection_reason <- "Dusuk esik skoru - en yakin eslesme"
        fallback_query$all_scores <- selected_query$all_scores
        selected_query <- fallback_query
      }
    }
    
    if (is.null(selected_query$id)) {
      return("\U0001F914 Aradığınız bilgi mevcut analiz kütüphanesinde bulunamadı. Lütfen sorunuzu farklı kelimelerle tekrar deneyin veya mevcut analiz kategorilerini inceleyin.")
    }
  }
  
  # Secim tanilamasi (yalnizca cat) secim katmanina tasindi; modul orkestrasyona
  # odakli kalir. Yardimci yoksa akis sessizce devam eder.
  if (exists("pk_select_log_selection", mode = "function", inherits = TRUE)) {
    pk_select_log_selection(selected_query)
  }

  # Faz 6 (§5.10): YURUTME BAGLAMI SECIMDEN HEMEN SONRA kurulur; per-query
  # `analysis_deadline_sec` override'ini uygular. Daha once SQL hazirligindan ve
  # `target_db != "primary"` dalindaki YENIDEN BAGLANMADAN SONRA kuruluyordu; o
  # reconnect kuresel son tarihi kullaniyor ve yavas bir ikincil DSN, sorguya
  # ozel butcenin cok otesinde bloklayabiliyordu. RLS kapsami henuz bilinmedigi
  # icin once yalnizca sorguyla kurulur, kapsam cozulunce TAZELENIR.
  pk_exec_ctx_restore <- NULL
  if (exists("pk_set_exec_context", mode = "function", inherits = TRUE)) {
    pk_exec_ctx_restore <- pk_set_exec_context(
      query = selected_query, rls_info = NULL, engine = pk_engine_mode()
    )
    # `after = FALSE`: `on.exit()` işleyicileri KAYIT SIRASINDA çalışır. İlk
    # geri yükleyici bağlamı özgün değerine döndürüyor, ARDINDAN aşağıdaki
    # tazeleme geri yükleyicisi onu "tazeleme öncesi" (yani sorgu kapsamlı)
    # değerle EZİYORDU: sorguya özgü `analysis_deadline_sec` fonksiyondan
    # döndükten SONRA da yürürlükte kalıyor ve aynı süreçte bağlamı okuyan bir
    # sonraki koda sızıyordu. LIFO çözüm sırası doğru olandır.
    on.exit(try(pk_exec_ctx_restore(), silent = TRUE), add = TRUE, after = FALSE)
  }

  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (sorgu secimi sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }

  # Secim ANCAK iptal kapisi gecildikten SONRA kalicilastirilir; aksi halde
  # hemen durdurulan bir secim, sonraki eksiltili takip sorusunu kullanicinin
  # durdurdugu analizle tohumlardi.
  if (exists("pk_select_commit_selection", mode = "function", inherits = TRUE)) {
    try(pk_select_commit_selection(selected_query, session), silent = TRUE)
  }

  # Faz 5 bozulma aciklamalari (ör. sozluksel uyusmazlik nedeniyle guvenin
  # dusurulmesi) yanit alt bilgisine ve telemetriye TASINIR: plan kurali her
  # bozulmanin yanitta gorunmesidir.
  pk_selection_disclosures <- if (exists("pk_select_disclosures", mode = "function", inherits = TRUE)) {
    tryCatch(pk_select_disclosures(selected_query), error = function(e) character(0))
  } else {
    character(0)
  }

  cat(sprintf("[PK_ANALIZ] Secilen Sorgu: '%s' (Table: %s)\n", selected_query$name, selected_query$description))
   
	# 1. SQL icerigini belirle
	# SQL artik startup sirasinda R/config_sql_loader.R tarafindan yukleniyor.
	# Burada dosyayi yeniden okumuyoruz; dogrudan preload edilmis sql alanini kullaniyoruz.
	sql_query_text <- selected_query$sql %||% ""

	if (!nzchar(trimws(sql_query_text))) {
	  if (!is.null(selected_query$sql_file) && nzchar(selected_query$sql_file)) {
		cat(sprintf("[PK_ANALIZ] HATA: Startup sirasinda preload edilmis SQL bos. Dosya: %s\n", selected_query$sql_file))
		return(paste0(
		  "\u26A0\uFE0F **Yapılandırma Hatası:** SQL dosyası startup sırasında yüklenmemiş görünüyor. Dosya: ",
		  selected_query$sql_file
		))
	  }

	  cat("[PK_ANALIZ] HATA: selected_query$sql bos.\n")
	  return("\u26A0\uFE0F **Yapılandırma Hatası:** Sorgu için SQL kodu bulunamadı.")
	}

	sql_query_text <- as.character(sql_query_text)[1]
	sql_query_text <- enc2utf8(sql_query_text)

	# BOM temizligi
	bom_char <- intToUtf8(65279L)
	if (startsWith(sql_query_text, bom_char)) {
	  sql_query_text <- substring(sql_query_text, 2L)
	}

	# Satir sonlarini normalize et
	sql_query_text <- gsub("\r\n?|\r", "\n", sql_query_text, perl = TRUE)

	cat(sprintf("[PK_ANALIZ] Preload edilmis SQL kullaniliyor. Uzunluk: %d karakter\n", nchar(sql_query_text)))
	cat(sprintf("[PK_ANALIZ] SQL baslangici:\n%s\n[...]\n", substr(sql_query_text, 1, 200)))

	if (grepl("^[a-zA-Z]:[\\\\/]|^[\\\\/]{2}|^\\./|^\\.\\./|^[^/\\\\]+[\\\\/]", sql_query_text)) {
	  cat("[PK_ANALIZ] KRITIK HATA: sql_query_text dosya yolu iceriyor!\n")
	  cat(sprintf("[PK_ANALIZ] Icerik: %s\n", substr(sql_query_text, 1, 300)))
	  return("\u26A0\uFE0F **Sistem Hatası:** SQL sorgusu yüklenemedi (dosya yolu algılandı).")
	}

	# D23: Eski dogrulama INSERT/UPDATE/EXEC iceren metni GECERLI sayiyordu.
	# Gercek salt-okunur kapisi asagida final_sql uzerinde calisir; burada
	# yalnizca bariz bos/kirik icerik elenir.
	if (nchar(sql_query_text) < 10) {
	  cat("[PK_ANALIZ] HATA: Gecersiz SQL icerigi!\n")
	  cat(sprintf("[PK_ANALIZ] Icerik: %s\n", substr(sql_query_text, 1, 200)))
	  return("\u26A0\uFE0F **Sistem Hatası:** Geçersiz SQL sorgusu yüklendi.")
	}

	target_db <- selected_query$db_target %||% DB_TARGETS$PRIMARY %||% "primary"
	target_db <- tolower(trimws(as.character(target_db)[1]))
	if (!nzchar(target_db)) target_db <- "primary"

	if (!is.null(target_db) && target_db != "primary") {
	   cat(sprintf("[PK_ANALIZ] Hedef DB 'primary' degil (%s). Baglanti degistiriliyor...\n", target_db))
	   
	   release_connection(conn_list)
	   
	   conn_list <- get_connection(target = target_db)
	   conn <- conn_list$conn
	}

	# SQL metnini parametre donusumunden gecirme.
	# normalize_db_value() parametreler icin uygundur; tam SQL metni icin kullanilmaz.
	final_sql <- trimws(sql_query_text)
	final_sql <- enc2utf8(final_sql)

	cat(sprintf("[PK_ANALIZ] SQL DB'ye gonderiliyor (Ilk 100 kar.):\n--> %s...\n", substr(final_sql, 1, 100)))

	# D23: Ifade farkinda, kapali basarisiz salt-okunur kapisi. Eski kara liste
	# (DELETE|DROP|TRUNCATE|ALTER) MERGE, SELECT ... INTO, veri degistiren CTE,
	# sp_/xp_ ve cok ifadeli batch'i serbest birakiyordu. Kapi baglanti
	# CALISTIRILMADAN ONCE uygulanir ve her iki motor icin KOSULSUZDUR.
	sql_gate <- pk_sql_readonly_guard(final_sql, context_label = "PK_ANALIZ")
	if (!isTRUE(sql_gate$allowed)) {
	  cat(sprintf(
		"[PK_ANALIZ] SQL kapisi reddetti | Sorgu ID: %s | Dosya: %s\n",
		selected_query$id %||% "?",
		selected_query$sql_file %||% "inline"
	  ))
	  return(sql_gate$message)
	}

	# Faz 6 (§5.10): baglam SECIMDEN HEMEN SONRA zaten kuruldu (son tarih
	# override'i reconnect'i de kapsasin diye). Burada YALNIZCA yetki kapsami
	# eklenerek TAZELENIR; onceki geri yukleyici `on.exit` ile kayitlidir.
	if (exists("pk_set_exec_context", mode = "function", inherits = TRUE)) {
	  pk_exec_ctx_refresh <- pk_set_exec_context(
		query = selected_query, rls_info = rls_info, engine = pk_engine_mode()
	  )
	  # LIFO: bkz. yukarıdaki `pk_exec_ctx_restore` açıklaması.
	  on.exit(try(pk_exec_ctx_refresh(), silent = TRUE), add = TRUE, after = FALSE)
	}

	raw_data <- tryCatch({

	  execute_pk_sql_unicode(conn, final_sql)

	}, error = function(e) {
	  # D22: Ham ODBC/surucu/DSN tanilamasi ARTIK sohbete gomulmez; sunucu
	  # loguna yazilir, kullanicaya genel Turkce mesaj doner.
	  cat(sprintf(
		"[PK_ANALIZ] SQL HATASI | DB: %s | Sorgu ID: %s | Sorgu Adi: %s\n",
		selected_query$db_target %||% "primary",
		selected_query$id %||% "?",
		selected_query$name %||% "?"
	  ))
	  cat(sprintf(
		"[PK_ANALIZ] SQL HATASI | SQL dosyasi: %s\n",
		selected_query$sql_file %||% "inline"
	  ))

	  # Redaksiyon gecirgendir: altyapi tanilamasi GIBI GORUNMEYEN bir metin
	  # (ornegin "Bos SQL metni gonderilemez.") oldugu gibi doner. Asagidaki
	  # sentinel kontrolu icin metin her kosulda isaretlenir.
	  return(pk_user_error_text(pk_report_db_error(
		conditionMessage(e),
		context_label = "PK_ANALIZ",
		context_detail = sprintf("sorgu=%s", selected_query$id %||% "?")
	  )))
	})

  # execute_pk_sql_unicode() BASARILI oldugunda daima data.frame doner; bu
  # noktada karakter deger YALNIZCA hata dalindan gelebilir. Onek kontrolu tek
  # basina kirilgandi: isareti tasimayan bir hata metni sonuc kumesi sanilip
  # akisi ham bir R hatasiyla ("argument is of length zero") cokertiyordu.
  if (is.character(raw_data)) return(raw_data)
  
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (SQL sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
	raw_data <- normalize_pk_dataframe_utf8(raw_data)

	cat(sprintf("[PK_ANALIZ] SQL Basarili. Dönen Satir: %d\n", nrow(raw_data)))
	cat("[PK_ANALIZ] SQL sonucu UTF-8 normalize edildi.\n")
  
  if (!is.null(selected_query$date_columns)) {
    raw_data <- convert_date_columns(raw_data, selected_query$date_columns)
  }
  
  # Faz 3a M8 baglantisi: SQL'den gelen GERCEK sutunlar, sorgu metadatasi ve
  # rls_columns beyanina karsi RLS'ten ONCE dogrulanir.
  #
  # Motor kipi istek basina TEK KEZ cozulur. `select_smart_query()` secim
  # aninda cozdugu kipi sorguya iliştirir; boylece kuresel bayrak ile sorgu
  # metadata'si farkli olsa bile secim ve asagi akis AYNI kipte kalir.
  pk_engine_v2 <- if (!is.null(selected_query$pk_engine_mode)) {
    identical(as.character(selected_query$pk_engine_mode)[1], "v2")
  } else {
    exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
      isTRUE(pk_engine_is_v2(selected_query$meta))
  }
  meta_gate <- pk_meta_actual_column_gate(selected_query, names(raw_data), pk_engine_v2)
  if (length(meta_gate$warn) > 0) {
    cat(sprintf(
      "[PK_ANALIZ] METADATA/RLS SUTUN UYUSMAZLIGI | sorgu=%s | %s\n",
      selected_query$id %||% "?", paste(meta_gate$warn, collapse = " ; ")
    ))
  }
  if (isTRUE(meta_gate$abort)) {
    return(PK_RLS_ABORT_USER_MESSAGE)
  }
  if (isTRUE(meta_gate$engine_abort)) {
    return(paste0(
      "\U000026A0\U0000FE0F **Yapılandırma Hatası:** Sorgu sonucu, tanımlı sorgu ",
      "metadatası ile uyuşmuyor. Analiz güvenli biçimde sürdürülemedi."
    ))
  }

  # D6/D6b: RLS artik kapali basarisizdir; plan uretilemezse siniflandirilmis
  # kosul yukselir ve kullaniciya ic ayrinti TASIMAYAN Turkce mesaj doner.
  secure_data <- tryCatch(
    apply_rls_to_data(raw_data, rls_info, selected_query$rls_columns),
    pk_rls_error = function(e) conditionMessage(e)
  )
  if (is.character(secure_data)) return(secure_data)
  cat(sprintf("[PK_ANALIZ] RLS sonrasi: %d satir\n", nrow(secure_data)))
  
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (RLS sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
  if (nrow(secure_data) == 0) {
      pk_observe(
        query_id = selected_query$id, query_name = selected_query$name,
        filter_status = "not_reached", filters = list(),
        pre_rls_rows = nrow(raw_data), authorized_rows = 0L, filtered_rows = 0L,
        outcome = "BosSonuc"
      )
      return(paste0("\U0001F50D **Sonuc:** Sorgu calistirildi ancak yetkiniz dahilinde veri bulunamadi."))
  }
    
  # AI fonksiyonuna veriyi de gonderiyoruz ki degerleri gorebilsin
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (filtreleme oncesi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
  pk_filter_policy <- NULL; pk_entity_decisions <- NULL  # P4-9: OZNE iptal kapisindan SONRA saklanir

  if (isTRUE(selected_query$disable_ai_filters)) {
    cat("[PK_ANALIZ] Ozel Sorgu Ayari: AI Filtreleme devre disi birakildi. Sadece RLS verisi kullaniliyor.\n")
    filter_criteria <- list(filters = list(), aggregation = NULL, status = "disabled")
    filtered_data <- secure_data
	} else {
	available_columns <- names(secure_data)
    filter_criteria <- extract_filter_criteria_from_prompt(user_prompt, secure_data, available_columns, conn, session, stop_check = stop_check)
  
    if (!is.null(filter_criteria$error)) {
      cat(sprintf("[PK_ANALIZ] AI filtreleme hatasi: %s\n", filter_criteria$error))
    }
  
    cat(sprintf("[PK_ANALIZ] AI Filter Sonucu -> column: %s, value: %s, operation: %s, aggregation: %s\n",
                filter_criteria$filter_column %||% "NULL",
                filter_criteria$filter_value %||% "NULL",
                filter_criteria$operation %||% "NULL",
                filter_criteria$aggregation %||% "NULL"))
  
	# D9: v2'de bozulmus filtre durumu (zaman asimi/hata/bozuk yanit) SESSIZCE
	# tum kume uzerinden devam ETMEZ; analiz aciklamayla reddedilir.
	if (pk_engine_v2 && exists("pk_filter_degraded_gate", mode = "function", inherits = TRUE)) {
	  bozuk_kapi <- pk_filter_degraded_gate(filter_criteria$status)
	  if (isTRUE(bozuk_kapi$refuse)) {
		pk_observe(
		  query_id = selected_query$id, query_name = selected_query$name,
		  filter_status = filter_criteria$status, filters = list(),
		  pre_rls_rows = nrow(raw_data), authorized_rows = nrow(secure_data),
		  filtered_rows = 0L, outcome = "BosSonuc"
		)
		return(list(type = "error_message", content = bozuk_kapi$message))
	  }
	}

	if (exists("pk_filter_instructions_with_context", mode = "function", inherits = TRUE)) filter_criteria <- pk_filter_instructions_with_context(filter_criteria, chat_history, session)  # D11: gecmis + onceki tur varlik baglami cozumleyiciye BURADA baglanir
	filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)
	# v2 politika karari, normalize_pk_dataframe_utf8() ozniteligi dusurmeden ONCE alinir.
	if (pk_engine_v2 && exists("PK_FILTER_V2_ATTR", inherits = TRUE)) {
	  pk_filter_policy <- attr(filtered_data, PK_FILTER_V2_ATTR, exact = TRUE); pk_entity_decisions <- pk_filter_policy$entity_decisions  # yazim iptal kapisindan SONRA
	}

	filtered_data <- normalize_pk_dataframe_utf8(filtered_data)
  }

  # D4: Birincil filtre sutununda sifir eslesme -> ANALIZ YAPILMAZ. Bos ekran
  # da, tum projeler uzerinden istatistik de dogru cevap degildir.
  if (is.list(pk_filter_policy) && identical(pk_filter_policy$action, "refuse")) {
    pk_observe(
      query_id = selected_query$id, query_name = selected_query$name,
      filter_status = filter_criteria$status, filters = list(),
      pre_rls_rows = nrow(raw_data), authorized_rows = nrow(secure_data),
      filtered_rows = 0L, outcome = "BosSonuc"
    )
    return(list(type = "error_message", content = pk_filter_policy$refusal_message))
  }
  
  cat(sprintf("[PK_ANALIZ] Filtreleme sonrası: %d satır (Orijinal: %d)\n",
              nrow(filtered_data), nrow(secure_data)))

  # Faz 6 (§5.10): YETKİ VE FİLTRE SONRASI satır tavanı. RLS'in içinde
  # çalıştırılmaz (geniş bir yetkili küme, soru onu birkaç satıra indirse bile
  # reddedilirdi) ve `MERGEN_PK_ASYNC=false` iken devreye girmez.
  pk_cap_stage <- pk_row_cap_stage(filtered_data, query_meta = selected_query$meta)
  if (identical(pk_cap_stage$status, "too_large")) {
    cat("[PK_ANALIZ] Satir tavani asildi; analiz reddedildi.\n")
    pk_observe(
      query_id = selected_query$id, query_name = selected_query$name,
      filter_status = filter_criteria$status, filters = filter_criteria$filters,
      pre_rls_rows = nrow(raw_data), authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data), outcome = "SonucCokBuyuk"
    )
    return(list(type = "error_message", content = pk_row_cap_refuse_message()))
  }

  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (filtreleme sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  if (!is.null(pk_entity_decisions) && exists("pk_entity_context_remember", mode = "function", inherits = TRUE)) try(pk_entity_context_remember(session, pk_entity_decisions, selected_query), silent = TRUE)  # P4-9: iptal edilen istek bir sonraki turu TOHUMLAMAZ
			  
	if (nrow(filtered_data) < nrow(secure_data) * 0.05 && nrow(secure_data) > 100) {
	  cat("[PK_ANALIZ] UYARI: Filtreleme sonucu çok az veri kaldı (<%5). Kullanıcı gereksiz filtre uygulanmış olabilir.\n")
	}
  
  if (nrow(filtered_data) == 0) {
    cat("[PK_ANALIZ] Filtreleme sonrasi veri yok, islem tamamlandi.\n")

    pk_observe(
      query_id = selected_query$id, query_name = selected_query$name,
      filter_status = filter_criteria$status, filters = filter_criteria$filters,
      pre_rls_rows = nrow(raw_data), authorized_rows = nrow(secure_data),
      filtered_rows = 0L, outcome = "BosSonuc"
    )

    # Bozulma (zaman aşımı/hata/bozuk yanıt) varsa boş sonucu sessizce
    # "veri yok" gibi sunmak yanıltıcıdır; nedeni kullanıcıya söylenir.
    bos_mesaj <- "\U0001F50D **Sonuç:** Filtreleme sonrası veri bulunamadı. Lütfen farklı kriterlerle tekrar deneyin."
    if (exists("pk_filter_status_is_degraded", mode = "function", inherits = TRUE) &&
        isTRUE(pk_filter_status_is_degraded(filter_criteria$status))) {
      bozulmalar <- pk_degradations_from_filter_status(filter_criteria$status)
      if (length(bozulmalar) > 0) {
        bos_mesaj <- paste0(bos_mesaj, "\n\n\U000026A0\U0000FE0F ", bozulmalar[[1]]$message)
      }
    }

    return(list(type = "error_message", content = bos_mesaj))
  }
  
  # Faz 2: istatistik/paket, sistem istemi, kompozisyon ve dışa aktarım tek bir
  # kurucudadır. v1 dalı BİREBİR korunur; v2 dalı analiz paketini (§5.7), R'ye
  # ait tabloyu/eki (§5.8-§5.9) ve olgu referanslarını (§5.11) üretir.
  # Paket kurulumu, dışa aktarım yazımı/geri okuması ve grup kırılımı bu
  # isteğin EN PAHALI adımlarıdır; `stop_check` kurucuya iletilir ve pahalı
  # sınırların arasında değerlendirilir.
  analiz_sonucu <- pk_build_analysis_result(
    filtered_data = filtered_data,
    secure_data = secure_data,
    query = selected_query,
    user_prompt = user_prompt,
    filter_criteria = filter_criteria,
    policy = pk_filter_policy,
    session = session,
    engine_is_v2 = pk_engine_v2,
    username = username,
    stop_check = stop_check
  )

  # Durdurma paket/dışa aktarım sırasında geldiyse sonuç GÖZLEMLENMEZ ve
  # LLM akışına devam EDİLMEZ.
  if (identical(analiz_sonucu$type, "pk_stopped") ||
      (is.function(stop_check) && isTRUE(stop_check()))) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (paket/disa aktarim sonrasi)\n")
    pk_observe(
      query_id = selected_query$id, query_name = selected_query$name,
      filter_status = filter_criteria$status, filters = filter_criteria$filters,
      pre_rls_rows = nrow(raw_data), authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data), outcome = "Durduruldu",
      engine = if (isTRUE(pk_engine_v2)) "v2" else "v1"
    )
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }

  # Paket istem bütçesine sığmadıysa kurucu deterministik bir ret döndürür;
  # bu bir LLM yanıtı değildir ve "Basarili" olarak kaydedilmemelidir.
  if (identical(analiz_sonucu$type, "error_message")) {
    pk_observe(
      query_id = selected_query$id, query_name = selected_query$name,
      filter_status = filter_criteria$status, filters = filter_criteria$filters,
      pre_rls_rows = nrow(raw_data), authorized_rows = nrow(secure_data),
      filtered_rows = nrow(filtered_data), outcome = "Reddedildi",
      engine = if (isTRUE(pk_engine_v2)) "v2" else "v1"
    )
    return(analiz_sonucu)
  }

  cat("[PK_ANALIZ] AI baglami hazirlandi. List donduruluyor.\n")

  # Alt bilgi burada hazırlanıp istek kapsamlı yuvaya konur; nihai yanıt metnine
  # akış sonlandırmasında iliştirilir (model onu ASLA yazmaz).
  pk_observe(
    query_id = selected_query$id, query_name = selected_query$name,
    filter_status = filter_criteria$status, filters = filter_criteria$filters,
    pre_rls_rows = nrow(raw_data), authorized_rows = nrow(secure_data),
    filtered_rows = nrow(filtered_data), outcome = "Basarili",
    # Motor etiketi ÇÖZÜLMÜŞ değerdir: `pk_observe` varsayılanı "v1" olduğu
    # için basarili her Faz-2 istegi v1 gibi kaydediliyor ve v2 yayilim
    # olcumleri bozuluyordu.
    engine = if (isTRUE(pk_engine_v2)) "v2" else "v1",
    attachment = analiz_sonucu$pk_attachment,
    answer_block = analiz_sonucu$pk_answer_block,
    facts = analiz_sonucu$pk_facts,
    fallback_text = analiz_sonucu$pk_fallback_text
  )

  return(analiz_sonucu)
}

# ==============================================================================
# 3. AKILLI SORGU SEÇİMİ (AI + HEURISTIC HYBRID ENGINE)
# ==============================================================================

select_smart_query <- function(prompt, library, chat_history,
                               session = NULL, stop_check = NULL) {
  cat("[PK_ANALIZ] Akilli Sorgu Secici (Smart Query Selector) calisiyor...\n")

  all_scores <- pk_init_query_score_table(library)

  # Cagiran ACIKCA bir oturum verdiyse o kullanilir; varsayilan reaktif alan
  # yalnizca geri donustur. Ortak Oturum koprusu sentetik bir oturum kurar ve
  # varsayilan alan BASKA bir kullaniciya aittir.
  session_obj <- session
  if (is.null(session_obj)) {
    try({ session_obj <- shiny::getDefaultReactiveDomain() }, silent = TRUE)
  }

  # Motor siniri (master plan §10): Faz 5 iki gecisli secim hatti YALNIZCA
  # MERGEN_PK_ENGINE=v2 iken calisir. Desen apply_smart_filters() ile AYNIDIR.
  # v1 govdesi (AI dali + sezgisel dal + esikler) asagida DEGISMEDEN kalir;
  # bayrak v1 iken bu dal hic calismaz.
  #
  # Motor kipi istek icin BIR KEZ cozulur ve secilen sorguya iliştirilir.
  # Aksi halde kupur bir istek olusabiliyordu: kuresel `v1` + sorgu metadata
  # `engine="v2"` bu kapiyi kapali birakip secim SONRASI v2 kapilarini aciyor,
  # tersi ise v2 secimini v1 asagi akisiyla karistiriyordu.
  pk_engine_v2_request <- exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
    isTRUE(pk_engine_is_v2())

  if (pk_engine_v2_request &&
      exists("pk_select_query_v2", mode = "function", inherits = TRUE)) {
    secim_v2 <- pk_select_query_v2(
      prompt, library, chat_history,
      session = session_obj, stop_check = stop_check
    )
    if (!is.null(secim_v2)) {
      if (is.list(secim_v2) && !is.null(secim_v2$id)) {
        secim_v2$pk_engine_mode <- "v2"
      }
      return(secim_v2)
    }
  }

  # v2 istendigi halde secici YUKLENMEMISSE sessizce v1'e DUSULMEZ: operatorun
  # acikca etkinlestirdigi kapilar olmadan bir sorgu otomatik calistirilamaz.
  if (pk_engine_v2_request &&
      !exists("pk_select_query_v2", mode = "function", inherits = TRUE)) {
    cat("[PK_ANALIZ] HATA: MERGEN_PK_ENGINE=v2 istendi ama v2 secici yuklenmedi.\n")
    return(list(
      all_scores = all_scores,
      refusal_message = paste0(
        "\U0001F914 **Analiz Seçimi Yapılamadı:** Sorgu seçimi bileşenleri ",
        "yüklenmediği için analiz güvenli biçimde çalıştırılamadı. Bu bir ",
        "kurulum sorunudur; lütfen operatöre bildirin."
      ),
      pk_selection = list(status = "internal_error")
    ))
  }

  ai_selection <- NULL
  ai_attempt <- 1
  max_ai_attempts <- 2
  
  while (is.null(ai_selection) && ai_attempt <= max_ai_attempts) {
    cat(sprintf("[PK_ANALIZ] AI secim denemesi: %d/%d\n", ai_attempt, max_ai_attempts))
    ai_selection <- find_best_query_with_ai(prompt, library, session_obj)
    ai_attempt <- ai_attempt + 1
  }
  
  if (!is.null(ai_selection)) {
    matched_idx <- ai_selection$.matched_idx
    
    if (!is.null(matched_idx) && length(matched_idx) == 1 && matched_idx > 0) {
      all_scores$ai_score[matched_idx] <- ai_selection$relevance_score %||% 0
      all_scores$final_score[matched_idx] <- ai_selection$relevance_score %||% 0
      
      cat(sprintf("[PK_ANALIZ] -> AI tarafindan kesin eslesme bulundu: %s (Skor: %.1f%%)\n", 
                  ai_selection$name, ai_selection$relevance_score %||% 0))
      
      print_score_table(all_scores)
      
      ai_selection$all_scores <- all_scores
      return(ai_selection)
    }
  }
  
  cat("[PK_ANALIZ] AI eslesme bulamadi veya hata aldi. Guclendirilmis Heuristic yonteme geciliyor...\n")
  
  hres <- pk_compute_heuristic_query_scores(prompt, library)
  all_scores <- hres$all_scores
  best_idx <- hres$best_idx
  max_score <- hres$max_score_raw
  max_score_pct <- hres$max_score_pct

  print_score_table(all_scores)

  THRESHOLD_RAW <- 2
  THRESHOLD_PCT <- 30

  passes_threshold <- hres$passes_threshold
  
  if (passes_threshold) {
    result <- library[[best_idx]]
    result$relevance_score <- max_score_pct
    result$selection_method <- "heuristic"
    result$selection_reason <- sprintf("Anahtar kelime eslesmesi (ham skor: %d, yuzde: %.1f%%)", max_score, max_score_pct)
    result$all_scores <- all_scores
    
    cat(sprintf("[PK_ANALIZ] -> Heuristic EN IYI ESLESME: %s (Skor: %.1f%%)\n", 
                result$name, max_score_pct))
    return(result)
  }
  
  cat(sprintf("[PK_ANALIZ] -> Hicbir sorgu yeterli skora ulasamadi. Ham: %d (esik: %d), Yuzde: %.1f%% (esik: %d%%)\n", max_score, THRESHOLD_RAW, max_score_pct, THRESHOLD_PCT))
  result <- list(all_scores = all_scores)
  return(result)
}