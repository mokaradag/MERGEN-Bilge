# ==============================================================================
# Dosya Yolu: R/helpers_app_http_routes.R
# Açıklama: Uygulama-içi HAFİF HTTP uç noktaları (sağlık/hazırlık) ve kök sayfa
#           yönlendirici (router).
#
# Neden: Tek Shiny/httpuv süreci ~400-425 eşzamanlı bağlantıda TCP kabul/backlog
# doygunluğuna girer (CPU düşükken connection_timeout baskın). Bunun DÜRÜST
# çözümü yatay ölçeklemedir: birden çok worker süreci (farklı MERGEN_PORT) bir
# kurumsal ters-vekil/yük-dengeleyici arkasında. Yük-dengeleyicinin worker'ları
# güvenle havuza alıp çıkarabilmesi için her worker'ın HAFİF bir sağlık/hazırlık
# uç noktası sunması gerekir. Bu modül bunu sağlar.
#
#   GET /healthz : canlılık (liveness). Süreç ayakta mı? Küçük statik 200 JSON.
#                  DB/oturum/dosya işi YAPMAZ.
#   GET /readyz  : hazırlık (readiness) + sır-güvenli gözlemlenebilirlik anlık
#                  görüntüsü (uptime, çalışma-zamanı sayaçları, backpressure ve
#                  DB havuz sayaçları). DB I/O YAPMAZ (yalnız bellek-içi sayaç).
#
# Bu uç noktalar attach-modlu yük sürücüsünün GÖREMEDİĞİ uygulama-içi metrikleri
# süreç dışına sır-güvenli biçimde açar; böylece operatör/yük-dengeleyici
# uygulama-tarafı iyileştirmeleri dürüstçe gözlemleyebilir. Soak kapısının
# pass/fail mantığını DEĞİŞTİRMEZ.
#
# Shiny dağıtımı: shinyApp(..., uiPattern = mergen_app_route_pattern()) ile ui
# yönlendiricisi `/`, `/healthz` ve `/readyz` için çağrılır. ui bir function(req)
# olduğunda ve httpResponse döndürdüğünde Shiny yanıtı doğrudan sunar.
#
# GÜVENLİK / GERİ DÖNÜŞ: Sağlık uç noktaları varsayılan AÇIK; MERGEN_HEALTH_ENDPOINT
# ile kapatılırsa router devre dışı kalır ve `index_ui` DEĞİŞMEDEN döner (mevcut
# davranışla bayt-bayt aynı). Saf yardımcılardır; source-time'da Shiny/ağ/DB
# erişimi yapmaz.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# Özellik bayrağı: sağlık/hazırlık uç noktaları varsayılan AÇIK. Kapatmak için
# MERGEN_HEALTH_ENDPOINT=false (veya 0/off/hayir/kapali).
mergen_health_endpoint_enabled <- function() {
  value <- tolower(trimws(Sys.getenv("MERGEN_HEALTH_ENDPOINT", "true")))
  !(value %in% c("0", "false", "f", "no", "n", "off", "hayir", "kapali"))
}

# Shiny uiPattern: kök sayfa + sağlık/hazırlık yollarını eşler. shinyApp bunu
# sprintf("^%s$", uiPattern) ile sarar; yani sonuç regex'i "^/(healthz|readyz)?$"
# olur ve YALNIZCA "/", "/healthz", "/readyz" eşleşir (statik kaynaklar etkilenmez).
mergen_app_route_pattern <- function() {
  if (!mergen_health_endpoint_enabled()) return("/")
  "/(healthz|readyz)?"
}

# İstek yolunu (PATH_INFO) normalize eder: NULL/boş -> "/"; sondaki "/" kırpılır
# (kök hariç). Sorgu dizesi PATH_INFO'da değildir, ayrı tutulur.
.mergen_route_path <- function(req) {
  path <- tryCatch(as.character(req$PATH_INFO)[1], error = function(e) NA_character_)
  if (is.na(path) || !nzchar(path)) return("/")
  if (nchar(path) > 1L) path <- sub("/+$", "", path)
  if (!nzchar(path)) path <- "/"
  path
}

