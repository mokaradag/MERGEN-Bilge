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
#   1) PARMAK İZİ. Bir girdi yalnızca SQL metni + db_target parmak izi AYNI
#      kaldığında kabul edilir. Aksi hâlde SELECT listesi değiştirilmiş bir
#      sorgu, eski şemasıyla sonsuza dek yeniden kullanılır ve üreticiyi tekrar
#      çalıştırmak bayat metadata'yı ONARAMAZ.
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

.pkgh_fallback_hash <- function(ham) {
  baytlar <- as.integer(charToRaw(ham))
  if (!length(baytlar)) return("empty-0")
  h1 <- 2166136261
  h2 <- 5381
  for (b in baytlar) {
    h1 <- (bitwXor(h1 %% 4294967296, b) * 16777619) %% 4294967296
    h2 <- (h2 * 33 + b) %% 4294967296
  }
  sprintf("%08x%08x-%d", as.integer(h1 %% 2147483647), as.integer(h2 %% 2147483647),
          length(baytlar))
}

#' Bir sorgunun devam-önbelleği parmak izi
#'
#' SQL metni ve hedef veritabanı girer. Bunlardan biri değiştiğinde eski şema
#' artık o sorguyu TEMSİL ETMEZ.
pkgh_state_fingerprint <- function(query) {
  sql <- as.character(query$sql %||% "")[1]
  hedef <- as.character(query$db_target %||% "primary")[1]
  if (is.na(sql)) sql <- ""
  if (is.na(hedef)) hedef <- "primary"
  .pkgh_hash_text(paste0(hedef, "", sql))
}

#' Bütün kütüphane için parmak izi haritası
pkgh_state_fingerprints <- function(query_library) {
  cikti <- list()
  if (!is.list(query_library)) return(cikti)
  for (q in query_library) {
    if (!is.list(q)) next
    id <- as.character(q$id %||% "")[1]
    if (is.na(id) || !nzchar(trimws(id))) next
    cikti[[trimws(id)]] <- pkgh_state_fingerprint(q)
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

    cikti <- list()
    for (girdi in (ham$entries %||% list())) {
      id <- as.character(girdi$query_id %||% "")[1]
      sutunlar <- girdi$columns %||% list()
      if (!nzchar(id) || !length(sutunlar)) next

      if (!is.null(fingerprints)) {
        beklenen <- fingerprints[[id]]
        kayitli <- as.character(girdi$fingerprint %||% NA_character_)[1]
        # Sorgu kütüphaneden kalkmış ya da SQL'i değişmişse eski şema o sorguyu
        # TEMSİL ETMEZ; girdi atlanır ve sorgu yeniden sorgulanır.
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
