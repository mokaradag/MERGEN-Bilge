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
  sequence_mutation    = "Sequence ilerleten ifade (NEXT VALUE FOR) durum değiştirir.",
  loader_placeholder   = "Sorgu SQL'i yüklenemedi; yer tutucu metin çalıştırılmaz."
)

# YÜKLEYİCİ YER TUTUCUSU.
#
# `R/config_sql_loader.R` bir sorgunun SQL dosyasını okuyamadığında (dosya yok,
# okuma hatası ya da ne `sql_file` ne `sql` tanımlı) `sql` alanını BOŞ
# bırakmaz; `pk_query_meta_attach()` boş SQL'de açılışı düşürdüğü için yer
# tutucu bir SELECT yazar. Bu metin SÖZDİZİMSEL OLARAK geçerli, salt-okunur bir
# SELECT'tir: kapı onu kendiliğinden reddetmez ve analiz, gerçek veri yerine
# sahte tek satırlık bir sonuç üzerinden yürüyebilirdi. İşaret açıkça
# REDDEDİLİR; degradasyon sessiz kalmaz.
PK_SQL_LOADER_PLACEHOLDER_MARKER <- "sql_loader_placeholder"

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

# TANIMLAYICI SINIRI UNICODE FARKINDADIR.
#
# T-SQL düzenli (tırnaksız) tanımlayıcıları Unicode HARFLERİ içerebilir; `Ş`
# (U+015E) geçerli bir tanımlayıcı karakteridir. ASCII-only sınıf + `useBytes`
# ile taranan `SELECT ŞDROP FROM dbo.T` metninde `Ş`nin baytları "harf değil"
# sayılıyor, sınır `DROP`tan hemen önce EŞLEŞİYOR ve salt-okunur kapı GEÇERLİ
# bir sorguyu analizden ÖNCE reddediyordu (`Şsp_name` için de aynısı).
#
# Metin geçerli UTF-8 değilse Unicode taraması hata verir; o durumda ESKİ bayt
# taramasına düşülür (daha geniş eşleşen, yani KAPALI BAŞARISIZ olan yol).
.PK_SQL_IDENT_BEFORE <- "(?<![\\p{L}\\p{N}_@#$])"
.PK_SQL_IDENT_AFTER  <- "(?![\\p{L}\\p{N}_@#$])"

.pk_sql_utf8_scan_text <- function(text) {
  ham <- suppressWarnings(enc2utf8(as.character(text %||% "")[1]))
  if (length(ham) != 1L || is.na(ham) || !validUTF8(ham)) NULL else ham
}

.pk_sql_has_word <- function(text, word) {
  utf <- .pk_sql_utf8_scan_text(text)
  if (is.null(utf)) {
    return(grepl(paste0("(^|[^A-Za-z0-9_@#$])", word, "($|[^A-Za-z0-9_@#$])"),
                 text, ignore.case = TRUE, perl = TRUE, useBytes = TRUE))
  }
  grepl(paste0(.PK_SQL_IDENT_BEFORE, word, .PK_SQL_IDENT_AFTER), utf,
        ignore.case = TRUE, perl = TRUE)
}

.pk_sql_starts_with_word <- function(text, word) {
  utf <- .pk_sql_utf8_scan_text(text)
  if (is.null(utf)) {
    return(grepl(paste0("^", word, "($|[^A-Za-z0-9_@#$])"),
                 text, ignore.case = TRUE, perl = TRUE, useBytes = TRUE))
  }
  grepl(paste0("^", word, .PK_SQL_IDENT_AFTER), utf, ignore.case = TRUE, perl = TRUE)
}

# ÖNEK TARAMASI: yalnızca SOL sınır vardır (`sp_` deseni `sp_who` ile eşleşmeli).
.pk_sql_has_prefix <- function(text, prefix) {
  utf <- .pk_sql_utf8_scan_text(text)
  if (is.null(utf)) {
    return(grepl(paste0("(^|[^A-Za-z0-9_])", prefix), text,
                 ignore.case = TRUE, perl = TRUE, useBytes = TRUE))
  }
  grepl(paste0("(?<![\\p{L}\\p{N}_])", prefix), utf, ignore.case = TRUE, perl = TRUE)
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

  # Yer tutucu işareti HAM metinde aranır: işaret bir dize sabitinin İÇİNDEDİR
  # ve maskeleme sonrası görünmez olurdu.
  if (grepl(PK_SQL_LOADER_PLACEHOLDER_MARKER, sql_text, fixed = TRUE)) {
    return(sonuc(FALSE, "loader_placeholder"))
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
    if (.pk_sql_has_prefix(ifade, onek)) {
      return(sonuc(FALSE, "forbidden_prefix", kind = onek, count = 1L))
    }
  }

  # Sequence ilerleten ifade: sözdizimi SELECT olsa da üretim durumunu değiştirir.
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
