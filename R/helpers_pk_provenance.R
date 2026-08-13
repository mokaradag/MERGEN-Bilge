# ==============================================================================
# Dosya Yolu: R/helpers_pk_provenance.R
# Açıklama: Proje ve Kaynak Analizi için tipli bozulma (degradation) durumları,
#           kullanıcıya görünen kaynak/köken alt bilgisi ("Kaynakça" üslubunda)
#           ve istek kapsamlı alt bilgi saklama/iliştirme yardımcıları.
#
# Sözleşme:
#   * Alt bilgi R tarafından üretilir; modele asla yazdırılmaz.
#   * Alt bilgi KULLANICININ YETKİLİ POPÜLASYONUNDAN başlar. RLS ÖNCESİ satır
#     sayısı buraya, ek dosyalara veya modele giden pakete ASLA yazılmaz; o
#     değer yalnızca erişimi kısıtlı sunucu telemetrisinde tutulur. Aksi hâlde
#     kullanıcı, yetkisi dışındaki satır sayısını öğrenir ve bu bilgi sorgular
#     arasında sondalanarak göremeyeceği veri haritalanabilir.
#   * Her bozulma (zaman aşımı, düşen filtre, hata) kullanıcının OKUDUĞU yanıta
#     çıkar; yalnızca sunucu logunda kalması yeterli değildir.
#
# Bu dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur. İstek kapsamlı
# saklama fonksiyonları yalnızca kendilerine verilen ortam nesnesi üzerinde
# çalışır (test edilebilirlik için).
# ==============================================================================

# Filtre çıkarım adımının tipli sonuç durumları (D9).
# Bugün v1'de zaman aşımı, hata, bozuk yanıt ve "gerçekten filtre gerekmiyordu"
# aynı değeri döndürüyor; bu ayrım tam olarak o körlüğü kaldırmak içindir.
PK_FILTER_STATUS <- c(
  "ok_no_filter",   # LLM çalıştı, meşru biçimde filtre üretmedi
  "ok_filtered",    # LLM çalıştı, geçerli filtre üretti
  "timeout",        # LLM çağrısı zaman aşımına uğradı
  "error",          # LLM çağrısı hata verdi
  "malformed",      # Yanıt geldi ama çözümlenebilir/geçerli değildi
  "stopped",        # Kullanıcı işlemi durdurdu
  "disabled",       # Sorgu tanımında AI filtreleme kapalı (disable_ai_filters)
  "not_reached"     # Analiz filtre aşamasına hiç gelmedi (ör. yetki sonrası 0 satır)
)

pk_filter_status_valid <- function(status) {
  is.character(status) && length(status) == 1L && !is.na(status) && status %in% PK_FILTER_STATUS
}

pk_filter_status_normalize <- function(status) {
  if (pk_filter_status_valid(status)) status else "error"
}

# Kullanıcının filtresinin gerçekten uygulanmadığı, ancak sessizce
# "filtre gerekmiyordu" gibi görünen durumlar. Bunlar yanıtta AÇIKÇA belirtilir.
pk_filter_status_is_degraded <- function(status) {
  pk_filter_status_normalize(status) %in% c("timeout", "error", "malformed")
}

# Bozulma kodlarının Türkçe, kullanıcıya görünen karşılıkları.
.pk_degradation_messages <- list(
  filter_timeout = paste0(
    "Filtre çıkarımı zaman aşımına uğradı; sorunuzdaki kısıt UYGULANAMADI ve ",
    "analiz yetkiniz dâhilindeki tüm kayıtlar üzerinden yapıldı."
  ),
  filter_error = paste0(
    "Filtre çıkarımı sırasında hata oluştu; sorunuzdaki kısıt UYGULANAMADI ve ",
    "analiz yetkiniz dâhilindeki tüm kayıtlar üzerinden yapıldı."
  ),
  filter_malformed = paste0(
    "Filtre çıkarımı geçersiz bir yanıt üretti; sorunuzdaki kısıt UYGULANAMADI ve ",
    "analiz yetkiniz dâhilindeki tüm kayıtlar üzerinden yapıldı."
  )
)

#' Filtre durumundan kullanıcıya görünen bozulma kaydı üret
#'
#' @return Bozulma yoksa boş liste; varsa `list(list(code=, message=))`.
pk_degradations_from_filter_status <- function(status) {
  status <- pk_filter_status_normalize(status)
  if (!pk_filter_status_is_degraded(status)) return(list())

  code <- switch(
    status,
    timeout   = "filter_timeout",
    error     = "filter_error",
    malformed = "filter_malformed",
    "filter_error"
  )

  list(list(code = code, message = .pk_degradation_messages[[code]]))
}

