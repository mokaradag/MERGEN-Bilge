# ==============================================================================
# Dosya Yolu: R/helpers_pk_sql_readonly.R
# Açıklama: Proje ve Kaynak Analizi için ifade farkında, KAPALI BAŞARISIZ
#           (fail-closed) salt-okunur SQL sınıflandırıcısı (D23).
#
#           Eski kapı bir KARA LİSTE idi: yalnızca DELETE/DROP/TRUNCATE/ALTER
#           engelleniyor, MERGE / SELECT ... INTO / veri değiştiren CTE /
#           sp_ / xp_ / çok ifadeli batch serbest kalıyordu. Bu dosya bunun
#           yerine tam tersini yapar: yalnızca TEK bir salt-okunur SELECT
#           (veya son ifadesi SELECT olan bir CTE) kabul edilir; ayrıştırma
#           belirsizliği veya tanınmayan yapı REDDEDİLİR. SQL Server sorgu
#           kütüphanesi uyumluluğu için yalnızca tam `SET NOCOUNT ON;`
#           öneki, arkasında tek bir salt-okunur SELECT/CTE varsa kabul edilir.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ bağımlılığı yoktur.
#           Böylece v1, v2, derin mod ve (Faz 3b'de yazılacak) metadata
#           üreticisi aynı kapıyı paylaşabilir.
#
# Yerel ayar notu: Anahtar kelimeler ASCII'dir. Türkçe Windows yerel ayarında
#   toupper()/tolower() yerel bağımlı davrandığı için hiçbir yerde kullanılmaz;
#   tarama grepl(..., ignore.case = TRUE, perl = TRUE, useBytes = TRUE) ile
#   yapılır (deponun module_proje_kaynak_analizi.R içinde zaten benimsediği
#   yerel-bağımsız kalıp).
# ==============================================================================

# Salt-okunur olmayan / yan etkili her aile. Kelime sınırıyla aranır.
PK_SQL_FORBIDDEN_KEYWORDS <- c(
  # MERGE listenin başındadır: `MERGE ... THEN UPDATE SET` biçimi aksi halde
  # "UPDATE" gerekçesiyle raporlanır ve operatör logu yanıltıcı olur.
  "MERGE", "INSERT", "UPDATE", "DELETE", "UPSERT",
  "CREATE", "DROP", "ALTER", "TRUNCATE", "RENAME",
  "GRANT", "DENY", "REVOKE",
  "BACKUP", "RESTORE",
  "EXEC", "EXECUTE",
  "INTO",
  "SET", "DECLARE", "USE", "GO",
  "BEGIN", "COMMIT", "ROLLBACK", "SAVE",
  "WAITFOR", "SHUTDOWN", "KILL", "RECONFIGURE", "DBCC",
  "RAISERROR", "THROW", "PRINT",
  "OPENROWSET", "OPENQUERY", "OPENDATASOURCE", "OPENXML", "BULK"
)

# Saklı yordam öneki aileleri (sp_/xp_) kelime sınırıyla değil önekle aranır.
PK_SQL_FORBIDDEN_PREFIXES <- c("sp_", "xp_")

# SQL Server'da sonuç satırlarını değiştirmeyen ve sorgu kütüphanesinde yaygın
# olan TEK güvenli batch öneki. Başka SET biçimleri veya ek ifadeler bu istisnaya
# girmez; normal çok-ifade kapısı tarafından kapalı başarısız reddedilir.
PK_SQL_SAFE_NOCOUNT_PREAMBLE_PATTERN <-
  "^SET[ \t\r\n]+NOCOUNT[ \t\r\n]+ON$"

