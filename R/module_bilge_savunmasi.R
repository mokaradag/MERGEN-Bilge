# ==============================================================================
# Dosya Yolu: R/module_bilge_savunmasi.R
# Açıklama: Bilge Savunması sunucu modülü. Sayfa açıldığında istemciye oyun
#           manifestini gönderir; koşu yaşam döngüsünü (başlat / kontrol
#           noktası / bitir / bırak), haftalık meydan okumayı, savunma
#           planlarını, topluluk operasyonunu ve oyun ayarlarını yönetir.
#
# Sözleşmeler:
#   * Oyun motoru YALNIZCA sayfa açıldığında (page_opened) başlatılır;
#     uygulama açılışında hiçbir oyun işi yapılmaz.
#   * Nihai puan istemciden körlemesine alınmaz; bs_db_finalize_run()
#     içindeki sunucu doğrulaması/yeniden hesaplaması bağlayıcıdır.
#   * Tüm kullanıcı işlemleri canlı kullanıcı kimliği sağlayıcısı üzerinden
#     ve DB katmanında UserID ile izole yürür.
#   * MB_Game_* tabloları kurulu değilse oyun kalıcılıksız modda oynanabilir
#     kalır; kullanıcıya açıklayıcı bir not gösterilir, uygulama çökmez.
#   * İstemci yükleri boyut sınırlı JSON'dur (bs_yuk_coz).
# ==============================================================================

# Canlı kullanıcı kimliği sağlayıcısını çözer; geçersiz/placeholder ise NULL.
.bs_srv_resolve_uid <- function(current_user_id) {
  deger <- tryCatch({
    if (is.function(current_user_id)) current_user_id() else current_user_id
  }, error = function(e) NULL)

  uid <- suppressWarnings(as.integer(deger %||% 0L)[1])
  if (is.na(uid) || uid <= 0L) return(NULL)
  uid
}

# data.frame'i istemci için satır listelerine çevirir (boşsa boş liste).
.bs_srv_df_satirlari <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0L) return(list())
  lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE]))
}

# Harita/zorluk kilidi sunucu tarafında da doğrulanır. Kalıcılık yokken
# (bundle NULL) tüm haritalar serbesttir; ödül de yazılmaz.
.bs_srv_harita_kilidi_acik_mi <- function(harita_id, zorluk, bundle) {
  katalog <- bs_harita_katalogu()
  kayit <- katalog[[harita_id]]
  if (is.null(kayit)) return(FALSE)
  if (is.null(bundle)) return(TRUE)

  kampanya <- bundle$kampanya
  tamamlanan <- if (is.data.frame(kampanya) && nrow(kampanya) > 0L) {
    unique(as.character(kampanya$MapID[kampanya$CompletedCount > 0]))
  } else {
    character(0)
  }

  if (!is.null(kayit$acilis_kosulu) && !kayit$acilis_kosulu %in% tamamlanan) {
    return(FALSE)
  }
  if (identical(zorluk, "gelismis") && !harita_id %in% tamamlanan) {
    return(FALSE)
  }
  TRUE
}

# İlerleme paketini (kalıcılık/profil/kampanya/kahraman/başarım/devam)
# çözer. Hem ilk sayfa açılışında (.bs_srv_init_yuku) hem de kalıcı bir koşu
# sonuçlandıktan sonra menüye dönüşte istemcinin BAYAT ilerleme göstermemesi
# için tam sayfa init'i beklemeden yeniden istenebilir (bkz.
# input$bs_profil_yenile ve www/js/bilge_savunmasi_uygulama.js "sunucu-profil").
.bs_srv_profil_yuku <- function(uid) {
  kalicilik <- isTRUE(bs_db_tables_available())

  bundle <- NULL
  devam <- NULL
  if (kalicilik && !is.null(uid)) {
    bundle <- bs_db_load_profile_bundle(uid)
    devam <- bs_db_active_run(uid)
  }

  list(
    kalicilik = kalicilik,
    profil = if (!is.null(bundle)) bundle$profil else NULL,
    kampanya = if (!is.null(bundle)) .bs_srv_df_satirlari(bundle$kampanya) else list(),
    kahraman_ilerlemesi = if (!is.null(bundle)) .bs_srv_df_satirlari(bundle$kahramanlar) else list(),
    basarimlar = if (!is.null(bundle)) .bs_srv_df_satirlari(bundle$basarimlar) else list(),
    devam = devam
  )
}

