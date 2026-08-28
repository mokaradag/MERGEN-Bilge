# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_state.R
# Açıklama: Faz 3b metadata üreticisi -- DEVAM (resume) ÖNBELLEĞİ.
#
# BU DOSYA ÇALIŞMA ZAMANI KODU DEĞİLDİR; kaynak manifestine EKLENMEZ.
#
# Önbellek YALNIZCA DB gözlemlerini taşır; karar/küresyon her koşuda YENİDEN
# hesaplanır, böylece küresyon değişikliği önbellek yüzünden kaçırılmaz.
#
# İKİ SERT KURAL:
#   1) PARMAK İZİ. Bir girdi yalnızca SQL metni + db_target + sonucu çalışma
#      zamanından ÖNCE yapısal olarak değiştiren sorgu beyanları + (yalnızca
#      `sample` kipinde) KANIT/GÜVENLİ ÖRNEKLEME ayarları parmak izi AYNI
#      kaldığında kabul edilir. Aksi hâlde SELECT listesi ya da `date_columns`
#      değiştirilmiş bir sorgu eski şemasıyla sonsuza dek yeniden kullanılır,
#      ya da eşik değiştiği hâlde eski `high_cardinality` kanıtı yeniden
#      yayımlanır; üreticiyi tekrar çalıştırmak bayat metadata'yı ONARAMAZ.
#   2) ATOMİK YAZMA. Durum dosyası geçici dosyaya yazılıp yerine taşınır ve
#      yazma hatası SESSİZCE YUTULMAZ; aksi hâlde kesinti yarım JSON bırakır ve
#      bir disk/izin hatası başarı gibi raporlanır.
# ==============================================================================

# Parmak izi bir GÜVENLİK değeri değildir; yalnızca "aynı sorgu mu" sorusunu
# yanıtlar. `digest` varsa kullanılır, yoksa saf R yedeği aynı kararlılığı
# sağlar (aynı girdi -> aynı çıktı, ASCII).
.pkgh_hash_text <- function(metin) {
  ham <- enc2utf8(as.character(metin %||% "")[1])
  if (is.na(ham)) ham <- ""

  if (requireNamespace("digest", quietly = TRUE)) {
    return(tryCatch(digest::digest(ham, algo = "sha256", serialize = FALSE),
                    error = function(e) NULL) %||% .pkgh_fallback_hash(ham))
  }
  .pkgh_fallback_hash(ham)
}

# FNV-1a benzeri yedek karma.
#
# BITWISE DURUM ISARETLI 32 BIT ARALIKTA TUTULUR. `bitwXor()` sayisal
# islenenleri `integer` turune ZORLAR; `2166136261` R'nin isaretli tam sayi
# ust siniri olan `2147483647` degerinin USTUNDE oldugu icin dogrudan
# verildiginde `NA` uretir (ve uyari basar). `digest` yoksa karmanin ilk
# bileseni bu yuzden GECERSIZ kalirdi. Bu nedenle durum, XOR'dan ONCE
# isaretli 32 bit temsile indirilir; carpma yine `%%` ile isaretsiz 32 bit
# alana geri tasinir.
.PKGH_UINT32 <- 4294967296

.pkgh_to_signed32 <- function(x) {
  kalan <- x %% .PKGH_UINT32
  if (kalan >= 2147483648) kalan <- kalan - .PKGH_UINT32
  as.integer(kalan)
}