# Türkçe binlik ayraçlı sayı biçimi (12405 -> "12.405"). Bilimsel gösterim yok.
.pk_format_count <- function(n) {
  if (is.null(n) || length(n) != 1L) return("?")
  num <- suppressWarnings(as.numeric(n))
  if (is.na(num) || !is.finite(num)) return("?")

  # Binlik ayracı ELLE eklenir. format()/formatC() Türkçe binlik ayracı "."
  # ile varsayılan ondalık ayracı "." çakıştığında uyarı üretir (katı test
  # paketi uyarıyı hata sayar) ve davranışları getOption("OutDec") yerel
  # ayarına bağlıdır. Bu biçimde çıktı yerelden bağımsızdır ve bilimsel
  # gösterim hiçbir koşulda oluşmaz (§5.7 / D19).
  x <- as.integer(round(num))
  grouped <- gsub("(?<=[0-9])(?=([0-9]{3})+$)", ".", as.character(abs(x)), perl = TRUE)

  if (x < 0L) paste0("-", grouped) else grouped
}

# Alt bilgiye giren serbest metinleri (LLM/kullanıcı kaynaklı filtre değerleri
# dâhil) tek satıra indirger, markdown yapısını bozabilecek karakterleri
# etkisizleştirir ve uzunluğu sınırlar. Ham HTML kaçışı ayrıca merkezî
# markdown güvenlik sınırında yapılır; burada amaç yapısal bozulmayı önlemektir.
.pk_footer_sanitize <- function(x, max_chars = 120L) {
  if (is.null(x) || length(x) == 0L) return("")

  txt <- as.character(x)[1]
  if (is.na(txt)) return("")

  txt <- gsub("[\r\n\t]+", " ", txt)
  txt <- gsub("[`|]", " ", txt)
  txt <- gsub("[[:space:]]+", " ", txt)
  txt <- trimws(txt)

  if (nchar(txt) > max_chars) {
    txt <- paste0(substr(txt, 1L, max_chars), "…")
  }

  txt
}

.pk_operation_label <- function(op) {
  switch(
    as.character(op %||% "exact_match")[1],
    exact_match  = "tam eşleşme",
    contains     = "içerir",
    greater_than = "büyüktür",
    less_than    = "küçüktür",
    "eşleşme"
  )
}

# Uygulanan filtrelerin tek satırlık okunur özeti.
.pk_footer_filter_line <- function(provenance) {
  status <- pk_filter_status_normalize(provenance$filter_status)
  filters <- provenance$filters %||% list()

  if (identical(status, "disabled")) {
    return("Bu sorgu için AI filtreleme kapalıdır (yalnızca yetki filtresi uygulandı).")
  }

  if (identical(status, "not_reached")) {
    return("Uygulanmadı (analiz filtre aşamasına ulaşmadı).")
  }

  if (identical(status, "stopped")) {
    return("İptal edildi (filtreleme tamamlanmadı).")
  }

  if (pk_filter_status_is_degraded(status)) {
    return("Uygulanamadı (aşağıdaki uyarıya bakınız).")
  }

  if (length(filters) == 0L) {
    return("Uygulanmadı (soru genel olarak yorumlandı).")
  }

  parts <- vapply(filters, function(f) {
    col <- .pk_footer_sanitize(f$column %||% "?", 60L)
    val <- .pk_footer_sanitize(paste(as.character(f$value %||% ""), collapse = ", "), 80L)
    sprintf("%s = \"%s\" (%s)", col, val, .pk_operation_label(f$operation))
  }, character(1))

  paste(parts, collapse = " · ")
}

# Satır sayısı satırı. Başlangıç noktası DAİMA yetkili popülasyondur.
.pk_footer_row_line <- function(provenance) {
  authorized <- provenance$authorized_rows
  filtered <- provenance$filtered_rows

  if (is.null(authorized)) return(NULL)

  if (is.null(filtered) || identical(as.integer(filtered), as.integer(authorized))) {
    return(sprintf("%s (yetkiniz dâhilinde)", .pk_format_count(authorized)))
  }

  sprintf(
    "%s (yetkiniz dâhilinde) → %s (filtre sonrası)",
    .pk_format_count(authorized),
    .pk_format_count(filtered)
  )
}

