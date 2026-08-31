# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_filters.R
# Açıklama: AI filtre motoru için uyumluluk yüzeyi ve Faz 0 gözlem bağdaştırıcısı.
#           Karar veren v1 motoru helpers_pk_analysis_filters_base.R içinde
#           korunur. Bu dosya, filtre yürütmesini TEK GEÇİŞTE gözlemler; aynı R
#           ifadesini telemetri amacıyla ikinci kez değerlendirmez.
# ==============================================================================

# TEMEL DOSYA KAYNAK MANİFESTİ TARAFINDAN YÜKLENİR.
#
# `R/config_source_manifest.R`, `helpers_pk_analysis_filters_base.R` dosyasını
# bu dosyadan HEMEN ÖNCE yükler. Buradaki eski blok, kardeş dosyayı çalışma
# zamanında `sys.frame()$ofile` ve aday yol taramasıyla bulup düz `source()`
# ile yüklüyordu; bu, manifest sahipliğini ve `safe_source()` sözleşmesini
# bypass eden gizli/dinamik bir yükleme yoluydu. Kaldırıldı: izole
# `testthat::test_file(...)` çalıştırmaları temel dosyayı AÇIKÇA source
# etmelidir (repo genelindeki izole-yükleme kuralıyla aynı).

if (!exists(".pk_filter_observation_state", inherits = FALSE) ||
    !is.environment(.pk_filter_observation_state)) {
  .pk_filter_observation_state <- new.env(parent = emptyenv())
}

# EKLEME SIRASI: sınırsız büyümeyi engelleyen LRU benzeri tahliye için tutulur.
if (!exists(".pk_filter_observation_order", inherits = FALSE) ||
    !is.environment(.pk_filter_observation_order)) {
  .pk_filter_observation_order <- new.env(parent = emptyenv())
  .pk_filter_observation_order$keys <- character(0)
}

# Süreç ömrü boyunca tutulacak en fazla gözlem kaydı.
.pk_filter_observation_cap <- function() {
  ham <- suppressWarnings(as.integer(getOption("mergen.pk.filter_observation_max", 256L))[1])
  if (length(ham) != 1L || is.na(ham) || ham < 1L) 256L else ham
}

.pk_filter_observation_scalar <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  out <- as.character(x)[1]
  if (is.na(out)) "" else out
}

.pk_filter_observation_key <- function(request_id, query_id, query_name, question) {
  paste(
    .pk_filter_observation_scalar(request_id),
    .pk_filter_observation_scalar(query_id),
    .pk_filter_observation_scalar(query_name),
    .pk_filter_observation_scalar(question),
    sep = "\u001f"
  )
}

.pk_filter_observation_context <- function(user_prompt) {
  request_id <- NULL
  query_meta <- NULL
  session_obj <- NULL

  for (fr in rev(sys.frames())) {
    if (is.null(request_id) && exists("pk_request_id", envir = fr, inherits = FALSE)) {
      request_id <- get("pk_request_id", envir = fr, inherits = FALSE)
    }

    if (is.null(query_meta)) {
      for (nm in c("selected_query", "query")) {
        if (exists(nm, envir = fr, inherits = FALSE)) {
          candidate <- get(nm, envir = fr, inherits = FALSE)
          if (is.list(candidate)) {
            query_meta <- candidate
            break
          }
        }
      }
    }

    if (is.null(session_obj) && exists("session", envir = fr, inherits = FALSE)) {
      candidate_session <- get("session", envir = fr, inherits = FALSE)
      if (!is.null(candidate_session)) session_obj <- candidate_session
    }
  }

  if ((is.null(request_id) || !nzchar(.pk_filter_observation_scalar(request_id))) &&
      !is.null(session_obj) &&
      exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
    request_id <- tryCatch(
      pk_provenance_current_request_id(session_obj),
      error = function(e) NULL
    )
  }

  list(
    request_id = request_id,
    query_id = query_meta$id %||% NULL,
    query_name = query_meta$name %||% NULL,
    query_meta = query_meta,
    question = user_prompt
  )
}

.pk_filter_dropped <- function(filter, reason) {
  list(filter = filter %||% list(), reason = as.character(reason)[1])
}

