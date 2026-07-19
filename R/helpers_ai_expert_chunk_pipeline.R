# R/helpers_ai_expert_chunk_pipeline.R
# AI Uzman TTS parça hattı: kalan konuşma parçalarını SINIRLI eşzamanlılıkla
# sentezler, tamamlananları SIRAYLA (kablo indeksi yeniden numaralandırılarak)
# istemci kuyruğuna teslim eder ve hat boşaldığında teslim edilen parça
# sayısını bildirir. Başarısız bir parça atlanır; sonraki hazır parça onun
# kablo indeksini devralır, böylece istemci indeks boşluğunda asılı kalmaz.
# Saf koordinasyon mantığıdır: Shiny/TTS bağımlılıkları enjekte edilir.

#' Merkezi parça hattı politikası. Dağınık sabitler yerine tek yapılandırma
#' noktası; ortam değişkenleriyle ayarlanabilir.
ai_expert_chunk_pipeline_policy <- function() {
  eszamanli <- suppressWarnings(as.integer(
    Sys.getenv("MERGEN_AI_EXPERT_TTS_CONCURRENCY", "2")
  ))
  if (is.na(eszamanli) || eszamanli < 1L) eszamanli <- 2L

  tampon_sn <- suppressWarnings(as.numeric(
    Sys.getenv("MERGEN_AI_EXPERT_TTS_START_BUFFER_SECS", "6")
  ))
  if (is.na(tampon_sn) || tampon_sn < 0) tampon_sn <- 6

  list(
    eszamanli_sinir = min(eszamanli, 4L),
    baslangic_tampon_suresi_sn = tampon_sn
  )
}

#' Oynatma başlangıç kapısı: ilk parça hazır OLSA BİLE, başlangıç tamponu
#' parçası sonuçlanana (ya da sınırlı süre dolana) kadar oynatma başlatılmaz.
#' Böylece yüklü sunucuda 1. parçadan sonra uzun sessizlik oluşmaz; tampon
#' hiç sonuçlanmazsa süre sınırı oynatmayı yine de başlatır. `domain`
#' verilirse süre sınırı geri çağrısı o Shiny oturum alanıyla koşar (çıplak
#' later geri çağrısında shinyjs oturumu çözemez).
ai_expert_baslangic_kapisi <- function(dispatch_fn, deadline_secs = 6,
                                       domain = NULL) {
  kapi <- new.env(parent = emptyenv())
  kapi$ilk <- NULL
  kapi$tampon_hazir <- FALSE
  kapi$acildi <- FALSE

  dene <- function() {
    if (isTRUE(kapi$acildi) || is.null(kapi$ilk) ||
        !isTRUE(kapi$tampon_hazir)) return(invisible(FALSE))
    kapi$acildi <- TRUE
    ilk <- kapi$ilk
    dispatch_fn(ilk$text, ilk$chunks, ilk$audio_src, ilk$duration)
    invisible(TRUE)
  }

  list(
    ilk_hazir = function(ilk) {
      if (!is.null(kapi$ilk)) return(invisible(FALSE))
      kapi$ilk <- ilk
      if (!isTRUE(kapi$tampon_hazir) && is.finite(deadline_secs) &&
          deadline_secs > 0) {
        later::later(function() {
          # Çıplak later geri çağrısı: hata üst düzeye kaçarsa runApp çöker.
          tryCatch({
            kapi$tampon_hazir <- TRUE
            if (is.null(domain)) dene() else shiny::withReactiveDomain(domain, dene())
          }, error = function(e) {
            cat(sprintf("[AI_EXPERT] Başlangıç kapısı süre sınırı hatası: %s\n",
                        conditionMessage(e)))
          })
        }, delay = deadline_secs)
      }
      dene()
    },
    tampon_hazir = function() {
      kapi$tampon_hazir <- TRUE
      dene()
    },
    acik_mi = function() isTRUE(kapi$acildi)
  )
}

