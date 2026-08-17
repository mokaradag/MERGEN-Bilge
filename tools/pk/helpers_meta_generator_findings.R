# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_findings.R
# Açıklama: Faz 3b metadata üreticisi -- BULGU ÜRETİMİ ve GİZLİLİK MASKELEME.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# Sağlık raporunun KARAR katmanıdır: bir sorgunun üretilen katmana alınıp
# alınmayacağı buradaki `blocking` bulgulardan çıkar. Rapor biçimlendirme ve
# artefakt yazma AYRI dosyadadır (helpers_meta_generator_health.R), böylece
# karar mantığı biçimden bağımsız test edilir.
#
# GİZLİ DEĞER SIZDIRMAZ: DSN, kimlik bilgisi, jeton, bağlantı dizesi ve
# ÜRETİM SATIR DEĞERLERİ rapora GİRMEZ. Şema/sütun ADLARI operatörün kendi
# VM'inde beklenen ve gerekli bilgidir; satır İÇERİĞİ değildir.
# ==============================================================================

# Bulgu şiddetleri:
#   blocking  -> üretilen şema İLE başlangıç doğrulamasını DÜŞÜRÜRDÜ; sorgu
#                bu koşuda üretilen katmandan GERİ ÇEKİLİR (withheld).
#   attention -> operatör eylemi gerekir ama başlangıcı düşürmez.
#   info      -> bilgilendirme.
PKG_HEALTH_SEVERITIES <- c("blocking", "attention", "info")

# Bağlantı dizesi anahtarları. Değer, `;` görünene KADAR ya da süslü/tırnaklı
# bir blok olarak maskelenir: `DSN={Prod SQL};UID={DOMAIN User};` biçimi
# boşluktan kesildiğinde `SQL}` / `User}` artıkları raporda KALIRDI.
.PKGH_SECRET_KEYS <- paste(
  c("dsn", "uid", "pwd", "password", "server", "database", "driver",
    "address", "addr", "app", "user", "user id", "uid", "trusted_connection",
    "authentication", "encrypt", "token", "apikey", "api_key", "secret"),
  collapse = "|"
)

.pkgh_redact <- function(x) {
  metin <- as.character(x %||% "")[1]
  if (is.na(metin)) return("")
  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    metin <- tryCatch(redact_sensitive_text(metin), error = function(e) metin)
  }
  # Yerel yedek: bağlantı dizesi değerinin TAMAMINI maskele (süslü/tırnaklı
  # bloklar dahil), sonraki anahtar/değer çiftlerine dokunmadan.
  metin <- gsub(
    sprintf("(?i)\\b(%s)\\s*=\\s*(\\{[^}]*\\}|\"[^\"]*\"|'[^']*'|[^;]*)", .PKGH_SECRET_KEYS),
    "\\1=<gizli>", metin, perl = TRUE
  )
  metin <- gsub("(?i)(https?://)[^\\s;'\"]+", "\\1<gizli>", metin, perl = TRUE)
  metin
}

#' Tek bir bulgu kaydı
pkgh_finding <- function(code, severity, detail, columns = character(0),
                         security = FALSE) {
  if (!(severity %in% PKG_HEALTH_SEVERITIES)) severity <- "attention"
  list(
    code = as.character(code)[1],
    severity = severity,
    security_relevant = isTRUE(security),
    detail = .pkgh_redact(detail),
    columns = as.character(columns %||% character(0))
  )
}

# Sürücü hatası metni SATIR DEĞERİ TAŞIYABİLİR.
#
# Salt-okunur bir SQL Server sorgusu bile "Conversion failed when converting
# the nvarchar value 'Ahmet Yılmaz' to data type int" gibi bir hata verebilir;
# bu metin ÜRETİM SATIR DEĞERİ içerir ve `.pkgh_redact()` yalnızca gizli anahtar
# kalıplarını temizler. Bu yüzden ham sürücü metni ASLA rapora yazılmaz;
# yerine KARARLI bir sınıflandırma kodu ve (varsa) SQLSTATE/hata numarası
# yazılır. Bunların ikisi de operatörün teşhis için ihtiyaç duyduğu, satır
# değeri TAŞIMAYAN bilgilerdir.
.PKGH_ERROR_CLASSES <- list(
  timeout             = "timeout|zaman asimi|query timeout|hywat|hyt00|hyt01",
  connection_lost     = "08s01|08001|08003|communication link|connection is closed|connection was closed|not connected|baglanti",
  permission_denied   = "permission|denied|unauthorized|login failed|28000|42000.*permission",
  object_missing      = "invalid object name|invalid column name|could not find|does not exist",
  conversion_failed   = "conversion failed|arithmetic overflow|cannot convert|out-of-range",
  syntax_error        = "incorrect syntax|syntax error|42s02|42s22",
  driver_unavailable  = "driver|im002|im003|data source name"
)

