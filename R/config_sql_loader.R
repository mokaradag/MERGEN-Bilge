# ==============================================================================
# R/config_sql_loader.R
# Dosya Yolu: R/config_sql_loader.R
# Aciklama: query_library icindeki sql_file tanimlarini zorunlu olarak yukler.
#           sql_file varsa, ilgili dosya her zaman okunur ve q_item$sql alani
#           dosya icerigi ile uzerine yazilir.
#           Dosya bulunamazsa veya okunamazsa uygulama durdurulur.
# ==============================================================================

# --- HATA AYIKLAMA MODU KONTROLU ---
.SQL_LOADER_DEBUG <- isTRUE(as.logical(Sys.getenv("MERGEN_DEBUG", "FALSE")))
.SQL_LOADER_STRICT <- !identical(
  tolower(Sys.getenv("MERGEN_SQL_LOADER_STRICT", "true")),
  "false"
)

# YER TUTUCU SQL ASLA ÇALIŞTIRILAMAZ.
#
# Metindeki `sql_loader_placeholder` işareti salt-okunur kapının
# (`R/helpers_pk_sql_readonly.R`, `PK_SQL_LOADER_PLACEHOLDER_MARKER`) REDDETME
# koşuludur. Yer tutucu sözdizimsel olarak geçerli bir SELECT olduğu için kapı
# onu kendiliğinden reddetmiyordu ve sahte tek satırlık bir sonuç
# döndürülebiliyordu. İşaret metni İKİ dosyada da AYNI olmak zorundadır;
# yükleyici kapıdan ÖNCE yüklendiği için sabit buraya kopyalanamaz, sözleşme
# `tests/testthat/test-pk-sql-readonly-gate-contract.R` ile korunur.
.sql_placeholder_text <- function(q_id) {
  sprintf(
    "SELECT '%s' AS QueryID, 'sql_loader_placeholder' AS LoaderStatus",
    q_id
  )
}

# --- YARDIMCI: BOS OLMAYAN KARAKTER KONTROLU ---
# KESIN MANTIKSAL DONUS: cagiran `if (has_sql_file)` icinde kullanir; NA veya
# sifir uzunluklu girdi burada FALSE olmalidir. `nzchar(NA)` varsayilan olarak
# TRUE dondurur ve `as.character(character(0))[1]` de NA uretir; ikisi de
# yukleyiciyi olmayan bir SQL dosyasini cozmeye zorlardi.
.sql_has_text <- function(x) {
  if (is.null(x) || length(x) == 0L) return(FALSE)

  deger <- suppressWarnings(as.character(x)[1])
  if (is.na(deger)) return(FALSE)

  nzchar(trimws(deger))
}

# --- YARDIMCI: SQL DOSYA YOLUNU COZ ---
.resolve_sql_file_path <- function(fpath) {
  fpath <- as.character(fpath)[1]
  fpath <- trimws(fpath)

  if (!nzchar(fpath)) {
    return(NULL)
  }

  aday_yollar <- unique(c(
    fpath,
    tryCatch(
      normalizePath(fpath, winslash = "/", mustWork = FALSE),
      error = function(e) NA_character_
    )
  ))

  aday_yollar <- aday_yollar[!is.na(aday_yollar) & nzchar(aday_yollar)]

  for (aday in aday_yollar) {
    if (file.exists(aday)) {
      return(aday)
    }
  }

  NULL
}

# --- YARDIMCI: UTF-8 BOM TEMIZLIGI ---
.remove_utf8_bom <- function(metin) {
  if (is.null(metin) || !nzchar(metin)) {
    return(metin)
  }

  ilk_karakter <- substr(metin, 1, 1)

  ilk_raw <- tryCatch(
    charToRaw(ilk_karakter),
    error = function(e) raw(0)
  )

  if (length(ilk_raw) >= 3 &&
      identical(as.integer(ilk_raw[1:3]), c(239L, 187L, 191L))) {
    return(substr(metin, 2, nchar(metin)))
  }

  metin
}

