# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_snapshot.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ-GÜVENLİ ANLIK GÖRÜNTÜ sözleşmesi.
#
# Bu dosya `R/helpers_pk_async_request.R` içinden BÖLÜNMÜŞTÜR: tek dosya bakım
# ratchet'inin 25-fonksiyon tavanını tüketiyordu. Ayrım aynı zamanda daha iyi
# bir sınır: "hangi VERİ işçiye taşınabilir" ile "istek nedir / gönderilebilir
# mi" farklı sorumluluklardır.
#
# SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ. Yalnızca düz veri doğrular/üretir.
#
# TEMEL SÖZLEŞME: bir Shiny `session`, `reactiveValues`, reaktif ifade, dış
# işaretçi (`externalptr`) veya DB bağlantısı işçiye ASLA serileştirilmez.
# `pk_async_validate_request()` bunu savunmacı biçimde DOĞRULAR; sessiz bir
# sızıntı, üretimde işçi tarafında anlaşılmaz serileştirme hatalarına dönüşür.
# ==============================================================================

# `chat_add_message()` normal asistan turlarını `type = "ai"` olarak saklar ve
# `role` alanını DOLDURMAZ. Rolü körlemesine "user" yapmak, v2 seçim durumunun
# sohbet imzasını (`role %||% type`) senkron yoldan FARKLI üretirdi; aynı
# konuşma senkron/asenkron arasında geçiş yaptığında önceki sorgu/netleştirme
# bağlamı kaybolurdu.
.pk_async_message_role <- function(mesaj) {
  rol <- as.character(mesaj$role %||% "")[1]
  if (!is.na(rol) && nzchar(rol)) return(rol)

  tip <- as.character(mesaj$type %||% "")[1]
  if (is.na(tip)) tip <- ""
  if (tip %in% c("ai", "assistant")) return("assistant")
  if (nzchar(tip)) return(tip)
  "user"
}

# Skaler kimlikler İŞÇİ-GÜVENLİDİR ve v2 seçim durumu sözleşmesinin parçasıdır:
# `pk_select_chat_key()` kayan geçmiş penceresinde aynı sohbet anahtarını
# koruyabilmek için `db_id`/`id` alanlarını tercih eder.
.pk_async_message_scalar_id <- function(deger) {
  if (is.null(deger) || length(deger) != 1L) return(NULL)
  if (is.function(deger) || is.environment(deger) || is.list(deger)) return(NULL)
  ham <- tryCatch(as.character(deger)[1], error = function(e) NA_character_)
  if (is.na(ham) || !nzchar(ham)) return(NULL)
  ham
}

.pk_async_plain_history <- function(chat_history) {
  if (!is.list(chat_history) || length(chat_history) == 0L) return(list())

  lapply(chat_history, function(mesaj) {
    if (!is.list(mesaj)) return(list(role = "user", content = as.character(mesaj)[1]))
    cikti <- list(
      role = .pk_async_message_role(mesaj),
      content = as.character(mesaj$content %||% "")[1],
      type = as.character(mesaj$type %||% "")[1]
    )
    kimlik <- .pk_async_message_scalar_id(mesaj$id)
    if (!is.null(kimlik)) cikti$id <- kimlik
    db_kimlik <- .pk_async_message_scalar_id(mesaj$db_id)
    if (!is.null(db_kimlik)) cikti$db_id <- db_kimlik
    cikti
  })
}

#' Ana süreçte çözülmüş PK yapılandırmasının DÜZ anlık görüntüsü
#'
#' Kalıcı PSOCK işçisi AYRI bir R oturumudur; ana süreçteki `options()`
#' basamağı orada YOKTUR. Anlık görüntü alınmazsa işçi `MERGEN_PK_MAX_RESULT_MB`
#' gibi güvenlik sınırlarını sessizce yerleşik varsayılana düşürebilir. Gizli
#' anahtarlar DIŞARIDA bırakılır; sır işçiye taşınmaz.
pk_async_config_snapshot <- function() {
  if (!exists("pk_config_spec", inherits = TRUE) ||
      !exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
    return(list())
  }

  spec <- get("pk_config_spec", inherits = TRUE)
  if (!is.list(spec)) return(list())

  cikti <- list()
  eksik <- character(0)
  for (anahtar in names(spec)) {
    if (isTRUE(spec[[anahtar]]$secret)) next
    # Motor kipi ve async bayrağı DIŞARIDA bırakılır: ikisi de isteğin KENDİ
    # alanlarıyla açıkça taşınır ve işçi onları ayrıca sabitler. Anlık görüntü
    # üzerinden İKİNCİ bir kez kurulmaları, iç içe geri yükleme sırası
    # yüzünden işçi çıkışında süreç durumunu kirletirdi.
    if (anahtar %in% c("MERGEN_PK_ENGINE", "MERGEN_PK_ASYNC")) next
    deger <- tryCatch(pk_config_resolve(anahtar), error = function(e) NULL)
    tasinabilir <- !is.null(deger) && length(deger) == 1L &&
      !is.function(deger) && !is.environment(deger) && !is.list(deger)
    if (!tasinabilir) {
      # ANAHTARI SESSİZCE ATLAMA (PR #703 incelemesi): işçi kurulumu YALNIZCA
      # anlık görüntüde bulunan anahtarları yazar, dolayısıyla atlanan bir
      # güvenlik anahtarı için SICAK işçi kendi BAYAT (ve daha gevşek olabilen)
      # değerini korurdu. Eksik anahtar bir YAPILANDIRMA ARIZASIDIR.
      eksik <- c(eksik, anahtar)
      next
    }
    cikti[[anahtar]] <- deger
  }
  # Eksik anahtarlar ÇAĞIRANA bildirilir; karar (gönderimi reddetmek) orada
  # verilir. Değerin kendisi düz veri olarak kalır.
  attr(cikti, "pk_missing_keys") <- eksik
  cikti
}