#' Sürücü/DB hatasını GÜVENLİ bir özet metnine indir
#'
#' @return Rapora yazılabilir, satır değeri TAŞIMAYAN metin.
pkgh_db_error_summary <- function(message) {
  ham <- as.character(message %||% "")[1]
  if (is.na(ham) || !nzchar(trimws(ham))) {
    return("DB hatasi (sinif=unknown). Ham surucu metni rapora GIRMEZ.")
  }

  kucuk <- tolower(ham)
  sinif <- "unknown"
  for (ad in names(.PKGH_ERROR_CLASSES)) {
    if (grepl(.PKGH_ERROR_CLASSES[[ad]], kucuk, perl = TRUE, useBytes = TRUE)) {
      sinif <- ad
      break
    }
  }

  # SQLSTATE ve sürücü hata numarası kararlı tanımlayıcılardır; satır değeri
  # içermezler ve operatörün araması için en değerli iki alandır.
  durum <- regmatches(ham, regexpr("[0-9A-Za-z]{5}(?=\\])", ham, perl = TRUE))
  numara <- regmatches(ham, regexpr("(?i)(?<=error )[0-9]{3,6}", ham, perl = TRUE))

  parcalar <- c(
    sprintf("sinif=%s", sinif),
    if (length(durum) == 1L && nzchar(durum)) sprintf("sqlstate=%s", durum),
    if (length(numara) == 1L && nzchar(numara)) sprintf("hata_no=%s", numara)
  )

  sprintf(paste0(
    "DB hatasi (%s). Ham surucu metni URETIM SATIR DEGERI tasiyabildigi icin ",
    "rapora YAZILMAZ; tam metin yalnizca operatorun kendi oturum konsolundadir."
  ), paste(parcalar, collapse = ", "))
}

#' Başlangıç doğrulama hatasını rapora GÜVENLİ biçimde hazırla
#'
#' `pk_query_meta_attach()` çıktısı, üretimden türetilmiş
#' `R/library_query_aliases_local.R` bindirmesini de uygular; alias hataları
#' KANONİK HEDEF değerleri (gerçek proje/program adları) taşıyabilir. Bu yüzden
#' alias ile ilgili satırlar sabit bir metne indirgenir; sorgu kimliği
#' (kararlı tanımlayıcı) korunur.
pkgh_sanitize_validation_error <- function(message) {
  ham <- as.character(message %||% "")[1]
  if (is.na(ham) || !nzchar(ham)) return(NA_character_)

  satirlar <- strsplit(ham, "\n", fixed = TRUE)[[1]]
  temiz <- vapply(satirlar, function(satir) {
    if (grepl("alias", satir, ignore.case = TRUE, useBytes = TRUE)) {
      kimlik <- regmatches(satir, regexpr("^\\s*-?\\s*\\[[^]]+\\]", satir))
      onek <- if (length(kimlik) == 1L) trimws(kimlik) else "-"
      return(paste0(
        onek, " alias bindirmesi dogrulamasi basarisiz. Ayrinti operator ",
        "oturumundadir; kanonik hedef degerleri (uretim proje/program adlari) ",
        "rapora YAZILMAZ."
      ))
    }
    satir
  }, character(1), USE.NAMES = FALSE)

  .pkgh_redact(paste(temiz, collapse = "\n"))
}

# Beyan edilen RLS sütun adlarını topla (biçimi GEÇERLİ olduğunda).
.pkgh_rls_declared <- function(rls) {
  beyan <- character(0)
  if (!is.list(rls)) return(beyan)
  for (alan in names(rls)) {
    deger <- rls[[alan]]
    if (is.null(deger)) next
    if (is.character(deger) && length(deger) == 1L && !is.na(deger) && nzchar(trimws(deger))) {
      beyan <- c(beyan, trimws(deger))
    }
  }
  unique(beyan)
}