# --- YARDIMCI: SQL DOSYASINI GUVENLI OLARAK OKU ---
.read_sql_file_text <- function(path_to_use) {
  raw_size <- file.info(path_to_use)$size

  if (is.na(raw_size) || raw_size <= 0) {
    stop(sprintf("SQL dosyasi bos veya okunamadi: %s", path_to_use))
  }

  raw_content <- readBin(path_to_use, what = "raw", n = raw_size)

  if (length(raw_content) == 0L) {
    stop(sprintf("SQL dosyasi bos veya okunamadi: %s", path_to_use))
  }

  # Ham byte verisini belirtilen kodlamadan UTF-8'e cevirir
  decode_raw_with_encoding <- function(raw_vec, from_enc) {
    metin <- tryCatch(
      iconv(list(raw_vec), from = from_enc, to = "UTF-8", sub = NA)[[1]],
      error = function(e) NA_character_
    )

    if (is.na(metin)) {
      return(NULL)
    }

    # U+FEFF karakterini regex kullanmadan temizle
    bom_char <- intToUtf8(65279L)
    if (startsWith(metin, bom_char)) {
      metin <- substring(metin, 2L)
    }

    # Satir sonlarini normalize et
    metin <- gsub("\r\n?|\r", "\n", metin, perl = TRUE)

    if (!nzchar(trimws(metin))) {
      return(NULL)
    }

    metin
  }

  # UTF-16 BOM yoksa null byte dagilimina bakarak tahmin yap
  detect_utf16_from_nuls <- function(raw_vec) {
    n <- min(length(raw_vec), 512L)

    if (n < 8L) {
      return(NULL)
    }

    bytes <- as.integer(raw_vec[seq_len(n)])

    tek_indeks <- bytes[seq(1L, n, by = 2L)]
    cift_indeks <- bytes[seq(2L, n, by = 2L)]

    tek_sifir_orani <- if (length(tek_indeks)) mean(tek_indeks == 0L) else 0
    cift_sifir_orani <- if (length(cift_indeks)) mean(cift_indeks == 0L) else 0

    # ASCII agirlikli UTF-16 LE dosyalarda cift byte'larda sifir yogun olur
    if (cift_sifir_orani > 0.20 && tek_sifir_orani < 0.05) {
      return("UTF-16LE")
    }

    # ASCII agirlikli UTF-16 BE dosyalarda tek byte'larda sifir yogun olur
    if (tek_sifir_orani > 0.20 && cift_sifir_orani < 0.05) {
      return("UTF-16BE")
    }

    NULL
  }

  ilk_bytes <- as.integer(raw_content[seq_len(min(length(raw_content), 4L))])

  # UTF-8 BOM: EF BB BF
  if (length(ilk_bytes) >= 3L &&
      identical(ilk_bytes[1:3], c(239L, 187L, 191L))) {
    metin <- decode_raw_with_encoding(raw_content[-(1:3)], "UTF-8")
    if (!is.null(metin)) {
      return(metin)
    }
  }

  # UTF-16 LE BOM: FF FE
  if (length(ilk_bytes) >= 2L &&
      identical(ilk_bytes[1:2], c(255L, 254L))) {
    metin <- decode_raw_with_encoding(raw_content[-(1:2)], "UTF-16LE")
    if (!is.null(metin)) {
      return(metin)
    }
  }

  # UTF-16 BE BOM: FE FF
  if (length(ilk_bytes) >= 2L &&
      identical(ilk_bytes[1:2], c(254L, 255L))) {
    metin <- decode_raw_with_encoding(raw_content[-(1:2)], "UTF-16BE")
    if (!is.null(metin)) {
      return(metin)
    }
  }

  # BOM yoksa UTF-16 tahmini yap
  guessed_utf16 <- detect_utf16_from_nuls(raw_content)
  if (!is.null(guessed_utf16)) {
    metin <- decode_raw_with_encoding(raw_content, guessed_utf16)
    if (!is.null(metin)) {
      return(metin)
    }
  }

  # Sonra tek baytli / UTF-8 kodlamalari dene
  for (kodlama in c("UTF-8", "WINDOWS-1254", "latin1")) {
    metin <- decode_raw_with_encoding(raw_content, kodlama)
    if (!is.null(metin)) {
      return(metin)
    }
  }

  stop(sprintf("SQL dosyasi uygun kodlama ile okunamadi: %s", path_to_use))
}