.pkgh_fallback_hash <- function(ham) {
  baytlar <- as.integer(charToRaw(ham))
  if (!length(baytlar)) return("empty-0")
  h1 <- 2166136261
  h2 <- 5381
  for (b in baytlar) {
    karisik <- bitwXor(.pkgh_to_signed32(h1), .pkgh_to_signed32(b))
    # 32 BIT CARPMA IKI 16 BITLIK PARCAYA BOLUNUR. Tek adimda carpmak
    # (2^32 * 16777619 ~ 7.2e16) cift duyarlikli sayinin TAM tam sayi
    # araligini (2^53 ~ 9.0e15) ASAR; carpim `%%` calismadan ONCE yuvarlanir,
    # dusuk bitler kaybolur ve `h1` 8/16'nin kati olur (FNV avalanche ozelligi
    # gider, etkin genislik ~28 bite duser). Bu yol `digest` yokken calisir ve
    # devam onbellegi yeniden kullanimini kapiladigi icin zayif karma, DEGISMIS
    # bir sorgunun BAYAT semayi yeniden kullanma olasiligini artirirdi.
    taban <- as.numeric(karisik) %% .PKGH_UINT32
    alt <- taban %% 65536
    ust <- (taban - alt) / 65536
    # PARANTEZ ZORUNLUDUR: R'de `%%` onceligi `*` onceliginden YUKSEKTIR, bu
    # yuzden parantezsiz `ust * 16777619 %% 65536` ifadesi `ust * 403` olarak
    # cozulur (16777619 %% 65536 == 403). Ust yarinin FNV carpani hic
    # uygulanmaz; boluk-bolme yalnizca cift duyarlikli tasmayi onlemek icin
    # var oldugundan bu, karmayi ust 16 bitte sistematik olarak zayiflatir.
    h1 <- (alt * 16777619 + ((ust * 16777619) %% 65536) * 65536) %% .PKGH_UINT32
    h2 <- (h2 * 33 + b) %% .PKGH_UINT32
  }
  sprintf("%08x%08x-%d", as.integer(h1 %% 2147483647), as.integer(h2 %% 2147483647),
          length(baytlar))
}

# KANIT URETEN AYARLARIN IMZASI.
#
# `sample` kipinde onbellek yalnizca sema degil, TURETILMIS GOZLEM de tasir
# (`high_cardinality_proved`, `distinct_observed`). Bu gozlemler
# `MERGEN_PK_META_HIGH_CARD_MIN` ve `MERGEN_PK_META_SAMPLE_ROWS` degerlerine
# BAGLIDIR: esik 10'dan 50'ye cikarildiginda eski `TRUE` artik KANITLANMIS
# degildir; esik dusuruldugunde ise yeni kanitlanabilir sutunlar hesaplanmaz.
# Bu yuzden kanit ureten ayarlar parmak izine girer ve degistiklerinde ilgili
# onbellek girdileri REDDEDILIR.
#
# `describe` kipi bu ayarlarin HICBIRINI kullanmaz; imza bilerek bostur,
# boylece kalintili bir ornekleme ayari describe onbellegini gecersiz kilmaz.
.pkgh_evidence_signature <- function(config) {
  yap <- if (is.list(config)) config else list()
  kip <- as.character(yap$mode %||% "")[1]
  if (!identical(kip, "sample")) return("")

  satir <- suppressWarnings(as.integer(yap$sample_rows %||% NA_integer_)[1])
  esik <- suppressWarnings(as.integer(yap$high_cardinality_threshold %||% NA_integer_)[1])
  sprintf(
    "rows=%s;hc=%s",
    if (is.na(satir)) "?" else format(satir),
    if (is.na(esik)) "?" else format(esik)
  )
}

# Sorgunun ÇALIŞMA ZAMANI sonucunu metadata kapısından ÖNCE değiştiren yapısal
# beyanlarının imzası. `convert_date_columns()` SQL fetch'ten hemen sonra bu
# tam isimleri Date'e çevirir; dolayısıyla `date_columns` değişikliği aynı SQL
# metni için bile ETKİN `result_schema` değerini değiştirebilir.
.pkgh_runtime_schema_signature <- function(query) {
  tarih <- query$date_columns
  if (is.null(tarih)) return("date_columns=<null>")

  if (!is.character(tarih)) {
    deger <- tryCatch(as.character(tarih), error = function(e) character(0))
    deger[is.na(deger)] <- "<NA>"
    return(paste0(
      "date_columns=<", typeof(tarih), ">:",
      paste(enc2utf8(deger), collapse = "\u001e")
    ))
  }

  deger <- tarih
  deger[is.na(deger)] <- "<NA>"
  paste0("date_columns=", paste(enc2utf8(deger), collapse = "\u001e"))
}

# `sample` kipinde gerçek DB yürütmesi yalnızca açıkça güvenli kürasyonla
# yapılabilir. Bu bayrak önbellek girdisinde `sample_info` içine de taşındığı
# için değiştiğinde eski cache'i yeniden yayımlamak raporu mevcut politikadan
# farklı gösterir. Describe kipinde bu beyan ilgisizdir.
.pkgh_sample_policy_signature <- function(query, config) {
  kip <- as.character((config %||% list())$mode %||% "")[1]
  if (!identical(kip, "sample")) return("")
  paste0("meta_sample_safe=", if (isTRUE(query$meta_sample_safe)) "true" else "false")
}

