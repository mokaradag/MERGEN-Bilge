# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_security_summary.R
# Açıklama: Proje/Kaynak Analizi için RLS, kullanıcı kimliği hazır olma kontrolü
#           ve istatistiksel özet yardımcıları. Shiny observer başlatmaz.
# ==============================================================================

resolve_pk_analysis_username <- function(session, fallback = "Unknown") {
  fallback <- as.character(fallback %||% "Unknown")[1]
  if (is.na(fallback) || !nzchar(fallback)) fallback <- "Unknown"

  user_data <- NULL
  if (!is.null(session) && !is.null(session$userData)) user_data <- session$userData

  if (is.null(user_data)) {
    return(list(ready = FALSE, username = fallback, reason = "session_user_data_missing"))
  }

  sso_active <- isTRUE(user_data$sso_active)
  auth_initialized <- user_data$auth_initialized
  if (isTRUE(sso_active) && !isTRUE(auth_initialized)) {
    return(list(ready = FALSE, username = fallback, reason = "auth_not_ready"))
  }

  username <- user_data$system_username %||% NULL
  if ((is.null(username) || !nzchar(trimws(as.character(username)[1]))) &&
      is.list(user_data$user_identity)) {
    username <- user_data$user_identity$username %||% NULL
  }

  username <- as.character(username %||% "")[1]
  if (is.na(username)) username <- ""
  username <- trimws(username)

  if (!nzchar(username)) {
    return(list(
      ready = !isTRUE(sso_active),
      username = fallback,
      reason = "username_missing"
    ))
  }

  list(ready = TRUE, username = username, reason = NULL)
}

# Faz 6 (§5.10): YETKİ okumaları da istek ömrüne dahildir. Bunlar analiz
# SQL'inden ÖNCE çalışır; sınırlanmazsa askıda kalan bir DB/ağ, dosya tabanlı
# iptal jetonu işaretlense bile işçiyi ve bağlantıyı süresiz tutar — sert
# analiz son tarihi HİÇ gözlenemez. Bütçe yoksa (`Inf`) davranış değişmez.
#
# İPTAL DE GÖZLENİR: Durdur bir DOSYA jetonu işaretler ve elapsed zamanlayıcıyı
# tetiklemez. Analiz SQL'iyle AYNI aşama kapısı burada da yoklanır; böylece
# durdurulmuş bir istek yetki okumalarına HİÇ başlamaz. (Bloklayan ODBC çağrısı
# tek iş parçacığında sinyalle kesilemez; sınır KALAN BÜTÇEDİR ve kapı çağrılar
# ARASINDA yoklanır — bu, analiz yolundaki sözleşmenin aynısıdır.)
.pk_rls_bounded_query <- function(conn, statement, params = NULL) {
  if (exists("pk_active_stage_halt", mode = "function", inherits = TRUE) &&
      isTRUE(tryCatch(pk_active_stage_halt(), error = function(e) FALSE))) {
    stop("PK istegi durduruldu; yetki okumasi baslatilmadi.", call. = FALSE)
  }

  cagri <- function() {
    if (is.null(params)) DBI::dbGetQuery(conn, statement)
    else DBI::dbGetQuery(conn, statement, params = params)
  }
  if (!exists(".db_with_elapsed_budget", mode = "function", inherits = TRUE) ||
      !exists(".db_pk_residual_budget_sec", mode = "function", inherits = TRUE)) {
    return(cagri())
  }
  .db_with_elapsed_budget(.db_pk_residual_budget_sec(), cagri)
}

# Bir yetki okuması BÜTÇE/İPTAL nedeniyle mi düştü?
#
# `get_user_rls_info()` her hatayı boş çerçeveye indirirse, bir son tarih/DB
# zaman aşımı "Kullanıcı DC01 tablosunda bulunamadı" YETKİ HATASI olarak
# raporlanırdı — kullanıcıya tamamen yanlış bir neden.
.pk_rls_halt_error <- function(e) {
  metin <- tryCatch(conditionMessage(e), error = function(x) "")
  if (is.null(metin) || is.na(metin) || !nzchar(metin)) return(FALSE)
  isaretler <- c("durduruldu", "butcesi tukendi", "butcesi tukendi;",
                 "reached elapsed time limit", "time limit")
  any(vapply(isaretler, function(p) grepl(p, metin, fixed = TRUE), logical(1)))
}