# --- library_queries.R manifest sırası ile önceden yüklenmiş olmalı ---
#
# ARAMA `globalenv()` İLE SINIRLI DEĞİLDİR. Faz 6 PK işçisi manifest
# dosyalarını önce bir SAHNELEME ortamına yükler ve `globalenv()`'e ancak
# TAMAMI başarılı olduğunda taşır. `envir = globalenv(), inherits = FALSE`
# sabitlemesi, `R/library_queries.R` bu dosyadan hemen ÖNCE başarıyla
# yüklenmiş olsa bile bu guard'ın PATLAMASINA yol açıyordu; sonuç temiz bir
# PSOCK işçisinde kalıcı `bootstrap_failed` ve her istekte senkron yedekti.
# `environment()` bu dosyanın yüklendiği ortamdır (ana süreçte `globalenv()`),
# dolayısıyla üretim davranışı DEĞİŞMEZ; yalnızca sahneleme ortamı da görünür.
#
# OKUMA VE YAZMA AYNI ORTAMDA OLMALIDIR.
#
# `exists(..., inherits = TRUE)` ÜST ortamdaki bir `query_library` kopyasını da
# kabul eder; buna karşılık `query_library[[i]]$sql <- ...` ve
# `query_library <- pk_query_meta_attach(...)` atamaları R'de HER ZAMAN GEÇERLİ
# ortamda yeni bir bağ oluşturur. Sonuç: yükleyici ÜST kopyayı okuyup YEREL bir
# kopyaya yazardı. Sahneleme ortamında `R/library_queries.R` atlandığında ya da
# başarısız olduğunda, önceki bir bootstrap'tan `globalenv()`'de kalan BAYAT
# envanter okunur, metadata ona iliştirilir ve boot "doğrulandı" derdi.
# Miras alınan değer bu yüzden ÖNCE bu ortama TAŞINIR ve yüksek sesle bildirilir.
.sql_loader_env <- environment()
if (!exists("query_library", envir = .sql_loader_env, inherits = FALSE)) {
  .sql_inherited <- exists("query_library", envir = .sql_loader_env, inherits = TRUE) &&
    is.list(get("query_library", envir = .sql_loader_env, inherits = TRUE))
  if (isTRUE(.sql_inherited)) {
    warning(
      "[SQL_LOADER] query_library bu ortamda TANIMLI DEĞİL; ÜST ortamdan miras alınan kopya kullanılıyor. ",
      "R/library_queries.R bu dosyayla AYNI ortama yüklenmelidir.",
      call. = FALSE
    )
    assign(
      "query_library",
      get("query_library", envir = .sql_loader_env, inherits = TRUE),
      envir = .sql_loader_env
    )
  }
  rm(.sql_inherited)
}

if (!exists("query_library", envir = .sql_loader_env, inherits = FALSE) ||
    !is.list(get("query_library", envir = .sql_loader_env, inherits = FALSE))) {
  stop(
    "[SQL_LOADER] HATA: query_library bulunamadı. R/library_queries.R, R/config_sql_loader.R öncesinde manifestten yüklenmelidir.",
    call. = FALSE
  )
}

# --- SAYACLAR ---
.sql_total_count <- length(query_library)
.sql_file_declared_count <- 0L
.sql_inline_only_count <- 0L
.sql_loaded_count <- 0L
.sql_failed_count <- 0L
.sql_overwritten_count <- 0L
.sql_missing_id_count <- 0L
.sql_failed_items <- character(0)

