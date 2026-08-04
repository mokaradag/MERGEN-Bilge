# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_security_summary.R
# Açıklama: Proje/Kaynak Analizi için RLS, kullanıcı kimliği hazır olma kontrolü
#           ve istatistiksel özet yardımcıları. Shiny observer başlatmaz.
# ==============================================================================

resolve_pk_analysis_username <- function(session, fallback = "Unknown") {
  fallback <- as.character(fallback %||% "Unknown")[1]
  if (is.na(fallback) || !nzchar(fallback)) {
    fallback <- "Unknown"
  }

  user_data <- NULL
  if (!is.null(session) && !is.null(session$userData)) {
    user_data <- session$userData
  }

  if (is.null(user_data)) {
    return(list(
      ready = FALSE,
      username = fallback,
      reason = "session_user_data_missing"
    ))
  }

  sso_active <- isTRUE(user_data$sso_active)
  auth_initialized <- user_data$auth_initialized

  if (isTRUE(sso_active) && !isTRUE(auth_initialized)) {
    return(list(
      ready = FALSE,
      username = fallback,
      reason = "auth_not_ready"
    ))
  }

  username <- user_data$system_username %||% NULL

  if ((is.null(username) || !nzchar(trimws(as.character(username)[1]))) &&
      is.list(user_data$user_identity)) {
    username <- user_data$user_identity$username %||% NULL
  }

  username <- as.character(username %||% "")[1]
  if (is.na(username)) {
    username <- ""
  }
  username <- trimws(username)

  if (!nzchar(username)) {
    return(list(
      ready = !isTRUE(sso_active),
      username = fallback,
      reason = "username_missing"
    ))
  }

  list(
    ready = TRUE,
    username = username,
    reason = NULL
  )
}

get_user_rls_info <- function(username, conn) {
  cat(sprintf("[PK_ANALIZ] get_user_rls_info calistiriliyor. Kullanici: %s\n", username))

  # 1. DC01_user_base tablosundan temel yetkileri çek
  base_query <- "SELECT TOP 1 * FROM DC01_user_base WHERE KullaniciAdi = ?"
  user_base <- tryCatch({
    DBI::dbGetQuery(conn, base_query, params = list(username))
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] HATA (DC01_user_base): %s\n", e$message))
    return(data.frame())
  })

  if (nrow(user_base) == 0) {
    cat("[PK_ANALIZ] Kullanici DC01 tablosunda bulunamadi.\n")
    return(list(authorized = FALSE, reason = "Kullanıcı DC01 tablosunda bulunamadı."))
  }

  info <- as.list(user_base[1, ])
  info$authorized <- TRUE
  cat(sprintf("[PK_ANALIZ] Yetki Tipi: %s, MasrafYeri: %s\n", info$Yetki, info$MasrafYeriKodu))

  # Masraf Yeri (Department) Parse Et
  if (!is.na(info$MasrafYeriKodu) && info$MasrafYeriKodu != "ADMIN") {
    info$allowed_depts <- trimws(unlist(strsplit(as.character(info$MasrafYeriKodu), ",")))
  } else {
    info$allowed_depts <- NULL # ADMIN veya hepsi
  }

  # 2. Yetki Tipine Göre Ek Kısıtlamaları (PY, KY-P, DIR-P) Çek
  info$allowed_projects <- NULL
  info$allowed_eps <- NULL

  # D6b: "izin sorgusu hata verdi" (unavailable) ile "kullanici izin tablosunda
  # yok" (empty) durumlari AYRI kaydedilir. Eskiden ikisi de allowed_* = NULL
  # birakiyor, apply_rls_to_data ise NULL kapsami "filtre yok" sayiyordu; yani
  # her iki durumda da kullanici TUM satirlari goruyordu.
  info$scope_state_projects <- "not_applicable"
  info$scope_state_eps <- "not_applicable"

  if (identical(info$Yetki, "PY")) {
    cat("[PK_ANALIZ] PY yetkisi kontrol ediliyor...\n")
    py_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_py), error = function(e) NULL)
    if (is.null(py_res)) {
      info$scope_state_projects <- "unavailable"
      cat("[PK_ANALIZ] UYARI: PY izin sorgusu calistirilamadi; kapsam COZULEMEDI.\n")
    } else {
      user_rows <- py_res[py_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_projs <- paste(user_rows$ProjeKodu, collapse = ",")
        info$allowed_projects <- unique(trimws(unlist(strsplit(all_projs, ","))))
        info$scope_state_projects <- "available"
        cat(sprintf("[PK_ANALIZ] PY Projeleri: %s\n", paste(info$allowed_projects, collapse=",")))
      } else {
        info$scope_state_projects <- "empty"
        cat("[PK_ANALIZ] PY izin tablosunda kullaniciya ait satir yok; kapsam BOS.\n")
      }
    }
  }

  if (info$Yetki %in% c("KY-P", "DIR-P")) {
    cat("[PK_ANALIZ] Program (EPS) yetkisi kontrol ediliyor...\n")
    eps_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_eps), error = function(e) NULL)
    if (is.null(eps_res)) {
      info$scope_state_eps <- "unavailable"
      cat("[PK_ANALIZ] UYARI: EPS izin sorgusu calistirilamadi; kapsam COZULEMEDI.\n")
    } else {
      user_rows <- eps_res[eps_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_eps <- paste(user_rows$EPSKodu, collapse = ",")
        info$allowed_eps <- unique(trimws(unlist(strsplit(all_eps, ","))))
        info$scope_state_eps <- "available"
        cat(sprintf("[PK_ANALIZ] EPS Kodlari: %s\n", paste(info$allowed_eps, collapse=",")))
      } else {
        info$scope_state_eps <- "empty"
        cat("[PK_ANALIZ] EPS izin tablosunda kullaniciya ait satir yok; kapsam BOS.\n")
      }
    }
  }

  return(info)
}

# D6 / D6b: RLS artik KAPALI BASARISIZ calisir ve karar saf `pk_rls_plan()`
# tarafindan uretilir. Bu davranis KOSULSUZDUR (master plan §10): guvenlik
# duzeltmesi MERGEN_PK_ENGINE bayraginin arkasina saklanamaz.
apply_rls_to_data <- function(data, user_info, rls_cols) {
  if (nrow(data) == 0) return(data)

  cat(sprintf("[PK_ANALIZ] RLS Uygulaniyor. Ham satir sayisi: %d\n", nrow(data)))

  if (!exists("pk_rls_plan", mode = "function", inherits = TRUE)) {
    # Karar katmani yoksa filtreleme YAPILMAZ, veri de DONDURULMEZ.
    stop("pk_rls_plan bulunamadi; RLS guvenli bicimde uygulanamaz.", call. = FALSE)
  }

  plan <- pk_rls_plan(user_info, rls_cols, names(data))

  if (isTRUE(plan$abort)) {
    pk_rls_stop(plan)
  }

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
    # Kapsami BOS olan kullanici SIFIR satir gorur; asla tum satirlar degil.
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

  return(filtered_data)
}