# Sınıflandırıcı gerekçelerinin tek kaynağı: makine kodu -> kullanıcıya
# gösterilmeyen Türkçe operatör açıklaması. Kullanıcıya yalnızca genel mesaj
# gider; ayrıntı sunucu logunda kalır.
PK_SQL_READONLY_REASONS <- list(
  empty_sql            = "SQL metni bos.",
  unterminated_literal = "Kapanmamis string literali; ayristirma belirsiz.",
  unterminated_comment = "Kapanmamis blok yorumu; ayristirma belirsiz.",
  unterminated_identifier = "Kapanmamis tirnakli/koseli tanimlayici.",
  no_statement         = "Calistirilabilir ifade bulunamadi.",
  multiple_statements  = "Birden fazla ifade iceren batch salt-okunur sayilmaz.",
  not_select           = "Ifade SELECT (veya CTE+SELECT) ile baslamiyor.",
  cte_not_select       = "CTE zincirinin son ifadesi SELECT degil.",
  forbidden_keyword    = "Yan etkili SQL anahtar kelimesi tespit edildi.",
  forbidden_prefix     = "Sakli yordam oneki (sp_/xp_) tespit edildi.",
  sequence_mutation    = "Sequence ilerleten ifade (NEXT VALUE FOR) durum değiştirir."
)

# SEQUENCE İLERLETEN İFADE.
#
# `SELECT NEXT VALUE FOR dbo.SomeSequence` sözdizimsel olarak bir SELECT'tir ve
# yasaklı anahtar kelimelerin HİÇBİRİNİ içermez; ancak SQL Server'da her
# `NEXT VALUE FOR` çağrısı sequence değerini AYIRIR/İLERLETİR. Değer hiçbir yere
# yazılmasa bile ÜRETİM DURUMU DEĞİŞİR. "Salt-okunur SELECT" sözü bunu
# kapsayamaz; bu yüzden kapı açıkça reddeder. (Faz 3b metadata üreticisi bu
# aynı kapıyı kullandığı için düzeltme burada yapılır ve TÜM tüketiciler
# kazanır.)
PK_SQL_SEQUENCE_MUTATION_PATTERN <- "(^|[^A-Za-z0-9_@#$])NEXT[ \t\r\n]+VALUE[ \t\r\n]+FOR($|[^A-Za-z0-9_@#$])"

# Kullanıcıya gösterilen genel mesaj: sürücü/DSN/şema ayrıntısı içermez.
PK_SQL_READONLY_USER_MESSAGE <- paste0(
  "\U000026A0\U0000FE0F **Güvenlik Kontrolü:** Seçilen sorgu ",
  "salt-okunur bir SELECT olarak doğrulanamadığı için ",
  "çalıştırılmadı. Lütfen sistem ",
  "yöneticisiyle iletişime geçin."
)

# Yerel-bağımsız ASCII kelime araması.
.pk_sql_has_word <- function(text, word) {
  grepl(
    paste0("(^|[^A-Za-z0-9_@#$])", word, "($|[^A-Za-z0-9_@#$])"),
    text,
    ignore.case = TRUE, perl = TRUE, useBytes = TRUE
  )
}

.pk_sql_starts_with_word <- function(text, word) {
  grepl(
    paste0("^", word, "($|[^A-Za-z0-9_@#$])"),
    text,
    ignore.case = TRUE, perl = TRUE, useBytes = TRUE
  )
}

