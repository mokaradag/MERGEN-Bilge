# ==============================================================================
# Dosya Yolu: R/helpers_pk_exec_context.R
# Açıklama: Faz 6 (§5.10) — İSTEK KAPSAMLI yürütme bağlamı.
#
# Sorgu seçimi ile SQL yürütmesi/RLS arasındaki katmanlar (modül gövdesi,
# `execute_pk_sql_unicode()` sembolü, `apply_rls_to_data()`) seçilen sorgunun
# metadata'sını PARAMETRE olarak taşımaz; yapılandırma sözleşmesi ise sorgu
# metadata'sına EN YÜKSEK önceliği verir. Bu süreç-yerel bağlam, imzaları
# değiştirmeden o metadata'yı (ve önbellek anahtarı için yetki kapsamını)
# aşağı akışa görünür kılar.
#
# `R/helpers_pk_result_size.R` içinden BÖLÜNMÜŞTÜR: orası SONUÇ BOYUTU
# matematiğidir (saf hesap), burası ise istek yaşam döngüsüne ait DEĞİŞKEN
# durumdur. İkisini aynı dosyada tutmak hem sorumlulukları karıştırıyor hem de
# tek dosya bakım ratchet bütçesini tüketiyordu.
#
# SAFTIR: yalnızca `options()` okur/yazar; Shiny/DB/ağ dokunuşu yoktur.
# ==============================================================================

# ------------------------------------------------------------------------------
# ETKİN YÜRÜTME BAĞLAMI
# ------------------------------------------------------------------------------
# Sorgu seçimi ile SQL yürütmesi/RLS arasındaki katmanlar (modül gövdesi,
# `execute_pk_sql_unicode()` sembolü, `apply_rls_to_data()`) seçilen sorgunun
# metadata'sını PARAMETRE olarak taşımaz. Yapılandırma sözleşmesi ise sorgu
# metadata'sına EN YÜKSEK önceliği verir. Bu süreç-yerel bağlam, imzaları
# değiştirmeden o metadata'yı (ve önbellek anahtarı için yetki kapsamını)
# aşağı akışa görünür kılar.
#
# SAFTIR: yalnızca `options()` okur/yazar; Shiny/DB/ağ dokunuşu yoktur.

#' Etkin yürütme bağlamını kur (geri yükleyici döndürür)
#'
#' @return Eski bağlamı geri yükleyen fonksiyon (`on.exit` ile çağrılmalıdır).
pk_set_exec_context <- function(query = NULL, rls_info = NULL, engine = "") {
  eski <- getOption("mergen.pk.exec_context", NULL)
  eski_son_tarih <- getOption("mergen.pk.async.deadline_at", NULL)
  options(mergen.pk.exec_context = list(
    query = query, rls_info = rls_info, engine = as.character(engine %||% "")[1]
  ))
  # Sorgu SEÇİLDİKTEN sonra analiz son tarihi yeniden çözülür. Dispatch anında
  # seçilen sorgu HENÜZ BİLİNMEDİĞİ için istek küresel bütçeyle dondurulur;
  # `pk_config_resolve()` sözleşmesi ise sorgu metadata'sına EN YÜKSEK önceliği
  # verir. Yeniden çözmezsek `analysis_deadline_sec` override'ı sessizce ölü
  # bir yapılandırma olurdu. Başlangıç anı DEĞİŞMEZ; yalnızca bütçe değişir.
  yeni_son_tarih <- .pk_exec_query_deadline_at(query)
  if (!is.null(yeni_son_tarih)) options(mergen.pk.async.deadline_at = yeni_son_tarih)
  function() {
    options(mergen.pk.exec_context = eski)
    if (!is.null(yeni_son_tarih)) options(mergen.pk.async.deadline_at = eski_son_tarih)
  }
}

