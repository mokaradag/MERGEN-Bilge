# R/module_boot_readiness.R
# Açıklama: Açılış ekranının yalnızca gerçek hazır olma kontrol noktalarından
# ilerlemesini sağlayan küçük koordinatör. Kontrol noktaları işaretlendikçe
# istemciye "bootReadinessCheckpoint" mesajı gönderilir; tüm zorunlu noktalar
# tamamlandığında ready=TRUE bilgisi iletilir.
#
# Not: Tamamlanan anahtarlar düz bir karakter vektöründe tutulur. Daha önce
# burada bir reactiveVal kullanılıyordu; ancak mark() hem senkron başlangıç
# kodundan (yerel mod) hem de observer'lardan hem de promise geri
# çağrılarından çağrılabildiği için reaktif bağlam hatası riskini tamamen
# ortadan kaldırmak adına basit vektör tercih edilir.

bootReadinessInit <- function(session, required = NULL) {
  # Zorunlu kontrol noktaları: her biri uygulama tarafında gerçekten
  # işaretlenir. İlerleme çubuğu yalnızca bu noktalarla 100'e ulaşır.
  required <- required %||% c(
    "auth_ready",
    "saved_chats_preview_ready",
    "file_index_ready",
    "character_media_ready",
    "welcome_client_ready",
    # Zengin Deneyim: Söyleşi Yönetimi sayfalarının verisi hazır (veya
    # kaynak kullanılamadığı dürüstçe bildirildi).
    "management_pages_ready"
  )

  done <- character()
  # "Kısmen" tamamlanan (kaynak okunamadı/kullanılamıyor) kontrol noktaları;
  # toplu anahtar bunları "hazır" diye bildirmez.
  kismen <- character()
  # Toplu anahtarın KAPSAMI: açılışta olay döngüsünü tutmadan hazırlanabilen
  # veriler, yani tam söyleşi listesi (Kayıtlı Söyleşiler) ve Söyleşi Geçmişi
  # ilk sayfası (ikisi de işçide okunur). Görsel Galerisi ve Ortak Söyleşiler
  # bilinçli olarak TEMBELDİR (eşzamanlı tarama/sorgu): ilk ziyarette hazırlanır
  # ve bu anahtar onları "hazır" diye bildirmez (detail$tembel).
  yonetim_alt <- c("saved_chats_full_loaded", "history_rows_ready")
  yonetim_tembel <- c("gallery_index_ready", "ortak_list_ready")
  # Son bildirilen "kısmen" toplu durumun eksik alt anahtarları; eksik küme
  # değişince (ör. biri toparlandı) toplu bildirim güncellenir.
  toplu_eksik <- NULL

  # Soğuk açılış faz zamanlaması: her kontrol noktası, oturum başlangıcından
  # itibaren geçen süreyle loglanır. Böylece açılış süresinin hangi fazda
  # harcandığı (kimlik, son konuşmalar, dosya envanteri, medya, karşılama
  # istemcisi) log dosyasından doğrudan okunabilir. Tek satır/kontrol noktası
  # olduğu için üretimde gürültü oluşturmaz.
  boot_started_at <- Sys.time()

  # Soğuk açılış faz ayrımı: ilk reaktif flush'a kadar geçen süre, sunucu
  # kablolama maliyetini dosya/kimlik kontrol noktalarından ayırır. Sahte
  # session kullanan testlerde onFlushed olmayabilir; sessizce atlanır.
  tryCatch({
    if (is.function(session$onFlushed)) {
      session$onFlushed(function() {
        cat(sprintf(
          "[STARTUP PERF] first_flush elapsed_ms=%.0f\n",
          as.numeric(difftime(Sys.time(), boot_started_at, units = "secs")) * 1000
        ))
      }, once = TRUE)
    }
  }, error = function(e) NULL)

  mark <- function(key, label = key, pct = NULL, detail = NULL) {
    if (is.null(key) || length(key) != 1L || !nzchar(as.character(key))) {
      return(invisible(FALSE))
    }
    key <- as.character(key)

    if (!key %in% done) {
      done <<- c(done, key)
      if (is.list(detail) && (isTRUE(detail$degraded) || isFALSE(detail$available))) {
        kismen <<- c(kismen, key)
      }

      elapsed_ms <- as.numeric(difftime(Sys.time(), boot_started_at, units = "secs")) * 1000
      deferred_flag <- isTRUE(is.list(detail) && isTRUE(detail$deferred))
      cat(sprintf(
        "[STARTUP PERF] checkpoint=%s elapsed_ms=%.0f deferred=%s\n",
        key, elapsed_ms, if (deferred_flag) "TRUE" else "FALSE"
      ))
    }

    payload <- list(
      key = key,
      label = label,
      pct = pct,
      detail = detail,
      required_done = intersect(done, required),
      required_total = length(required),
      ready = all(required %in% done)
    )

    # Oturum kapanmış olabilir (geç gelen promise geri çağrısı vb.);
    # bu durumda sessizce yut.
    tryCatch(
      session$sendCustomMessage("bootReadinessCheckpoint", payload),
      error = function(e) NULL
    )

    # Söyleşi Yönetimi: alt sayfalar sonuçlanınca toplu kontrol noktası
    # işaretlenir; biri kısmen sonuçlandıysa toplu durum da "kısmen"dir. Kısmen
    # (ör. zaman aşımı) bildirilmiş toplu durum, alt sayfalar sonradan başarıyla
    # tamamlanınca "hazır"a döner.
    toplu_kismen <- "management_pages_ready" %in% kismen
    if ((!"management_pages_ready" %in% done || toplu_kismen) && all(yonetim_alt %in% done)) {
      eksik <- intersect(yonetim_alt, kismen)
      if (length(eksik)) {
        if (!toplu_kismen || !identical(eksik, toplu_eksik)) {
          sifirla("management_pages_ready")
          toplu_eksik <<- eksik
          mark("management_pages_ready", "Söyleşi Yönetimi verisi kısmen hazır",
               detail = list(degraded = TRUE, kismen = eksik, tembel = yonetim_tembel))
        }
      } else {
        sifirla("management_pages_ready")
        mark("management_pages_ready", "Söyleşi Yönetimi verisi hazır",
             detail = list(tembel = yonetim_tembel))
      }
    }

    invisible(TRUE)
  }

  # Kontrol noktalarını yeniden bildirilebilir yapar (ör. oturum sahibi
  # değişince sahibe özgü anahtarlar yeni sahip için baştan değerlendirilir).
  sifirla <- function(keys) {
    keys <- as.character(keys)
    done <<- setdiff(done, keys)
    kismen <<- setdiff(kismen, keys)
    if ("management_pages_ready" %in% keys) toplu_eksik <<- NULL
    invisible(TRUE)
  }

  # Tek seferlik işaretleme: sayfa yenilemeleri ve tekrarlayan taramalar aynı
  # kontrol noktası için istemciye yinelenen bildirim göndermez. Tek istisna
  # toparlanmadır: "kısmen" kaydedilmiş bir anahtar sonraki başarılı sonuçla
  # "hazır"a döner (başarısızlık başarının yerini almaz).
  mark_once <- function(key, label = key, pct = NULL, detail = NULL) {
    if (length(key) == 1L && as.character(key) %in% done) {
      basarili <- !(is.list(detail) && (isTRUE(detail$degraded) || isFALSE(detail$available)))
      if (!(basarili && as.character(key) %in% kismen)) return(invisible(FALSE))
      sifirla(key)
    }
    mark(key, label = label, pct = pct, detail = detail)
  }

  list(
    mark = mark,
    mark_once = mark_once,
    reset = sifirla,
    degraded = function() kismen,
    is_ready = function() all(required %in% done),
    done = function() done,
    required = required
  )
}