#' Kalan parçaları sınırlı eşzamanlılıkla sentezleyip sırayla teslim et.
#'
#' @param parcalar Tam parça listesi (1. parça başlangıç yolunda sentezlenir).
#' @param baslangic İlk sentezlenecek parça indeksi (normalde 2).
#' @param synth_fn function(text) -> promise (list(success, audio_src, duration)).
#' @param is_current_fn function() -> TRUE ise konuşma hâlâ aktif (iptal koruması).
#' @param queue_fn function(index0, text, audio_src, duration) — sıradaki hazır
#'   parçayı istemciye teslim eder (index0 kablo indeksidir, 0 tabanlı).
#' @param on_buffer_settled function() — başlangıç tamponu parçası (baslangic
#'   indeksli parça) BAŞARILI/BAŞARISIZ fark etmeksizin sonuçlandığında bir kez
#'   çağrılır; oynatma başlangıç kapısını açar.
#' @param on_drained function(teslim_edilen) — hat boşaldığında teslim edilen
#'   toplam parça sayısıyla (1. parça dahil) bir kez çağrılır.
#' @param policy ai_expert_chunk_pipeline_policy() çıktısı.
ai_expert_chunk_pipeline_baslat <- function(parcalar, baslangic, synth_fn,
                                            is_current_fn, queue_fn,
                                            on_buffer_settled = NULL,
                                            on_drained = NULL,
                                            policy = ai_expert_chunk_pipeline_policy()) {
  toplam <- length(parcalar)
  durum <- new.env(parent = emptyenv())
  durum$sonuclar <- list()               # parça indeksi -> payload | FALSE
  durum$siradaki_teslim <- baslangic     # sıradaki teslim edilecek parça indeksi
  durum$siradaki_sentez <- baslangic
  durum$aktif <- 0L
  durum$kablo <- baslangic - 1L          # sıradaki 0 tabanlı kablo indeksi
  durum$tampon_bildirildi <- FALSE
  durum$bosaldi_bildirildi <- FALSE

  tampon_bildir <- function() {
    if (isTRUE(durum$tampon_bildirildi)) return(invisible(NULL))
    durum$tampon_bildirildi <- TRUE
    if (is.function(on_buffer_settled)) on_buffer_settled()
    invisible(NULL)
  }

  bosaldi_bildir <- function() {
    if (isTRUE(durum$bosaldi_bildirildi)) return(invisible(NULL))
    if (durum$siradaki_teslim <= toplam || durum$aktif > 0L) return(invisible(NULL))
    durum$bosaldi_bildirildi <- TRUE
    if (is.function(on_drained)) on_drained(durum$kablo)
    invisible(NULL)
  }

  if (baslangic > toplam) {
    tampon_bildir()
    bosaldi_bildir()
    return(invisible(durum))
  }

  teslim_et <- function() {
    while (durum$siradaki_teslim <= toplam) {
      anahtar <- as.character(durum$siradaki_teslim)
      sonuc <- durum$sonuclar[[anahtar]]
      if (is.null(sonuc)) break
      durum$sonuclar[[anahtar]] <- NULL
      durum$siradaki_teslim <- durum$siradaki_teslim + 1L
      if (!isFALSE(sonuc)) {
        # Başarısız parçalar kablo indeksi TÜKETMEZ; sıradaki hazır parça
        # onun yerini alır ve istemci kuyruğu boşluksuz ilerler.
        queue_fn(durum$kablo, sonuc$text, sonuc$audio_src, sonuc$duration)
        durum$kablo <- durum$kablo + 1L
      }
    }
    invisible(NULL)
  }

  parca_sonuclandi <- function(idx, sonuc) {
    durum$aktif <- durum$aktif - 1L
    durum$sonuclar[[as.character(idx)]] <- sonuc
    if (isTRUE(is_current_fn())) teslim_et()
    if (idx == baslangic) tampon_bildir()
    sentez_surdur()
    bosaldi_bildir()
    invisible(NULL)
  }

  sentez_surdur <- function() {
    while (durum$aktif < policy$eszamanli_sinir &&
           durum$siradaki_sentez <= toplam) {
      if (!isTRUE(is_current_fn())) {
        # Konuşma iptal edildi: kuyruktaki işi başlatma, hattı boşalt.
        durum$siradaki_sentez <- toplam + 1L
        durum$siradaki_teslim <- toplam + 1L
        tampon_bildir()
        bosaldi_bildir()
        return(invisible(NULL))
      }
      idx <- durum$siradaki_sentez
      durum$siradaki_sentez <- idx + 1L
      durum$aktif <- durum$aktif + 1L
      local({
        parca_idx <- idx
        parca_metin <- parcalar[[parca_idx]]
        # promises operatörleri global olarak bağlı olmayabilir (izole test/
        # worker bağlamı); açık promises::then çağrısı kullanılır.
        promises::then(
          synth_fn(parca_metin),
          onFulfilled = function(res) {
            tryCatch({
              gecerli <- isTRUE(res$success) && nzchar(res$audio_src %||% "")
              parca_sonuclandi(parca_idx, if (gecerli) {
                list(text = parca_metin, audio_src = res$audio_src,
                     duration = res$duration %||% 0)
              } else {
                FALSE
              })
            }, error = function(e) {
              cat(sprintf("[AI_EXPERT] Parça teslim hatası: %s\n", conditionMessage(e)))
            })
          },
          onRejected = function(e) {
            tryCatch(parca_sonuclandi(parca_idx, FALSE), error = function(e2) NULL)
          }
        )
      })
    }
    invisible(NULL)
  }

  sentez_surdur()
  invisible(durum)
}

