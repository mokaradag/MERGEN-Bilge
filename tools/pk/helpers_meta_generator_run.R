# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_run.R
# Açıklama: Faz 3b metadata üreticisi -- ENVANTER KOŞUSU.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# TASARIM: DB erişimi ENJEKTE EDİLİR (`connect_fn`, `describe_fn`, `sample_fn`).
# Böylece koşu mantığının tamamı -- salt-okunur kapısı, şema çıkarımı, birleşme,
# geri çekme kararı, sağlık kaydı -- gerçek bir veritabanı OLMADAN test edilir.
# Varsayılan enjeksiyonlar `helpers_meta_generator_db.R` içindedir.
#
# ŞEMA GETİRME AYRI DOSYADADIR: helpers_meta_generator_fetch.R (bu dosyadan
# ÖNCE yüklenir). Burada yalnızca envanter DÖNGÜSÜ ve KARARLAR vardır.
#
# SERT KURALLAR:
#   * SALT OKUNUR. Her SQL, üretimin kullandığı AYNI `pk_sql_classify_readonly()`
#     kapısından geçer. Kapı reddederse sorgu ÇALIŞTIRILMAZ.
#   * SQL METNİ DEĞİŞTİRİLMEZ. Örnekleme, SQL'i sarmalayarak değil, açık imleçten
#     yalnızca N satır çekerek yapılır; böylece kapıdan geçen metin ile çalışan
#     metin AYNIDIR.
#   * BİLİNMEYEN HEDEFE BAĞLANILMAZ. `get_connection()` bilinmeyen bir hedefi
#     sessizce birincil DSN'e düşürür; bu yüzden hedef, bağlantı AÇILMADAN önce
#     doğrulanır.
#   * TEK BİR SORGU KOŞUYU DÜŞÜRMEZ. Hata bir sağlık bulgusu olur.
#   * BAĞLANTI HER DURUMDA BIRAKILIR (`on.exit`).
# ==============================================================================

.pkgn_is_text <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}

#' Üretilen yerel katman girdisi oluştur
#'
#' YALNIZCA YAPISAL alanlar yazılır. `capability`, `grain`, `additive`, `unit`,
#' `primary_entity`, `intents`, `default_measures` gibi ANLAMSAL alanlar
#' BİLİNÇLİ OLARAK ÜRETİLMEZ: onlar insan küresyonudur ve yokluğunda anlamsal
#' istekler SQL'den önce fail-closed durur.
#' @param source_fingerprint Girdinin türetildiği SQL'in KAYNAK parmak izi.
#'   Bir sonraki koşuda `pkgc_merge_local_layers()` bu damgayı güncel sorguyla
#'   karşılaştırır: damgasız bir girdi doğrulanamaz, bu yüzden geçici bir hatada
#'   KORUNMAZ. Aksi hâlde SELECT listesi değişmiş bir sorgunun eski
#'   `result_schema` değeri canlı kalırdı ve bütün-kütüphane kapısı bunu
#'   YAKALAYAMAZDI (o kapı SQL'i çalıştırmaz).
pkgn_build_local_entry <- function(schema, source_types, mode, observations = list(),
                                   source_fingerprint = NA_character_) {
  cmeta <- pkgs_build_column_meta(schema, source_types = source_types, mode = mode)
  cmeta <- pkgs_apply_observations(cmeta, observations)

  list(
    result_schema = schema,
    column_meta = cmeta,
    generated_mode = as.character(mode)[1],
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    source_fingerprint = as.character(source_fingerprint %||% NA_character_)[1],
    tier = 1L
  )
}