# İstemci başlangıç yükünü derler (statik manifest alanları + ilerleme paketi).
.bs_srv_init_yuku <- function(uid) {
  c(
    list(
      etkin = TRUE,
      surumler = bs_surum_bilgisi(),
      personalar = bs_persona_manifest(),
      haritalar = bs_harita_katalogu(),
      zorluklar = bs_zorluk_katalogu(),
      basarim_katalogu = bs_basarim_katalogu(),
      haftalik = bs_haftalik_meydan_okuma()
    ),
    .bs_srv_profil_yuku(uid)
  )
}

# Koşu başlatma isteğini moda göre sunucu-otoriter üçlüye (harita/zorluk/
# tohum) çözer. Hata durumunda list(hata=...) döner.
.bs_srv_kosu_istegi_cozumle <- function(uid, istek) {
  mod <- as.character(istek$mod %||% "kampanya")[1]

  if (identical(mod, "haftalik")) {
    meydan <- bs_haftalik_meydan_okuma()
    sezon <- if (isTRUE(bs_db_tables_available())) {
      bs_db_get_or_create_season(meydan)
    } else {
      NULL
    }
    return(list(
      mod = "haftalik",
      harita = meydan$harita,
      zorluk = meydan$zorluk,
      tohum = meydan$tohum,
      sezon_id = if (!is.null(sezon)) sezon$sezon_id else NULL,
      plan_id = NULL
    ))
  }

  if (identical(mod, "plan")) {
    # Devam isteği plan silinse bile aktif koşu satırından çözülür; koruma
    # plan_bulunamadi reddinden ÖNCE gelir (sunucu koruması sözleşmesi).
    istek_kosu_id <- suppressWarnings(as.integer(istek$kosu_id))
    istek_jeton <- .bs_metin_temizle(istek$istemci_jetonu, 64L)
    if (!is.null(uid) && !is.na(istek_kosu_id) && nzchar(istek_jeton)) {
      aktif <- bs_db_active_run(uid)
      if (!is.null(aktif) && identical(aktif$kosu_id, istek_kosu_id) &&
          identical(as.character(aktif$mod), "plan") &&
          identical(aktif$istemci_jetonu, istek_jeton)) {
        return(list(
          mod = "plan",
          harita = aktif$harita,
          zorluk = aktif$zorluk,
          tohum = aktif$tohum,
          sezon_id = NULL,
          plan_id = aktif$plan_id
        ))
      }
    }

    plan_id <- suppressWarnings(as.integer(istek$plan_id))
    if (is.na(plan_id)) return(list(hata = "plan_kimligi"))
    plan <- bs_db_get_blueprint(plan_id)
    if (is.null(plan) || isTRUE(plan$desteklenmiyor)) {
      return(list(hata = "plan_bulunamadi"))
    }
    return(list(
      mod = "plan",
      harita = plan$harita,
      zorluk = plan$zorluk,
      tohum = plan$tohum,
      sezon_id = NULL,
      plan_id = plan$plan_id
    ))
  }

  # Kampanya: istemci seçimi katalog + kilit doğrulamasından geçer.
  harita <- as.character(istek$harita %||% "")[1]
  zorluk <- as.character(istek$zorluk %||% "normal")[1]
  if (!harita %in% names(bs_harita_katalogu()) ||
      !zorluk %in% names(bs_zorluk_katalogu())) {
    return(list(hata = "harita_zorluk"))
  }

  bundle <- if (isTRUE(bs_db_tables_available()) && !is.null(uid)) {
    bs_db_load_profile_bundle(uid)
  } else {
    NULL
  }
  if (!.bs_srv_harita_kilidi_acik_mi(harita, zorluk, bundle)) {
    return(list(hata = "harita_kilitli"))
  }

  # Kampanya tohumu: sunucu üretir (tekrarlanabilirlik için koşuya yazılır).
  tohum <- sample.int(2147483646L, 1L)

  list(
    mod = "kampanya",
    harita = harita,
    zorluk = zorluk,
    tohum = tohum,
    sezon_id = NULL,
    plan_id = NULL
  )
}