#' Kalan konuşma parçalarını modül bağımlılıklarıyla hatta bağla.
#'
#' @description Modül tarafındaki lambda yoğunluğunu azaltan uyarlayıcı:
#' sentez/teslim/tamamlanma kapanışlarını burada kurar. `kapi` başlangıç
#' tamponu kapısıdır; hat, tampon parçası sonuçlanınca kapıyı açar ve
#' başarısız parçalar dizi sonunu kısaltırsa istemciye gerçek teslim
#' sayısını `aiExpertSequenceComplete` ile bildirir.
ai_expert_kalan_parcalari_kuyrukla <- function(all_chunks, baslangic,
                                               tts_processor, char_id,
                                               chunk_dispatch, session,
                                               ns_prefix, speech_token,
                                               kapi,
                                               policy = ai_expert_chunk_pipeline_policy()) {
  ai_expert_chunk_pipeline_baslat(
    parcalar = all_chunks,
    baslangic = baslangic,
    synth_fn = function(parca_metin) {
      tts_processor$synthesize_speech(parca_metin, persona_id = char_id)
    },
    is_current_fn = chunk_dispatch$is_current,
    queue_fn = function(index0, parca_metin, audio_src, duration) {
      chunk_dispatch$queue(list(
        index         = index0,
        text          = parca_metin,
        audioSrc      = audio_src,
        audioDuration = duration,
        nsPrefix      = ns_prefix,
        speechToken   = speech_token
      ))
    },
    on_buffer_settled = kapi$tampon_hazir,
    on_drained = function(teslim_edilen) {
      if (!chunk_dispatch$is_current()) return(invisible(NULL))
      if (teslim_edilen < length(all_chunks)) {
        chunk_dispatch$complete(list(
          deliveredChunks = teslim_edilen,
          nsPrefix        = ns_prefix,
          speechToken     = speech_token
        ))
      }
    },
    policy = policy
  )
}

#' Doğal konuşma bitişi kancasını güvenle çağır (tek slotlu env sahibi).
ai_expert_konusma_bitti_bildir <- function(cb_env, ...) {
  cb <- cb_env$fn
  if (is.function(cb)) tryCatch(cb(...), error = function(e) NULL)
  invisible(NULL)
}