#' Üretilen girdinin başlangıç doğrulamasını GEÇİP GEÇMEDİĞİNİ simüle et
#'
#' Başlangıçta çalışan doğrulayıcıların AYNISI kullanılır. Üreticinin "bu sorgu
#' güvenle dahil edilebilir" kararı, uygulamanın açılışta vereceği kararla
#' birebir aynı olmalıdır; aksi hâlde üretici dosyayı yazar ve uygulama açılmaz.
#'
#' @param alias_overlay Operatörün `pk_query_aliases_local` bindirmesi. Başlangıç
#'   kapısı bu bindirmeyi de uygular; burada UYGULANMAZSA bir sorguya özgü alias
#'   kusuru yalnızca BÜTÜN KÜTÜPHANE kapısında görülür ve tek bir bozuk sorgu
#'   TÜM üretilen katmanın yazılmamasına yol açar. Sorgu bazında geri çekmek
#'   doğru davranıştır.
pkgn_validate_candidate <- function(query, local_entry, auto_entry = NULL,
                                    curated_entry = NULL, registry = NULL,
                                    alias_overlay = NULL) {
  birlesik <- pk_meta_merge_layers(
    auto = if (is.null(auto_entry)) list() else stats::setNames(list(auto_entry), "x"),
    local = stats::setNames(list(local_entry), "x"),
    curated = if (is.null(curated_entry)) list() else stats::setNames(list(curated_entry), "x")
  )[["x"]]

  # KANONİK KİMLİK. `query_library` sözleşmesi boşluklu bir id'yi kabul edip
  # `trimws()` ile kanonikleştirir; üretilen katman da `q1` olarak anahtarlanır.
  # Ham `" q1 "` ile bakmak, `alias_overlay[[" q1 "]]` bulunamadığı için sorguya
  # özgü alias kusurunu KAÇIRIR ve kusur yalnızca BÜTÜN KÜTÜPHANE kapısında
  # patlar; o zaman da tek bir bozuk sorgu TÜM üretilen katmanı bloklar.
  ham_id <- as.character(query$id %||% "?")[1]
  id <- if (is.na(ham_id)) "?" else trimws(ham_id)

  # Alias katlama: birleşmiş metadata üzerinde başlangıçta da çalışır.
  normal <- pk_meta_normalize_aliases(stats::setNames(list(birlesik), id))
  birlesik <- normal$meta[[id]]
  hatalar <- normal$errors

  if (!is.null(alias_overlay) && is.list(alias_overlay) && !is.null(alias_overlay[[id]])) {
    bindirme <- pk_meta_apply_alias_overlay(
      stats::setNames(list(birlesik), id),
      stats::setNames(list(alias_overlay[[id]]), id)
    )
    birlesik <- bindirme$meta[[id]]
    hatalar <- c(hatalar, bindirme$errors)
  }

  hatalar <- unique(c(
    hatalar,
    pk_meta_validate_query(id, birlesik, registry),
    pk_meta_validate_schema_dependent(id, birlesik, birlesik$result_schema, query$rls_columns)
  ))

  list(merged = birlesik, errors = hatalar[nzchar(hatalar)])
}

# Kanıtlanmış üst sınırı olmayan sütunlar OPERATÖR EYLEMİ gerektirir (operatör
# kılavuzu bunu böyle listeler). `info` şiddeti insan raporunda BASTIRILIR;
# tek bulgusu bu olan bir sorgu rapordan tamamen kaybolurdu.
.pkgn_unbounded_finding <- function(sutunlar) {
  pkgh_finding(
    "unbounded_lob_column", "attention",
    sprintf(
      "Kanitlanmis genislik ust siniri OLMAYAN sutun(lar): %s.",
      paste(sutunlar, collapse = ", ")
    ),
    columns = sutunlar
  )
}

.pkgn_unmapped_finding <- function(eslenmeyen) {
  sutunlar <- vapply(eslenmeyen, function(o) as.character(o$column)[1], character(1))
  etiketler <- vapply(eslenmeyen, function(o) {
    sprintf("%s (%s)", as.character(o$column)[1], as.character(o$source_type)[1])
  }, character(1))

  pkgh_finding(
    "unmapped_sql_type", "attention",
    sprintf(
      paste0(
        "SQL tipi eslenemedi; EN MUHAFAZAKAR yapiya (character/dimension) ",
        "dusuldu: %s. Bu sutun icin toplama YAPILMAZ; gerekiyorsa NATIF tipi ",
        "eslemeye ekleyin ya da kure edin."
      ),
      paste(etiketler, collapse = ", ")
    ),
    columns = sutunlar
  )
}