cat(sprintf("[SQL_LOADER] getwd() = %s\n", getwd()))
cat(sprintf("[SQL_LOADER] query_library uzunlugu = %d\n", .sql_total_count))

# --- ZORUNLU SQL DOSYA YUKLEME ---
for (i in seq_along(query_library)) {
  q_item <- query_library[[i]]

  q_id <- if (.sql_has_text(q_item$id)) {
    as.character(q_item$id)[1]
  } else {
    .sql_missing_id_count <- .sql_missing_id_count + 1L
    sprintf("index_%d", i)
  }

  has_sql_file <- .sql_has_text(q_item[["sql_file"]])
  # `$` KISMİ EŞLEŞME YAPAR: `sql` alanı YOKKEN `q_item$sql`, `sql_file`
  # değerine düşer ve satır içi SQL varmış gibi görünürdü. Sonuç: eksik/
  # okunamayan dosya için yer tutucu yerine DOSYA YOLU saklanıyor ve giriş
  # "üzerine yazıldı" sayılıyordu.
  has_sql_inline <- .sql_has_text(q_item[["sql"]])

  if (has_sql_file) {
    .sql_file_declared_count <- .sql_file_declared_count + 1L

    fpath <- as.character(q_item[["sql_file"]])[1]
    path_to_use <- .resolve_sql_file_path(fpath)

    if (is.null(path_to_use)) {
      .sql_failed_count <- .sql_failed_count + 1L
      .sql_failed_items <- c(
        .sql_failed_items,
        sprintf("ID: %s | Yol: %s | Hata: dosya bulunamadi", q_id, fpath)
      )

      if (isTRUE(.SQL_LOADER_STRICT)) {
        cat(sprintf(
          "[SQL_LOADER] HATA: SQL dosyasi bulunamadi! ID: %s, Yol: %s\n",
          q_id, fpath
        ))

        if (.SQL_LOADER_DEBUG) {
          cat(sprintf(
            "[SQL_LOADER] Denenen normalize yol: %s\n",
            tryCatch(normalizePath(fpath, winslash = "/", mustWork = FALSE), error = function(e) fpath)
          ))
        }

        next
      }

      cat(sprintf(
        "[SQL_LOADER] UYARI: SQL dosyasi bulunamadi; placeholder SQL atanıyor. ID: %s, Yol: %s\n",
        q_id, fpath
      ))

      # KORUNAN SATIR İÇİ SQL YER TUTUCU DEĞİLDİR: `sql_source` gerçek
      # kaynağı bildirmelidir, aksi hâlde çalıştırılabilir bir sorgu
      # aşağı akışta "yer tutucu" sanılırdı.
      if (has_sql_inline) {
        query_library[[i]]$sql <- as.character(q_item[["sql"]])[1]
        query_library[[i]]$sql_source <- "inline_missing_sql_file"
      } else {
        query_library[[i]]$sql <- .sql_placeholder_text(q_id)
        query_library[[i]]$sql_source <- "placeholder_missing_sql_file"
      }
      query_library[[i]]$sql_loaded_path <- NA_character_

      next
    }

    full_sql <- tryCatch(
      .read_sql_file_text(path_to_use),
      error = function(e) e
    )

    if (inherits(full_sql, "error")) {
      .sql_failed_count <- .sql_failed_count + 1L
      .sql_failed_items <- c(
        .sql_failed_items,
        sprintf("ID: %s | Yol: %s | Hata: %s", q_id, path_to_use, conditionMessage(full_sql))
      )

      if (isTRUE(.SQL_LOADER_STRICT)) {
        cat(sprintf(
          "[SQL_LOADER] HATA: SQL dosyasi okunamadi! ID: %s, Yol: %s | Hata: %s\n",
          q_id, path_to_use, conditionMessage(full_sql)
        ))

        next
      }

      cat(sprintf(
        "[SQL_LOADER] UYARI: SQL dosyasi okunamadi; placeholder SQL atanıyor. ID: %s, Yol: %s | Hata: %s\n",
        q_id, path_to_use, conditionMessage(full_sql)
      ))

      # Aynı gerekçe: okunamayan dosyada KORUNAN satır içi SQL yer tutucu
      # değildir ve öyle etiketlenmemelidir.
      if (has_sql_inline) {
        query_library[[i]]$sql <- as.character(q_item[["sql"]])[1]
        query_library[[i]]$sql_source <- "inline_sql_read_error"
      } else {
        query_library[[i]]$sql <- .sql_placeholder_text(q_id)
        query_library[[i]]$sql_source <- "placeholder_sql_read_error"
      }
      query_library[[i]]$sql_loaded_path <- path_to_use

      next
    }

    if (has_sql_inline) {
      .sql_overwritten_count <- .sql_overwritten_count + 1L
    }

    query_library[[i]]$sql <- full_sql
    query_library[[i]]$sql_source <- "sql_file"
    query_library[[i]]$sql_loaded_path <- path_to_use

    .sql_loaded_count <- .sql_loaded_count + 1L

    if (.SQL_LOADER_DEBUG) {
      cat(sprintf(
        "[SQL_LOADER] OK: %s (%s) -> %d karakter\n",
        q_id, path_to_use, nchar(full_sql, type = "chars")
      ))
    }

  } else if (has_sql_inline) {
    .sql_inline_only_count <- .sql_inline_only_count + 1L
    query_library[[i]]$sql_source <- "inline"
    query_library[[i]]$sql_loaded_path <- NA_character_

  } else {
    .sql_failed_count <- .sql_failed_count + 1L
    .sql_failed_items <- c(
      .sql_failed_items,
      sprintf("ID: %s | Hata: ne sql_file ne de sql tanimli", q_id)
    )

    cat(sprintf(
      "[SQL_LOADER] HATA: Sorguda ne sql_file ne de sql tanimli! ID: %s\n",
      q_id
    ))

    if (!isTRUE(.SQL_LOADER_STRICT)) {
      # DİĞER İKİ BAŞARISIZLIK YOLUYLA AYNI DEGRADASYON UYGULANIR. Bu dal
      # yalnızca sayıyor ve `sql` alanını YOK bırakıyordu; non-strict modda
      # `pk_query_meta_attach()` "bos olmayan SQL tasimalidir" diyerek AÇILIŞI
      # DÜŞÜRÜYORDU. Belgelenen degradasyon bu başarısızlık sınıfı için de
      # geçerlidir; yer tutucu SQL asla çalıştırılamaz (kapı reddeder).
      query_library[[i]]$sql <- .sql_placeholder_text(q_id)
      query_library[[i]]$sql_source <- "placeholder_missing_sql"
      query_library[[i]]$sql_loaded_path <- NA_character_
    }
  }
}