#' String literallerini, yorumları ve tırnaklı/köşeli tanımlayıcıları maskele
#'
#' Anahtar kelime taraması YALNIZCA maskelenmiş metin üzerinde yapılır. Aksi
#' halde `WHERE Aciklama = 'DROP TABLE'` gibi zararsız bir literal veya
#' `[Silme Tarihi]` gibi Türkçe köşeli bir sütun adı yanlış pozitif üretir.
#'
#' Maskeleme kayıpsız DEĞİLDİR; yalnızca sınıflandırma içindir. İfade sınırları
#' (`;`) ve parantez yapısı korunur.
#'
#' @return list(ok, masked, reason)
pk_sql_mask_literals <- function(sql) {
  sql <- as.character(sql %||% "")[1]
  if (is.na(sql)) sql <- ""

  chars <- strsplit(sql, "", fixed = TRUE)[[1]]
  n <- length(chars)
  out <- character(n)

  i <- 1L
  state <- "kod"
  blok_derinlik <- 0L

  while (i <= n) {
    ch <- chars[i]
    nxt <- if (i < n) chars[i + 1L] else ""

    if (identical(state, "kod")) {
      if (identical(ch, "'")) {
        state <- "metin"; out[i] <- "'"; i <- i + 1L; next
      }
      if (identical(ch, "\"")) {
        state <- "tirnakli_ad"; out[i] <- " "; i <- i + 1L; next
      }
      if (identical(ch, "[")) {
        state <- "koseli_ad"; out[i] <- " "; i <- i + 1L; next
      }
      if (identical(ch, "-") && identical(nxt, "-")) {
        state <- "satir_yorum"; out[i] <- " "; i <- i + 1L; next
      }
      if (identical(ch, "/") && identical(nxt, "*")) {
        state <- "blok_yorum"; blok_derinlik <- 1L
        out[i] <- " "; out[i + 1L] <- " "; i <- i + 2L; next
      }
      out[i] <- ch; i <- i + 1L; next
    }

    if (identical(state, "metin")) {
      # SQL'de tek tırnak kaçışı '' biçimindedir.
      if (identical(ch, "'") && identical(nxt, "'")) {
        out[i] <- " "; out[i + 1L] <- " "; i <- i + 2L; next
      }
      if (identical(ch, "'")) {
        state <- "kod"; out[i] <- "'"; i <- i + 1L; next
      }
      out[i] <- " "; i <- i + 1L; next
    }

    if (identical(state, "tirnakli_ad")) {
      if (identical(ch, "\"") && identical(nxt, "\"")) {
        out[i] <- " "; out[i + 1L] <- " "; i <- i + 2L; next
      }
      if (identical(ch, "\"")) {
        state <- "kod"; out[i] <- " "; i <- i + 1L; next
      }
      out[i] <- " "; i <- i + 1L; next
    }

    if (identical(state, "koseli_ad")) {
      # ]] köşeli tanımlayıcı içinde kaçışlanmış ] demektir.
      if (identical(ch, "]") && identical(nxt, "]")) {
        out[i] <- " "; out[i + 1L] <- " "; i <- i + 2L; next
      }
      if (identical(ch, "]")) {
        state <- "kod"; out[i] <- " "; i <- i + 1L; next
      }
      out[i] <- " "; i <- i + 1L; next
    }

    if (identical(state, "satir_yorum")) {
      # T-SQL satır yorumunu CR, LF ve CRLF'in HEPSİ sonlandırır. Yalnızca `\n`
      # arayan bir durum makinesi, CR ile biten bir dosyada yorumdan SONRAKİ
      # tüm batch'i de yorum sayar ve `SELECT 1 -- x<CR>DROP TABLE T` metni
      # "tek salt-okunur SELECT" olarak KABUL edilirdi (kapalı başarısız kapı
      # sessizce AÇILIRDI). Ana modül metni kapıdan önce normalleştirir, ama
      # derin mod SQL dosyasını HAM okur; bu yüzden burada karşılanmalıdır.
      # Satır sonu karakteri AYNEN korunur: `GO` ayırıcısı onu arar.
      if (identical(ch, "\n") || identical(ch, "\r")) {
        state <- "kod"; out[i] <- ch; i <- i + 1L; next
      }
      out[i] <- " "; i <- i + 1L; next
    }

    if (identical(state, "blok_yorum")) {
      # T-SQL blok yorumları iç içe geçebilir.
      if (identical(ch, "/") && identical(nxt, "*")) {
        blok_derinlik <- blok_derinlik + 1L
        out[i] <- " "; out[i + 1L] <- " "; i <- i + 2L; next
      }
      if (identical(ch, "*") && identical(nxt, "/")) {
        blok_derinlik <- blok_derinlik - 1L
        out[i] <- " "; out[i + 1L] <- " "; i <- i + 2L
        if (blok_derinlik <= 0L) state <- "kod"
        next
      }
      out[i] <- if (identical(ch, "\n")) "\n" else " "
      i <- i + 1L; next
    }
  }

  if (identical(state, "metin")) {
    return(list(ok = FALSE, masked = "", reason = "unterminated_literal"))
  }
  if (identical(state, "blok_yorum")) {
    return(list(ok = FALSE, masked = "", reason = "unterminated_comment"))
  }
  if (state %in% c("tirnakli_ad", "koseli_ad")) {
    return(list(ok = FALSE, masked = "", reason = "unterminated_identifier"))
  }

  list(ok = TRUE, masked = paste(out, collapse = ""), reason = NULL)
}

