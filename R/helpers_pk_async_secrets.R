# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_secrets.R
# Açıklama: PK asenkron işçisine TAŞINAN sırların anlık görüntüsü ve kurulumu.
#
#           NEDEN AYRI DOSYA: `R/helpers_pk_async_snapshot.R` yapılandırma/
#           oturum anlık görüntüsünü ve doğrulamasını taşır. Sır taşıma AYRI bir
#           güvenlik sınırıdır (tek istisna, telemetri parmak izi anahtarıdır) ve
#           sahip dosya bakım ratchet'i sınırındadır.
#
#           Dosya saftır: Shiny/DB/ağ bağımlılığı YOKTUR. Kaynak manifesti bu
#           dosyayı `helpers_pk_async_snapshot.R` dosyasından SONRA yükler
#           (`pk_async_config_install_env()` oradadır).
# ==============================================================================

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
    metin <- if (is.null(deger) || length(deger) != 1L) {
      NA_character_
    } else {
      tryCatch(as.character(deger)[1], error = function(e) NA_character_)
    }
    # KALDIRMA DA TAŞINIR. Anahtar atlandığında SICAK bir PSOCK işçisi önceki
    # istekten kalan `MERGEN_PK_TELEMETRY_HMAC_KEY` değerini KORUYOR ve
    # operatör anahtarı kaldırdıktan sonra bile ilişkilendirilebilir soru
    # parmak izleri üretmeye devam ediyordu. Havuz seçeneklerindeki
    # `.PK_ASYNC_OPTION_UNSET` sözleşmesinin aynısı kullanılır.
    cikti[[anahtar]] <- if (is.na(metin) || !nzchar(metin)) {
      .PK_ASYNC_OPTION_UNSET
    } else {
      metin
    }
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