# Sonuçlandırma sonrası eşzamansız çok oyunculu kayıtları işler (haftalık
# giriş + topluluk katkısı) ve istemci yanıt paketini tamamlar. `conn`
# testlerde SQLite enjeksiyonu için opsiyoneldir; üretimde NULL bırakılır.
.bs_srv_bitirme_sonrasi <- function(uid, kosu_id, istek, sonuc, conn = NULL) {
  if (!isTRUE(sonuc$kabul)) return(sonuc)

  # Topluluk katkısı: doğrulanmış dalga özetlerinden etkisizleştirme toplamı.
  etkisiz <- 0L
  dalgalar <- istek$ozet$dalga_ozetleri
  if (is.list(dalgalar)) {
    for (dalga in dalgalar) {
      v <- suppressWarnings(as.integer(dalga$olduruldu))
      if (!is.na(v) && v > 0L) etkisiz <- etkisiz + v
    }
  }
  hafta <- bs_hafta_kodu()
  bs_db_add_community_contribution(uid, kosu_id, hafta,
                                   etkisizlestirilen = etkisiz, conn = conn)

  # Haftalık koşu: liderlik girişini işle ve güncel tabloyu pakete ekle.
  # ÖNEMLİ: "şimdiki" hafta burada YENİDEN TÜRETİLMEZ. Koşu, ISO hafta
  # dönümünün tam ortasında bitirilmiş olabilir; bu durumda "şimdiki" hafta
  # koşunun BAŞLADIĞI haftadan farklı olur ve bs_db_submit_challenge_entry()
  # sezon uyuşmazlığından geçerli koşuyu sessizce reddeder. Bunun yerine
  # koşunun MB_Game_Runs.ChallengeSeasonID alanında sunucu tarafından
  # BAŞLARKEN sabitlenmiş sezonu (sonuc$sezon_id) kullanılır.
  if (identical(as.character(istek$mod %||% "")[1], "haftalik") &&
      !is.null(sonuc$sezon_id)) {
    sezon <- bs_db_get_season_by_id(sonuc$sezon_id, conn = conn)
    if (!is.null(sezon)) {
      bs_db_submit_challenge_entry(uid, sezon$sezon_id, kosu_id, conn = conn)
      sonuc$liderlik <- bs_db_challenge_leaderboard(sezon$sezon_id, uid, conn = conn)
      sonuc$sezon <- sezon
    }
  }

  sonuc
}

