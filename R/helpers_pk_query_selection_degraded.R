# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_degraded.R
# Açıklama: Faz 5 (§5.2) — LLM hata SINIFLANDIRMASI ve BOZULMA KİPİ kararları.
#
# TEŞHİS DOĞRULUĞU BİR ÜRÜN ÖZELLİĞİDİR: kullanıcıya "yapay zekâ servisine
# ulaşılamıyor" demek, servis yanıt verirken sözleşmeyi ihlal ettiğinde ya da
# kimlik bilgisi eksik olduğunda YANLIŞ bir yönlendirmedir; operatör asılı uç
# nokta ararken gerçek kusur (istem/ayrıştırıcı gerilemesi ya da anahtar
# yapılandırması) görünmez kalır.
#
# Sınıflandırma tablosu:
#   * zaman aşımı metinleri + HTTP 408/504    -> timeout
#   * AUTH_MISSING_KEY / HTTP 401 / HTTP 403  -> auth_error
#   * EMPTY_RESPONSE                          -> malformed (onarım denenebilir)
#   * geri kalan her şey                      -> llm_unavailable
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# DİKKAT — burada yalın `"connect"` KULLANILMAZ: "connection refused" bir zaman
# aşımı DEĞİL, anında reddedilmiş bir bağlantıdır ve ölçüldüğünde `timeout`
# olarak sınıflanıyordu. Gerçek zaman aşımı metinleri ("Connection timed out"
# dâhil) zaten "timed out" ile yakalanır.
.PK_SELECT_TIMEOUT_PATTERNS <- c(
  "timeout", "timed out", "zaman a", "operation was aborted",
  "resolving timed out"
)

# `call_local_llm()` HTTP kusurlarını `API_HTTP_ERROR_<status>` ile bildirir.
# 504 "Gateway Time-out" gövdesi metinsel desenlere UYMAYABİLİR; durum kodu
# tek güvenilir sinyaldir.
.PK_SELECT_TIMEOUT_HTTP <- c("api_http_error_408", "api_http_error_504")
.PK_SELECT_AUTH_MARKERS <- c(
  "auth_missing_key", "api_http_error_401", "api_http_error_403"
)

#' LLM hata metnini KARAR DURUMUNA çevir
.pk_select_classify_error <- function(message) {
  metin <- tolower(as.character(message)[1] %||% "")

  esles <- function(desenler) {
    any(vapply(desenler, function(p) grepl(p, metin, fixed = TRUE), logical(1)))
  }

  if (esles(.PK_SELECT_TIMEOUT_PATTERNS) || esles(.PK_SELECT_TIMEOUT_HTTP)) {
    return(PK_SELECT_STATUS_TIMEOUT)
  }
  if (esles(.PK_SELECT_AUTH_MARKERS)) return(PK_SELECT_STATUS_AUTH_ERROR)
  # Servis CEVAP VERDİ ama gövde boştu: bu bir kesinti değil, bozuk çıktıdır ve
  # onarım denemesi anlamlıdır.
  if (esles("empty_response")) return(PK_SELECT_STATUS_MALFORMED)

  PK_SELECT_STATUS_LLM_UNAVAILABLE
}

#' Bozulma kipinde kullanıcıya gösterilecek mesaj
.pk_select_degraded_message <- function(status) {
  if (identical(status, PK_SELECT_STATUS_AUTH_ERROR)) {
    return(paste0(
      "Sorgu seçimi yapılamadı: yapay zekâ servisi için geçerli bir API ",
      "anahtarı bulunamadı ya da reddedildi. Ayarlar > API Anahtarı bölümünü ",
      "kontrol edin. Aşağıdaki analizlerden birini belirtirseniz devam edebilirim."
    ))
  }
  if (identical(status, PK_SELECT_STATUS_MALFORMED)) {
    return(paste0(
      "Sorgu seçimi güvenilir bir sonuç üretemedi (model sözleşmeye uymayan bir ",
      "cevap döndürdü). Aşağıdaki analizlerden birini belirtebilir ya da ",
      "sorunuzu daha açık yazabilirsiniz."
    ))
  }
  paste0(
    "Sorgu seçimi şu anda yapılamadı (yapay zekâ servisine ulaşılamıyor). ",
    "Aşağıdaki analizlerden hangisini istediğinizi belirtirseniz devam edebilirim."
  )
}