#' YEREL (DB GEREKTİRMEYEN) KAPILAR
#'
#' Kimlik, hedef, SQL varlığı ve salt-okunur sınıflandırması BİR VERİTABANI
#' GEREKTİRMEZ. Bunlar bağlantıdan ÖNCE çalıştırılabildiği için envanter
#' döngüsü de aynı sırayı kullanır: aksi hâlde bozuk ya da reddedilmiş bir
#' yazma sorgusu için bile GERÇEK bir üretim oturumu açılır (ve erişilemeyen
#' bir DSN'de bu, hiç ihtiyaç duyulmayan bir bloklamaya dönüşür).
#'
#' @return Karar verilmişse `list(record, local_entry, cache)`; aksi hâlde NULL.
pkgn_precheck_query <- function(query, config, target_error = NULL) {
  reddet <- function(status, finding) {
    list(
      record = pkgh_query_record(query, status, config$mode, findings = list(finding)),
      local_entry = NULL, cache = NULL
    )
  }

  if (!.pkgn_is_text(query$id)) {
    return(reddet("failed", pkgh_finding(
      "missing_query_id", "blocking",
      "Sorgu KARARLI bir id tasimiyor; metadata liste konumuna baglanamaz."
    )))
  }

  # --- HEDEF KAPISI (bağlantı AÇILMADAN önce) ---------------------------------
  if (!is.null(target_error)) {
    return(reddet("failed", pkgh_finding("invalid_db_target", "blocking", target_error)))
  }

  # --- SALT-OKUNUR KAPISI (üretimle AYNI sınıflandırıcı) -----------------------
  if (!.pkgn_is_text(query$sql)) {
    return(reddet("failed", pkgh_finding(
      "missing_sql", "blocking",
      "Sorgu icin SQL metni yok (sql_file yuklenmemis olabilir)."
    )))
  }

  kapi <- pk_sql_classify_readonly(query$sql)
  if (!isTRUE(kapi$allowed)) {
    # HAM SQL RAPORA GİRMEZ; yalnızca gerekçe.
    return(reddet("skipped", pkgh_finding(
      "sql_not_readonly", "blocking",
      sprintf(
        paste0(
          "SQL salt-okunur kapisindan gecemedi (gerekce=%s, tur=%s). ",
          "Sorgu CALISTIRILMADI. Uretici asla DDL/yazma/EXEC calistirmaz."
        ),
        kapi$reason %||% "?", kapi$statement_kind %||% "?"
      )
    )))
  }

  NULL
}

