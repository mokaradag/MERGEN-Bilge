# ==============================================================================
# Dosya Yolu: R/helpers_pk_sql_local_temp_batch.R
# Açıklama: Salt-okunur SQL kapısının YEREL #temp analitik batch istisnası.
#
#           NEDEN AYRI DOSYA: `R/helpers_pk_sql_readonly.R` KÜRESEL 796 satır
#           bakım tavanına ulaşmıştı. Temel sınıflandırıcı (tek ifade / CTE /
#           yasaklı anahtar kelime / sequence / yükleyici yer tutucusu) ile
#           çok ifadeli #temp batch analizi AYRI sorumluluklardır; ikincisi
#           buraya taşındı. DAVRANIŞ DEĞİŞMEZ: aynı fonksiyonlar, aynı sıra.
#
#           YÜKLEME SIRASI ZORUNLUDUR: bu dosya `helpers_pk_sql_readonly.R`
#           dosyasından SONRA yüklenmelidir. Temel sınıflandırıcıyı
#           `.pk_sql_classify_readonly_base` adıyla YAKALAR ve ardından
#           `pk_sql_classify_readonly()` adını #temp/DECLARE batch istisnasını
#           da uygulayan SARMALAYICI ile değiştirir. İzole testler iki dosyayı
#           da AYNI ortama kaynaklamalıdır.
# ==============================================================================

# ==============================================================================
# SQL Server yerel #temp analitik batch uyumluluğu
#
# Mevcut D23 yasakları DEĞİŞTİRİLMEZ. Aşağıdaki dar istisna yalnızca şu şekli
# kanıtlayabilen çok ifadeli batch'leri kabul eder:
#   [isteğe bağlı IF OBJECT_ID('tempdb..#T') ... DROP TABLE #T;]
#   SELECT ... INTO #T ...;
#   [yalnızca oluşturulmuş #T üzerinde CREATE [NON]CLUSTERED INDEX ...;]
#   [aynı yerel #temp hazırlama zinciri tekrarlanabilir]
#   tek bir salt-okunur sonuç SELECT/CTE;
#   DROP TABLE [IF EXISTS] #T [, #T2 ...];
# Kalıcı tablo yazımı/DDL, ##global temp, EXEC, ek sonuç SELECT'i veya belirsiz
# herhangi bir şekil mevcut kapalı-başarısız davranışında kalır.
# ==============================================================================

# Normal tek-SELECT/NOCOUNT sınıflandırıcısını aynen sakla. Yerel-temp denetimi
# hazırlama SELECT'lerinin güvenliğini de AYNI yasaklarla yeniden kanıtlar.
# YAKALAMA ETKİSİZDİR (idempotent). Dosya aynı ortamda iki kez source edilirse
# ikinci yakalama aşağıda tanımlanan SARMALAYICIYI alır; sarmalayıcı da bu
# ismi çağırdığı için her sınıflandırma SONSUZ ÖZYİNELEMEYE (C stack) düşerdi.
if (!exists(".pk_sql_classify_readonly_base", mode = "function", inherits = FALSE)) {
  .pk_sql_classify_readonly_base <- pk_sql_classify_readonly
}

.pk_sql_local_temp_name_equal <- function(a, b) {
  a <- as.character(a %||% "")[1]
  b <- as.character(b %||% "")[1]
  if (is.na(a) || is.na(b) || !nzchar(a) || !nzchar(b)) return(FALSE)
  grepl(paste0("^", a, "$"), b,
        ignore.case = TRUE, perl = TRUE, useBytes = TRUE)
}

