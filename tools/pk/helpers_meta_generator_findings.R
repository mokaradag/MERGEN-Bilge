# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_findings.R
# Açıklama: Faz 3b metadata üreticisi -- YAPISAL BULGU ÜRETİMİ.
#
#           GİZLİLİK MASKELEME ve HATA SINIFLANDIRMA AYRI DOSYADADIR:
#           helpers_meta_generator_redact.R (bu dosyadan ÖNCE yüklenir).
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
#
# BEYAN EDİLEN AD AYNEN KARŞILAŞTIRILIR (KIRPILMAZ).
#
# `convert_date_columns()` beyan edilen dizeleri OLDUĞU GİBİ gezer ve her birini
# tam `%in% names(data)` eşleşmesiyle sınar; kırpma YAPMAZ. Burada `trimws()`
# uygulamak, `" Tarih "` gibi bozuk bir beyanı `"Tarih"` sonuç sütunuyla
# EŞLEŞMİŞ sayar ve hiçbir bulgu üretilmez -- oysa runtime o tarih çevrimini
# SESSİZCE ATLAR. Rapor, uygulamanın KULLANMAYACAĞI bir beyanı "temiz" diye
# onaylayamaz.
.pkgh_query_column_refs <- function(query) {
  if (!is.list(query)) return(list())
  cikti <- list()
  for (alan in c("date_columns", "pre_aggregated_columns")) {
    deger <- query[[alan]]
    if (!is.character(deger) || !length(deger)) next
    temiz <- deger[!is.na(deger) & nzchar(trimws(deger))]
    if (length(temiz)) cikti[[alan]] <- unique(temiz)
  }
  cikti
}

# ÖZEL BULGULARIN ZATEN KAPSADIĞI DOĞRULAYICI MESAJ İMZALARI.
#
# `pk_meta_validate_schema_dependent()` / `.pk_meta_validate_rls_columns()`
# mesajları KARARLI metin şablonlarıdır; her şablon yukarıdaki özel bulgulardan
# BİRİNE karşılık gelir. Eşleşme bu şablon parçaları üzerinden yapılır, böylece
# yeni bir doğrulayıcı hatası (henüz özel bulgusu olmayan) SESSİZCE
# bilgilendirmeye düşmez, bloklayıcı kalır.
.PKGH_VALIDATOR_COVERAGE <- list(
  rls_declaration_invalid = c(
    "rls_columns adlandirilmis liste olmalidir",
    "rls_columns icinde tekrar eden alan",
    "rls_columns bilinmeyen alan iceriyor",
    "ya NULL ya tek bos olmayan sutun adi olmalidir"
  ),
  rls_column_missing = "D6 fail-open deligi",
  duplicate_result_column = "result_schema icinde tekrar eden sutun adi",
  column_meta_missing_in_schema = "column_meta sutunu semada yok",
  grain_columns_missing_in_schema = "metadata atifi semada yok",
  default_group_by_missing_in_schema = "metadata atifi semada yok",
  default_measures_missing_in_schema = "metadata atifi semada yok",
  primary_entity_missing_in_schema = "metadata atifi semada yok",
  role_type_mismatch = c("role='date' ama semadaki tip", "role='measure' ama semadaki tip"),
  role_type_mismatch_declared_date = "role='date' ama semadaki tip"
)

# Doğrulayıcı mesajlarını, ZATEN bloklayıcı bir özel bulguyla temsil edilenler
# ve edilmeyenler olarak ayır.
.pkgh_split_validator_messages <- function(blocking, findings) {
  imzalar <- character(0)
  for (f in findings) {
    if (!identical(f$severity, "blocking")) next
    kod <- as.character(f$code %||% "")[1]
    if (!nzchar(kod)) next
    imzalar <- c(imzalar, .PKGH_VALIDATOR_COVERAGE[[kod]] %||% character(0))
  }
  imzalar <- unique(imzalar)

  mesajlar <- as.character(blocking)
  mesajlar <- mesajlar[!is.na(mesajlar) & nzchar(mesajlar)]
  if (!length(imzalar)) return(list(covered = character(0), uncovered = mesajlar))

  kapsanan <- vapply(mesajlar, function(m) {
    any(vapply(imzalar, function(imza) {
      grepl(imza, m, fixed = TRUE, useBytes = TRUE)
    }, logical(1)))
  }, logical(1), USE.NAMES = FALSE)

  list(covered = mesajlar[kapsanan], uncovered = mesajlar[!kapsanan])
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
  # KARAR bu listeden verilir.
  #
  # YİNELEME YALNIZCA MESAJ BAZINDA ELENİR, TOPLU DEĞİL.
  #
  # Eskiden herhangi bir özel bloklayıcı bulgu varken doğrulayıcı yükünün
  # TAMAMI `info` şiddetine düşürülüyordu. `blocking` birden çok BAĞIMSIZ
  # doğrulayıcı hatası taşıyabilir; `health.txt` `info` bulgularını atladığı
  # için (örneğin) RLS uyuşmazlığı + ayrı bir metadata kusuru olan bir sorguda
  # operatör yalnızca RLS'i görür, onu düzeltir, yeniden koşar ve İKİNCİ
  # bloklayıcıyı ancak o zaman keşfeder. Bu yüzden yalnızca ÖZEL bir bulguyla
  # ZATEN temsil edilen mesajlar ayrıntıya indirilir; temsil edilmeyenler
  # BLOKLAYICI kalır.
  if (length(blocking)) {
    bolunmus <- .pkgh_split_validator_messages(blocking, bulgular)

    if (length(bolunmus$uncovered)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "startup_validation_would_fail", "blocking",
        paste(bolunmus$uncovered, collapse = " | ")
      )))
    }
    if (length(bolunmus$covered)) {
      bulgular <- c(bulgular, list(pkgh_finding(
        "startup_validation_detail", "info",
        paste(bolunmus$covered, collapse = " | ")
      )))
    }
  }

  bulgular
}
