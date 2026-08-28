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

  # `NA` DA "YOK" SAYILIR.
  #
  # `nzchar(NA_character_)` `TRUE` döner; `system_username` `NA_character_`
  # olduğunda koşul `FALSE` olup `user_identity$username` yedeği ATLANIYORDU.
  # Aşağıdaki dönüşüm değeri `""` yapıyor ve fonksiyon SSO dışı oturumda
  # `ready = TRUE` ile `fallback` adını döndürüyordu; o ad dışa aktarım,
  # telemetri ve RLS aramalarının DENETİM KİMLİĞİ hâline geliyordu.
  .gecerli_ad <- function(x) {
    d <- suppressWarnings(as.character(x)[1])
    length(d) == 1L && !is.na(d) && nzchar(trimws(d))
  }
  username <- user_data$system_username %||% NULL
  if (!.gecerli_ad(username) && is.list(user_data$user_identity)) {
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
#' Tipli RLS durdurma sonucundan kullanıcıya görünen mesaj
#'
#' Çağıranlar (`pk_analiz_process_request()`, `pk_deep_analysis_process()`)
#' `authorized` dalına GİRMEDEN ÖNCE bunu kullanır: bir Durdur/son tarih
#' "kullanıcı kaydınız bulunamadı" diye raporlanmamalıdır.
pk_rls_halt_message <- function(rls_info) {
  mesaj_var <- exists("pk_async_halt_message", mode = "function", inherits = TRUE)

  # SON TARİH KARARI AŞAMA KAPISI YARDIMCISINA BAĞLI DEĞİLDİR. `pk_active_stage_halt`
  # bu kararla ilgisizdir; yüklenmediğinde son tarih dalı hiç çalışmıyor ve
  # zaman aşımı "isteği siz durdurdunuz" diye raporlanıyordu.
  durum <- tryCatch(getOption("mergen.pk.async.deadline_at", NULL), error = function(e) NULL)
  son_tarih_doldu <- !is.null(durum) &&
    exists("pk_deadline_expired", mode = "function", inherits = TRUE) &&
    isTRUE(tryCatch(pk_deadline_expired(durum), error = function(e) FALSE))
  if (son_tarih_doldu && mesaj_var) return(pk_async_halt_message("deadline"))

  # GEÇEN SÜRE BÜTÇESİ de zaman aşımıdır. `.pk_rls_bounded_query()`
  # `.db_with_elapsed_budget()` üzerinden durabilir ve bu, sınırlı senkron
  # yolda `mergen.pk.async.deadline_at` HİÇ AYARLANMADAN olabilir. Kullanıcı
  # gerçekten iptal jetonunu tetiklemediyse "iptal ettiniz" metni yanlıştır.
  jeton <- tryCatch(getOption("mergen.pk.async.cancel_token", NULL), error = function(e) NULL)
  kullanici_iptali <- !is.null(jeton) &&
    exists("pk_cancel_token_is_signalled", mode = "function", inherits = TRUE) &&
    isTRUE(tryCatch(pk_cancel_token_is_signalled(jeton), error = function(e) FALSE))
  if (!kullanici_iptali && mesaj_var) return(pk_async_halt_message("deadline"))

  if (mesaj_var) return(pk_async_halt_message("cancelled"))
  as.character(rls_info$reason %||%
    "\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz tamamlanamadı.")[1]
}

.pk_rls_halt_error <- function(e) {
  metin <- tryCatch(conditionMessage(e), error = function(x) "")
  if (is.null(metin) || is.na(metin) || !nzchar(metin)) return(FALSE)
  isaretler <- c("durduruldu", "butcesi tukendi", "butcesi tukendi;",
                 "reached elapsed time limit", "time limit")
  any(vapply(isaretler, function(p) grepl(p, metin, fixed = TRUE), logical(1)))
}

# YETKİ KAPSAMI KODLARINI GÜVENLİ AYRIŞTIR (kapalı başarısız).
#
# `paste(x, collapse = ",")` bir `NA` girdisini SIRADAN `"NA"` metnine çevirir;
# `strsplit()` sonrasında bu değer GERÇEK bir kapsam kodundan ayırt edilemez.
# İzin tablosunda eksik bir kod bulunduğunda hesaplanan kapsam tablodan
# FARKLILAŞIR ve `"NA"` adlı bir kod varmış gibi davranılır. `NA`/boş girdiler
# birleştirmeden ÖNCE atılır.
.pk_rls_scope_codes <- function(values) {
  ham <- as.character(values %||% character(0))
  ham <- ham[!is.na(ham)]
  if (!length(ham)) return(character(0))

  parcalar <- trimws(unlist(strsplit(ham, ",", fixed = TRUE), use.names = FALSE))
  parcalar <- parcalar[!is.na(parcalar) & nzchar(parcalar)]
  unique(parcalar)
}

get_user_rls_info <- function(username, conn) {
  cat("[PK_ANALIZ] get_user_rls_info calistiriliyor.\n")

  # `TOP 1` + `ORDER BY` YOK => KEYFİ SATIR. `DC01_user_base` dış bir kaynaktır;
  # dizin/veri eşitlemesi sırasında aynı `KullaniciAdi` için FARKLI `Yetki` /
  # `MasrafYeriKodu` taşıyan mükerrer satırlar bulunabilir. SQL Server hangisini
  # döndüreceğini garanti etmez; daha geniş yetkili bir mükerrer satır RLS'i
  # NONDETERMİNİSTİK biçimde genişletebilirdi. İKİ satır istenir: birden fazla
  # kayıt varsa yetki BELİRSİZDİR ve kapalı başarısız olunur.
  base_query <- "SELECT TOP 2 * FROM DC01_user_base WHERE KullaniciAdi = ?"
  halt_reason <- NULL
  db_error <- NULL
  user_base <- tryCatch({
    .pk_rls_bounded_query(conn, base_query, params = list(username))
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] HATA (DC01_user_base): %s\n",
                .pk_rls_safe_detail(conditionMessage(e))))
    # SON TARİH/İPTAL bir YETKİ SONUCU DEĞİLDİR; tipli olarak korunur.
    if (isTRUE(.pk_rls_halt_error(e))) {
      halt_reason <<- conditionMessage(e)
    } else {
      db_error <<- conditionMessage(e)
    }
    data.frame()
  })

  if (!is.null(halt_reason)) {
    return(list(authorized = FALSE, halted = TRUE, reason = paste0(
      "Analiz süre sınırı veya kullanıcı iptali nedeniyle yetki bilgisi ",
      "okunamadı. Lütfen tekrar deneyin."
    )))
  }

  # ALTYAPI HATASI "KULLANICI BULUNAMADI" DEĞİLDİR.
  #
  # Eskiden SON TARİH/İPTAL dışındaki HER hata (bağlantı kopması, ODBC/sürücü
  # hatası, SQL hatası) boş bir çerçeveye indirgeniyordu; bir sonraki dal da
  # bunu "Kullanıcı DC01 tablosunda bulunamadı" diye raporluyordu. Yani geçici
  # bir DC01 kesintisi, HER kullanıcıya YANLIŞ bir yetki teşhisiyle erişimi
  # kapatıyor ve gerçek altyapı arızasını gizliyordu.
  #
  # Karar her iki hâlde de KAPALI BAŞARISIZ kalır (yetki verilmez); değişen
  # yalnızca TEŞHİStir. Ham sürücü/SQL metni kullanıcıya SIZDIRILMAZ; ayrıntı
  # sunucu log'undadır.
  if (!is.null(db_error)) {
    return(list(authorized = FALSE, db_error = TRUE, reason = paste0(
      "Yetki bilgisi okunamadı (veritabanı erişim hatası). Bu bir yetki ",
      "kararı değildir; lütfen daha sonra tekrar deneyin, sorun sürerse ",
      "sistem yöneticisine bildirin."
    )))
  }

  if (nrow(user_base) == 0) {
    cat("[PK_ANALIZ] Kullanici DC01 tablosunda bulunamadi.\n")
    return(list(authorized = FALSE, reason = "Kullanıcı DC01 tablosunda bulunamadı."))
  }

  if (nrow(user_base) > 1L) {
    cat("[PK_ANALIZ] DC01_user_base icinde MUKERRER yetki kaydi; karar BELIRSIZ.\n")
    return(list(authorized = FALSE, ambiguous = TRUE, reason = paste0(
      "Yetki kaydınız benzersiz değil (birden fazla kayıt bulundu). Yanlış bir ",
      "kapsamla analiz çalıştırmamak için işlem durduruldu; sistem yöneticisine ",
      "bildirin."
    )))
  }

  info <- as.list(user_base[1, ])
  info$authorized <- TRUE

  # ROL DEĞERİ KAPSAM SEÇİMİNDEN ÖNCE BİR KEZ NORMALLEŞTİRİLİR.
  #
  # `pk_rls_plan()` rolü `trimws()` ile kırpar; bu dosya ise aşağıda HAM
  # `info$Yetki` üzerinde `identical(..., "PY")` / `%in% c("KY-P","DIR-P")`
  # karşılaştırması yapıyordu. `Yetki` sütunu SQL Server'da sabit genişlikli
  # (`char(n)`) ise DBI `"PY "` döndürür: buradaki dal ÇALIŞMAZ, proje/EPS
  # kapsamı `not_applicable` kalır, ama plan katmanı kırpılmış `"PY"` rolünü
  # görüp yüklemi ATLAR. Sonuç, kullanıcının proje kapsamı DIŞINDAKİ satırların
  # dönmesidir. Normalleştirme `pk_rls_code_norm()` sözleşmesiyle aynıdır:
  # yalnızca kırpma; Türkçe I/İ anlamını değiştirebileceği için harf durumu
  # DÖNÜŞTÜRÜLMEZ.
  yetki_ham <- info$Yetki
  info$Yetki <- if (is.null(yetki_ham) || !length(yetki_ham)) {
    NA_character_
  } else {
    ham <- as.character(yetki_ham)[1]
    if (is.na(ham)) NA_character_ else trimws(ham)
  }
  # Rol/masraf yeri değerleri KULLANICIYA ÖZEL yetkilendirme verisidir; sunucu
  # log'una yazılmaz. Yalnızca kararın ALINDIĞI kaydedilir.
  cat("[PK_ANALIZ] DC01 yetki kaydi cozuldu.\n")

  # EKSİK DEPARTMAN KAPSAMI, "KISIT YOK" DEMEK DEĞİLDİR.
  #
  # `MasrafYeriKodu` AÇIK `"ADMIN"` işaretiyse departman kısıtı BİLEREK yoktur.
  # Değer `NA`/boş ise kapsam ÇÖZÜLEMEMİŞTİR; eskiden ikisi de `NULL` olup
  # `pk_rls_plan()` boyutu `not_applicable` sayıyordu ve `USER` gibi proje/EPS
  # yüklemi de olmayan bir rol TÜM satırları görebiliyordu.
  masraf_ham <- info$MasrafYeriKodu
  masraf <- if (is.null(masraf_ham) || !length(masraf_ham)) NA_character_ else as.character(masraf_ham)[1]
  if (!is.na(masraf) && identical(trimws(masraf), "ADMIN")) {
    info$allowed_depts <- NULL
    info$scope_state_depts <- "not_applicable"
  } else if (!is.na(masraf) && nzchar(trimws(masraf))) {
    info$allowed_depts <- .pk_rls_scope_codes(masraf)
    info$scope_state_depts <- if (length(info$allowed_depts)) "available" else "empty"
  } else {
    info$allowed_depts <- NULL
    info$scope_state_depts <- "unavailable"
  }

  info$allowed_projects <- NULL
  info$allowed_eps <- NULL
  info$scope_state_projects <- "not_applicable"
  info$scope_state_eps <- "not_applicable"

  if (identical(info$Yetki, "PY")) {
    cat("[PK_ANALIZ] PY yetkisi kontrol ediliyor...\n")
    # DURDURMA/SON TARİH burada da TİPLİ kalır: `NULL`'a indirgemek, iptal
    # edilmiş bir isteği "kapsam çözülemedi" diye RAPORLAYIP analize devam
    # etmek olurdu (PR #703 incelemesi).
    # DURDURMA DIŞI HATA da KAYBOLMAZ: bağlantı/ODBC/SQL hatası `NULL` dönüp
    # kapsamı `unavailable` yapıyor ve `pk_rls_plan()` isteği durduruyordu, ama
    # sunucu log'unda HİÇBİR neden yoktu (DC01 dalı bunu zaten kaydediyor).
    py_res <- tryCatch(.pk_rls_permission_rows(conn, sql_permission_py, username), error = function(e) {
      if (isTRUE(.pk_rls_halt_error(e))) {
        halt_reason <<- conditionMessage(e)
      } else {
        cat(sprintf("[PK_ANALIZ] UYARI: PY izin sorgusu hatasi: %s\n",
                    .pk_rls_safe_detail(conditionMessage(e))))
      }
      NULL
    })
    if (!is.null(halt_reason)) {
      return(list(authorized = FALSE, halted = TRUE, reason = paste0(
        "Analiz süre sınırı veya kullanıcı iptali nedeniyle yetki bilgisi ",
        "okunamadı. Lütfen tekrar deneyin."
      )))
    }
    if (is.null(py_res)) {
      info$scope_state_projects <- "unavailable"
      cat("[PK_ANALIZ] UYARI: PY izin sorgusu calistirilamadi; kapsam COZULEMEDI.\n")
    } else {
      user_rows <- .pk_rls_rows_for_user(py_res, username)
      if (nrow(user_rows) > 0) {
        info$allowed_projects <- .pk_rls_scope_codes(user_rows$ProjeKodu)
        # BEYAN EDİLEN DURUM ÇÖZÜLEN KOD SAYISIYLA TUTARLI OLMALIDIR: tüm
        # değerler NA/boşsa `.pk_rls_scope_codes()` `character(0)` döner ve
        # "available" beyanı `pk_rls_plan()` tarafına BOŞ değer kümeli bir
        # yüklem taşırdı; `apply_rls_to_data()` TÜM satırları eler ve kullanıcı
        # tipli boş-kapsam durumu yerine sessiz boş sonuç görürdü. Departman
        # dalı (yukarıda) zaten bu ayrımı yapar.
        info$scope_state_projects <- if (length(info$allowed_projects)) "available" else "empty"
        # Kapsam KODLARI kullanıcının iç erişim sınırını yeniden kurar; log'a
        # yalnızca SAYI yazılır.
        cat(sprintf("[PK_ANALIZ] PY kapsami cozuldu (%d kod).\n",
                    length(info$allowed_projects)))
      } else {
        info$scope_state_projects <- "empty"
        cat("[PK_ANALIZ] PY izin tablosunda kullaniciya ait satir yok; kapsam BOS.\n")
      }
    }
  }

  if (info$Yetki %in% c("KY-P", "DIR-P")) {
    cat("[PK_ANALIZ] Program (EPS) yetkisi kontrol ediliyor...\n")
    # Aynı gerekçeyle EPS dalında da kök neden kaydedilir.
    eps_res <- tryCatch(.pk_rls_permission_rows(conn, sql_permission_eps, username), error = function(e) {
      if (isTRUE(.pk_rls_halt_error(e))) {
        halt_reason <<- conditionMessage(e)
      } else {
        cat(sprintf("[PK_ANALIZ] UYARI: EPS izin sorgusu hatasi: %s\n",
                    .pk_rls_safe_detail(conditionMessage(e))))
      }
      NULL
    })
    if (!is.null(halt_reason)) {
      return(list(authorized = FALSE, halted = TRUE, reason = paste0(
        "Analiz süre sınırı veya kullanıcı iptali nedeniyle yetki bilgisi ",
        "okunamadı. Lütfen tekrar deneyin."
      )))
    }
    if (is.null(eps_res)) {
      info$scope_state_eps <- "unavailable"
      cat("[PK_ANALIZ] UYARI: EPS izin sorgusu calistirilamadi; kapsam COZULEMEDI.\n")
    } else {
      user_rows <- .pk_rls_rows_for_user(eps_res, username)
      if (nrow(user_rows) > 0) {
        info$allowed_eps <- .pk_rls_scope_codes(user_rows$EPSKodu)
        # ProjeKodu dalıyla AYNI gerekçe: boş kod kümesi "available" sayılmaz.
        info$scope_state_eps <- if (length(info$allowed_eps)) "available" else "empty"
        cat(sprintf("[PK_ANALIZ] EPS kapsami cozuldu (%d kod).\n",
                    length(info$allowed_eps)))
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
    # `drop = FALSE` ZORUNLUDUR.
    #
    # Sonuç kümesi TEK sütunlu olduğunda (yalnızca RLS sütununu döndüren bir
    # sorgu) `[i, ]` çerçeveyi VEKTÖRE indirir: `nrow()` NULL olur, `cat()`
    # hata verir, ikinci predikat `[[` üzerinde çöker ve fonksiyon
    # `pk_build_analysis_result()` çağrısına çerçeve yerine vektör döndürür.
    filtered_data <- filtered_data[
      filtered_data[[predikat$column]] %in% predikat$values, , drop = FALSE
    ]
    cat(sprintf(
      "[PK_ANALIZ] RLS predikati '%s' sonrasi: %d satir\n",
      predikat$column, nrow(filtered_data)
    ))
  }

  filtered_data
}