# Ek (attachment) satırı: dosya adı, satır x sütun ve (varsa) oturum kapsamlı
# indirme bağlantısı. Reddedilen dışa aktarım da GÖRÜNÜR olmalıdır; sessizce
# kırpılmış bir dosya "eksiksiz" gibi sunulmaz (§5.9 madde 6).
.pk_footer_attachment_line <- function(attachment) {
  if (!is.list(attachment)) return(NULL)

  if (identical(attachment$status, "refused") || identical(attachment$status, "failed")) {
    msg <- .pk_footer_sanitize(attachment$message %||% "", 300L)
    if (!nzchar(msg)) return(NULL)
    return(sprintf("- **Ek:** Üretilmedi — %s", msg))
  }

  dosyalar <- attachment$files %||% list()
  if (!length(dosyalar)) return(NULL)

  parcalar <- vapply(dosyalar, function(d) {
    ad <- .pk_footer_sanitize(d$name %||% "", 80L)
    olcu <- sprintf("%s satır × %s sütun", .pk_format_count(d$rows), .pk_format_count(d$cols))
    if (is.null(d$url) || !nzchar(as.character(d$url)[1])) {
      sprintf("%s (%s)", ad, olcu)
    } else {
      sprintf("[%s](%s) (%s)", ad, as.character(d$url)[1], olcu)
    }
  }, character(1))

  sprintf("- **Ek:** %s", paste(parcalar, collapse = " · "))
}

#' Kullanıcıya görünen köken (provenance) alt bilgisini üret
#'
#' @param provenance `list(query_id=, query_name=, filter_status=, filters=,
#'   authorized_rows=, filtered_rows=, degradations=)`
#' @return Markdown metni; üretilemezse "" döner.
pk_build_provenance_footer <- function(provenance) {
  if (!is.list(provenance) || length(provenance) == 0L) return("")

  # Güvenlik ağı: RLS öncesi sayım kazara eklenmiş olsa bile alt bilgiye
  # asla yazılmaz. Bu alan yalnızca kısıtlı telemetride yaşar.
  lines <- character(0)

  query_id <- .pk_footer_sanitize(provenance$query_id %||% "", 40L)
  query_name <- .pk_footer_sanitize(provenance$query_name %||% "", 120L)
  source_txt <- if (nzchar(query_id) && nzchar(query_name)) {
    sprintf("%s · %s", query_id, query_name)
  } else if (nzchar(query_name)) {
    query_name
  } else if (nzchar(query_id)) {
    query_id
  } else {
    ""
  }

  if (nzchar(source_txt)) {
    lines <- c(lines, sprintf("- **Sorgu:** %s", source_txt))
  }

  lines <- c(lines, sprintf("- **Filtre:** %s", .pk_footer_filter_line(provenance)))

  row_line <- .pk_footer_row_line(provenance)
  if (!is.null(row_line)) {
    lines <- c(lines, sprintf("- **Satır:** %s", row_line))
  }

  attachment_line <- .pk_footer_attachment_line(provenance$attachment)
  if (!is.null(attachment_line)) {
    lines <- c(lines, attachment_line)
  }

  degradations <- provenance$degradations %||% list()
  for (d in degradations) {
    msg <- .pk_footer_sanitize(d$message %||% "", 400L)
    if (nzchar(msg)) {
      lines <- c(lines, sprintf("- **\U000026A0\U0000FE0F Uyarı:** %s", msg))
    }
  }

  if (length(lines) == 0L) return("")

  paste0(
    "\n\n---\n",
    "**Analiz Kaynağı**\n",
    paste(lines, collapse = "\n"),
    "\n"
  )
}

# İstek kapsamlı alt bilgi saklama ------------------------------------------
#
# Alt bilgi, PK modülü LLM'den ÖNCE döndüğü anda bilinir; yanıt metnine ise
# akış sonlandırmasında iliştirilir. Arada tutulacak küçük bir yuvaya ihtiyaç
# vardır. Yuva her istekte temizlendiği ve okunduğunda tüketildiği için bayat
# bir alt bilgi bir sonraki yanıta yapışamaz.

.pk_provenance_slot <- "pk_provenance_pending"

# session$userData yerine doğrudan verilen ortam nesnesiyle çalışır; böylece
# testler sahte bir ortam geçirebilir.
.pk_provenance_store <- function(session) {
  if (is.null(session)) return(NULL)
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(NULL)
  ud
}

.pk_provenance_request_slot <- "pk_provenance_request_id"
.pk_provenance_done_slot <- "pk_provenance_decorated_ids"