#' Tek bir sorgunun envanterini çıkar
#'
#' @return list(record, local_entry, cache) -- `local_entry` NULL ise sorgu
#'   üretilen katmana GİRMEZ (Tier-0'da kalır; bu bir GERİLEME DEĞİLDİR).
pkgn_inventory_one <- function(query, config, conn = NULL,
                               describe_fn = NULL, sample_fn = NULL,
                               auto_entry = NULL, curated_entry = NULL,
                               registry = NULL, cached = NULL,
                               alias_overlay = NULL, target_error = NULL,
                               connect_error = NULL) {
  # Yerel kapılar burada da çalışır: `pkgn_inventory_one()` tek başına da
  # çağrılabilen bir sözleşmedir ve kapılar İDEMPOTENTTİR.
  onkontrol <- pkgn_precheck_query(query, config, target_error)
  if (!is.null(onkontrol)) return(onkontrol)

  # --- ŞEMA (önbellekten ya da DB'den) ----------------------------------------
  sema_sonucu <- if (!is.null(cached)) {
    cached
  } else {
    pkgn_fetch_schema(query, config, conn, describe_fn, sample_fn,
                      connect_error = connect_error)
  }

  if (!isTRUE(sema_sonucu$ok)) {
    return(list(
      record = pkgh_query_record(
        query, "failed", config$mode, error = sema_sonucu$error,
        findings = list(pkgh_finding(
          sema_sonucu$code %||% "schema_unavailable", "attention",
          sema_sonucu$detail %||% "Sorgu semasi alinamadi; sorgu Tier-0 olarak kalir."
        )),
        sample_info = sema_sonucu$sample_info %||% list()
      ),
      local_entry = NULL, cache = NULL,
      connection_error = isTRUE(sema_sonucu$connection_error)
    ))
  }

  sema <- sema_sonucu$schema
  yerel <- pkgn_build_local_entry(
    sema, sema_sonucu$source_types, config$mode, sema_sonucu$observations %||% list(),
    source_fingerprint = if (exists("pkgh_source_fingerprint", mode = "function",
                                    inherits = TRUE)) {
      pkgh_source_fingerprint(query)
    } else {
      NA_character_
    }
  )

  dogrulama <- pkgn_validate_candidate(query, yerel, auto_entry, curated_entry, registry,
                                       alias_overlay = alias_overlay)
  bulgular <- pkgh_structural_findings(query, dogrulama$merged, sema, dogrulama$errors)

  if (length(sema_sonucu$unmapped %||% list())) {
    bulgular <- c(bulgular, list(.pkgn_unmapped_finding(sema_sonucu$unmapped)))
  }

  if (length(sema_sonucu$unbounded %||% character(0))) {
    bulgular <- c(bulgular, list(.pkgn_unbounded_finding(sema_sonucu$unbounded)))
  }

  ornek_bilgi <- sema_sonucu$sample_info %||% list()

  # SIFIR SATIRLI SONUÇ: sütunları olduğu için şema GEÇERLİDİR, ama sağlık
  # sözleşmesi böyle bir sorgunun BİLDİRİLMESİNİ gerektirir (SQL yaşayan veriyi
  # döndürmüyor olabilir).
  #
  # ÖNBELLEKTEN GELEN KANIT DA BİLDİRİLİR. Devam önbelleği `rows_seen` değerini
  # taşır; bulguyu yalnızca taze koşularda üretmek, ilk sıfır satırlı örneklemeden
  # sonraki HER varsayılan (resume açık) koşuda aynı sorguyu `health.txt` içindeki
  # eylem listesinden SESSİZCE düşürürdü -- üstelik durumun düzeldiğine dair
  # HİÇBİR yeni kanıt olmadan.
  if (identical(config$mode, "sample") &&
      identical(as.integer(ornek_bilgi$rows_seen %||% NA_integer_), 0L)) {
    onbellekten <- isTRUE(ornek_bilgi$from_cache)
    bulgular <- c(bulgular, list(pkgh_finding(
      "sample_zero_rows", "attention",
      paste0(
        "Ornekleme SIFIR satir dondurdu. Sema gecerli, ancak sorgu su an veri ",
        "uretmiyor; kanit gerektiren gozlemler (null/benzersizlik/kardinalite) ",
        "URETILEMEDI.",
        if (onbellekten) {
          paste0(
            " (Bu kanit DEVAM ONBELLEGINDEN gelmektedir; bu kosuda yeniden ",
            "orneklenmedi. Taze kanit icin MERGEN_PK_META_RESUME=false ile ",
            "calistirin.)"
          )
        } else {
          ""
        }
      )
    )))
  }

  # NATİF TİP KANITI YOKKEN YAPISAL KONTROLLER ÇALIŞMAZ.
  #
  # Tanımlayıcı gerçekten alınamadığında -- yani `sample` kipine EN ÇOK ihtiyaç
  # duyulan durumda -- `pkgs_schema_from_dataframe()` eşlenmeyen SQL tipini ve
  # sınırsız LOB genişliğini GÖREMEZ. Bunu yalnızca makine alanı
  # `native_types_available = FALSE` ile bildirmek, `health.txt` içinde
  # "eylem gerektiren bulgu yok" denmesine yol açardı; oysa o kontroller HİÇ
  # çalışmamıştır.
  if (identical(config$mode, "sample") && !isTRUE(ornek_bilgi$from_cache) &&
      isTRUE(ornek_bilgi$executed) && !isTRUE(ornek_bilgi$native_types_available)) {
    bulgular <- c(bulgular, list(pkgh_finding(
      "native_types_unavailable", "attention",
      paste0(
        "Sonuc kumesi tanimlayicisi ALINAMADI; sema yalnizca surucunun R ",
        "siniflarindan kuruldu. Bu sorgu icin ESLENMEYEN SQL TIPI ve SINIRSIZ ",
        "LOB GENISLIGI kontrolleri CALISTIRILAMADI (yok demek DEGILDIR)."
      )
    )))
  }

  # ÖNEK ÖRNEĞİNİN KANITLADIĞI row_cap AŞIMI. Örnek satır sayısı etkin
  # `row_cap` değerini GEÇTİYSE, önek TEK BAŞINA aşımı kanıtlar; bu durumda
  # "bilinmiyor" demek elde olan kanıtı gizlemek olurdu.
  # ETKİN row_cap ÇALIŞMA ZAMANI ÇÖZÜMLEYİCİSİNDEN GELİR.
  #
  # Metadata `row_cap` beyan ETMEDİĞİNDE etkin tavan `MERGEN_PK_ROW_CAP`
  # ortamından gelir; ham alanı `NA`ya çevirmek `row_cap_exceeded` bulgusunu
  # HİÇ üretmiyor ve `health.txt` bulguyu ATLIYORDU.
  etkin_cap <- if (exists("pk_meta_row_cap", mode = "function", inherits = TRUE)) {
    tryCatch(pk_meta_row_cap(list(meta = dogrulama$merged)), error = function(e) NULL)
  } else {
    NULL
  }
  ust_sinir <- suppressWarnings(as.numeric(
    etkin_cap %||% dogrulama$merged$row_cap %||% NA_real_
  )[1])
  gorulen <- suppressWarnings(as.numeric(ornek_bilgi$rows_seen %||% NA_real_)[1])
  if (!is.na(ust_sinir) && !is.na(gorulen) && is.finite(ust_sinir) && gorulen > ust_sinir) {
    ornek_bilgi$cardinality_claim <- "row_cap_exceeded"
    bulgular <- c(bulgular, list(pkgh_finding(
      "row_cap_exceeded", "attention",
      sprintf(paste0(
        "Onek ornegi row_cap asimini KANITLADI: gorulen %s satir > row_cap %s. ",
        "Kuresyondaki row_cap degeri ya da sorgu kapsami gozden gecirilmelidir."
      ), format(gorulen), format(ust_sinir))
    )))
  }

  # --- KARAR ------------------------------------------------------------------
  # Bloklayıcı bulgu VARSA sorgu üretilen katmana ALINMAZ. Böylece:
  #   * uygulama başlangıcı ASLA bir üretici koşusu yüzünden kırılmaz,
  #   * sağlıklı sorgular gerçek şemalarını alır,
  #   * sorunlu sorgu BUGÜNKÜ davranışında kalır (Tier-0, pending_no_schema) --
  #     istek zamanı RLS zorlaması KOŞULSUZ olduğu için güvenlik ZAYIFLAMAZ.
  bloklayici <- sum(vapply(bulgular, function(f) identical(f$severity, "blocking"), logical(1)))

  if (bloklayici > 0L) {
    return(list(
      record = pkgh_query_record(query, "withheld", config$mode, schema = sema,
                                 findings = bulgular, sample_info = ornek_bilgi),
      local_entry = NULL,
      cache = sema_sonucu$cache
    ))
  }

  list(
    record = pkgh_query_record(query, "ok", config$mode, schema = sema,
                               findings = bulgular, sample_info = ornek_bilgi),
    local_entry = yerel,
    cache = sema_sonucu$cache
  )
}