#' Maskelenmiş SQL'i üst düzey ifadelere böl
#'
#' `;` ayırıcıdır. Kendi satırındaki `GO` batch ayırıcısı da ifade sınırı sayılır;
#' böylece çok batch'li metin "birden fazla ifade" olarak reddedilir.
#'
#' Satır sonu ailesi CR/LF/CRLF olarak ele alınır. Ana modül metni kapıdan ÖNCE
#' `\n` normalleştirir ama derin mod SQL dosyasını HAM okur; Windows/SSMS
#' dosyaları CRLF'tir. Yalnızca `\n` arayan bir kalıp orada `GO` satırını
#' ayırıcı olarak GÖRMEZ ve kapı, aynı sorgu için satır sonuna göre farklı
#' karar verirdi: LF metinde geçerli sayılan tek SELECT + sondaki `GO`, CRLF
#' metinde "yasaklı anahtar kelime" gerekçesiyle reddedilirdi.
pk_sql_split_statements <- function(masked_sql) {
  masked_sql <- as.character(masked_sql %||% "")[1]
  if (is.na(masked_sql)) masked_sql <- ""

  # Kendi satırındaki GO -> ifade ayırıcı (CR, LF ve CRLF için).
  masked_sql <- gsub(
    "(^|\r\n|\n|\r)[ \t]*GO[ \t]*(?=\r\n|\n|\r|$)", "\\1;", masked_sql,
    ignore.case = TRUE, perl = TRUE, useBytes = TRUE
  )

  parcalar <- strsplit(masked_sql, ";", fixed = TRUE)[[1]]
  parcalar <- trimws(parcalar)
  parcalar[nzchar(parcalar)]
}

# CTE zincirinden sonraki gövdeyi bulur: WITH <ad> AS ( ... ) [, ...] <govde>
# Parantez derinliği sayılarak son kapanıştan sonrası alınır.
.pk_sql_cte_body <- function(statement) {
  chars <- strsplit(statement, "", fixed = TRUE)[[1]]
  derinlik <- 0L
  i <- 1L
  n <- length(chars)
  gorulen_paren <- FALSE

  while (i <= n) {
    ch <- chars[i]
    if (identical(ch, "(")) {
      derinlik <- derinlik + 1L
      gorulen_paren <- TRUE
    } else if (identical(ch, ")")) {
      derinlik <- derinlik - 1L
      if (derinlik < 0L) return(NULL)
      if (derinlik == 0L) {
        kalan <- trimws(paste(chars[seq.int(i + 1L, n)], collapse = ""))
        # Virgülle devam eden bir sonraki CTE tanımı; gövde henüz gelmedi.
        if (startsWith(kalan, ",")) {
          i <- i + 1L
          next
        }
        # CTE SÜTUN LİSTESİ GÖVDE DEĞİLDİR.
        #
        # `WITH c(a,b) AS (SELECT ...) SELECT ...` geçerli T-SQL'dir ve ilk üst
        # düzey parantez SÜTUN LİSTESİDİR (`(a,b)`). Derinlik onun kapanışında
        # sıfıra döndüğü için tarayıcı `AS (SELECT ...) SELECT ...` döndürüyor,
        # çağıran da ifadeyi `cte_not_select` diye REDDEDİYORDU: CTE sütun
        # listesi kullanan HER salt-okunur kütüphane sorgusu kapıda düşerdi.
        # Kalan `AS` ile başlıyorsa gerçek gövde bir sonraki dengeli
        # parantezden SONRA gelir; taramaya devam edilir.
        if (grepl("^AS[[:space:](]", kalan, ignore.case = TRUE)) {
          i <- i + 1L
          next
        }
        return(kalan)
      }
    }
    i <- i + 1L
  }

  if (!gorulen_paren) return(NULL)
  NULL
}