#' Yeni istek başlat: bekleyen alt bilgiyi temizle ve aktif istek kimliğini yaz
#'
#' Her istek başında çağrıldığı için bayat bir alt bilgi bir sonraki yanıta
#' yapışamaz. Geç tamamlanan eski bir istek alt bilgisini kaybedebilir; bu
#' bilinçli bir ödünleşimdir - eksik alt bilgi güvenlidir, YANLIŞ alt bilgi
#' değildir.
pk_provenance_clear <- function(session, request_id = NULL) {
  store <- .pk_provenance_store(session)
  if (is.null(store)) return(invisible(FALSE))

  tryCatch({
    store[[.pk_provenance_slot]] <- NULL
    store[[.pk_provenance_request_slot]] <- if (is.null(request_id)) {
      NULL
    } else {
      as.character(request_id)[1]
    }
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

#' Aktif istek kimliğini oku (telemetri korelasyonu ve bayatlık koruması için)
pk_provenance_current_request_id <- function(session) {
  store <- .pk_provenance_store(session)
  if (is.null(store)) return(NULL)

  tryCatch(store[[.pk_provenance_request_slot]], error = function(e) NULL)
}

#' Alt bilgiyi istek kapsamlı olarak sakla
#'
#' Faz 2: alt bilginin yanında, §5.11 sayısal köken doğrulaması için
#' yapılandırılmış olgular ve `block` kipinde gösterilecek deterministik yedek
#' metin de saklanabilir. Alanlar OPSİYONELDİR; verilmezse davranış Faz 0 ile
#' aynıdır.
pk_provenance_stash <- function(session, footer, request_id = NULL,
                                facts = NULL, fallback_text = NULL,
                                query_id = NULL, mode = NULL) {
  store <- .pk_provenance_store(session)
  if (is.null(store)) return(invisible(FALSE))
  if (is.null(footer) || !nzchar(as.character(footer)[1])) return(invisible(FALSE))

  # BAYAT İSTEK KORUMASI: yuva tektir. B isteği olgularını koyduktan sonra
  # geç biten A isteği yazarsa B'nin sayısal doğrulaması, R'ye ait tablosu,
  # eki ve alt bilgisi kaybolurdu; `pk_provenance_take()` içindeki kimlik
  # denetimi ezilmiş kaydı GERİ GETİREMEZ.
  aktif <- store[[.pk_provenance_request_slot]]
  if (!is.null(request_id) && !is.null(aktif) &&
      !identical(as.character(request_id)[1], as.character(aktif)[1])) {
    return(invisible(FALSE))
  }

  tryCatch({
    store[[.pk_provenance_slot]] <- list(
      footer = as.character(footer)[1],
      request_id = if (is.null(request_id)) NULL else as.character(request_id)[1],
      facts = facts,
      fallback_text = fallback_text,
      query_id = query_id,
      mode = mode
    )
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

#' Bekleyen alt bilgiyi al ve yuvayı tüket
#'
#' `request_id` verilirse ve saklanan kimlikle uyuşmazsa alt bilgi
#' İLİŞTİRİLMEZ (yanlış yanıta yapışmaktansa hiç görünmemesi yeğlenir).
#'
#' @param full `TRUE` ise yalnızca alt bilgi metni değil, saklanan kaydın
#'   tamamı (olgular ve yedek metin dâhil) döner.
pk_provenance_take <- function(session, request_id = NULL, full = FALSE) {
  store <- .pk_provenance_store(session)
  if (is.null(store)) return(NULL)

  pending <- tryCatch(store[[.pk_provenance_slot]], error = function(e) NULL)
  if (is.null(pending) || !is.list(pending)) return(NULL)

  # Kimlik ÖNCE karşılaştırılır: uyuşmayan bayat bir tamamlama, yuvayı
  # tüketerek YENİ isteğin kaydını silmemelidir.
  #
  # KİMLİKSİZ ÇAĞRI DA REDDEDİLİR. Eski davranışta muhafız YALNIZCA çağıran
  # `request_id` verdiğinde çalışıyordu; kimliksiz bir tamamlama yolu (eş
  # zamanlı olmayan yanıt işleyicisi, benzetilmiş akış, hata temizliği) o an
  # bekleyen HANGİ kayıt varsa onu tüketiyordu. A isteği B'den sonra bittiğinde
  # A, B'nin olgularına göre doğrulanıyor ve B'nin alt bilgisini/ekini alıyor;
  # B ise kaydını kaybediyordu. Kayıt bir isteğe AİTSE, sahibini kanıtlamayan
  # çağrı onu ne okuyabilir ne de silebilir.
  if (!is.null(pending$request_id) &&
      (is.null(request_id) ||
       !identical(as.character(request_id)[1], pending$request_id))) {
    return(NULL)
  }

  tryCatch(store[[.pk_provenance_slot]] <- NULL, error = function(e) NULL)

  if (isTRUE(full)) return(pending)
  pending$footer
}

#' Nihai yanıt metnine bekleyen alt bilgiyi iliştir
#'
#' İdempotentlik MODEL METNİNE DEĞİL, istek kimliğine bağlıdır: eskiden metinde
#' `**Analiz Kaynağı**` başlığını görmek dekorasyonu tamamen atlatıyordu, yani
#' modelin (ya da bir veri değerinin yönlendirmesiyle) o başlığı yazması
#' doğrulanmamış düzyazıyı `[fact:...]` işaretleriyle birlikte geçirir, R'ye ait
#' bloğu ve alt bilgiyi düşürürdü.
#'
#' Hiçbir koşulda hata fırlatmaz; başarısızlıkta metin değişmeden döner.
pk_provenance_decorate <- function(text, session, request_id = NULL) {
  # KAYIT TÜKETİLDİKTEN SONRAKİ HER HATA İÇİN GÜVENLİ GERİ DÜŞME.
  #
  # Dıştaki hata yakalayıcı, kaydı TÜKETTİKTEN SONRA
  # oluşan bir hatada da ham model metnini döndürüyordu. `block` kipinde bu,
  # doğrulanmamış düzyazının kullanıcıya gitmesi demektir ve kayıt tüketildiği
  # için yeniden denemek de mümkün değildir. Bu yüzden tüketilen kaydın
  # deterministik yedek metni burada tutulur ve hata hâlinde O kullanılır.
  guvenli_yedek <- NULL

  tryCatch({
    pending <- pk_provenance_take(session, request_id = request_id, full = TRUE)
    if (is.null(pending) || !is.list(pending)) return(text)

    # `block` kipinde TÜKETİLMİŞ kayıt için güvenli geri düşme metni hazırlanır.
    if (identical(as.character(pending$mode %||% "")[1], "block")) {
      yedek <- as.character(pending$fallback_text %||% "")[1]
      if (!is.na(yedek) && nzchar(yedek)) {
        guvenli_yedek <- paste0(yedek, as.character(pending$footer %||% "")[1])
      }
    }

    footer <- pending$footer
    if (is.null(footer) || !nzchar(footer)) return(text)

    base_txt <- if (is.null(text) || length(text) == 0L) "" else as.character(text)[1]
    if (is.na(base_txt)) base_txt <- ""

    # Bant dışı idempotentlik: aynı istek ikinci kez dekore edilmez.
    store <- .pk_provenance_store(session)
    kimlik <- as.character(request_id %||% pending$request_id %||% "")[1]
    if (is.environment(store) && nzchar(kimlik)) {
      bitenler <- as.character(store[[.pk_provenance_done_slot]] %||% character(0))
      if (kimlik %in% bitenler) return(text)
      store[[.pk_provenance_done_slot]] <- utils::tail(unique(c(bitenler, kimlik)), 20L)
    }

    # §5.11: Sayısal iddialar olgulara karşı doğrulanır ve `[fact:...]`
    # referansları YALNIZCA doğrulamadan SONRA gösterimden silinir. Olgu
    # saklanmamışsa (v1 yolu) bu adım tamamen atlanır.
    #
    # KAPALI BAŞARISIZLIK: doğrulama kendi içinde hata verse bile
    # `pk_numeric_provenance_apply()` deterministik yedek metni döndürür
    # (bkz. helpers_pk_numeric_provenance.R). Bekleyen kayıt zaten
    # tüketildiği için dıştaki tryCatch'e düşüp ham model metnini döndürmek,
    # `block` kipinde bile doğrulanmamış düzyazıyı göstermek olurdu.
    if (!is.null(pending$facts) &&
        exists("pk_numeric_provenance_apply", mode = "function", inherits = TRUE)) {
      sonuc <- pk_numeric_provenance_apply(
        base_txt, pending$facts, mode = pending$mode,
        fallback_text = pending$fallback_text
      )
      base_txt <- sonuc$text
      if (exists("pk_numeric_provenance_report", mode = "function", inherits = TRUE)) {
        try(pk_numeric_provenance_report(sonuc, pending$query_id), silent = TRUE)
      }
    }

    # Model metni kapatılmamış bir kod bloğuyla bitiyorsa, R'ye ait tablo/ek/alt
    # bilgi o bloğun İÇİNE düşer ve indirme bağlantısı tıklanamaz hâle gelir.
    if (exists("pk_compose_close_markdown", mode = "function", inherits = TRUE)) {
      base_txt <- pk_compose_close_markdown(base_txt)
    }

    paste0(base_txt, footer)
  }, error = function(e) {
    if (!is.null(guvenli_yedek)) return(guvenli_yedek)
    text
  })
}