# v2 derleyicisinin normalleştirilmiş yaprağını v1 filtre şekline çevirir.
#
# Gözlem hattının tamamı (köken alt bilgisi `.pk_footer_filter_line()` ve
# düşürülen filtre bozulma metni `.pk_dropped_filter_degradations()`) `f$value`
# alanını okur; normalleştirilmiş yaprakta ise alan adı ÇOĞULdur (`values`).
# BUGÜN bu bir kusur DEĞİLDİR: `$` listelerde kısmi ad eşleştirmesi yaptığı için
# `f$value` sessizce `values`'a çözülür ve alt bilgi doğru yazar. Ancak bu
# kurtarma tesadüfidir ve iki yolla sessizce kaybolur: `[[` kısmi eşleştirme
# YAPMAZ ve yaprağa "value" ile başlayan ikinci bir alan (ör. `value_label`)
# eklendiği an eşleştirme belirsizleşip NULL döner. Sonuç, kullanıcının gördüğü
# `ProjeAdi = "" (içerir)` satırı olurdu. Şekil bu yüzden AÇIKÇA çevrilir;
# telemetri/köken tarafı da her iki motorda tek bir filtre şekli görür.
.pk_filter_leaf_to_v1 <- function(leaf) {
  leaf <- if (is.list(leaf)) leaf else list()

  deger <- leaf$values %||% leaf$value %||% character(0)

  # SENTETİK GRUP ADI KULLANICIYA GÖSTERİLMEZ.
  #
  # v2 değerlendirilemeyen bir mantık grubunu düşürdüğünde düşen yaprak
  # sentetik `__group__` sütununu taşır; bu kayıt düşen-filtre bozulma metnini
  # besler ve kullanıcı alan adı yerine bir İÇ TOKEN okurdu.
  ad <- as.character(leaf$column %||% "?")[1]
  if (identical(ad, "__group__")) ad <- "(koşul grubu)"

  list(
    column = ad,
    value = as.character(deger),
    operation = as.character(leaf$operation %||% "exact_match")[1]
  )
}

# İSTEK KİMLİĞİ OLMADAN SAKLAMA YAPILMAZ (kapalı başarısız).
#
# Anahtar `request_id + query_id + query_name + question` birleşimidir. İstek
# kimliği çözülemediğinde bileşen BOŞ kalır; aynı sorguya aynı soruyu soran İKİ
# EŞZAMANLI KULLANICI o zaman TEK bir anahtarı paylaşır ve ikinci saklama
# birincisini ezer. Sonuç, bir kullanıcının köken alt bilgisinde BAŞKA bir
# kullanıcının `matched_rows` değerinin yayımlanmasıdır. Kimliksiz kayıt artık
# hiç saklanmaz: alt bilgi yoksa yanlış alt bilgiden iyidir.
#
# Ayrıca ortam SINIRLIDIR. `pk_filter_observation_take()` tek kaldırma yoludur;
# alınmayan her kayıt (v2 reddi, çağıran hatası, iptal edilen istek) süreç ömrü
# boyunca kalırdı. Ekleme sırasına göre en eski kayıtlar tahliye edilir.
.pk_filter_observation_store <- function(context, observation) {
  istek <- .pk_filter_observation_scalar(context$request_id)
  if (!nzchar(istek)) {
    cat("[PK_OBSERVE] İstek kimliği çözülemedi; gözlem kaydı saklanmadı.\n")
    return(invisible(observation))
  }

  key <- .pk_filter_observation_key(
    istek,
    context$query_id,
    context$query_name,
    context$question
  )
  observation$query_meta <- context$query_meta
  assign(key, observation, envir = .pk_filter_observation_state)

  sira <- .pk_filter_observation_order$keys
  sira <- c(sira[sira != key], key)
  tavan <- .pk_filter_observation_cap()
  if (length(sira) > tavan) {
    eski <- sira[seq_len(length(sira) - tavan)]
    sira <- sira[-seq_len(length(sira) - tavan)]
    for (k in eski) {
      if (exists(k, envir = .pk_filter_observation_state, inherits = FALSE)) {
        rm(list = k, envir = .pk_filter_observation_state)
      }
    }
  }
  .pk_filter_observation_order$keys <- sira
  invisible(observation)
}

pk_filter_observation_take <- function(info) {
  info <- if (is.list(info)) info else list()
  key <- .pk_filter_observation_key(
    info$request_id,
    info$query_id,
    info$query_name,
    info$question
  )

  if (!exists(key, envir = .pk_filter_observation_state, inherits = FALSE)) return(NULL)

  observation <- get(key, envir = .pk_filter_observation_state, inherits = FALSE)
  rm(list = key, envir = .pk_filter_observation_state)
  .pk_filter_observation_order$keys <-
    .pk_filter_observation_order$keys[.pk_filter_observation_order$keys != key]
  observation
}