# Maskelenmiş metindeki noktalı virgüller ham metinle AYNI konumdadır; literal ve
# yorum içindeki noktalı virgüller maskelendiği için ifade sınırı sayılmaz.
.pk_sql_local_temp_statement_pairs <- function(raw_sql, masked_sql) {
  raw_chars <- strsplit(as.character(raw_sql)[1], "", fixed = TRUE)[[1]]
  masked_chars <- strsplit(as.character(masked_sql)[1], "", fixed = TRUE)[[1]]
  if (length(raw_chars) != length(masked_chars)) return(NULL)
  if (!length(masked_chars)) return(list())

  ayiricilar <- which(masked_chars == ";")
  baslar <- c(1L, ayiricilar + 1L)
  biter <- c(ayiricilar - 1L, length(masked_chars))
  sonuc <- list()

  for (i in seq_along(baslar)) {
    if (baslar[i] > biter[i]) next
    idx <- seq.int(baslar[i], biter[i])
    parca_mask <- masked_chars[idx]
    dolu <- which(!(parca_mask %in% c(" ", "\t", "\r", "\n")))
    if (!length(dolu)) next

    lo <- baslar[i] + min(dolu) - 1L
    hi <- baslar[i] + max(dolu) - 1L
    sec <- seq.int(lo, hi)
    sonuc[[length(sonuc) + 1L]] <- list(
      raw = paste(raw_chars[sec], collapse = ""),
      masked = paste(masked_chars[sec], collapse = "")
    )
  }
  sonuc
}

.pk_sql_local_temp_predrop <- function(raw_statement) {
  kalip <- paste0(
    "^IF[ \\t\\r\\n]+OBJECT_ID[ \\t\\r\\n]*\\([ \\t\\r\\n]*N?'tempdb\\.\\.",
    "(#[A-Za-z_][A-Za-z0-9_]*)'[ \\t\\r\\n]*",
    # İSTEĞE BAĞLI NESNE TÜRÜ ARGÜMANI (PR #705 inceleme, P3): T-SQL
    # `OBJECT_ID('tempdb..#T', 'U')` biçimini de kabul eder ve bu, SSMS'te
    # YAYGIN ön-DROP deyimidir. Reddedildiğinde deyim ne hazırlama ne indeks
    # şekline uyuyor, `pk_sql_analyze_local_temp_batch()` boş dönüyor ve TÜM
    # toplu iş `multiple_statements` ile read-only kapısında reddediliyordu.
    "(?:,[ \\t\\r\\n]*N?'U'[ \\t\\r\\n]*)?\\)[ \\t\\r\\n]+",
    "IS[ \\t\\r\\n]+NOT[ \\t\\r\\n]+NULL[ \\t\\r\\n]+",
    "DROP[ \\t\\r\\n]+TABLE[ \\t\\r\\n]+(#[A-Za-z_][A-Za-z0-9_]*)$"
  )
  m <- regexec(kalip, raw_statement, ignore.case = TRUE, perl = TRUE)
  parca <- regmatches(raw_statement, m)[[1]]
  if (length(parca) != 3L) return(NULL)
  if (!.pk_sql_local_temp_name_equal(parca[2], parca[3])) return(NULL)
  parca[2]
}

# Son temizlik hem klasik `DROP TABLE #T` hem de SQL Server 2016+ biçimi
# `DROP TABLE IF EXISTS #A, #B` olabilir. Her hedef MUTLAKA yerel #temp'tir.
.pk_sql_local_temp_cleanup <- function(raw_statement) {
  # `(?s)`: PCRE'de `.` varsayılan olarak `\n` ile EŞLEŞMEZ. SSMS biçimli
  # kütüphane SQL'inde `DROP TABLE #A,\n  #B` listesi satırlara bölünebilir;
  # `(.+)$` o listeyi tek satırla sınırlar, ad listesi eksik yakalanır ve
  # yerel `#temp` toplu işi bütünüyle REDDEDİLİRDİ.
  kalip <- paste0(
    "(?s)",
    "^DROP[ \\t\\r\\n]+TABLE",
    "(?:[ \\t\\r\\n]+IF[ \\t\\r\\n]+EXISTS)?",
    "[ \\t\\r\\n]+(.+)$"
  )
  m <- regexec(kalip, raw_statement, ignore.case = TRUE, perl = TRUE)
  parca <- regmatches(raw_statement, m)[[1]]
  if (length(parca) != 2L) return(NULL)

  adlar <- trimws(strsplit(parca[2], ",", fixed = TRUE)[[1]])
  if (!length(adlar) || any(!nzchar(adlar))) return(NULL)
  if (any(!grepl("^#[A-Za-z_][A-Za-z0-9_]*$", adlar, perl = TRUE))) return(NULL)
  adlar
}