#' Bir sorgunun KAYNAK parmak izi (SQL + hedef + etkin şema beyanı)
#'
#' YAYIMLANAN katman girdilerine damgalanır. Sorunun cevapladığı şey tektir:
#' "bu girdi HÂLÂ güncel sorgu sonucunu mu anlatıyor?". `date_columns` da
#' buraya girer, çünkü runtime metadata kapısından ÖNCE bu sütunları Date'e
#' dönüştürür. KANIT ÜRETEN örnekleme ayarları ise buraya GİRMEZ:
#' `MERGEN_PK_META_HIGH_CARD_MIN` değişmesi, yayımlanmış bir `result_schema`
#' değerini geçersiz KILMAZ.
pkgh_source_fingerprint <- function(query) {
  sql <- as.character(query$sql %||% "")[1]
  hedef <- as.character(query$db_target %||% "primary")[1]
  if (is.na(sql)) sql <- ""
  if (is.na(hedef)) hedef <- "primary"
  # AYIRICI ZORUNLUDUR: ayirici olmadan alan sinirlari kayabilir ve farkli iki
  # girdi ayni metne cozulebilir. `\u001f` (unit separator) ASCII'dir, kaynak
  # dosyada KACIS olarak yazilir ve uretim SQL metninde bulunmaz.
  .pkgh_hash_text(paste(
    hedef, sql, .pkgh_runtime_schema_signature(query), sep = "\u001f"
  ))
}

#' Bütün kütüphane için KAYNAK parmak izi haritası
pkgh_source_fingerprints <- function(query_library) {
  .pkgh_fingerprint_map(query_library, function(q) pkgh_source_fingerprint(q))
}

#' Bir sorgunun devam-önbelleği parmak izi
#'
#' KAYNAK parmak izinin üstüne (yalnızca `sample` kipinde) KANIT ÜRETEN
#' ayarların ve açık örnekleme güvenlik kürasyonunun imzası eklenir. Önbellek
#' yalnızca şema değil TÜRETİLMİŞ GÖZLEM ve örnekleme kanıtı da taşıdığı için,
#' eşik/satır sınırı ya da güvenli-örnekleme beyanı değiştiğinde eski kayıt
#' artık mevcut koşunun kanıtı değildir.
#'
#' @param config `pkg_meta_resolve_config()` çıktısı. `NULL` verildiğinde kanıt
#'   imzası boş kalır; bu yalnızca izole test/teşhis içindir, üretici giriş
#'   noktası HER ZAMAN gerçek yapılandırmayı geçirir.
pkgh_state_fingerprint <- function(query, config = NULL) {
  .pkgh_hash_text(paste(
    pkgh_source_fingerprint(query),
    .pkgh_evidence_signature(config),
    .pkgh_sample_policy_signature(query, config),
    sep = "\u001f"
  ))
}

#' Bütün kütüphane için devam-önbelleği parmak izi haritası
pkgh_state_fingerprints <- function(query_library, config = NULL) {
  .pkgh_fingerprint_map(query_library, function(q) pkgh_state_fingerprint(q, config))
}

.pkgh_fingerprint_map <- function(query_library, fn) {
  cikti <- list()
  if (!is.list(query_library)) return(cikti)
  for (q in query_library) {
    if (!is.list(q)) next
    id <- as.character(q$id %||% "")[1]
    if (is.na(id) || !nzchar(trimws(id))) next
    cikti[[trimws(id)]] <- fn(q)
  }
  cikti
}

# Adlandırılmış karakter vektörünü JSON'a uygun kayıt listesine çevir.
.pkgh_named_to_records <- function(sema, tipler) {
  unname(lapply(names(sema %||% character(0)), function(sutun) list(
    name = sutun,
    r_class = unname(sema[[sutun]]),
    source_type = if (sutun %in% names(tipler %||% character(0))) {
      unname(tipler[[sutun]])
    } else {
      NA_character_
    }
  )))
}