#' Bilge Savunması Sunucu Modülü
#'
#' @param id Modül kimliği (bilge_savunmasi_module).
#' @param current_user_id Canlı kullanıcı kimliği sağlayıcısı (fonksiyon).
bilgeSavunmasiServer <- function(id, current_user_id) {
  shiny::moduleServer(id, function(input, output, session) {

    gonder <- function(tip, veri) {
      session$sendCustomMessage(tip, veri)
    }

    # Sayfa açıldı: istemciye tam başlangıç paketi gönder. Oyun motoru bu
    # mesaj gelene kadar hiçbir kaynak ayırmaz (tembel başlatma sözleşmesi).
    shiny::observeEvent(input$page_opened, {
      if (!bilge_savunmasi_enabled()) {
        gonder("bs-init", list(etkin = FALSE))
        return(NULL)
      }
      uid <- .bs_srv_resolve_uid(current_user_id)
      gonder("bs-init", .bs_srv_init_yuku(uid))
    })

    # Koşu başlat: sunucu koşu kimliği + otoriter harita/zorluk/tohum üçlüsü.
    shiny::observeEvent(input$bs_kosu_baslat, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      istek <- bs_yuk_coz(input$bs_kosu_baslat)
      if (is.null(istek)) {
        gonder("bs-hata", list(neden = "istek_bicimi"))
        return(NULL)
      }

      uid <- .bs_srv_resolve_uid(current_user_id)
      cozum <- .bs_srv_kosu_istegi_cozumle(uid, istek)
      if (!is.null(cozum$hata)) {
        gonder("bs-hata", list(neden = cozum$hata))
        return(NULL)
      }

      kosu <- NULL
      kalicilik_var <- isTRUE(bs_db_tables_available()) && !is.null(uid)
      if (isTRUE(kalicilik_var)) {
        kosu <- bs_db_start_run(
          uid,
          harita = cozum$harita, zorluk = cozum$zorluk, tohum = cozum$tohum,
          mod = cozum$mod, sezon_id = cozum$sezon_id, plan_id = cozum$plan_id,
          istemci_jetonu = istek$istemci_jetonu
        )
        # DB geçici olarak koşu açamazsa oyun yine kalıcılıksız başlayabilmelidir.
        # Bu, tablolar eksikken kullanılan serbest oyun sözleşmesinin DB hata
        # anlarında da korunmasını sağlar; yanıt paketi kalici = FALSE olur.
      }

      # Idempotent resume/start requests can return an already-persisted run
      # for the supplied client token. In that branch, the freshly resolved
      # config above may contain a new campaign seed (or a new weekly seed
      # after ISO-week rollover), so the client must receive the run fields
      # that actually live in MB_Game_Runs.
      etkin_mod <- if (!is.null(kosu)) kosu$mod else cozum$mod
      degistirici <- NULL
      if (identical(etkin_mod, "haftalik")) {
        # Değiştirici KOŞUNUN KENDİ sezonundan çözülür; istemcinin "şimdiki"
        # haftaya bakması YANLIŞTIR. Aksi halde hafta dönümünden sonra devam
        # edilen eski bir haftalık koşu, yanlışlıkla yeni haftanın
        # değiştiricisiyle (düşman hızı/kaynak/dalga yoğunluğu) oynanır.
        etkin_sezon_id <- if (!is.null(kosu)) kosu$sezon_id else cozum$sezon_id
        sezon_kaydi <- if (!is.null(etkin_sezon_id)) {
          bs_db_get_season_by_id(etkin_sezon_id)
        } else {
          NULL
        }
        degistirici <- if (!is.null(sezon_kaydi)) {
          sezon_kaydi$degistirici
        } else {
          bs_haftalik_meydan_okuma()$degistirici
        }
      }

      gonder("bs-kosu-basladi", list(
        kosu_id = if (!is.null(kosu)) kosu$kosu_id else NULL,
        kalici = !is.null(kosu),
        mod = etkin_mod,
        harita = if (!is.null(kosu)) kosu$harita else cozum$harita,
        zorluk = if (!is.null(kosu)) kosu$zorluk else cozum$zorluk,
        tohum = if (!is.null(kosu)) kosu$tohum else cozum$tohum,
        plan_id = if (!is.null(kosu)) kosu$plan_id else cozum$plan_id,
        degistirici = degistirici,
        istemci_jetonu = as.character(istek$istemci_jetonu %||% "")[1]
      ))
    })

    # İlerleme yenileme: kalıcı bir koşu sonuçlandıktan sonra menüye dönüşte
    # profil/kampanya/kahraman/başarım verisi tam sayfa açılışı beklemeden
    # tazelenir (bkz. www/js/bilge_savunmasi_uygulama.js "sunucu-profil").
    shiny::observeEvent(input$bs_profil_yenile, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      uid <- .bs_srv_resolve_uid(current_user_id)
      gonder("bs-profil", .bs_srv_profil_yuku(uid))
    })

    # Kontrol noktası: dalga sınırında sınırlı durum yazımı.
    shiny::observeEvent(input$bs_kontrol_noktasi, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      istek <- bs_yuk_coz(input$bs_kontrol_noktasi,
                          sinir = BS_MAX_KONTROL_NOKTASI_KARAKTER)
      if (is.null(istek)) return(NULL)

      uid <- .bs_srv_resolve_uid(current_user_id)
      kosu_id <- suppressWarnings(as.integer(istek$kosu_id))
      if (is.null(uid) || is.na(kosu_id)) return(NULL)

      bs_db_save_checkpoint(
        uid, kosu_id,
        dalga = istek$dalga,
        durum_json = .bs_db_json(istek$durum, empty = "{}")
      )
    })

    # Koşu bitir: sunucu doğrulaması + idempotent sonuçlandırma + eşzamansız
    # çok oyunculu kayıtlar; sonuç paketi istemciye döner.
    shiny::observeEvent(input$bs_kosu_bitir, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      istek <- bs_yuk_coz(input$bs_kosu_bitir)
      if (is.null(istek)) {
        gonder("bs-kosu-sonuc", list(kabul = FALSE, neden = "istek_bicimi"))
        return(NULL)
      }

      uid <- .bs_srv_resolve_uid(current_user_id)
      kosu_id <- suppressWarnings(as.integer(istek$kosu_id))
      if (is.null(uid) || is.na(kosu_id)) {
        gonder("bs-kosu-sonuc", list(kabul = FALSE, neden = "kimlik"))
        return(NULL)
      }

      sonuc <- bs_db_finalize_run(
        uid, kosu_id,
        istemci_jetonu = istek$istemci_jetonu,
        ozet = istek$ozet
      )
      sonuc <- .bs_srv_bitirme_sonrasi(uid, kosu_id, istek, sonuc)
      # Bayat yanıt koruması: istemci, sonucu aktif koşu kimliğiyle eşleştirir.
      sonuc$kosu_id <- kosu_id
      gonder("bs-kosu-sonuc", sonuc)
    })

    # Koşuyu bırak (onaylı vazgeçme).
    shiny::observeEvent(input$bs_kosu_birak, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      istek <- bs_yuk_coz(input$bs_kosu_birak)
      uid <- .bs_srv_resolve_uid(current_user_id)
      kosu_id <- suppressWarnings(as.integer(istek$kosu_id))
      if (is.null(uid) || is.na(kosu_id)) return(NULL)
      bs_db_abandon_run(uid, kosu_id)
    })

    # Oyun ayarları (ses/kalite/erişilebilirlik) profil satırına yazılır.
    shiny::observeEvent(input$bs_ayar_kaydet, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      istek <- bs_yuk_coz(input$bs_ayar_kaydet, sinir = 4000L)
      uid <- .bs_srv_resolve_uid(current_user_id)
      if (is.null(istek) || is.null(uid)) return(NULL)
      bs_db_update_settings(uid, istek)
    })

    # Haftalık liderlik tablosu yenileme.
    shiny::observeEvent(input$bs_liderlik, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      uid <- .bs_srv_resolve_uid(current_user_id)
      meydan <- bs_haftalik_meydan_okuma()
      sezon <- if (isTRUE(bs_db_tables_available())) {
        bs_db_get_or_create_season(meydan)
      } else {
        NULL
      }
      gonder("bs-liderlik", list(
        haftalik = meydan,
        sezon = sezon,
        tablo = if (!is.null(sezon)) {
          bs_db_challenge_leaderboard(sezon$sezon_id, uid)
        } else {
          NULL
        }
      ))
    })

    # Topluluk operasyonu toplamları.
    shiny::observeEvent(input$bs_topluluk, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      uid <- .bs_srv_resolve_uid(current_user_id)
      hafta <- bs_hafta_kodu()
      gonder("bs-topluluk", list(
        hafta_kodu = hafta,
        toplamlar = if (isTRUE(bs_db_tables_available())) {
          bs_db_community_totals(hafta, uid)
        } else {
          NULL
        }
      ))
    })

    # Savunma planı yayınla.
    shiny::observeEvent(input$bs_plan_yayinla, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      istek <- bs_yuk_coz(input$bs_plan_yayinla, sinir = BS_MAX_PLAN_KARAKTER)
      uid <- .bs_srv_resolve_uid(current_user_id)
      if (is.null(istek) || is.null(uid)) {
        gonder("bs-plan-yaniti", list(tamam = FALSE, neden = "istek"))
        return(NULL)
      }
      kosu_id <- suppressWarnings(as.integer(istek$kosu_id))
      plan_id <- if (!is.na(kosu_id)) {
        bs_db_publish_blueprint(uid, kosu_id, istek$baslik, istek$plan)
      } else {
        NULL
      }
      gonder("bs-plan-yaniti", list(
        tamam = !is.null(plan_id),
        neden = if (is.null(plan_id)) "plan_dogrulama" else NULL,
        plan_id = plan_id
      ))
    })

    # Plan listesi.
    shiny::observeEvent(input$bs_plan_listesi, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      uid <- .bs_srv_resolve_uid(current_user_id)
      planlar <- if (isTRUE(bs_db_tables_available())) {
        bs_db_list_blueprints(uid)
      } else {
        NULL
      }
      gonder("bs-plan-listesi", list(planlar = planlar))
    })

    # Plan deneme: doğrulanmış plan yükünü istemciye gönder (koşu, ardından
    # bs_kosu_baslat ile mod=plan olarak açılır).
    shiny::observeEvent(input$bs_plan_dene, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      istek <- bs_yuk_coz(input$bs_plan_dene, sinir = 1000L)
      plan_id <- suppressWarnings(as.integer(istek$plan_id))
      if (is.na(plan_id)) return(NULL)
      plan <- bs_db_get_blueprint(plan_id)
      if (is.null(plan)) {
        gonder("bs-hata", list(neden = "plan_bulunamadi"))
      } else if (isTRUE(plan$desteklenmiyor)) {
        gonder("bs-hata", list(neden = "plan_surumu"))
      } else {
        gonder("bs-plan-config", plan)
      }
    })

    # Plan silme (yalnızca sahibi; yumuşak silme).
    shiny::observeEvent(input$bs_plan_sil, {
      if (!bilge_savunmasi_enabled()) return(NULL)
      istek <- bs_yuk_coz(input$bs_plan_sil, sinir = 1000L)
      uid <- .bs_srv_resolve_uid(current_user_id)
      plan_id <- suppressWarnings(as.integer(istek$plan_id))
      if (is.null(uid) || is.na(plan_id)) return(NULL)
      tamam <- bs_db_soft_delete_blueprint(uid, plan_id)
      gonder("bs-plan-yaniti", list(
        tamam = isTRUE(tamam),
        neden = if (isTRUE(tamam)) NULL else "plan_silinemedi",
        silindi = isTRUE(tamam)
      ))
    })

    invisible(NULL)
  })
}