cat(sprintf("[SQL_LOADER] sql_file sayisi = %d\n", .sql_file_declared_count))
cat(sprintf("[SQL_LOADER] dosyadan yuklenen sayi = %d\n", .sql_loaded_count))
cat(sprintf("[SQL_LOADER] inline-only sayisi = %d\n", .sql_inline_only_count))
cat(sprintf("[SQL_LOADER] uzerine yazilan sql sayisi = %d\n", .sql_overwritten_count))
cat(sprintf("[SQL_LOADER] basarisiz sayi = %d\n", .sql_failed_count))

if (.sql_failed_count > 0L) {
  cat("[SQL_LOADER] BASARISIZ OGELER:\n")
  for (item in .sql_failed_items) {
    cat(sprintf("[SQL_LOADER] - %s\n", item))
  }

  if (isTRUE(.SQL_LOADER_STRICT)) {
    stop(sprintf(
      "[SQL_LOADER] HATA: %d adet SQL yuklenemedi. Uygulama durduruluyor.",
      .sql_failed_count
    ))
  }

  warning(sprintf(
    "[SQL_LOADER] UYARI: %d adet SQL yuklenemedi; non-strict modda placeholder SQL ile devam ediliyor.",
    .sql_failed_count
  ))
}

cat(sprintf(
  "[SQL_LOADER] Tamamlandi: %d/%d sql_file dosyadan zorunlu yuklendi, %d sorgu inline-only.\n",
  .sql_loaded_count, .sql_file_declared_count, .sql_inline_only_count
))