# Canlılık (liveness) gövdesi: küçük, statik, sır içermez.
mergen_health_liveness_body <- function() {
  '{"status":"ok","service":"mergen-bilge"}'
}

# Hazırlık (readiness) yükü: SADECE sır-güvenli sayısal/boolean alanlar. DB I/O
# yapmaz; yalnızca bellek-içi sayaç anlık görüntüleri okunur. Her bileşen guard'lı
# ve tryCatch'lidir; biri başarısız olursa hazırlık yine de 200/ok döner.
mergen_readiness_payload <- function() {
  payload <- list(status = "ok", service = "mergen-bilge")

  if (exists("mergen_runtime_metrics_snapshot", mode = "function", inherits = TRUE)) {
    payload$runtime <- tryCatch(mergen_runtime_metrics_snapshot(), error = function(e) NULL)
  }
  if (exists("mergen_backpressure_snapshot", mode = "function", inherits = TRUE)) {
    payload$backpressure <- tryCatch(mergen_backpressure_snapshot(), error = function(e) NULL)
  }
  # DB havuz anlık görüntüsü yalnızca bellek-içi sayaçları okur (DB sorgusu YOK)
  # ve zaten sır-güvenlidir (ham DSN/secret içermez).
  if (exists("db_pool_status_snapshot", mode = "function", inherits = TRUE)) {
    payload$db_pool <- tryCatch(db_pool_status_snapshot(), error = function(e) NULL)
  }

  payload
}

# JSON gövdesini güvenli biçimde üretir. jsonlite yoksa/başarısızsa minimal
# güvenli gövdeye düşer (sağlık uç noktası asla kırılgan/ağır yol olmamalı).
.mergen_route_json <- function(payload) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return('{"status":"ok"}')
  }
  tryCatch(
    as.character(jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", na = "null")),
    error = function(e) '{"status":"ok"}'
  )
}

# Sağlık/hazırlık için httpResponse üretir. Yük-dengeleyicinin bayat bir sağlık
# yanıtı önbelleğe almaması için no-store.
.mergen_route_response <- function(body) {
  shiny::httpResponse(
    status = 200L,
    content_type = "application/json; charset=utf-8",
    content = body,
    headers = list("Cache-Control" = "no-store")
  )
}

# Kök sayfa + sağlık/hazırlık yönlendiricisi.
#
# Argümanlar:
#   index_ui : kök sayfa UI'si. Statik Shiny etiket nesnesi VEYA function(req)
#              (R/helpers_index_page_cache.R önbellekli sürümü) olabilir.
#   enabled  : sağlık uç noktaları açık mı (varsayılan: ortam bayrağı).
#
# Dönüş:
#   - enabled FALSE ise : index_ui DEĞİŞMEDEN (mevcut davranış; bayt-bayt aynı).
#   - enabled TRUE ise  : function(req) router. `/healthz` ve `/readyz` küçük JSON
#                         yanıtları döndürür; diğer her yol index_ui'ye delege
#                         edilir (statik etiket ise olduğu gibi, fonksiyon ise
#                         req ile çağrılarak).
mergen_build_app_ui <- function(index_ui, enabled = mergen_health_endpoint_enabled()) {
  if (!isTRUE(enabled)) {
    return(index_ui)
  }

  index_is_fn <- is.function(index_ui)

  delegate_index <- function(req) {
    if (index_is_fn) index_ui(req) else index_ui
  }

  function(req) {
    path <- .mergen_route_path(req)

    if (identical(path, "/healthz")) {
      if (exists("mergen_runtime_metric_inc", mode = "function", inherits = TRUE)) {
        try(mergen_runtime_metric_inc("health_liveness_hit"), silent = TRUE)
      }
      return(.mergen_route_response(mergen_health_liveness_body()))
    }

    if (identical(path, "/readyz")) {
      if (exists("mergen_runtime_metric_inc", mode = "function", inherits = TRUE)) {
        try(mergen_runtime_metric_inc("health_readiness_hit"), silent = TRUE)
      }
      body <- tryCatch(
        .mergen_route_json(mergen_readiness_payload()),
        error = function(e) '{"status":"ok"}'
      )
      return(.mergen_route_response(body))
    }

    delegate_index(req)
  }
}