#' Tüm kütüphane için envanter koşusu
#'
#' @param connect_fn `function(target, timeout_sec)` -> bağlantı nesnesi ya da
#'   NULL. `timeout_sec` YALNIZCA işlev onu beyan ettiğinde geçirilir, böylece
#'   testlerin sade `function(target)` sözleşmesi korunur.
#' @param release_fn `function(handle, timeout_sec)` -> serbest bırak.
#' @param fingerprints Devam önbelleği parmak izleri (yalnızca önbellek
#'   girdisinin kaydedilmesi için; kabul kararı `pkgh_read_state()` içindedir).
# KOŞU KİLİDİ KAYBI İÇİN KOŞUL SINIFI.
#
# Ara kayıt yazıcısı (`generate_query_meta.R` içindeki `ara_kayit`) kilidi
# kaybettiğinde bu sınıfla sinyal verir. Sınıf, hata METNİNE bakmadan ayırt
# etmeyi sağlar; metin eşleştirme yerelleştirme/redaksiyon ile bozulabilirdi.
PKG_META_LOCK_LOST_CLASS <- "pkg_meta_lock_lost"

#' @param checkpoint_fn `function(cache)` -> her sorgudan SONRA çağrılır.
#'   Kesintiye uğrayan bir koşunun devam edebilmesi için durum ARA ARA
#'   yazılmalıdır; yalnızca koşu sonunda yazmak, kesintide TÜM ilerlemeyi
#'   kaybettirir.
pkg_meta_run_inventory <- function(query_library, config,
                                   connect_fn, release_fn,
                                   describe_fn, sample_fn,
                                   auto_layer = list(), curated_layer = list(),
                                   registry = NULL, cache = list(),
                                   progress_fn = NULL, alias_overlay = NULL,
                                   fingerprints = NULL, checkpoint_fn = NULL) {
  kayitlar <- list()
  yerel <- list()

  # ARA KAYIT ÖNBELLEĞİ, KABUL EDİLEN GİRDİ ÖNBELLEĞİYLE TOHUMLANIR.
  #
  # Boş başlatıldığında, ilk sorgudan sonraki `checkpoint_fn(yeni_cache)` çağrısı
  # `generator-state.json` dosyasını YALNIZCA o ana kadar gezilen girdilerle
  # yeniden yazar ve HENÜZ GEZİLMEMİŞ tüm önbellek girdilerini SİLER. Koşu tam
  # o noktada kesilirse, "kaldığı yerden devam" özelliği önceki koşunun
  # tamamlanmış işini KAYBETTİRİRDİ. Girdi önbelleği zaten `pkgh_read_state()`
  # tarafından parmak izi/kip/sürüm kapılarından geçirilerek KABUL edilmiştir.
  #
  # ŞEKİL ÖNEMLİDİR: `pkgh_read_state()` girdi başına TAM sonuç nesnesini döner
  # (`ok`, `schema`, ... ve içinde `cache`). Durum yazıcısı ise DURUM ŞEKLİNİ
  # (`columns`, `source_types`, `fingerprint`, ...) bekler. Tam nesneyi olduğu
  # gibi tohumlamak `columns = NULL` yazar ve girdi sonraki okumada SESSİZCE
  # düşerdi -- yani koruma hiç işlemezdi. Bu yüzden yalnızca `$cache` alt
  # nesnesi taşınır; koşu içinde üretilen girdiler de aynı şekildedir.
  yeni_cache <- list()
  if (isTRUE(config$resume) && is.list(cache)) {
    for (onbellek_id in names(cache)) {
      girdi <- cache[[onbellek_id]]$cache
      if (is.list(girdi) && length(girdi)) yeni_cache[[onbellek_id]] <- girdi
    }
  }

  baglantilar <- list()
  baglanti_hatalari <- list()

  baglanti_birak <- function(hedef) {
    tutamac <- baglantilar[[hedef]]
    if (is.null(tutamac)) return(invisible(NULL))
    tryCatch(
      .pkgn_call_injected(release_fn, positional = list(tutamac$handle),
                          optional = list(timeout_sec = config$sql_timeout_sec)),
      error = function(e) NULL
    )
    baglantilar[[hedef]] <<- NULL
    invisible(NULL)
  }

  on.exit({
    for (hedef in names(baglantilar)) {
      tryCatch(
        .pkgn_call_injected(release_fn, positional = list(baglantilar[[hedef]]$handle),
                            optional = list(timeout_sec = config$sql_timeout_sec)),
        error = function(e) NULL
      )
    }
  }, add = TRUE)

  # BAŞARISIZ BAĞLANTI ÖNBELLEĞE ALINMAZ. Tek bir geçici checkout/ağ hatası
  # önbelleğe NULL yazsaydı, o hedefteki BÜTÜN sonraki sorgular yeniden deneme
  # şansı bulamadan düşerdi.
  #
  # EDİNİM HATASI KORUNUR: `connect_fn()` düştüğünde koşul düz `NULL`'a
  # çevrilirse, sağlık kaydında yalnızca genel `no_connection` kalır ve kimlik
  # doğrulama hatası / eksik ODBC sürücüsü / oturum açma zaman aşımı / havuz
  # checkout hatası AYIRT EDİLEMEZ olur.
  baglanti_al <- function(hedef) {
    if (!is.null(baglantilar[[hedef]])) return(baglantilar[[hedef]]$conn)

    tutamac <- tryCatch(
      .pkgn_call_injected(connect_fn, positional = list(hedef),
                          optional = list(timeout_sec = config$sql_timeout_sec)),
      error = function(e) e
    )

    if (inherits(tutamac, "condition")) {
      baglanti_hatalari[[hedef]] <<- pkgh_db_error_summary(conditionMessage(tutamac))
      return(NULL)
    }
    if (is.null(tutamac)) {
      baglanti_hatalari[[hedef]] <<- NULL
      return(NULL)
    }

    baglanti_hatalari[[hedef]] <<- NULL
    baglantilar[[hedef]] <<- list(handle = tutamac,
                                  conn = .pkgn_unwrap_connection(tutamac))
    baglantilar[[hedef]]$conn
  }

  for (i in seq_along(query_library)) {
    q <- query_library[[i]]

    # BOZUK KÜTÜPHANE ÖGESİ SESSİZCE DÜŞÜRÜLMEZ: aksi hâlde `total_queries`
    # gerçek kütüphaneden küçük olur ve denetim bu kusur sınıfını göremez.
    if (!is.list(q)) {
      kayitlar[[length(kayitlar) + 1L]] <- pkgh_query_record(
        list(id = sprintf("index_%d", i), name = NA_character_),
        "failed", config$mode,
        findings = list(pkgh_finding(
          "malformed_library_entry", "blocking",
          sprintf("query_library[[%d]] bir liste degil; sorgu envanterlenemez.", i)
        ))
      )
      next
    }

    id <- if (.pkgn_is_text(q$id)) trimws(q$id) else NA_character_
    hedef_ham <- as.character(q$db_target %||% "primary")[1]
    hedef_dogrulama <- pkg_meta_validate_db_target(hedef_ham)
    hedef <- if (isTRUE(hedef_dogrulama$ok)) hedef_dogrulama$target else hedef_ham
    hedef_hatasi <- if (isTRUE(hedef_dogrulama$ok)) NULL else hedef_dogrulama$detail

    if (is.function(progress_fn)) {
      progress_fn(i, length(query_library), id %||% sprintf("index_%d", i))
    }

    # YEREL KAPILAR ÖNCE ÇALIŞIR (BAĞLANTI AÇILMADAN).
    #
    # Kimlik/SQL/salt-okunur kararları DB GEREKTİRMEZ. Önce bağlanmak, asla
    # veritabanına ihtiyaç duymayacak bozuk ya da reddedilmiş bir yazma sorgusu
    # için bile gerçek bir üretim oturumu açar; erişilemeyen bir DSN'de bu, hiç
    # gerekmeyen bir bloklamaya dönüşür.
    onkontrol <- pkgn_precheck_query(q, config, hedef_hatasi)

    onbellek <- if (isTRUE(config$resume) && !is.na(id)) cache[[id]] else NULL
    baglanti <- if (!is.null(onkontrol) || !is.null(onbellek)) NULL else baglanti_al(hedef)

    sonuc <- if (!is.null(onkontrol)) {
      onkontrol
    } else {
      tryCatch(
        pkgn_inventory_one(
          query = q, config = config, conn = baglanti,
          describe_fn = describe_fn, sample_fn = sample_fn,
          auto_entry = if (!is.na(id)) auto_layer[[id]] else NULL,
          curated_entry = if (!is.na(id)) curated_layer[[id]] else NULL,
          registry = registry,
          cached = onbellek,
          alias_overlay = alias_overlay,
          target_error = hedef_hatasi,
          connect_error = baglanti_hatalari[[hedef]]
        ),
        # TEK BİR SORGU KOŞUYU DÜŞÜRMEZ.
        error = function(e) list(
          record = pkgh_query_record(
            q, "failed", config$mode, error = pkgh_db_error_summary(conditionMessage(e)),
            findings = list(pkgh_finding(
              "inventory_exception", "attention",
              "Envanter cikarimi sirasinda beklenmeyen hata; sorgu Tier-0 kaldi."
            ))
          ),
          local_entry = NULL, cache = NULL,
          connection_error = .pkgn_is_connection_error(conditionMessage(e))
        )
      )
    }

    # ÖLÜ BAĞLANTIYI BIRAK. Bağlantı seviyesinde bir hata olduysa önbellekteki
    # tutamaç artık geçersizdir; bırakılmazsa aynı hedefteki sonraki her sorgu
    # da aynı ölü tutamacı kullanıp düşerdi.
    if (isTRUE(sonuc$connection_error)) baglanti_birak(hedef)

    kayitlar[[length(kayitlar) + 1L]] <- sonuc$record
    if (!is.null(sonuc$local_entry) && !is.na(id)) yerel[[id]] <- sonuc$local_entry
    if (!is.null(sonuc$cache) && !is.na(id)) {
      girdi <- sonuc$cache
      if (is.null(girdi$fingerprint)) {
        girdi$fingerprint <- if (!is.null(fingerprints) && !is.null(fingerprints[[id]])) {
          fingerprints[[id]]
        } else if (exists("pkgh_state_fingerprint", mode = "function", inherits = TRUE)) {
          pkgh_state_fingerprint(q, config)
        } else {
          NA_character_
        }
      }
      yeni_cache[[id]] <- girdi
    }

    # ARA KAYIT: koşu burada kesilse bile buraya kadarki ilerleme korunur.
    #
    # PR #705: BAŞARISIZ ARA KAYIT SESSİZ GEÇMEZ. Disk/izin/geçici Windows
    # dosya kilidi yüzünden `checkpoint_fn` FALSE dönerse ya da hata atarsa,
    # operatör koşuyu son başarılı kayıttan SONRA keserse aradaki iş DEVAM
    # ETTİRİLEMEZ; oysa belgelenen garanti "her sorgudan sonra kayıt"tır.
    # Envanteri durdurmak yerine GÖRÜNÜR uyarı üretilir: kalan sorgular hâlâ
    # taranır, ancak operatör devam edilebilirliğin kaybolduğunu ANINDA görür.
    if (is.function(checkpoint_fn)) {
      kayit_ok <- tryCatch(checkpoint_fn(yeni_cache), error = function(e) e)
      # ÇİTLEME (fencing) KAYBI UYARIYA İNDİRGENMEZ.
      #
      # Ara kayıt, koşu kilidini KAYBETTİĞİ için de başarısız olabilir: o anda
      # kilidi başka bir üretici devralmıştır. Bu hatayı yutup envantere devam
      # etmek, iki koşunun AYNI paylaşılan metadata/artefakt dosyalarına
      # yazmasına izin verirdi. Sınıf İMZAYLA ayırt edilir (metin eşleştirme
      # DEĞİL) ve yukarı YAYILIR; sıradan yazma hataları aşağıdaki uyarı
      # yolunda kalır.
      if (inherits(kayit_ok, PKG_META_LOCK_LOST_CLASS)) stop(kayit_ok)
      if (inherits(kayit_ok, "condition") || !isTRUE(kayit_ok)) {
        neden <- if (inherits(kayit_ok, "condition")) {
          if (exists("pkgh_sanitize_bootstrap_error", mode = "function", inherits = TRUE)) {
            pkgh_sanitize_bootstrap_error(conditionMessage(kayit_ok))
          } else {
            "yazma hatasi"
          }
        } else {
          "yazma basarisiz"
        }
        cat(sprintf(paste0(
          "[PK_META_GEN] !!! ARA KAYIT BASARISIZ (sorgu=%s): %s\n",
          "[PK_META_GEN]     Bu noktadan sonraki is DEVAM ETTIRILEMEZ; kosu\n",
          "[PK_META_GEN]     kesilirse bastan baslamak gerekir.\n"
        ), id, neden))
      }
    }
  }

  list(
    local_meta = yerel,
    records = kayitlar,
    summary = pkgh_summarize(kayitlar),
    cache = yeni_cache
  )
}
