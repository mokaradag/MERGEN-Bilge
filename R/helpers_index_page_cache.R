# ==============================================================================
# Dosya Yolu: R/helpers_index_page_cache.R
# Açıklama: Kök sayfa (GET /) HTML önbellekleme yardımcıları.
#
# Shiny, STATİK bir UI nesnesi için bile HER GET / isteğinde renderPage() ile
# tüm etiket ağacını yeniden HTML'e serileştirir. MERGEN Bilge UI'si tamamen
# statiktir: önyüklemede (ui.R source edilirken) bir kez kurulur, her istek ve
# her kullanıcı için aynıdır ve yer imi (bookmark) kullanılmaz. Bu yüzden
# serileştirilen HTML her istekte BİREBİR AYNIDIR; her istekte yeniden üretmek
# gereksiz CPU maliyetidir (üretim Windows VM'inde boşta ~0.64 sn/GET /, eş
# zamanlı yük altında soak gecikmesinin başlıca HTTP-kanal kaynağı).
#
# shiny:::uiHttpHandler iç davranışı: ui FONKSİYONU bir httpResponse döndürürse
# renderPage() ATLANIR ve yanıt doğrudan sunulur. Bu yardımcı, kök sayfayı İLK
# istekte bir kez render edip httpResponse'u önbelleğe alır; sonraki istekler
# yeniden serileştirme olmadan sunulur.
#
# GÜVENLİK / GERİ DÖNÜŞ: render veya iç Shiny API erişimi başarısız olursa
# statik UI etiketleri döndürülür ve Shiny her zamanki gibi render eder (mevcut
# davranışla bayt-bayt aynı). Önbellek hiçbir zaman bozuk/yarım bir yanıtla
# kirletilmez; başarısızlıkta bir sonraki istekte yeniden denenir. Özellik
# bayrağı MERGEN_CACHE_INDEX_HTML ile hızlıca kapatılabilir (VM'de geri alma).
#
# Bu dosya SAF yardımcılar içerir: yalnızca fonksiyon tanımlar, source-time'da
# Shiny/ağ/DB erişimi yapmaz; izole testlerde tek başına source edilebilir.
# ==============================================================================

# Özellik bayrağı: varsayılan AÇIK. VM'de hızlıca kapatmak için
# MERGEN_CACHE_INDEX_HTML=false (veya 0/off/hayir/kapali) ayarlanabilir.
mergen_index_html_cache_enabled <- function() {
  value <- tolower(trimws(Sys.getenv("MERGEN_CACHE_INDEX_HTML", "true")))
  !(value %in% c("0", "false", "f", "no", "n", "off", "hayir", "kapali"))
}

# Shiny'nin kök sayfayı render eden iç fonksiyonunu güvenli biçimde çözer.
# İç (unexported) API olduğu için bulunamazsa NULL döner ve çağıran taraf
# statik UI'ye güvenli biçimde geri döner.
mergen_resolve_render_page_fn <- function() {
  tryCatch(
    get("renderPage", envir = asNamespace("shiny")),
    error = function(e) NULL
  )
}

# Kök sayfa (GET /) için ya statik UI'yi (önbellek kapalı) ya da ilk render'ı
# önbelleğe alan bir ui fonksiyonu döndürür.
#
# Argümanlar:
#   static_ui      : önyüklemede kurulmuş statik Shiny UI etiket nesnesi.
#   enabled        : önbellekleme açık mı (varsayılan: ortam bayrağı).
#   render_page_fn : test edilebilirlik için enjekte edilebilir render
#                    fonksiyonu; NULL ise Shiny'nin renderPage'i çözülür.
#
# Dönüş:
#   - enabled FALSE ise : static_ui (mevcut davranış; Shiny her istekte render eder)
#   - enabled TRUE ise  : function(req) -> httpResponse (ilk render önbelleğe alınır)
mergen_build_index_ui <- function(static_ui,
                                  enabled = mergen_index_html_cache_enabled(),
                                  render_page_fn = NULL) {
  if (is.function(static_ui)) {
    # Shiny, dinamik `function(req)` UI sözleşmesini zaten doğrudan destekler.
    # Bu yardımcı yalnızca statik etiket ağacını önbelleğe almak içindir; bir
    # UI fonksiyonunu renderPage()'e statik etiket gibi vermek yeni Shiny/htmltools
    # sürümlerinde "closure -> character" serileştirme hatasına düşebilir.
    return(static_ui)
  }

  if (!isTRUE(enabled)) {
    return(static_ui)
  }

  if (is.null(render_page_fn)) {
    render_page_fn <- mergen_resolve_render_page_fn()
  }
  if (!is.function(render_page_fn)) {
    # Render fonksiyonu çözülemedi (ör. beklenmeyen Shiny sürümü):
    # güvenli geri dönüş -> statik UI, Shiny her zamanki gibi render eder.
    return(static_ui)
  }

  cached_response <- NULL

  # Süreç-içi gözlemlenebilirlik sayacı (guard'lı; metrik modülü yoksa no-op,
  # böylece bu yardımcı izole testlerde tek başına source edilebilir kalır).
  .count_index <- function(name) {
    if (exists("mergen_runtime_metric_inc", mode = "function", inherits = TRUE)) {
      try(mergen_runtime_metric_inc(name), silent = TRUE)
    }
  }

  function(req) {
    if (!is.null(cached_response)) {
      # Sıcak önbellek isabeti: yeniden serileştirme YOK.
      .count_index("index_cache_hit")
      return(cached_response)
    }

    {
      start <- if (exists("mergen_perf_now", mode = "function", inherits = TRUE)) {
        mergen_perf_now()
      } else {
        NULL
      }

      # uiHttpHandler ile aynı çağrı: showcase kapalı, testMode kapalı.
      rendered <- tryCatch(
        render_page_fn(static_ui, showcase = 0, testMode = FALSE),
        error = function(e) {
          if (exists("log_warn", mode = "function", inherits = TRUE)) {
            try(log_warn(sprintf(
              "[INDEX CACHE] Kok sayfa render edilemedi, statik UI'ye donuluyor: %s",
              conditionMessage(e)
            )), silent = TRUE)
          }
          NULL
        }
      )

      if (is.null(rendered)) {
        # Bu istekte Shiny statik UI'yi her zamanki gibi render etsin; önbellek
        # NULL kalır, bir sonraki istekte yeniden denenir.
        .count_index("index_cache_miss_fallback")
        return(static_ui)
      }

      response <- tryCatch(
        shiny::httpResponse(200L, content = rendered),
        error = function(e) NULL
      )
      if (is.null(response)) {
        .count_index("index_cache_miss_fallback")
        return(static_ui)
      }

      cached_response <<- response
      .count_index("index_cache_miss_build")

      if (!is.null(start) &&
          exists("mergen_perf_log", mode = "function", inherits = TRUE)) {
        bytes <- tryCatch(
          sum(nchar(as.character(rendered), type = "bytes")),
          error = function(e) NA_integer_
        )
        try(mergen_perf_log(
          "index_render",
          start = start,
          fields = list(cache = "miss_build", bytes = bytes)
        ), silent = TRUE)
      }
    }

    cached_response
  }
}