#' Anlık görüntü EKSİKSİZ mi? (güvenlik yapılandırması kapalı başarısız)
pk_async_config_snapshot_complete <- function(snapshot) {
  if (!is.list(snapshot)) return(FALSE)
  eksik <- attr(snapshot, "pk_missing_keys", exact = TRUE)
  length(as.character(eksik %||% character(0))) == 0L
}

#' Taşınacak DÜZ hâl (tanılama attribute'ları çıkarılır)
pk_async_config_snapshot_plain <- function(snapshot) {
  if (!is.list(snapshot)) return(list())
  adlar <- names(snapshot)
  duz <- unname(snapshot)
  names(duz) <- adlar
  duz
}

#' Anlık görüntüyü işçi sürecinde `options()` basamağına kur
#'
#' Öncelik zinciri KORUNUR: sorgu metadata'sı (1) ve ortam değişkeni (2) hâlâ
#' önce gelir; anlık görüntü yalnızca ana sürecin `options()` basamağını taşır.
#'
#' @return Geri yükleme için ESKİ option değerleri.
pk_async_config_install <- function(snapshot) {
  if (!is.list(snapshot) || length(snapshot) == 0L) return(list())
  if (!exists("pk_config_option_key", mode = "function", inherits = TRUE)) return(list())

  yeni <- list()
  for (anahtar in names(snapshot)) {
    ad <- tryCatch(pk_config_option_key(anahtar), error = function(e) NA_character_)
    if (is.na(ad) || !nzchar(ad)) next
    yeni[[ad]] <- snapshot[[anahtar]]
  }
  if (length(yeni) == 0L) return(list())

  eski <- do.call(options, yeni)
  eski
}

#' Anlık görüntüyü işçi ORTAM DEĞİŞKENİ basamağına da kur
#'
#' `pk_config_resolve()` önceliği "sorgu metadata -> ORTAM -> options"tır.
#' Yalnızca `options()` yazmak yetmez: KALICI bir PSOCK işçisi ana süreç
#' yapılandırmayı sıkılaştırdıktan sonra da ESKİ ortamını taşıyabilir ve o
#' bayat ortam taze istek anlık görüntüsünü YENERDİ (ör. operatör
#' `MERGEN_PK_MAX_RESULT_MB` değerini düşürür ama işçi eski gevşek sınırla
#' devam eder). Bu yüzden istek süresince ortam da anlık görüntüye eşitlenir.
#'
#' @return Ortamı ESKİ hâline döndüren fonksiyon.
pk_async_config_install_env <- function(snapshot) {
  bos <- function() invisible(FALSE)
  if (!is.list(snapshot) || length(snapshot) == 0L) return(bos)

  yeni <- list()
  eski <- list()
  for (anahtar in names(snapshot)) {
    deger <- snapshot[[anahtar]]
    if (is.null(deger) || length(deger) != 1L) next
    if (is.function(deger) || is.environment(deger) || is.list(deger)) next
    eski[[anahtar]] <- Sys.getenv(anahtar, unset = NA_character_)
    yeni[[anahtar]] <- as.character(deger)[1]
  }
  # BOŞ OLMAYAN bir anlık görüntüden HİÇBİR anahtar kurulamadıysa bu bir
  # ARIZADIR: `NULL` döndürerek çağıranın kapalı başarısız olmasını sağlar
  # (aksi hâlde işçinin BAYAT ortamı taze isteğin sınırlarını yenerdi).
  if (!length(yeni)) return(NULL)

  do.call(Sys.setenv, yeni)

  function() {
    for (anahtar in names(eski)) {
      if (is.na(eski[[anahtar]])) Sys.unsetenv(anahtar)
      else do.call(Sys.setenv, stats::setNames(list(eski[[anahtar]]), anahtar))
    }
    invisible(TRUE)
  }
}

