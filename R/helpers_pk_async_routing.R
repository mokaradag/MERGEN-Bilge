# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_routing.R
# Açıklama: Faz 6 (§5.10) — ASENKRON YÖNLENDİRME KARARININ iki yardımcısı:
#           yönlendirme anındaki sorgu metadata'sı ve DEGRADE senkron yolda
#           sınırlı SQL yürütücüsünün zorlanması.
#
# `R/helpers_pk_async_lifecycle.R` içinden BÖLÜNMÜŞTÜR: orası TEK bir isteğin
# sonucunun nasıl sunulduğu/temizlendiğidir ve 24-fonksiyon bakım tavanına
# dayanmıştı. Yönlendirme "bu istek işçiye GİDER Mİ ve gitmezse hangi güvenlik
# sınırlarıyla çalışır" sorusudur.
#
# SAFTIR sayılmaz (ortam sembolü değiştirir) ama Shiny/reaktif/DB DOKUNMAZ.
# ==============================================================================

# ------------------------------------------------------------------------------
# YÖNLENDİRME İÇİN SORGU METADATA'SI
# ------------------------------------------------------------------------------
# Yönlendirme kararı sorgu SEÇİMİNDEN ÖNCE alınır: `pk_active_query_meta()` o
# anda normalde `NULL`'dur, dolayısıyla `async = FALSE` işaretli bir üretim
# sorgusu küresel bayrak açıkken YİNE işçiye gönderilirdi (per-query override
# ölü bir yapılandırma).
#
# Seçimi burada çalıştırmak (ikinci bir LLM turu) kabul edilemez. Bunun yerine
# METİN TABANLI bir ÖN EŞLEŞME denenir: kullanıcının istemi kütüphanedeki bir
# sorgunun adı/kimliğiyle KESİN olarak eşleşiyorsa o sorgunun metadata'sı
# kullanılır. Eşleşme yoksa davranış DEĞİŞMEZ (`NULL` = küresel bayrak).
#
# ÖNEMLİ: bu bir SEÇİM DEĞİLDİR; yalnızca "bu sorgu asenkrondan muaf mı"
# sorusuna daha iyi bir cevap verir ve YALNIZCA muafiyeti GENİŞLETİR
# (async'i kapatabilir, açamaz).
mergen_pk_routing_query_meta <- function(ctx) {
  aktif <- tryCatch(pk_active_query_meta(), error = function(e) NULL)
  if (!is.null(aktif)) return(aktif)

  kutuphane <- get0("query_library", inherits = TRUE)
  if (!is.list(kutuphane) || !length(kutuphane)) return(NULL)

  istem <- tryCatch(as.character(ctx$user_prompt %||% "")[1], error = function(e) "")
  if (is.na(istem) || !nzchar(istem)) return(NULL)
  katla <- function(x) {
    metin <- tryCatch(enc2utf8(as.character(x)[1]), error = function(e) "")
    if (is.na(metin)) return("")
    if (exists("pk_tr_fold", mode = "function", inherits = TRUE)) {
      return(tryCatch(pk_tr_fold(metin), error = function(e) metin))
    }
    chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", metin)
  }
  istem_katli <- katla(istem)

  for (sorgu in kutuphane) {
    if (!is.list(sorgu) || !is.list(sorgu$meta)) next
    ad <- katla(sorgu$name %||% "")
    if (nzchar(ad) && grepl(ad, istem_katli, fixed = TRUE)) return(sorgu$meta)
  }
  NULL
}

# ------------------------------------------------------------------------------
# DEGRADE YOLDA SINIRLI SENKRON YÜRÜTÜCÜ
# ------------------------------------------------------------------------------
# `MERGEN_PK_ASYNC=true` iken yetenek sondası başarısız olduğunda (plan yok,
# bağımlılık eksik) senkron boru hattı `execute_pk_sql_unicode()` üzerinden TAM
# `DBI::dbGetQuery()` materyalizasyonu yapar: yeni parça/bellek/son tarih
# denetimleri DEVREYE GİRMEZ ve tek bir geniş sorgu Shiny sürecini bloklayıp
# belleği tüketebilir. Operatör asenkronu AÇIK bıraktığına göre yeni sınırların
# geçerli olmasını bekler; bu yüzden sınırlı yürütücü zorlanır.
#
# `flag_off` (BİLİNÇLİ geri alma) bu yoldan GEÇMEZ: orada eski davranış aynen
# korunur.
#
# @return Önceki durumu geri yükleyen fonksiyon.
mergen_pk_force_bounded_sync <- function() {
  bos <- function() invisible(FALSE)
  if (!exists("pk_async_bounded_sql_executor", mode = "function", inherits = TRUE)) return(bos)
  if (!exists("pk_analiz_process_request", mode = "function", inherits = TRUE)) return(bos)

  hedef <- environment(pk_analiz_process_request)
  if (!is.environment(hedef)) return(bos)

  eski <- get0("execute_pk_sql_unicode", envir = hedef, inherits = TRUE)
  kutu <- pk_async_sql_status_box()
  sinirli <- pk_async_bounded_sql_executor(
    stage_gate = function() list(halt = FALSE, status = "ok"),
    deadline_at = function() getOption("mergen.pk.async.deadline_at", NULL),
    status_box = kutu
  )

  ok <- isTRUE(tryCatch({
    assign("execute_pk_sql_unicode", sinirli, envir = hedef)
    TRUE
  }, error = function(e) FALSE))
  if (!isTRUE(ok)) return(bos)

  function() {
    if (is.function(eski)) {
      try(assign("execute_pk_sql_unicode", eski, envir = hedef), silent = TRUE)
    }
    invisible(TRUE)
  }
}