#' SQL metnini salt-okunur olarak sınıflandır (KAPALI BAŞARISIZ)
#'
#' @return list(allowed, reason, detail, statement_kind, statement_count)
#'   `allowed = TRUE` yalnızca metin TEK bir salt-okunur SELECT (ya da son
#'   ifadesi SELECT olan bir CTE) olduğunda döner. Bunun önünde yalnızca tam
#'   `SET NOCOUNT ON;` öneki bulunabilir; başka batch yapıları reddedilir.
pk_sql_classify_readonly <- function(sql) {
  sonuc <- function(allowed, reason, kind = NA_character_, count = NA_integer_) {
    list(
      allowed = allowed,
      reason = reason,
      detail = if (is.null(reason)) NA_character_ else (PK_SQL_READONLY_REASONS[[reason]] %||% reason),
      statement_kind = kind,
      statement_count = count
    )
  }

  sql_text <- as.character(sql %||% "")[1]
  if (is.na(sql_text) || !nzchar(trimws(sql_text))) {
    return(sonuc(FALSE, "empty_sql"))
  }

  maske <- pk_sql_mask_literals(sql_text)
  if (!isTRUE(maske$ok)) {
    return(sonuc(FALSE, maske$reason))
  }

  ifadeler <- pk_sql_split_statements(maske$masked)
  if (length(ifadeler) == 2L &&
      grepl(PK_SQL_SAFE_NOCOUNT_PREAMBLE_PATTERN, ifadeler[[1L]],
            ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) {
    # Yalnızca tam SET NOCOUNT ON öneki tüketilir. İkinci ifade aşağıdaki
    # SELECT/CTE ve yan-etki kapılarının TAMAMINDAN geçmek zorundadır.
    ifadeler <- ifadeler[2L]
  }

  if (length(ifadeler) == 0L) {
    return(sonuc(FALSE, "no_statement", count = 0L))
  }
  if (length(ifadeler) > 1L) {
    return(sonuc(FALSE, "multiple_statements", count = length(ifadeler)))
  }

  ifade <- ifadeler[[1]]

  # Yan etkili anahtar kelimeler: maskelenmiş metinde HER YERDE aranır; böylece
  # veri değiştiren CTE (WITH x AS (DELETE ...)) ve SELECT ... INTO yakalanır.
  for (kelime in PK_SQL_FORBIDDEN_KEYWORDS) {
    if (.pk_sql_has_word(ifade, kelime)) {
      return(sonuc(FALSE, "forbidden_keyword", kind = kelime, count = 1L))
    }
  }

  for (onek in PK_SQL_FORBIDDEN_PREFIXES) {
    if (grepl(paste0("(^|[^A-Za-z0-9_])", onek), ifade,
              ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) {
      return(sonuc(FALSE, "forbidden_prefix", kind = onek, count = 1L))
    }
  }

  # Sequence ilerleten ifade: sozdizimi SELECT olsa da uretim durumunu degistirir.
  if (grepl(PK_SQL_SEQUENCE_MUTATION_PATTERN, ifade,
            ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) {
    return(sonuc(FALSE, "sequence_mutation", kind = "next_value_for", count = 1L))
  }

  # NOKTALI VİRGÜLSÜZ İKİNCİ İFADE.
  #
  # T-SQL ifadeler arasında `;` ZORUNLU KILMAZ: `SELECT 1\nSELECT 2` tek bir
  # dize olarak döner, hiçbir yasak-kelime taraması onu reddetmez ve
  # sınıflandırıcı "tek SELECT" der. Böyle bir kütüphane sorgusu BİRDEN FAZLA
  # sonuç kümesi üretebilir ve DBI, metadata/RLS yolunun beklediğinden BAŞKA
  # bir sonuç kümesini tüketebilir.
  #
  # Tespit DERİNLİK farkındadır: alt sorgular, türetilmiş tablolar, `EXISTS`,
  # `APPLY` ve CTE gövdeleri parantez içindedir (derinlik > 0) ve SAYILMAZ.
  # Derinlik-0'daki ikinci bir `SELECT` yalnızca bir küme işlecinden
  # (`UNION [ALL]` / `EXCEPT` / `INTERSECT`) sonra geliyorsa MEŞRUDUR.
  ek_ifade <- .pk_sql_extra_top_level_statement(ifade)
  if (!is.null(ek_ifade)) {
    return(sonuc(FALSE, "multiple_statements", kind = ek_ifade, count = 2L))
  }

  if (.pk_sql_starts_with_word(ifade, "SELECT")) {
    return(sonuc(TRUE, NULL, kind = "select", count = 1L))
  }

  if (.pk_sql_starts_with_word(ifade, "WITH")) {
    govde <- .pk_sql_cte_body(ifade)
    if (is.null(govde) || !nzchar(govde)) {
      return(sonuc(FALSE, "cte_not_select", count = 1L))
    }
    if (!.pk_sql_starts_with_word(govde, "SELECT")) {
      return(sonuc(FALSE, "cte_not_select", count = 1L))
    }
    return(sonuc(TRUE, NULL, kind = "cte_select", count = 1L))
  }

  # Parantezle başlayan `(SELECT ...) UNION ...` gibi biçimler de kabul edilir.
  if (grepl("^\\(\\s*SELECT($|[^A-Za-z0-9_@#$])", ifade,
            ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) {
    return(sonuc(TRUE, NULL, kind = "select", count = 1L))
  }

  sonuc(FALSE, "not_select", count = 1L)
}

#' Kapıyı çağrı yerinde uygula
#'
#' Reddedilen SQL için ham metin ASLA kullanıcıya dönmez; yalnızca sunucu
#' loguna operatör gerekçesi yazılır.
#'
#' @return list(allowed, message, reason)
pk_sql_readonly_guard <- function(sql, context_label = "PK_ANALIZ") {
  siniflandirma <- pk_sql_classify_readonly(sql)

  if (isTRUE(siniflandirma$allowed)) {
    return(list(allowed = TRUE, message = NULL, reason = NULL))
  }

  try(
    cat(sprintf(
      "[%s] SQL SALT-OKUNUR KAPISI REDDETTI | gerekce=%s | tur=%s | ifade_sayisi=%s | aciklama=%s\n",
      context_label,
      siniflandirma$reason %||% "?",
      siniflandirma$statement_kind %||% "?",
      siniflandirma$statement_count %||% "?",
      siniflandirma$detail %||% "?"
    )),
    silent = TRUE
  )

  list(
    allowed = FALSE,
    message = PK_SQL_READONLY_USER_MESSAGE,
    reason = siniflandirma$reason
  )
}

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

# Maskelenmis metindeki noktalivirguller ham metinle AYNI konumdadir; literal ve
# yorum icindeki noktalivirguller maskelendigi icin ifade siniri sayilmaz.
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
    "(#[A-Za-z_][A-Za-z0-9_]*)'[ \\t\\r\\n]*\\)[ \\t\\r\\n]+",
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
  kalip <- paste0(
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

  # Yalniz `INTO #YerelTemp` parcasi cikarilir; geri kalan SELECT mevcut D23
  # siniflandiricisinin BUTUN yasaklarindan tekrar gecmek zorundadir.
  kapi <- .pk_sql_classify_readonly_base(salt_okunur_karsilik)
  if (!isTRUE(kapi$allowed)) return(NULL)

  list(temp_name = parca[2], sql = pair$raw)
}

.pk_sql_local_temp_has_name <- function(names, name) {
  if (!length(names)) return(FALSE)
  any(vapply(names, function(x) .pk_sql_local_temp_name_equal(x, name), logical(1)))
}

# CREATE INDEX genel olarak yasaktir. Bu istisna yalnizca batch'in DAHA ONCE
# olusturdugu yerel #temp uzerindeki fiziksel indeksleri kabul eder. Kalici
# tablo, ##global temp veya baska yasakli SQL ailesi hedeflenirse NULL doner.
.pk_sql_local_temp_index <- function(pair, temp_names) {
  if (!is.list(pair) || !.pk_sql_starts_with_word(pair$masked %||% "", "CREATE")) {
    return(NULL)
  }

  metin <- trimws(as.character(pair$masked %||% "")[1])
  if (is.na(metin) || !nzchar(metin) || grepl("##", metin, fixed = TRUE)) return(NULL)

  m <- regexec(
    paste0(
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
  for (onek in PK_SQL_FORBIDDEN_PREFIXES) {
    if (grepl(paste0("(^|[^A-Za-z0-9_])", onek), metin,
              ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) return(NULL)
  }
  if (grepl(PK_SQL_SEQUENCE_MUTATION_PATTERN, metin,
            ignore.case = TRUE, perl = TRUE, useBytes = TRUE)) return(NULL)

  hedef
}

#' Yalnizca kanitlanmis yerel-#temp analitik batch planini dondur
#'
#' @return `list(ok, temp_names, staging_sql, result_sql, statement_count)`.
#'   `ok=FALSE` durumunda hicbir SQL parcasi yurutulmek icin guvenilir sayilmaz.
pk_sql_analyze_local_temp_batch <- function(sql) {
  bos <- function() list(
    ok = FALSE, temp_names = character(0), staging_sql = character(0),
    result_sql = NULL, statement_count = 0L
  )

  sql_text <- as.character(sql %||% "")[1]
  if (is.na(sql_text) || !nzchar(trimws(sql_text))) return(bos())

  maske <- pk_sql_mask_literals(sql_text)
  if (!isTRUE(maske$ok)) return(bos())

  # Yerel-temp istisnasi GO ile coklu batch'e ASLA genislemez.
  if (grepl(
    "(^|\\r\\n|\\n|\\r)[ \\t]*GO[ \\t]*(?=\\r\\n|\\n|\\r|$)",
    maske$masked, ignore.case = TRUE, perl = TRUE, useBytes = TRUE
  )) return(bos())

  ifadeler <- .pk_sql_local_temp_statement_pairs(sql_text, maske$masked)
  if (is.null(ifadeler) || length(ifadeler) < 3L) return(bos())

  temp_adlari <- character(0)
  staging <- character(0)
  sonuc_sql <- NULL
  temizlik <- character(0)
  i <- 1L

  while (i <= length(ifadeler)) {
    pair <- ifadeler[[i]]

    if (is.null(sonuc_sql)) {
      # Eski guvenli biçim korunur: predrop varsa hemen arkasindaki staging ile
      # birebir ayni #temp adini hedeflemelidir.
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

      # SSMS'te yaygin olan ikinci guvenli biçim: dinamik batch kapsami zaten
      # yerel #temp'i yalittigi icin predrop ZORUNLU degildir.
      stage <- .pk_sql_local_temp_stage(pair)
      if (!is.null(stage)) {
        if (.pk_sql_local_temp_has_name(temp_adlari, stage$temp_name)) return(bos())
        temp_adlari <- c(temp_adlari, stage$temp_name)
        staging <- c(staging, stage$sql)
        i <- i + 1L
        next
      }

      # Performans icin CREATE INDEX yalnizca daha once kanitlanmis yerel #temp
      # uzerinde olabilir. Metadata CTE donusumunde indeksler bilerek atlanir.
      index_hedef <- .pk_sql_local_temp_index(pair, temp_adlari)
      if (!is.null(index_hedef)) {
        i <- i + 1L
        next
      }

      # Kurulum bittikten sonra TAM OLARAK bir sonuc SELECT/CTE kabul edilir.
      if (!length(temp_adlari)) return(bos())
      sonuc_kapi <- .pk_sql_classify_readonly_base(pair$raw)
      if (!isTRUE(sonuc_kapi$allowed)) return(bos())
      sonuc_sql <- pair$raw
      i <- i + 1L
      next
    }

    # Sonuc SELECT'inden sonra yalnizca ayni batch'in yarattigi #temp DROP'lari.
    silinecekler <- .pk_sql_local_temp_cleanup(pair$raw)
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

# Mevcut siniflandiriciyi yalnizca `multiple_statements` sonucu icin daralt.
# Diger HER ret gerekcesi ve butun yasak anahtar kelime ratchet'leri aynen kalir.
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
    ifadeler <- if (isTRUE(maske$ok)) pk_sql_split_statements(maske$masked) else character(0)
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