# ------------------------------------------------------------------------------
# İŞÇİYE TAŞINAN SIRLAR (YALNIZCA GEREKENLER)
# ------------------------------------------------------------------------------
# Genel kural: sırlar işçiye TAŞINMAZ. Tek istisna, senkron yolun ZATEN
# yazdığı sözde-anonim soru korelasyonudur: `pk_telemetry_question_fingerprint()`
# anahtarsız `NA` döner ve asenkron istekler bu korelasyonu SESSİZCE kaybeder.
# Anahtar burada AYRI bir alanla taşınır; hiçbir log/telemetri/artifact'a
# yazılmaz ve genel yapılandırma anlık görüntüsüne KARIŞMAZ.
.PK_ASYNC_WORKER_SECRET_KEYS <- c("MERGEN_PK_TELEMETRY_HMAC_KEY")

pk_async_secret_snapshot <- function() {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(list())

  cikti <- list()
  for (anahtar in .PK_ASYNC_WORKER_SECRET_KEYS) {
    deger <- tryCatch(pk_config_resolve(anahtar), error = function(e) NULL)
    if (is.null(deger) || length(deger) != 1L) next
    metin <- tryCatch(as.character(deger)[1], error = function(e) NA_character_)
    if (is.na(metin) || !nzchar(metin)) next
    cikti[[anahtar]] <- metin
  }
  cikti
}

#' Taşınan sırları işçide kur (geri yükleyici döndürür)
pk_async_secret_install <- function(secrets) {
  if (!is.list(secrets) || length(secrets) == 0L) return(function() invisible(FALSE))
  gecerli <- secrets[intersect(names(secrets), .PK_ASYNC_WORKER_SECRET_KEYS)]
  if (!length(gecerli)) return(function() invisible(FALSE))
  pk_async_config_install_env(gecerli)
}

# Vekil oturumun `userData` içeriği: yalnızca ATOMİK, düz alanlar.
.PK_ASYNC_USER_DATA_FIELDS <- c(
  "system_username", "user_id", "auth_source", "auth_initialized",
  "sso_active", "current_chat_id"
)

.pk_async_plain_user_data <- function(snapshot) {
  if (!is.list(snapshot)) return(list())

  cikti <- list()
  for (alan in .PK_ASYNC_USER_DATA_FIELDS) {
    deger <- snapshot[[alan]]
    if (is.null(deger)) next
    if (is.function(deger) || is.environment(deger) || is.list(deger)) next
    if (length(deger) != 1L) next
    cikti[[alan]] <- deger
  }

  # D11 DEVRALINAN VARLIK BAĞLAMI AÇIKÇA TAŞINIR.
  #
  # Yukarıdaki genel döngü `is.list(deger)` olan HER alanı atlar ve kayıt tam
  # olarak o şekildedir (`values` + `key`). Taşınmadığı için PSOCK işçileri
  # önceki turda çözülmüş kanonik varlığı HİÇ görmüyor, yani asenkron takip
  # soruları senkron isteklerin kullanabildiği bağlamı kaybediyordu.
  #
  # Yalnızca DÜZ veri kopyalanır (karakter vektörü + karakter alanlı anahtar);
  # bu, işçi sınırı doğrulayıcısının kabul ettiği şekildir.
  kayit <- snapshot[["pk_entity_prior_context"]]
  if (is.list(kayit) && length(kayit$values)) {
    degerler <- as.character(kayit$values)
    degerler <- degerler[!is.na(degerler) & nzchar(degerler)]
    anahtar <- kayit$key
    if (length(degerler)) {
      cikti[["pk_entity_prior_context"]] <- list(
        values = degerler,
        key = if (is.list(anahtar)) list(
          query_id    = as.character(anahtar$query_id %||% "")[1],
          column      = as.character(anahtar$column %||% "")[1],
          entity_kind = as.character(anahtar$entity_kind %||% "")[1]
        ) else NULL
      )
    }
  }

  cikti
}

#' Ana süreçte vekil oturum için `userData` anlık görüntüsü topla
#'
#' Gerçek `session` nesnesi ASLA taşınmaz; yalnızca bu düz alanlar.
pk_async_capture_user_data <- function(session) {
  if (is.null(session)) return(list())
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(list())

  cikti <- list()
  for (alan in .PK_ASYNC_USER_DATA_FIELDS) {
    deger <- tryCatch(ud[[alan]], error = function(e) NULL)
    if (is.null(deger) || length(deger) != 1L) next
    if (is.function(deger) || is.environment(deger) || is.list(deger)) next
    cikti[[alan]] <- deger
  }

  cikti
}