# --- FAZ 3a: SORGU METADATA SÖZLEŞMESİ ----------------------------------------
# Katmanlar (iskelet -> üretilen -> küre edilmiş, küre edilmiş kazanır) burada
# birleştirilir, yalnızca-alias yerel bindirmesi uygulanır ve sözleşme
# doğrulanır. Şemadan BAĞIMSIZ her geçersiz sözleşme başlangıcı DÜŞÜRÜR; bu
# bilinçli olarak .SQL_LOADER_STRICT bayrağından bağımsızdır, çünkü geçersiz
# metadata ile açılan bir uygulama sessizce yanlış cevap üretir.
#
# Şema henüz yoksa (bulut checkout'u; üretici VM'de çalışmadı) şemaya bağlı
# kontroller `pending_no_schema` olarak kaydedilir ve sorgu belgelenmiş Tier-0
# yapısal yolundan boot eder. Bu ERTELEME, istek zamanı zorlamayı zayıflatmaz:
# SQL döndükten sonraki gerçek sütun doğrulaması koşulsuzdur.
#
# `pk_query_metadata` manifest bölümü bu dosyadan ÖNCE biter; yardımcı yoksa
# manifest sırası bozulmuş ya da sahneleme ortamı kısmi yüklenmiştir. Bu
# durumda BOOT DÜŞER: bir `cat()` uyarısı boot kapısı değildir ve doğrulanmamış
# metadata ile açılan uygulama sessizce yanlış cevap üretir.
if (!exists("pk_query_meta_attach", mode = "function")) {
  stop(
    "[SQL_LOADER] HATA: pk_query_meta_attach bulunamadı. ",
    "R/helpers_pk_query_meta.R, R/config_sql_loader.R öncesinde manifestten yüklenmelidir.",
    call. = FALSE
  )
}

# YÜKLEME ORTAMI AÇIKÇA GEÇİLİR.
#
# PK işçisi manifest dosyalarını önce bir SAHNELEME ortamında değerlendirir.
# Varsayılan `envir = globalenv()` ile metadata katmanları (`pk_query_meta*`,
# `pk_query_aliases_local`, `pk_capability_registry`) yanlış ortamdan
# toplanıyordu: temiz bir işçi BOŞ katmanları doğrular, YENİDEN KULLANILAN bir
# işçi ise ÖNCEKİ bootstrap'tan kalan BAYAT katmanları iliştirebilirdi.
# Üretimde bu dosya `globalenv()` içine kaynaklandığından `environment()` zaten
# `globalenv()`tir; davranış değişmez.
query_library <- pk_query_meta_attach(query_library, envir = .sql_loader_env)

cat(sprintf(
  "[SQL_LOADER] PK metadata sözleşmesi doğrulandı: %d sorgu.\n",
  length(query_library)
))

# --- GECICI NESNELERI TEMIZLE ---
rm(
  .sql_loader_env,
  .SQL_LOADER_DEBUG,
  .SQL_LOADER_STRICT,
  .sql_placeholder_text,
  .sql_total_count,
  .sql_file_declared_count,
  .sql_inline_only_count,
  .sql_loaded_count,
  .sql_failed_count,
  .sql_overwritten_count,
  .sql_missing_id_count,
  .sql_failed_items,
  .sql_has_text,
  .resolve_sql_file_path,
  .remove_utf8_bom,
  .read_sql_file_text
)