# Sorgu nesnesindeki ESKİ sütun beyanları. Bunlar metadata katmanında değil,
# `query_library` ögesinin kendisinde yaşar; runtime bunları SESSİZCE atlar
# (`date_columns`) ya da bayat listeyi istatistik özetine GEÇİRİR
# (`pre_aggregated_columns`). Bu yüzden sağlık denetimine dahil edilirler.
.pkgh_query_column_refs <- function(query) {
  if (!is.list(query)) return(list())
  cikti <- list()
  for (alan in c("date_columns", "pre_aggregated_columns")) {
    deger <- query[[alan]]
    if (!is.character(deger) || !length(deger)) next
    temiz <- deger[!is.na(deger) & nzchar(trimws(deger))]
    if (length(temiz)) cikti[[alan]] <- unique(trimws(temiz))
  }
  cikti
}

#' Sorgu için YAPISAL sağlık bulgularını üret
#'
#' Girdi:
#'   query   : query_library ögesi (id, name, db_target, rls_columns, ...)
#'   merged  : üretilen yerel katman + küresyon birleşmiş metadata
#'   schema  : üretilen şema (adlandırılmış karakter vektörü) veya NULL
#'   blocking: `pk_meta_validate_schema_dependent()` çıktısı (mesaj vektörü)
#'
#' `pk_meta_validate_actual_columns()` ÇALIŞMA ZAMANI kapısıdır ve buradaki
#' kurallar onunla AYNI mantığı paylaşır: rapor "temiz" derken üretimde
#' patlayan bir uyuşmazlık kalmamalıdır.
pkgh_structural_findings <- function(query, merged, schema, blocking = character(0)) {
  bulgular <- list()
  sema_ham <- if (is.null(schema)) character(0) else names(schema)
  sema_ham <- sema_ham[!is.na(sema_ham) & nzchar(trimws(sema_ham))]
  sema_sutunlari <- unique(sema_ham)
  sema_tekrar <- unique(sema_ham[duplicated(sema_ham)])

  query_id <- if (is.list(query) && length(query$id) == 1L && !is.na(query$id)) {
    trimws(as.character(query$id))
  } else {
    "?"
  }

  rls <- if (is.list(query)) query$rls_columns else NULL

  # --- 0) RLS BEYANININ BİÇİMİ ------------------------------------------------
  # `pk_meta_validate_actual_columns()` geçersiz bir RLS beyanı için istek
  # zamanında `fail_closed = TRUE` döner. Rapor bunu GÜVENLİK bulgusu saymazsa
  # `rls_mismatches` sıfır kalır ve konsoldaki DURDURUCU uyarı BASILMAZ.
  rls_bicim_hatalari <- if (exists(".pk_meta_validate_rls_columns", mode = "function",
                                   inherits = TRUE)) {
    tryCatch(.pk_meta_validate_rls_columns(query_id, rls), error = function(e) character(0))
  } else {
    character(0)
  }

  if (length(rls_bicim_hatalari)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "rls_declaration_invalid", "blocking",
      sprintf(paste0(
        "rls_columns beyani GECERSIZ: %s. Istek zamaninda sorgu KAPALI ",
        "BASARISIZ olur; beyan silinerek 'cozulmez', duzeltilir."
      ), paste(rls_bicim_hatalari, collapse = " | ")),
      security = TRUE
    )))
  }

  rls_beyan <- if (length(rls_bicim_hatalari)) character(0) else .pkgh_rls_declared(rls)

  # --- 1) RLS: GÜVENLİK KRİTİK -------------------------------------------------
  # Beyan edilen bir RLS sütunu gerçek sonuçta yoksa, o sorgu istek zamanında
  # KAPALI BAŞARISIZ olur (D6). Otomatik olarak KALDIRILMAZ/DEVRE DIŞI
  # BIRAKILMAZ; operatör ya SQL'i ya beyanı düzeltir.
  if (length(sema_sutunlari) && length(rls_beyan)) {
    eksik_rls <- setdiff(rls_beyan, sema_sutunlari)
    if (length(eksik_rls)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "rls_column_missing", "blocking",
        sprintf(
          paste0(
            "Beyan edilen RLS sutunu gercek sonucda yok: %s. ",
            "Ya SQL bu guvenlik sutununu dondurmeli ya da rls_columns beyani yanlis. ",
            "Beyan OTOMATIK KALDIRILMAZ; istek zamaninda sorgu kapali basarisiz olur."
          ),
          paste(eksik_rls, collapse = ", ")
        ),
        columns = eksik_rls, security = TRUE
      )))
    }

    # MÜKERRER RLS SÜTUNU DA GÜVENLİK BULGUSUDUR: çalışma zamanı doğrulayıcısı
    # tekrar eden bir gerçek sütunu `fail_closed = TRUE` sayar. Yalnızca
    # "var mi" diye bakan bir rapor bunu KAÇIRIRDI.
    tekrar_rls <- intersect(sema_tekrar, rls_beyan)
    if (length(tekrar_rls)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "rls_column_duplicated", "blocking",
        sprintf(paste0(
          "Sonucta TEKRAR EDEN RLS sutunu: %s. Yetki filtresi hangi sutuna ",
          "uygulanacagi belirsiz oldugu icin istek zamaninda kapali basarisiz olur."
        ), paste(tekrar_rls, collapse = ", ")),
        columns = tekrar_rls, security = TRUE
      )))
    }
  }

  if (length(sema_tekrar)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "duplicate_result_column", "blocking",
      sprintf("Sonuc semasinda tekrar eden sutun adi: %s",
              paste(sema_tekrar, collapse = ", ")),
      columns = sema_tekrar
    )))
  }

  if (!length(rls_beyan) && !length(rls_bicim_hatalari)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "rls_not_declared", "info",
      "Sorgu icin RLS sutunu beyan edilmemis (yetki filtresi uygulanmayacak)."
    )))
  }

  # --- 2) Metadata atıfları şemada var mi? -------------------------------------
  if (length(sema_sutunlari)) {
    cmeta_adlari <- names(merged$column_meta %||% list())
    eksik_cmeta <- setdiff(cmeta_adlari, sema_sutunlari)
    if (length(eksik_cmeta)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "column_meta_missing_in_schema", "blocking",
        sprintf("column_meta sutunu semada yok: %s", paste(eksik_cmeta, collapse = ", ")),
        columns = eksik_cmeta
      )))
    }

    atif_alanlari <- list(
      grain_columns = merged$grain_columns,
      default_group_by = merged$default_group_by,
      default_measures = merged$default_measures,
      primary_entity = merged$primary_entity
    )
    for (alan in names(atif_alanlari)) {
      deger <- atif_alanlari[[alan]]
      if (!is.character(deger) || !length(deger)) next
      eksik <- setdiff(deger[!is.na(deger) & nzchar(trimws(deger))], sema_sutunlari)
      if (length(eksik)) {
        bulgular <- c(bulgular, list(pkgh_finding(
          sprintf("%s_missing_in_schema", alan), "blocking",
          sprintf("%s beyan edilen sutun semada yok: %s", alan, paste(eksik, collapse = ", ")),
          columns = eksik
        )))
      }
    }

    # ESKİ (query nesnesi üzerindeki) sütun beyanları. Runtime bunları
    # DÜŞÜRMEZ, bu yüzden bulgular `attention` şiddetindedir; ama sessiz de
    # kalmazlar: bayat bir `pre_aggregated_columns` listesi istatistik özetine
    # geçirilmeye devam eder.
    eski_beyanlar <- .pkgh_query_column_refs(query)
    for (alan in names(eski_beyanlar)) {
      eksik <- setdiff(eski_beyanlar[[alan]], sema_sutunlari)
      if (!length(eksik)) next
      bulgular <- c(bulgular, list(pkgh_finding(
        sprintf("query_%s_missing_in_schema", alan), "attention",
        sprintf(paste0(
          "query$%s beyan edilen sutun sonucta yok: %s. Runtime bunu SESSIZCE ",
          "atlar; beyan ya da SQL guncellenmelidir."
        ), alan, paste(eksik, collapse = ", ")),
        columns = eksik
      )))
    }
  }

  # --- 3) Rol / tip uyuşmazlıkları ---------------------------------------------
  # Küresyon "measure" derken şemadaki tip metin ise, sessizce yanlış toplam
  # üretilmeden ÖNCE yakalanmalıdır.
  if (length(sema_sutunlari) &&
      exists(".pk_meta_role_from_class", mode = "function", inherits = TRUE)) {
    # `convert_date_columns()` istek yolunda, metadata kapısından ÖNCE çalışır:
    # `date_columns` içinde beyan edilen bir sütun biçimlendirilmiş metin olarak
    # döndürülse bile çalışma zamanında Date'e çevrilir. Bu BAĞLAM operatöre
    # verilmelidir; ancak KARARI değiştirmez: `pk_meta_validate_query()`
    # role='date' için TARİH TİPLİ bir şema bekler ve sorgu yine geri çekilir.
    # Bu yüzden burada yalnızca AYNI kusurun İKİNCİ kez bloklayıcı sayılması
    # önlenir; bulgu açıklayıcı bir nota dönüşür.
    tarih_beyani <- .pkgh_query_column_refs(query)$date_columns %||% character(0)

    uyusmaz <- character(0)
    beyan_kaynakli <- character(0)
    for (sutun in intersect(names(merged$column_meta %||% list()), sema_sutunlari)) {
      cmeta <- merged$column_meta[[sutun]]
      if (!is.list(cmeta) || is.null(cmeta$role)) next
      yapisal <- .pk_meta_role_from_class(schema[[sutun]])
      if (identical(cmeta$role, "date") && !identical(yapisal, "date")) {
        etiket <- sprintf("%s (role=date, sema=%s)", sutun, schema[[sutun]])
        if (sutun %in% tarih_beyani) {
          beyan_kaynakli <- c(beyan_kaynakli, etiket)
        } else {
          uyusmaz <- c(uyusmaz, etiket)
        }
      }
      if (identical(cmeta$role, "measure") && !identical(yapisal, "measure")) {
        uyusmaz <- c(uyusmaz, sprintf("%s (role=measure, sema=%s)", sutun, schema[[sutun]]))
      }
    }
    if (length(uyusmaz)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "role_type_mismatch", "blocking",
        sprintf("Beyan edilen role semadaki tiple uyusmuyor: %s", paste(uyusmaz, collapse = "; "))
      )))
    }
    if (length(beyan_kaynakli)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "role_type_mismatch_declared_date", "attention",
        sprintf(paste0(
          "role=date sutunu ham semada tarih degil, ancak query$date_columns ",
          "icinde beyan edildigi icin istek yolunda Date'e cevrilir: %s. ",
          "DIKKAT: baslangic metadata sozlesmesi role='date' icin TARIH TIPLI ",
          "sema bekler; bu yuzden sorgu YINE DE geri cekilir. Duzeltme: SQL ",
          "tipini tarihe cevirin ya da kuresyondaki role degerini duzeltin."
        ), paste(beyan_kaynakli, collapse = "; "))
      )))
    }
  }

  # --- 4) Anlamsal yetenek durumu ----------------------------------------------
  yetenekler <- character(0)
  for (cmeta in (merged$column_meta %||% list())) {
    if (is.list(cmeta) && is.character(cmeta$capability) && length(cmeta$capability) == 1L &&
        !is.na(cmeta$capability) && nzchar(trimws(cmeta$capability))) {
      yetenekler <- c(yetenekler, trimws(cmeta$capability))
    }
  }
  yetenekler <- unique(yetenekler)

  if (!length(yetenekler)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "no_semantic_capability", "attention",
      paste0(
        "Sorguda anlamsal yetenek (capability) beyani YOK. Olcu/tarih/boyut ",
        "gerektiren istekler bu sorgu icin SQL'den ONCE ",
        "'unknown_no_semantic_metadata' ile durur. Uretici bunu KENDILIGINDEN ",
        "dolduramaz: hangi sayinin planlanan hangisinin kalan isgucu oldugu ",
        "insan kuresyonudur (R/library_query_meta.R)."
      )
    )))
  }

  if (is.null(merged$primary_entity)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "no_primary_entity", "attention",
      "primary_entity beyan edilmemis; Tier-0 geri dususu uygulanir (tek filtre yapragi birincil)."
    )))
  }
  if (is.null(merged$grain)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "no_grain", "info",
      "grain beyan edilmemis; mukerrer satir elemesi YAPILMAZ."
    )))
  }

  # --- 5) Başlangıcı düşürecek ham bulgular (otoriter) --------------------------
  # `pk_meta_validate_schema_dependent()` başlangıçta ÇALIŞAN doğrulayıcıdır.
  # KARAR bu listeden verilir; ancak yukarıdaki ÖZEL bulgular aynı kusuru zaten
  # bloklayıcı saydıysa, aynı kusuru İKİNCİ KEZ bloklayıcı saymak
  # `blocking_count` değerini ve insan raporunu ŞİŞİRİR. Bu yüzden özel bir
  # bloklayıcı bulgu varken doğrulayıcı yükü TEŞHİS ayrıntısı olarak saklanır.
  if (length(blocking)) {
    zaten_bloklayici <- any(vapply(bulgular, function(f) {
      identical(f$severity, "blocking")
    }, logical(1)))

    bulgular <- c(bulgular, list(pkgh_finding(
      if (zaten_bloklayici) "startup_validation_detail" else "startup_validation_would_fail",
      if (zaten_bloklayici) "info" else "blocking",
      paste(blocking, collapse = " | ")
    )))
  }

  bulgular
}