#' Devam (resume) önbelleği durumunu yaz
#'
#' Yazma başarısız olursa `FALSE` döner ve çağıran bunu UYARI olarak bildirir;
#' sessizce başarı raporlanmaz.
pkgh_write_state <- function(cache, state_path, mode, timestamp,
                             state_version = PKG_META_STATE_VERSION) {
  girdiler <- unname(lapply(names(cache %||% list()), function(id) {
    girdi <- cache[[id]]
    list(
      query_id = id,
      fingerprint = as.character(girdi$fingerprint %||% NA_character_)[1],
      rows_seen = girdi$rows_seen %||% NA_integer_,
      columns = .pkgh_named_to_records(girdi$columns, girdi$source_types),
      # KANIT ALANLARI DA TAŞINIR: yeniden kurulan boş değerler, ikinci bir
      # koşuda yüksek kardinalite gözlemlerini ve eşlenmeyen/sınırsız tip
      # bulgularını SESSİZCE düşürürdü.
      unmapped = girdi$unmapped %||% list(),
      unbounded = as.character(girdi$unbounded %||% character(0)),
      observations = girdi$observations %||% list(),
      sample_info = girdi$sample_info %||% list()
    )
  }))

  durum <- list(
    state_version = as.integer(state_version)[1],
    mode = mode,
    timestamp = timestamp,
    entries = girdiler
  )

  dizin <- dirname(state_path)
  if (!dir.exists(dizin)) dir.create(dizin, recursive = TRUE, showWarnings = FALSE)

  sonuc <- tryCatch({
    metin <- as.character(jsonlite::toJSON(
      pkgh_stabilize_report(durum), auto_unbox = TRUE, pretty = TRUE, null = "null"
    ))
    .pkgh_atomic_write_bytes(charToRaw(enc2utf8(metin)), state_path)
    TRUE
  }, error = function(e) FALSE)

  isTRUE(sonuc)
}

#' Devam durumunu KARANTİNAYA AL (kullanılamaz yap)
#'
#' NEDEN GEREKLİ: `pkgh_write_state()` ATOMİK yazar; SON durum yazımı
#' başarısız olduğunda diskte ÖNCEKİ GEÇERLİ anlık görüntü kalır. O anlık
#' görüntü hâlâ aynı kip/sürüm/parmak izlerini taşıdığı için SONRAKİ koşu
#' tarafından KABUL EDİLİR: koşu DB'ye hiç gitmez ve BAŞARILI koşudan ÖNCE
#' öğrenilmiş şemayı/kanıtı yeniden yayımlar. Bu, araya giren bir DB şema
#' değişikliğinde bayat metadata demektir.
#'
#' Dosya SİLİNMEZ, yeniden adlandırılır: operatör isterse inceleyebilir.
#'
#' @return list(ok, path) -- `path` karantina dosyası ya da NA.
pkgh_quarantine_state <- function(state_path) {
  if (!file.exists(state_path)) return(list(ok = TRUE, path = NA_character_))

  karantina <- sprintf("%s.stale-%s", state_path, format(Sys.time(), "%Y%m%d%H%M%S"))
  tasindi <- isTRUE(tryCatch(file.rename(state_path, karantina), error = function(e) FALSE))
  if (tasindi) return(list(ok = TRUE, path = karantina))

  # Yeniden adlandırma da düşerse SİLMEK, bayat bir anlık görüntüyü canlı
  # bırakmaktan daha güvenlidir: en kötü ihtimalle sonraki koşu bastan baslar.
  silindi <- isTRUE(tryCatch({
    unlink(state_path, force = TRUE)
    !file.exists(state_path)
  }, error = function(e) FALSE))

  list(ok = silindi, path = NA_character_)
}