.pk_sql_local_temp_stage <- function(pair) {
  if (!is.list(pair) || !.pk_sql_starts_with_word(pair$masked %||% "", "SELECT")) {
    return(NULL)
  }

  into_word <- gregexpr(
    "(?<![A-Za-z0-9_@#$])INTO(?![A-Za-z0-9_@#$])",
    pair$masked, ignore.case = TRUE, perl = TRUE
  )[[1]]
  if (length(into_word) != 1L || identical(into_word[1], -1L)) return(NULL)

  kalip <- paste0(
    "(?<![A-Za-z0-9_@#$])INTO[ \\t\\r\\n]+",
    "(#[A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_@#$])"
  )
  m <- regexec(kalip, pair$masked, ignore.case = TRUE, perl = TRUE)
  parca <- regmatches(pair$masked, m)[[1]]
  if (length(parca) != 2L) return(NULL)

  bas <- m[[1]][1]
  uzunluk <- attr(m[[1]], "match.length")[1]
  if (is.na(bas) || bas < 1L || is.na(uzunluk) || uzunluk < 1L) return(NULL)

  ham_uzunluk <- nchar(pair$raw, type = "chars")
  once <- if (bas > 1L) substr(pair$raw, 1L, bas - 1L) else ""
  sonraki <- bas + uzunluk
  sonra <- if (sonraki <= ham_uzunluk) substr(pair$raw, sonraki, ham_uzunluk) else ""
  salt_okunur_karsilik <- paste0(once, " ", sonra)

  # Yalnız `INTO #YerelTemp` parçası çıkarılır; geri kalan SELECT mevcut D23
  # sınıflandırıcısının BÜTÜN yasaklarından tekrar geçmek zorundadır.
  kapi <- .pk_sql_classify_readonly_base(salt_okunur_karsilik)
  if (!isTRUE(kapi$allowed)) return(NULL)

  list(temp_name = parca[2], sql = pair$raw)
}

.pk_sql_local_temp_has_name <- function(names, name) {
  if (!length(names)) return(FALSE)
  any(vapply(names, function(x) .pk_sql_local_temp_name_equal(x, name), logical(1)))
}