get_user_rls_info <- function(username, conn) {
  cat(sprintf("[PK_ANALIZ] get_user_rls_info calistiriliyor. Kullanici: %s\n", username))

  base_query <- "SELECT TOP 1 * FROM DC01_user_base WHERE KullaniciAdi = ?"
  halt_reason <- NULL
  user_base <- tryCatch({
    .pk_rls_bounded_query(conn, base_query, params = list(username))
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] HATA (DC01_user_base): %s\n", e$message))
    # SON TARİH/İPTAL bir YETKİ SONUCU DEĞİLDİR; tipli olarak korunur.
    if (isTRUE(.pk_rls_halt_error(e))) halt_reason <<- conditionMessage(e)
    data.frame()
  })

  if (!is.null(halt_reason)) {
    return(list(authorized = FALSE, halted = TRUE, reason = paste0(
      "Analiz süre sınırı veya kullanıcı iptali nedeniyle yetki bilgisi ",
      "okunamadı. Lütfen tekrar deneyin."
    )))
  }

  if (nrow(user_base) == 0) {
    cat("[PK_ANALIZ] Kullanici DC01 tablosunda bulunamadi.\n")
    return(list(authorized = FALSE, reason = "Kullanıcı DC01 tablosunda bulunamadı."))
  }

  info <- as.list(user_base[1, ])
  info$authorized <- TRUE
  cat(sprintf("[PK_ANALIZ] Yetki Tipi: %s, MasrafYeri: %s\n", info$Yetki, info$MasrafYeriKodu))

  if (!is.na(info$MasrafYeriKodu) && info$MasrafYeriKodu != "ADMIN") {
    info$allowed_depts <- trimws(unlist(strsplit(as.character(info$MasrafYeriKodu), ",")))
  } else {
    info$allowed_depts <- NULL
  }

  info$allowed_projects <- NULL
  info$allowed_eps <- NULL
  info$scope_state_projects <- "not_applicable"
  info$scope_state_eps <- "not_applicable"

  if (identical(info$Yetki, "PY")) {
    cat("[PK_ANALIZ] PY yetkisi kontrol ediliyor...\n")
    py_res <- tryCatch(.pk_rls_bounded_query(conn, sql_permission_py), error = function(e) NULL)
    if (is.null(py_res)) {
      info$scope_state_projects <- "unavailable"
      cat("[PK_ANALIZ] UYARI: PY izin sorgusu calistirilamadi; kapsam COZULEMEDI.\n")
    } else {
      user_rows <- py_res[py_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_projs <- paste(user_rows$ProjeKodu, collapse = ",")
        info$allowed_projects <- unique(trimws(unlist(strsplit(all_projs, ","))))
        info$scope_state_projects <- "available"
        cat(sprintf("[PK_ANALIZ] PY Projeleri: %s\n", paste(info$allowed_projects, collapse = ",")))
      } else {
        info$scope_state_projects <- "empty"
        cat("[PK_ANALIZ] PY izin tablosunda kullaniciya ait satir yok; kapsam BOS.\n")
      }
    }
  }

  if (info$Yetki %in% c("KY-P", "DIR-P")) {
    cat("[PK_ANALIZ] Program (EPS) yetkisi kontrol ediliyor...\n")
    eps_res <- tryCatch(.pk_rls_bounded_query(conn, sql_permission_eps), error = function(e) NULL)
    if (is.null(eps_res)) {
      info$scope_state_eps <- "unavailable"
      cat("[PK_ANALIZ] UYARI: EPS izin sorgusu calistirilamadi; kapsam COZULEMEDI.\n")
    } else {
      user_rows <- eps_res[eps_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_eps <- paste(user_rows$EPSKodu, collapse = ",")
        info$allowed_eps <- unique(trimws(unlist(strsplit(all_eps, ","))))
        info$scope_state_eps <- "available"
        cat(sprintf("[PK_ANALIZ] EPS Kodlari: %s\n", paste(info$allowed_eps, collapse = ",")))
      } else {
        info$scope_state_eps <- "empty"
        cat("[PK_ANALIZ] EPS izin tablosunda kullaniciya ait satir yok; kapsam BOS.\n")
      }
    }
  }

  info
}

# D6 / D6b: RLS kapalı başarısız çalışır ve karar saf `pk_rls_plan()` tarafından üretilir.
apply_rls_to_data <- function(data, user_info, rls_cols) {
  if (nrow(data) == 0) return(data)

  cat(sprintf("[PK_ANALIZ] RLS Uygulaniyor. Ham satir sayisi: %d\n", nrow(data)))

  if (!exists("pk_rls_plan", mode = "function", inherits = TRUE)) {
    stop("pk_rls_plan bulunamadi; RLS guvenli bicimde uygulanamaz.", call. = FALSE)
  }

  plan <- pk_rls_plan(user_info, rls_cols, names(data))
  if (isTRUE(plan$abort)) pk_rls_stop(plan)

  if (isTRUE(plan$admin)) {
    cat("[PK_ANALIZ] Rol ADMIN -> Filtre uygulanmadi.\n")
    return(data)
  }

  if (length(plan$unenforced) > 0) {
    cat(sprintf(
      "[PK_ANALIZ] UYARI: Cozulmus yetki kapsami sorgu sutunu beyan edilmedigi icin uygulanamadi: %s\n",
      paste(plan$unenforced, collapse = ", ")
    ))
  }

  if (isTRUE(plan$zero_rows)) {
    cat("[PK_ANALIZ] Yetki kapsami bos -> sifir satir donduruluyor.\n")
    return(data[0, , drop = FALSE])
  }

  filtered_data <- data
  for (predikat in plan$predicates) {
    filtered_data <- filtered_data[filtered_data[[predikat$column]] %in% predikat$values, ]
    cat(sprintf(
      "[PK_ANALIZ] RLS predikati '%s' sonrasi: %d satir\n",
      predikat$column, nrow(filtered_data)
    ))
  }

  filtered_data
}