#' Bozulma kipi için ANLAMLI sözlüksel adaylar
#'
#' `pk_retrieval_score()` skoru 0 olsa bile TÜM kütüphaneyi döndürür ve
#' eşitlikte kimliğe göre sıralar. Filtrelenmeden kullanıldığında, soruyla
#' hiçbir örtüşmesi olmayan ilk üç kimlik "olası analizler" diye sunuluyordu.
#' Yalnızca POZİTİF skorlu adaylar seçenek olabilir.
#'
#' Takip bağlamı korunur: eksiltili bir soruda ("peki 2024 için?") sorgu
#' taşıyan tek kanıt ÖNCEKİ KARARLI KİMLİKTİR; kesinti onu silmemelidir.
pk_select_degraded_candidates <- function(index, prompt, library_index,
                                          prior_query_id = NULL,
                                          restrict_ids = NULL) {
  siralama <- if (is.null(index)) NULL else pk_retrieval_score(index, prompt)

  kimlikler <- character(0)
  if (!is.null(siralama) && nrow(siralama)) {
    pozitif <- siralama[siralama$score > 0, , drop = FALSE]
    kimlikler <- as.character(pozitif$query_id)
  }

  # Geçiş A başarılıysa aday kümesi ZATEN bağlam farkındadır; bozulma o kümenin
  # İÇİNDE kalmalıdır. Aksi hâlde `candidate_ids` bir kümeyi, `chips` bambaşka
  # bir kümeyi anlatırdı.
  if (!is.null(restrict_ids) && length(restrict_ids)) {
    sirali <- kimlikler[kimlikler %in% restrict_ids]
    kimlikler <- unique(c(sirali, as.character(restrict_ids)))
  }

  onceki <- if (!is.null(prior_query_id) && length(prior_query_id) &&
                !is.na(prior_query_id[1]) && nzchar(trimws(as.character(prior_query_id)[1]))) {
    trimws(as.character(prior_query_id)[1])
  } else {
    NA_character_
  }

  if (!is.na(onceki) && !is.null(library_index[[onceki]])) {
    kimlikler <- unique(c(onceki, kimlikler))
  }

  kimlikler
}

#' Bozulma kipi kararı (§5.2)
#'
#' Sözlüksel adaylar KULLANICIYA seçenek olarak sunulur; hiçbir zaman otomatik
#' çalıştırılmaz. Bu, sözlüksel katmanın izin verilen tek "öne çıkarma"
#' rolüdür (D10).
pk_select_degraded_decision <- function(status, index, prompt, library_index,
                                        prior_query_id = NULL,
                                        restrict_ids = NULL) {
  kimlikler <- pk_select_degraded_candidates(
    index, prompt, library_index,
    prior_query_id = prior_query_id, restrict_ids = restrict_ids
  )

  if (!length(kimlikler)) {
    return(.pk_select_decision(
      status,
      message_tr = paste0(
        "Sorgu seçimi şu anda yapılamadı ve sorunuza yakın bir analiz de ",
        "bulunamadı. Lütfen sorunuzu farklı kelimelerle yeniden ifade edin."
      ),
      disclosures = "Seçim sözlüksel getirime düşürüldü; eşleşen aday yok."
    ))
  }

  .pk_select_decision(
    status,
    message_tr = .pk_select_degraded_message(status),
    chips = pk_select_chips(kimlikler, library_index),
    disclosures = "Seçim sözlüksel getirime düşürüldü; otomatik çalıştırma yapılmadı."
  )
}