# CREATE INDEX genel olarak yasaktır. Bu istisna yalnızca batch'in DAHA ÖNCE
# oluşturduğu yerel #temp üzerindeki fiziksel indeksleri kabul eder. Kalıcı
# tablo, ##global temp veya başka yasaklı SQL ailesi hedeflenirse NULL döner.
.pk_sql_local_temp_index <- function(pair, temp_names) {
  if (!is.list(pair) || !.pk_sql_starts_with_word(pair$masked %||% "", "CREATE")) {
    return(NULL)
  }

  metin <- trimws(as.character(pair$masked %||% "")[1])
  if (is.na(metin) || !nzchar(metin) || grepl("##", metin, fixed = TRUE)) return(NULL)

  m <- regexec(
    paste0(
      # `(?s)`: `.` `\n` ile de eşleşsin. SSMS biçimli
      # `CREATE NONCLUSTERED INDEX ix_t\n  ON #T (Kolon)` ifadesi çok
      # satırlıdır; DOTALL olmadan eşleşme başarısız olur,
      # `.pk_sql_local_temp_index()` `NULL` döner ve TÜM toplu iş
      # `local_temp_batch` istisnasını kaybederek salt-okunur kapısında
      # güvenlik mesajıyla reddedilirdi.
      "(?s)",
      "^CREATE[ \\t\\r\\n]+",
      "(?:UNIQUE[ \\t\\r\\n]+)?",
      "(?:(?:CLUSTERED|NONCLUSTERED)[ \\t\\r\\n]+)?",
      "INDEX(?=$|[^A-Za-z0-9_@#$]).*?",
      "(?<![A-Za-z0-9_@#$])ON[ \\t\\r\\n]+",
      "(#[A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_@#$])"
    ),
    metin, ignore.case = TRUE, perl = TRUE
  )
  parca <- regmatches(metin, m)[[1]]
  if (length(parca) != 2L) return(NULL)
  hedef <- parca[2]
  if (!.pk_sql_local_temp_has_name(temp_names, hedef)) return(NULL)

  for (kelime in setdiff(PK_SQL_FORBIDDEN_KEYWORDS, "CREATE")) {
    if (.pk_sql_has_word(metin, kelime)) return(NULL)
  }
  # EK ÜST DÜZEY İFADE BU DALDA DA REDDEDİLİR (PR #705 incelemesi, P2).
  #
  # Hazırlama (`.pk_sql_local_temp_stage()`) ve sonuç dalları metni
  # `.pk_sql_classify_readonly_base()` üzerinden yeniden doğruluyordu; indeks
  # dalı doğrulamıyordu. `ON #T` eşleşmesi ifadenin KALANINI denetlemez ve
  # T-SQL ifadeler arasında `;` ZORUNLU KILMAZ, bu yüzden
  # `CREATE INDEX ix ON #T (a) DISABLE TRIGGER ALL ON DATABASE` biçimi
  # denylist'e yakalanmadan geçip salt-okunur kapısını atlıyordu. Aynı açık
  # ikinci bir `SELECT`, `CHECKPOINT` veya `REVERT` için de geçerliydi.
  if (!is.null(.pk_sql_extra_top_level_statement(metin))) return(NULL)
  # ÜST DÜZEY `SELECT` BU İFADEDE HİÇ BULUNAMAZ.
  #
  # `.pk_sql_extra_top_level_statement()` yalnızca İKİNCİ `SELECT`i bildirir;
  # `CREATE INDEX ... ON #T (a) SELECT * FROM dbo.Gizli` içindeki TEK `SELECT`
  # ilk `SELECT` sayıldığı için o kapıdan geçiyordu. Geçerli bir `CREATE INDEX`
  # ifadesi üst düzeyde `SELECT` İÇEREMEZ (`INCLUDE (...)` ve filtreli indeks
  # `WHERE` yüklemi parantez içindedir ya da `SELECT` barındırmaz), bu yüzden
  # üst düzey `SELECT` KOŞULSUZ reddedilir.
  if ("SELECT" %in% .pk_sql_top_level_words(metin)) return(NULL)
  for (onek in PK_SQL_FORBIDDEN_PREFIXES) {
    if (grepl(paste0("(^|[^A-Za-z0-9_])", onek), metin,
              ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) return(NULL)
  }
  if (grepl(PK_SQL_SEQUENCE_MUTATION_PATTERN, metin,
            ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) return(NULL)

  hedef
}

#' Yalnızca kanıtlanmış yerel-#temp analitik batch planını döndür
#'
#' @return `list(ok, temp_names, staging_sql, result_sql, statement_count)`.
#'   `ok=FALSE` durumunda hiçbir SQL parçası yürütülmek için güvenilir sayılmaz.
pk_sql_analyze_local_temp_batch <- function(sql) {
  bos <- function() list(
    ok = FALSE, temp_names = character(0), staging_sql = character(0),
    result_sql = NULL, statement_count = 0L
  )

  sql_text <- as.character(sql %||% "")[1]
  if (is.na(sql_text) || !nzchar(trimws(sql_text))) return(bos())

  maske <- pk_sql_mask_literals(sql_text)
  if (!isTRUE(maske$ok)) return(bos())

  # Yerel-temp istisnası GO ile çoklu batch'e ASLA genişlemez.
  if (grepl(
    "(^|\\r\\n|\\n|\\r)[ \\t]*GO[ \\t]*(?=\\r\\n|\\n|\\r|$)",
    maske$masked, ignore.case = TRUE, perl = TRUE, useBytes = TRUE
  )) return(bos())

  ifadeler <- .pk_sql_local_temp_statement_pairs(sql_text, maske$masked)
  if (is.null(ifadeler) || length(ifadeler) < 1L) return(bos())

  # `SET NOCOUNT ON;` ÖNEKİ TÜKETİLİR.
  #
  # Tek-SELECT sınıflandırıcısı bu öneki ZATEN kabul ediyor; yerel-#temp
  # çözümleyicisi etmiyordu. SSMS ile yazılmış analitik sorgularda öneki olan
  # bir batch'te İLK ifade çifti `SET NOCOUNT ON` oluyor, hiçbir predrop/stage/
  # index biçimine uymuyor ve `temp_adlari` boş kalarak istisna TAMAMEN devre
  # dışı kalıyordu. Yalnızca TAM önek tüketilir; kalan ifadeler aşağıdaki
  # kapıların TAMAMINDAN geçmek zorundadır.
  if (length(ifadeler) > 1L &&
      grepl(PK_SQL_SAFE_NOCOUNT_PREAMBLE_PATTERN, ifadeler[[1L]]$masked,
            ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) {
    ifadeler <- ifadeler[-1L]
  }
  if (length(ifadeler) < 3L) return(bos())

  temp_adlari <- character(0)
  staging <- character(0)
  sonuc_sql <- NULL
  temizlik <- character(0)
  i <- 1L

  while (i <= length(ifadeler)) {
    pair <- ifadeler[[i]]

    if (is.null(sonuc_sql)) {
      # Eski güvenli biçim korunur: predrop varsa hemen arkasındaki staging ile
      # birebir aynı #temp adını hedeflemelidir.
      # HAM METİN KULLANILIR (maskelenmiş DEĞİL).
      #
      # `pk_sql_mask_literals()` YORUMLARI DA DİZE SABİTLERİNİ DE boşluğa
      # çevirir; ön-DROP deseni ise `'tempdb..#Ad'` sabitini OKUMAK zorundadır.
      # Maskelenmiş metinle çalışmak yerel #temp muafiyetini tamamen kaybettirir.
      # SONDAKİ YORUM ZATEN SORUN DEĞİLDİR: `.pk_sql_statement_pairs()` ifade
      # sınırlarını MASKELENMİŞ metne göre kırptığı için `DROP TABLE #T -- not`
      # ifadesinde `pair$raw` yalnızca `DROP TABLE #T` içerir.
      on_drop <- .pk_sql_local_temp_predrop(pair$raw)
      if (!is.null(on_drop)) {
        if (i >= length(ifadeler) || .pk_sql_local_temp_has_name(temp_adlari, on_drop)) {
          return(bos())
        }
        stage <- .pk_sql_local_temp_stage(ifadeler[[i + 1L]])
        if (is.null(stage) || !.pk_sql_local_temp_name_equal(on_drop, stage$temp_name)) {
          return(bos())
        }
        temp_adlari <- c(temp_adlari, on_drop)
        staging <- c(staging, stage$sql)
        i <- i + 2L
        next
      }

      # SSMS'te yaygın olan ikinci güvenli biçim: dinamik batch kapsamı zaten
      # yerel #temp'i yalıttığı için predrop ZORUNLU değildir.
      stage <- .pk_sql_local_temp_stage(pair)
      if (!is.null(stage)) {
        if (.pk_sql_local_temp_has_name(temp_adlari, stage$temp_name)) return(bos())
        temp_adlari <- c(temp_adlari, stage$temp_name)
        staging <- c(staging, stage$sql)
        i <- i + 1L
        next
      }

      # Performans için CREATE INDEX yalnızca daha önce kanıtlanmış yerel #temp
      # üzerinde olabilir. Metadata CTE dönüşümünde indeksler bilerek atlanır.
      index_hedef <- .pk_sql_local_temp_index(pair, temp_adlari)
      if (!is.null(index_hedef)) {
        i <- i + 1L
        next
      }

      # Kurulum bittikten sonra TAM OLARAK bir sonuç SELECT/CTE kabul edilir.
      if (!length(temp_adlari)) return(bos())
      sonuc_kapi <- .pk_sql_classify_readonly_base(pair$raw)
      if (!isTRUE(sonuc_kapi$allowed)) return(bos())
      sonuc_sql <- pair$raw
      i <- i + 1L
      next
    }

    # Sonuç SELECT'inden sonra yalnızca aynı batch'in yarattığı #temp DROP'ları.
    # TEMİZLİK DESENİ MASKELENMİŞ METNİ KULLANABİLİR: ön-DROP'un aksine hiçbir
    # DİZE SABİTİ okumaz, yalnızca çıplak `#Ad` belirteçleri arar. Böylece
    # `DROP TABLE /* not */ #T` gibi ORTADA yorum taşıyan bir ifade de eşleşir
    # (sondaki yorumu `.pk_sql_local_temp_statement_pairs()` zaten kırpar).
    silinecekler <- .pk_sql_local_temp_cleanup(pair$masked %||% pair$raw)
    if (is.null(silinecekler) || !length(silinecekler)) return(bos())

    for (silinecek in silinecekler) {
      if (!.pk_sql_local_temp_has_name(temp_adlari, silinecek) ||
          .pk_sql_local_temp_has_name(temizlik, silinecek)) {
        return(bos())
      }
      temizlik <- c(temizlik, silinecek)
    }
    i <- i + 1L
  }

  if (is.null(sonuc_sql) || !length(temp_adlari) || length(temizlik) != length(temp_adlari)) {
    return(bos())
  }
  for (ad in temp_adlari) {
    if (!.pk_sql_local_temp_has_name(temizlik, ad)) return(bos())
  }

  list(
    ok = TRUE,
    temp_names = temp_adlari,
    staging_sql = staging,
    result_sql = sonuc_sql,
    statement_count = as.integer(length(ifadeler))
  )
}

# Mevcut sınıflandırıcıyı yalnızca `multiple_statements` sonucu için daralt.
# Diğer HER ret gerekçesi ve bütün yasak anahtar kelime ratchet'leri aynen kalır.
pk_sql_classify_readonly <- function(sql) {
  temel <- .pk_sql_classify_readonly_base(sql)
  if (isTRUE(temel$allowed) || !identical(temel$reason, "multiple_statements")) {
    return(temel)
  }

  plan <- pk_sql_analyze_local_temp_batch(sql)
  if (isTRUE(plan$ok)) {
    temel$statement_kind <- "local_temp_batch"
    temel$statement_count <- as.integer(plan$statement_count)
  } else {
    maske <- pk_sql_mask_literals(sql)
    # `GO` AYIRICISI DECLARE İSTİSNASINDA DA REDDEDİLİR.
    #
    # Yerel-#temp yolu bunu zaten yapıyordu; DECLARE dalında denetim YOKTU.
    # `pk_sql_split_statements()` tek başına duran `GO` ifadesini ifade sınırına
    # çeviriyor, `DECLARE @x INT` + `GO` + `SELECT @x` iki kabul edilmiş parça
    # üretiyordu. SQL Server yerel değişkenleri batch sınırında YOK EDER; yani
    # onaylanan metin çalıştığında değişken tanımsızdır.
    if (!isTRUE(maske$ok) || grepl(
      "(^|\\r\\n|\\n|\\r)[ \\t]*GO[ \\t]*(?=\\r\\n|\\n|\\r|$)",
      maske$masked, ignore.case = TRUE, perl = TRUE, useBytes = TRUE
    )) return(temel)
    ifadeler <- pk_sql_split_statements(maske$masked)
    if (length(ifadeler) > 1L &&
        grepl(PK_SQL_SAFE_NOCOUNT_PREAMBLE_PATTERN, ifadeler[[1L]],
              ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) {
      ifadeler <- ifadeler[-1L]
    }
    if (length(ifadeler) < 2L ||
        !isTRUE(.pk_sql_classify_readonly_base(ifadeler[[length(ifadeler)]])$allowed)) {
      return(temel)
    }
    for (bildirim in ifadeler[-length(ifadeler)]) {
      denetim <- .pk_sql_classify_readonly_base(sub(
        "^DECLARE", "SELECT", bildirim,
        ignore.case = TRUE, perl = TRUE, useBytes = TRUE
      ))
      if (!grepl("^DECLARE[ \\t\\r\\n]+@[A-Za-z_][A-Za-z0-9_]*", bildirim,
                 ignore.case = TRUE, perl = TRUE, useBytes = TRUE) ||
          .pk_sql_has_word(bildirim, "TABLE") || .pk_sql_has_word(bildirim, "CURSOR") ||
          !isTRUE(denetim$allowed)) return(temel)
    }
    temel$statement_kind <- "declare_select_batch"
  }

  temel$allowed <- TRUE
  temel$reason <- NULL
  temel$detail <- NA_character_
  temel
}