#' Devam önbelleğini geri oku
#'
#' Kip DEĞİŞTİYSE önbellek YOK SAYILIR: `describe` ile alınmış bir şema
#' `sample` koşusunun gözlemlerini taşımaz. Biçim sürümü ya da PARMAK İZİ
#' uyuşmazsa o girdi (ya da tüm dosya) YOK SAYILIR.
#'
#' @param fingerprints `pkgh_state_fingerprints()` çıktısı. `NULL` verildiğinde
#'   parmak izi karşılaştırması YAPILMAZ; bu yalnızca izole test/teşhis içindir,
#'   üretici giriş noktası HER ZAMAN gerçek haritayı geçirir.
pkgh_read_state <- function(state_path, mode, fingerprints = NULL,
                            state_version = PKG_META_STATE_VERSION) {
  if (!file.exists(state_path)) return(list())

  tryCatch({
    ham <- jsonlite::fromJSON(state_path, simplifyVector = FALSE)
    if (!identical(as.character(ham$mode)[1], as.character(mode)[1])) return(list())

    surum <- suppressWarnings(as.integer(ham$state_version %||% NA_integer_)[1])
    if (is.na(surum) || !identical(surum, as.integer(state_version)[1])) return(list())

    # VERİTABANI KANITI EskİR: DEVAM DURUMU YALNIZCA KISA SÜRE GEÇERLİDİR.
    #
    # Parmak izleri SQL METNİNDEN ve yapılandırmadan türetilir. SQL değişmeden
    # arkadaki görünüm/tip değişirse (ör. `SELECT *` altında bir ALTER, tip
    # genişletme) parmak izi AYNI kalır ve normal bir yeniden koşu describe/
    # sample adımını tamamen ATLAR: üretilen `result_schema` süresiz BAYAT
    # kalabilirdi. Devam durumu bu yüzden yalnızca KESİLMİŞ bir koşuyu
    # sürdürecek kadar yaşar. `MERGEN_PK_META_RESUME_MAX_AGE_SEC` ile ayarlanır
    # (varsayılan 6 saat; `0` = süre sınırı yok, yalnızca teşhis içindir).
    azami_yas <- suppressWarnings(as.numeric(
      Sys.getenv("MERGEN_PK_META_RESUME_MAX_AGE_SEC", unset = "21600")
    )[1])
    if (is.na(azami_yas) || !is.finite(azami_yas) || azami_yas < 0) azami_yas <- 21600
    if (azami_yas > 0) {
      # Damga `pkg_meta_config()` içinde YEREL saatte "%Y%m%d-%H%M%S" biçiminde
      # üretilir; ayrıştırma da aynı biçimi ve yereli kullanır.
      ham_damga <- as.character(ham$timestamp %||% NA_character_)[1]
      damga <- suppressWarnings(strptime(ham_damga, format = "%Y%m%d-%H%M%S"))
      if (length(damga) != 1L || is.na(damga)) {
        damga <- suppressWarnings(as.POSIXct(ham_damga, optional = TRUE))
      }
      if (length(damga) != 1L || is.na(damga)) {
        # Damga okunamıyorsa DB kanıtı doğrulanamaz; yeniden sorgulanır.
        return(list())
      }
      yas <- suppressWarnings(as.numeric(difftime(Sys.time(), damga, units = "secs")))
      if (!is.finite(yas) || yas > azami_yas) return(list())
    }

    cikti <- list()
    for (girdi in (ham$entries %||% list())) {
      id <- as.character(girdi$query_id %||% "")[1]
      sutunlar <- girdi$columns %||% list()
      if (!nzchar(id) || !length(sutunlar)) next

      if (!is.null(fingerprints)) {
        beklenen <- fingerprints[[id]]
        kayitli <- as.character(girdi$fingerprint %||% NA_character_)[1]
        # Sorgu kütüphaneden kalkmış ya da SQL'i/yapısal sonucu değişmişse eski
        # şema o sorguyu TEMSİL ETMEZ; girdi atlanır ve sorgu yeniden sorgulanır.
        if (is.null(beklenen) || is.na(kayitli) || !identical(kayitli, beklenen)) next
      }

      adlar <- vapply(sutunlar, function(s) as.character(s$name)[1], character(1))
      siniflar <- vapply(sutunlar, function(s) as.character(s$r_class)[1], character(1))
      tipler <- vapply(sutunlar, function(s) {
        as.character(s$source_type %||% NA_character_)[1]
      }, character(1))

      sema <- stats::setNames(siniflar, adlar)
      kaynak <- stats::setNames(tipler, adlar)
      ornek_bilgi <- girdi$sample_info %||% list()
      ornek_bilgi$from_cache <- TRUE
      ornek_bilgi$mode <- ornek_bilgi$mode %||% mode

      cikti[[id]] <- list(
        ok = TRUE, schema = sema, source_types = kaynak,
        unmapped = girdi$unmapped %||% list(),
        unbounded = as.character(unlist(girdi$unbounded %||% character(0))),
        observations = girdi$observations %||% list(),
        rows_seen = girdi$rows_seen,
        sample_info = ornek_bilgi,
        cache = list(
          mode = mode, columns = sema, source_types = kaynak,
          fingerprint = as.character(girdi$fingerprint %||% NA_character_)[1],
          rows_seen = girdi$rows_seen,
          unmapped = girdi$unmapped %||% list(),
          unbounded = as.character(unlist(girdi$unbounded %||% character(0))),
          observations = girdi$observations %||% list(),
          sample_info = ornek_bilgi
        )
      )
    }
    cikti
  }, error = function(e) list())
}