#' Filtreleri uygula ve aynı yürütme sırasında gözlem bilgisini kaydet
#'
#' Kritik sözleşme: filter_expression yalnızca bir kez değerlendirilir. Uygulanan
#' filtreler, düşürülen filtreler ve toplulaştırma öncesi eşleşen satır sayısı,
#' gerçek motor geçişinden alınır; telemetri için kod yeniden çalıştırılmaz.
apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  cat(sprintf("[SMART_FILTER] Baslangic satir: %d\n", nrow(data)))

  context <- .pk_filter_observation_context(user_prompt)
  applied <- list()
  dropped <- list()

  # `context$query_meta` çağrı çerçevesinden toplanan TAM sorgu nesnesidir
  # (`selected_query`), sorgunun metadata bloğu DEĞİLDİR. Motor kipi bu yüzden
  # modülün okuduğu alanla AYNI yerden çözülmelidir: `selected_query$meta`.
  # Tam nesneyi vermek `pk_config_resolve()`'un metadata basamağını
  # `selected_query$engine` üzerinden okumasına yol açıyor ve modül ile filtre
  # motoru farklı kipe düşebiliyordu: modül v2 sanıp politika/bütçe uygularken
  # filtreler v1 gövdesinde kalıyor, D1-D5 sessizce devre dışı kalıyordu.
  motor_meta <- if (is.list(context$query_meta)) context$query_meta$meta else NULL

  # Motor sınırı (master plan §10): D1-D5/D12 YALNIZCA v2'de etkindir. v1
  # gövdesi aşağıda değişmeden korunur; bayrak v1 iken bu dal hiç çalışmaz.
  if (exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
      isTRUE(pk_engine_is_v2(motor_meta)) &&
      exists("pk_apply_smart_filters_v2", mode = "function", inherits = TRUE)) {

    # Yürütücüye TAM sorgu nesnesi verilir; `pk_meta_primary_entity()` birincil
    # varlığı `query$meta` üzerinden okur ve metadata bloğunu kendi çözer.
    sonuc_v2 <- pk_apply_smart_filters_v2(data, filter_instructions, context$query_meta)
    karar <- attr(sonuc_v2, PK_FILTER_V2_ATTR, exact = TRUE)

    try(
      .pk_filter_observation_store(context, list(
        matched_rows = as.integer(karar$matched_rows %||% nrow(sonuc_v2)),
        # Yapraklar v1 filtre şekline çevrilir; köken alt bilgisi ve düşürülen
        # filtre uyarısı `value` alanını okur (bkz. .pk_filter_leaf_to_v1).
        applied_filters = lapply(karar$applied %||% list(), .pk_filter_leaf_to_v1),
        dropped_filters = lapply(karar$dropped %||% list(), function(d) {
          .pk_filter_dropped(.pk_filter_leaf_to_v1(d$leaf), d$reason)
        })
      )),
      silent = TRUE
    )

    return(sonuc_v2)
  }

  finish <- function(result, matched_rows) {
    try(
      .pk_filter_observation_store(context, list(
        matched_rows = as.integer(matched_rows),
        applied_filters = applied,
        dropped_filters = dropped
      )),
      silent = TRUE
    )
    result
  }

  # BOŞ SONUÇTA DA `count` OTORİTER CEVABI SIFIRDIR (v2 ile AYNI sözleşme).
  #
  # Bu erken dönüş toplulaştırma anahtarından ÖNCE çalışıyordu; geçerli bir
  # `aggregation = "count"` isteği sıfır satır/sıfır sütunluk bir çerçeveye
  # düşüyor, aşağı akış ise bunu "veri yok" diye anlatıyordu. Oysa sorunun
  # DOĞRU cevabı `Adet = 0`dır. v1 varsayılan motor olduğundan bu yol üretimde
  # ulaşılabilirdir.
  if (nrow(data) == 0) {
    agg_bos <- if (exists("pk_ascii_token", mode = "function", inherits = TRUE)) {
      pk_ascii_token(as.character(filter_instructions$aggregation %||% "")[1])
    } else {
      chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz",
             trimws(as.character(filter_instructions$aggregation %||% "")[1]))
    }
    if (identical(agg_bos, "count")) {
      aciklama <- if (length(filter_instructions$filters %||% list()) > 0) {
        "Filtrelenen Kayıt Sayısı"
      } else {
        "Toplam Kayıt Sayısı"
      }
      return(finish(
        data.frame(Sonuc = aciklama, Adet = 0L, stringsAsFactors = FALSE),
        0L
      ))
    }
    return(finish(data.frame(), 0L))
  }

  dt <- data.table::as.data.table(data)

  filters <- filter_instructions$filters
  # TOPLULAŞTIRMA DA TEK KARAKTER DEĞERE İNDİRGENİR (grup sütunuyla aynı gerekçe).
  aggregation <- .pk_filter_scalar_token(filter_instructions$aggregation)
  # GRUPLAMA SÜTUNU TEK BİR KARAKTER DEĞERE İNDİRGENİR.
  #
  # `simplifyVector = FALSE` ile ayrıştırılan model çıktısında birden çok grup
  # sütunu LİSTE olarak gelir. `group_col %in% names(dt)` o zaman uzunluğu
  # birden büyük bir vektör üretir ve R 4.3+ `&&` içinde HATA fırlatır; ayrıca
  # `by =` argümanına liste geçmek data.table tarafında tanımsız davranıştır.
  group_col <- local({
    ham <- filter_instructions$group_column
    if (is.null(ham)) return(NULL)
    duz <- unlist(ham, use.names = FALSE)
    duz <- as.character(duz)
    duz <- duz[!is.na(duz) & nzchar(trimws(duz))]
    if (!length(duz)) return(NULL)
    trimws(duz[1])
  })

  genel_soru_kaliplari <- c(
    "kaç", "toplam", "sayı", "adet", "hangi", "dağılım", "özet",
    "analiz", "liste", "göster", "tüm", "hepsi", "en fazla",
    "en az", "ortalama", "maksimum", "minimum"
  )

  prompt_lower <- tolower(user_prompt)
  genel_soru_mu <- any(sapply(genel_soru_kaliplari, function(pattern) {
    grepl(pattern, prompt_lower, fixed = TRUE)
  }))

  spesifik_varlik_var <- grepl("\\b[A-Z][0-9]{3,}\\b|\\b[A-Z]{1,3}[0-9]{1,}\\b", user_prompt, perl = TRUE) ||
    grepl("[A-ZÜĞIŞÖÇ][a-züğışöç]+ [A-ZÜĞIŞÖÇ][a-züğışöç]+", user_prompt, perl = TRUE)

  if (genel_soru_mu && !spesifik_varlik_var && (is.null(filters) || length(filters) == 0)) {
    cat("[SMART_FILTER] GENEL SORU tespit edildi, filtre UYGULANMAYACAK.\n")
    filters <- list()
  }

  cat(sprintf(
    "[SMART_FILTER] Filtre sayisi: %d (Genel soru: %s, Spesifik varlik: %s)\n",
    length(filters %||% list()),
    genel_soru_mu,
    spesifik_varlik_var
  ))

  cat(sprintf("[SMART_FILTER] Filtre sayisi: %d\n", length(filters %||% list())))
  if (length(filters) > 0) {
    for (i in seq_along(filters)) {
      f <- filters[[i]]
      cat(sprintf(
        "[SMART_FILTER] Filtre #%d: sutun='%s', deger='%s', islem='%s'\n",
        i,
        f$column %||% "NULL",
        # Çok değerli yaprakta `sprintf` vektörleşip filtre başına birden çok
        # satır basardı; günlük tek satır kalsın diye değerler birleştirilir.
        paste(as.character(unlist(f$value %||% "NULL", use.names = FALSE)), collapse = "|"),
        f$operation %||% "NULL"
      ))
    }
  }

  # GÜVENLİK SINIRI — MODEL ÜRETİMİ İFADE ASLA ÇALIŞTIRILMAZ.
  #
  # Bu blok eskiden `subset(dt, eval(parse(text = expr_str)))` çağırıyordu.
  # `expr_str` tamamen LLM üretimidir ve LLM girdisi kullanıcı istemi ile
  # sohbet geçmişinden beslenir; yani istem enjeksiyonuyla erişilebilen bir
  # UZAKTAN KOD ÇALIŞTIRMA yoluydu. `eval(parse())`'ı "güvenli hâle getirmek"
  # için ifadeyi ayıklamak mümkün değildir; mekanizmanın kendisi kaldırılmıştır.
  #
  # Yerine geçen yol: yapılandırılmış `filters` listesi (ve v2'de açık
  # `children`/`operator` mantık grupları) — bunlar VERİdir, kod değildir ve
  # yalnızca izin verilen işlemlerle değerlendirilir. Bu, ifadenin
  # ayrıştırılamadığı durumda zaten var olan ve sınanmış geri düşme yoludur.
  applied_expression_success <- FALSE

  # BOŞ DİZİ İFADE DEĞİLDİR: ayrıştırıcı `simplifyVector = FALSE` kullandığı
  # için `"filter_expression": []` BOŞ LİSTE olarak gelir. `as.character(
  # list())[1]` `NA` üretir ve `nzchar(NA)` TRUE olduğu için model hiç ifade
  # göndermemişken kullanıcıya SAHTE bir bozulma bildirimi yazılıyordu.
  expr_str <- .pk_filter_observation_scalar(filter_instructions$filter_expression)

  if (nzchar(expr_str)) {
    cat("[SMART_FILTER] filter_expression yok sayildi (calistirilabilir ifade kabul edilmez).\n")
    dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
      list(column = "filter_expression", value = expr_str, operation = "expression"),
      "çalıştırılabilir ifade kabul edilmez"
    )
  }

  if (!applied_expression_success) {
    if (!is.null(filters) && length(filters) > 0) {
      cat("[SMART_FILTER] Standart filtre listesi uygulanıyor (AND mantığı)...\n")

      for (f in filters) {
        # MANTIK GRUBU (`{operator, children}`) YAPRAK DEĞİLDİR.
        #
        # Ortak çıkarım istemi, sütunlar ARASI VEYA'yı grup düğümü olarak
        # istiyor ve doğrulayıcı bu düğümü koruyor; ancak grubu yalnızca v2
        # motoru (`helpers_pk_filter_compile.R`) değerlendirebiliyor. v1
        # gövdesinde düğüm zaten düşüyordu, fakat `f$column` boş olduğu için
        # "sütun veri kümesinde bulunamadı" gibi YANLIŞ bir gerekçeyle
        # raporlanıyordu. Karar (düşürme) değişmedi; bildirim artık doğru.
        if (.pk_filter_base_is_group(f)) {
          dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
            f, "mantık grubu (VEYA) v1 motorunda değerlendirilemiyor"
          )
          next
        }

        col <- .pk_filter_observation_scalar(f$column)
        val <- f$value
        op <- .pk_filter_observation_scalar(f$operation %||% "exact_match")
        if (!nzchar(op)) op <- "exact_match"
        # İŞLEM ADI YERELDEN BAĞIMSIZ KATLANIR ve DESTEKLENMEYEN İŞLEM
        # EŞİTLİĞE ÇEVRİLMEZ, DÜŞÜRÜLÜR. İstem modele YALNIZCA dört işlem
        # bildirir (exact_match / contains / greater_than / less_than); model
        # `CONTAINS` veya `greater_or_equal` döndürdüğünde eski `else` dalı
        # sessizce TAM EŞLEŞME uyguluyor, yaprağı da UYGULANDI olarak
        # kaydediyordu: analiz daha dar bir soruya cevap veriyor, köken alt
        # bilgisi de hiç uygulanmamış bir kısıtlamayı bildiriyordu.
        op <- if (exists("pk_ascii_token", mode = "function", inherits = TRUE)) {
          pk_ascii_token(op)
        } else {
          chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", trimws(op))
        }
        if (!(op %in% PK_V1_SUPPORTED_FILTER_OPS)) {
          dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
            f, "işlem v1 motorunda desteklenmiyor"
          )
          next
        }

        if (!nzchar(col) || !(col %in% names(dt))) {
          dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
            f, "sütun veri kümesinde bulunamadı"
          )
          next
        }

        col_vals <- dt[[col]]

        # v1 ÇOK DEĞERLİ YAPRAĞI BİLİNÇLİ OLARAK KIRPAR. Aynı sütun içi VEYA
        # v2 motorunun (`helpers_pk_filter_compile.R`) sözleşmesidir; v1 geri
        # dönüş şeridi olduğu için davranışı BİT BAZINDA sabit kalmalıdır
        # (`test-pk-v1-compatibility-contract.R` D2 bunu kilitler).
        # `helpers_pk_analysis_filters_base.R` içindeki gövdeyle AYNI olmalıdır.
        val_str <- .pk_filter_observation_scalar(val)

        if (is.character(col_vals) || is.factor(col_vals)) {
          # TERS BÖLÜ DE KAÇILIR: UNC yolu ya da alan adı taşıyan bir değer
          # (`\\sunucu\\pay`) eskiden ASILI bir kaçış karakteri üretiyor,
          # `grepl()` HİÇBİR satırı tutmuyor ama yaprak UYGULANDI sayılıyordu.
          val_regex <- gsub("([.|()\\^{}+$*?\\\\]|\\[|\\])", "\\\\\\1", val_str)
          col_vals_char <- as.character(col_vals)

          if (op == "exact_match") {
            dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
          } else if (op == "contains") {
            dt <- dt[grepl(val_regex, col_vals_char, ignore.case = TRUE), ]
          } else {
            # KARŞILAŞTIRMA İŞLEMİ METİN SÜTUNUNDA EŞİTLİĞE ÇEVRİLMEZ:
            # `greater_than`/`less_than` bir metin/faktör sütununda
            # DEĞERLENDİRİLEMEZ; sessizce tam eşleşmeye düşmek analizi daha dar
            # bir soruya cevap verdiriyor, köken alt bilgisi de HİÇ
            # uygulanmamış bir kısıtlamayı bildiriyordu.
            dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
              f, "işlem sütun türü için değerlendirilemiyor"
            )
            next
          }
          applied[[length(applied) + 1L]] <- f
          next
        }

        if (is.numeric(col_vals)) {
          # `integer64` de `is.numeric()` TRUE'dur; `as.numeric()` 2^53'te
          # YUVARLAR ve filtre yanlış satırı tutar. Operand üretimi ortak
          # kesinlik yardımcısına devredilir (izole gövdeyle AYNI sözleşme).
          operand <- pk_filter_numeric_operand(col_vals, val_str)
          if (!isTRUE(operand$ok)) {
            dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
              f, "değer sayısal biçime dönüştürülemedi"
            )
            next
          }
          val_num <- operand$value

          if (op == "greater_than") {
            dt <- dt[col_vals > val_num, ]
          } else if (op == "less_than") {
            dt <- dt[col_vals < val_num, ]
          } else if (op == "exact_match") {
            dt <- dt[col_vals == val_num, ]
          } else {
            # `contains` SAYISAL SÜTUNDA DEĞERLENDİRİLEMEZ (aynı gerekçe).
            dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
              f, "işlem sütun türü için değerlendirilemiyor"
            )
            next
          }
          applied[[length(applied) + 1L]] <- f
          next
        }

        dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(
          f, "sütun türü filtreleme için desteklenmiyor"
        )
      }
    } else {
      if (is.null(aggregation) || !tolower(aggregation) %in% c("count", "sum", "group_by")) {
        cat(sprintf(
          "[SMART_FILTER] Ne filtre ne aggregation var. GENEL SORU olarak işleniyor - tüm veri döndürülecek (%d satır).\n",
          nrow(dt)
        ))
      } else {
        cat("[SMART_FILTER] Aggregation mevcut, filtre yok - tüm veri üzerinde aggregation yapılacak\n")
      }
    }
  }

  # Toplulaştırma bu noktadan sonra yapılır. Köken/telemetri için korunması
  # gereken sayı, çıktı satırı değil burada eşleşen gerçek kayıt sayısıdır.
  matched_rows <- nrow(dt)

  if (!is.null(aggregation)) {
    agg_str <- tolower(aggregation)

    if (agg_str == "count") {
      aciklama <- if (length(filters) > 0) "Filtrelenen Kayıt Sayısı" else "Toplam Kayıt Sayısı"
      return(finish(data.frame(Sonuc = aciklama, Adet = matched_rows), matched_rows))
    } else if (agg_str == "sum") {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        sums <- lapply(num_cols, function(nc) sum(dt[[nc]], na.rm = TRUE))
        # KAYNAK ÖLÇÜ ADLARI KORUNUR. Adsız listeden üretilen çerçeve
        # `V1`/`V2` başlıkları alıyordu; yanıt metni ve CSV/XLSX dışa aktarımı
        # kullanıcının kaynak sütuna EŞLEYEMEDİĞİ başlıklar yayımlıyordu.
        # `check.names = FALSE`: boşluklu/Türkçe ölçü adı `make.names()` ile
        # YENİDEN YAZILMAZ.
        names(sums) <- num_cols
        return(finish(as.data.frame(sums, check.names = FALSE), matched_rows))
      }
    } else if (agg_str == "group_by" && !is.null(group_col) && group_col %in% names(dt)) {
      return(finish(as.data.frame(dt[, .N, by = group_col]), matched_rows))
    }
  }

  finish(as.data.frame(dt), matched_rows)
}