# Seçilen sorgunun analiz son tarihi (override yoksa `NULL`).
#
# KAPSAM NOTU: bu override TEKİL analiz yolu içindir. Derin Düşünme'de bir
# analiz BİRDEN ÇOK sorgu çalıştırır; orada "hangi sorgunun son tarihi tüm
# analizi belirler" sorusunun doğru cevabı YOKTUR, bu yüzden derin yol
# analiz-seviyesi bütçeyi korur ve sorgu metadata'sı yalnızca SQL zaman
# aşımı/sonuç tavanı gibi sorgu-seviyesi sınırlara uygulanır.
#
# `pk_deadline_at()` BİLEREK kullanılmaz: işçi derin yolda o fonksiyonu dondurulmuş
# son tarihi döndürecek şekilde geçici olarak değiştirir, dolayısıyla override
# hesabı kendi kendini iptal ederdi.
.pk_exec_query_deadline_at <- function(query) {
  if (!is.list(query) || !is.list(query$meta)) return(NULL)
  baslangic <- getOption("mergen.pk.async.started_at", NULL)
  if (is.null(baslangic)) return(NULL)
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(NULL)

  coz <- function(meta) suppressWarnings(as.numeric(tryCatch(
    pk_config_resolve("MERGEN_PK_ANALYSIS_DEADLINE_SEC", meta),
    error = function(e) NA_real_
  ))[1])

  butce <- coz(query$meta)
  if (length(butce) != 1L || is.na(butce) || !is.finite(butce) || butce <= 0) return(NULL)
  kuresel <- coz(NULL)
  # Override YOKSA (metadata küresel değerle aynı) hiçbir şey değiştirilmez;
  # böylece varsayılan davranış bit bazında korunur.
  if (is.finite(kuresel) && isTRUE(all.equal(butce, kuresel))) return(NULL)

  an <- tryCatch(as.POSIXct(baslangic), error = function(e) NA)
  if (length(an) != 1L || is.na(an)) return(NULL)

  # SORGU BAZLI SON TARİH KÜRESEL TAVANI AŞAMAZ.
  #
  # Metadata `analysis_deadline_sec` değerini küresel değerin ÜSTÜNE
  # koyduğunda, üretilen yürütme bağlamı ve bekçi köpeği o sorgunun — ve
  # dolayısıyla İSTEĞİN TAMAMININ — operatörün beyan ettiği sert analiz
  # tavanının ötesinde çalışmasına izin veriyordu. Sorgu bazlı değer yalnızca
  # SIKILAŞTIRABİLİR; gevşetemez.
  if (is.finite(kuresel) && kuresel > 0 && butce > kuresel) butce <- kuresel

  yeni <- an + butce

  # YÜRÜRLÜKTEKİ SON TARİH İLERİ ALINAMAZ: kelepçe yalnızca BÜTÇELERİ
  # karşılaştırıyordu. Dispatch kuyrukta geçen süreyi düşerek daha KISA bir son
  # tarih yayınlayabilir; küresel tavanın altında ama kalan süreden büyük bir
  # sorgu bütçesi o zaman daha GEÇ bir an üretip seçeneği eziyor, bekçi köpeği
  # de yürürlükteki tavanı uygulamıyordu (`kuresel` NA iken de aynı gevşeme).
  mevcut <- tryCatch(as.POSIXct(getOption("mergen.pk.async.deadline_at", NULL)),
                     error = function(e) NULL)
  if (length(mevcut) == 1L && !is.na(mevcut) && mevcut < yeni) return(NULL)
  yeni
}

#' Etkin yürütme bağlamını oku (yoksa boş liste)
pk_active_exec_context <- function() {
  baglam <- getOption("mergen.pk.exec_context", NULL)
  if (!is.list(baglam)) return(list(query = NULL, rls_info = NULL, engine = ""))
  baglam
}

#' Etkin sorgu metadata'sı (yoksa `NULL`)
pk_active_query_meta <- function() {
  sorgu <- pk_active_exec_context()$query
  if (!is.list(sorgu)) return(NULL)
  sorgu$meta
}

#' AKTİF istek durdurulmuş / süresi dolmuş mu? (imza değiştirmeden yoklama)
#'
#' Bloklayan LLM/HTTP aşamaları iptal jetonunu PARAMETRE olarak almaz. Dispatch
#' anında yayınlanan option'lar üzerinden kapı yoklanabilir; böylece iptal
#' edilmiş bir isteğin ara sonucu KULLANILMAZ ve sonraki aşamalar hiç başlamaz.
#' Bütçe/jeton yoksa `FALSE` döner ve davranış değişmez.
pk_active_stage_halt <- function() {
  if (!exists("pk_async_stage_gate", mode = "function", inherits = TRUE)) return(FALSE)
  jeton <- getOption("mergen.pk.async.cancel_token", NULL)
  son_tarih <- getOption("mergen.pk.async.deadline_at", NULL)
  if (is.null(jeton) && is.null(son_tarih)) return(FALSE)
  isTRUE(tryCatch(pk_async_stage_gate(jeton, son_tarih)$halt, error = function(e) FALSE))
}
