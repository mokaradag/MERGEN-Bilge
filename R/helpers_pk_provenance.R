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
pk_provenance_stash <- function(session, footer, request_id = NULL) {
  store <- .pk_provenance_store(session)
  if (is.null(store)) return(invisible(FALSE))
  if (is.null(footer) || !nzchar(as.character(footer)[1])) return(invisible(FALSE))

  tryCatch({
    store[[.pk_provenance_slot]] <- list(
      footer = as.character(footer)[1],
      request_id = if (is.null(request_id)) NULL else as.character(request_id)[1]
    )
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

#' Bekleyen alt bilgiyi al ve yuvayı tüket
#'
#' `request_id` verilirse ve saklanan kimlikle uyuşmazsa alt bilgi
#' İLİŞTİRİLMEZ (yanlış yanıta yapışmaktansa hiç görünmemesi yeğlenir).
pk_provenance_take <- function(session, request_id = NULL) {
  store <- .pk_provenance_store(session)
  if (is.null(store)) return(NULL)

  pending <- tryCatch(store[[.pk_provenance_slot]], error = function(e) NULL)
  if (is.null(pending) || !is.list(pending)) return(NULL)

  tryCatch(store[[.pk_provenance_slot]] <- NULL, error = function(e) NULL)

  if (!is.null(request_id) && !is.null(pending$request_id) &&
      !identical(as.character(request_id)[1], pending$request_id)) {
    return(NULL)
  }

  pending$footer
}

#' Nihai yanıt metnine bekleyen alt bilgiyi iliştir
#'
#' Fonksiyon idempotenttir: alt bilgi zaten iliştirilmişse tekrar eklenmez.
#' Hiçbir koşulda hata fırlatmaz; başarısızlıkta metin değişmeden döner.
pk_provenance_decorate <- function(text, session, request_id = NULL) {
  tryCatch({
    footer <- pk_provenance_take(session, request_id = request_id)
    if (is.null(footer) || !nzchar(footer)) return(text)

    base_txt <- if (is.null(text) || length(text) == 0L) "" else as.character(text)[1]
    if (is.na(base_txt)) base_txt <- ""

    if (grepl("**Analiz Kaynağı**", base_txt, fixed = TRUE)) return(text)

    paste0(base_txt, footer)
  }, error = function(e) text)
}
