# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_sunum.R
# Açıklama: Ortak Oturumlar SAF sunum-karar yardımcıları: rol görünen ad,
#           atanabilir rol seçenekleri ve canlı durum sunum rozeti (renk sınıfı
#           + erişilebilir Türkçe etiket). Yetki matrisi ve iş kuralı sabitleri
#           R/helpers_ortak_oturum_permissions.R içindedir ve bu dosyadan ÖNCE
#           yüklenir (ortak_oturum_rolleri bağımlılığı).
#
# Sözleşmeler:
#   * Bu dosya SAF kalır: Shiny, reactive, DB, ağ, dosya sistemi yok.
#   * Teknik rol anahtarları (OturumYöneticisi) DEĞİŞMEZ; yalnızca görünen ad
#     boşluklu üretilir. Görünüm ayrımı güvenlik değildir.
#   * Durum göstergesi yalnızca renge dayanmaz: rozet daima title/aria-label
#     için Türkçe etiket taşır.
# ==============================================================================

# DB'de saklanan teknik rol adının kullanıcıya görünen Türkçe etiketi.
# Teknik anahtarlar değişmez; yalnızca görünüm ayrışır.
ortak_rol_gorunen_ad <- function(rol) {
  etiketler <- c(
    "Sahip" = "Sahip",
    "OturumYöneticisi" = "Oturum Yöneticisi",
    "Katılımcı" = "Katılımcı",
    "İzleyici" = "İzleyici"
  )

  rol <- as.character(rol %||% "")[1]
  if (!is.na(rol) && nzchar(rol) && rol %in% names(etiketler)) {
    return(unname(etiketler[[rol]]))
  }
  if (is.na(rol)) "" else rol
}

# Davet/rol atama seçenekleri: Sahip atanamaz; görünen etiket + teknik değer.
ortak_rol_secenekleri <- function() {
  roller <- setdiff(ortak_oturum_rolleri(), ortak_oturum_rolleri()[1])
  stats::setNames(roller, vapply(roller, ortak_rol_gorunen_ad, character(1)))
}

# Katılımcı/davet listelerindeki durum göstergesi: renk sınıfı + erişilebilir
# Türkçe etiket (yalnızca renge dayanılmaz).
#   davet bekliyor            -> sarı (oo-canli-davetli)
#   çevrim içi + bu odada     -> yeşil (oo-canli-odada)
#   çevrim içi (başka sayfa)  -> mavi (oo-canli-cevrimici)
#   boşta                     -> turuncu (oo-canli-bosta)
#   aksi                      -> gri (oo-canli-cevrimdisi)
ortak_sunum_rozeti <- function(canli_durum,
                               ayni_odada = FALSE,
                               davet_bekliyor = FALSE) {
  if (isTRUE(davet_bekliyor)) {
    return(list(sinif = "oo-canli-davetli", etiket = "Davet bekliyor"))
  }

  durum <- as.character(canli_durum %||% "")[1]

  if (identical(durum, "Çevrimİçi")) {
    if (isTRUE(ayni_odada)) {
      return(list(sinif = "oo-canli-odada", etiket = "Bu odada çevrim içi"))
    }
    return(list(sinif = "oo-canli-cevrimici", etiket = "Uygulamada çevrim içi"))
  }

  if (identical(durum, "Boşta")) {
    return(list(sinif = "oo-canli-bosta", etiket = "Boşta"))
  }

  list(sinif = "oo-canli-cevrimdisi", etiket = "Çevrim dışı")
}

# Davet paneli aday kullanıcı süzme kararı (SAF; Shiny/DB yok). Kullanıcı
# dizinine canlı durum + mevcut katılım durumu ekler ve seçili filtreye göre
# süzer. Kendisi ve zaten katılmış (Katıldı) kullanıcılar her filtrede elenir.
#   * "Çevrim İçi Kullanıcılar" -> Çevrimİçi + Boşta durumundaki kullanıcılar
#   * "Davet Edilenler"         -> yalnızca DavetEdildi satırları
#   * "Tüm Kullanıcılar"        -> katılmamış tüm kullanıcılar
# Sonuç, orijinal kolonlara ek OoCanliDurum ve OoMevcutDurum kolonlarını taşır;
# render bu iki kolonu doğrudan okur (canlı durum tazeliği burada garanti edilir).
ortak_davet_aday_kullanicilar <- function(kullanicilar,
                                          canli_durum_df = NULL,
                                          mevcut_katilimcilar = NULL,
                                          benim_id = NA_integer_,
                                          filtre = "Çevrim İçi Kullanıcılar") {
  if (!is.data.frame(kullanicilar) || nrow(kullanicilar) == 0L ||
      !("UserID" %in% names(kullanicilar))) {
    if (is.data.frame(kullanicilar)) {
      return(kullanicilar[0, , drop = FALSE])
    }
    return(data.frame())
  }

  benim_id <- suppressWarnings(as.integer(benim_id)[1])
  filtre <- as.character(filtre %||% "Çevrim İçi Kullanıcılar")[1]

  canli_var <- is.data.frame(canli_durum_df) && nrow(canli_durum_df) > 0L &&
    all(c("KullaniciID", "CanliDurum") %in% names(canli_durum_df))
  mevcut_var <- is.data.frame(mevcut_katilimcilar) && nrow(mevcut_katilimcilar) > 0L &&
    all(c("KullaniciID", "KatilimDurumu") %in% names(mevcut_katilimcilar))

  n <- nrow(kullanicilar)
  tut <- logical(n)
  canli <- rep("ÇevrimDışı", n)
  mevcut <- rep("", n)

  for (i in seq_len(n)) {
    uid <- suppressWarnings(as.integer(kullanicilar$UserID[i]))
    if (is.na(uid) || (!is.na(benim_id) && identical(uid, benim_id))) {
      next
    }

    if (canli_var) {
      eslesen <- canli_durum_df[canli_durum_df$KullaniciID == uid, , drop = FALSE]
      if (nrow(eslesen) > 0L) {
        canli[i] <- as.character(eslesen$CanliDurum[1])
      }
    }
    if (mevcut_var) {
      eslesen <- mevcut_katilimcilar[mevcut_katilimcilar$KullaniciID == uid, , drop = FALSE]
      if (nrow(eslesen) > 0L) {
        mevcut[i] <- as.character(eslesen$KatilimDurumu[1])
      }
    }

    if (identical(mevcut[i], "Katıldı")) {
      next
    }

    tut[i] <- switch(
      filtre,
      "Çevrim İçi Kullanıcılar" = canli[i] %in% c("Çevrimİçi", "Boşta"),
      "Davet Edilenler" = identical(mevcut[i], "DavetEdildi"),
      TRUE
    )
  }

  sonuc <- kullanicilar[tut, , drop = FALSE]
  sonuc$OoCanliDurum <- canli[tut]
  sonuc$OoMevcutDurum <- mevcut[tut]
  sonuc
}

# --- Ortak oturum personası (SAF; config_characters saf verisine dayanır) --------

# Ortak oturumun etkin persona kimliğini çözer. Geçerli bir kimlik verilmişse
# normalize edilir; yoksa oturum kimliğinden deterministik ve KARARLI bir
# varsayılan türetilir. Böylece persona metadata'sı olmayan eski oturumlar da
# güvenli, kararlı ve çeşitli bir persona ile açılır (varsayılan hep aynı olmaz).
ortak_oturum_persona_kimligi <- function(secilen = NULL, oturum_id = NULL) {
  gecerli <- c("emre", "selin", "deniz", "can", "ipek")

  sec <- tolower(trimws(as.character(secilen %||% "")[1]))
  if (is.na(sec)) {
    sec <- ""
  }
  if (nzchar(sec) &&
      exists("normalize_character_id", mode = "function", inherits = TRUE)) {
    sec <- tryCatch(normalize_character_id(sec), error = function(e) sec)
  }
  if (sec %in% gecerli) {
    return(sec)
  }

  oid <- suppressWarnings(as.integer(oturum_id)[1])
  if (is.na(oid) || oid <= 0L) {
    return(gecerli[1])
  }
  gecerli[(oid %% length(gecerli)) + 1L]
}

# Persona kimliğinden render için görünüm verisi üretir: görünen ad, baş harf
# ve aksan rengi. Persona görselleri depoda bulunmayabilir; bu yüzden avatar
# baş harf + aksan rengiyle çizilir (kırık görsel riski yok). config_characters
# yoksa güvenli varsayılana düşer.
ortak_oturum_persona_gorunumu <- function(persona_id, oturum_id = NULL) {
  id <- ortak_oturum_persona_kimligi(persona_id, oturum_id)

  ad <- id
  accent <- "#7C4DFF"
  if (exists("get_character_record", mode = "function", inherits = TRUE)) {
    rec <- tryCatch(get_character_record(id), error = function(e) NULL)
    if (is.list(rec)) {
      ad <- as.character(rec$full_name %||% rec$display_name %||% id)[1]
      accent <- as.character(rec$accent %||% accent)[1]
    }
  }

  temiz <- trimws(as.character(ad)[1])
  bas <- if (nzchar(temiz)) toupper(substr(temiz, 1L, 1L)) else "Y"

  list(id = id, ad = if (nzchar(temiz)) temiz else id, bas_harf = bas, accent = accent)
}

# Persona için LLM sistem mesajı: ortak oturum yanıtları seçili persona tarzında
# üretilsin. config_characters sistem talimatını tek kaynak olarak kullanır;
# yoksa boş metin döner (davranış değişmeden normal LLM yoluna devam edilir).
ortak_oturum_persona_sistem_prompt <- function(persona_id, oturum_id = NULL) {
  id <- ortak_oturum_persona_kimligi(persona_id, oturum_id)

  if (!exists("get_character_record", mode = "function", inherits = TRUE)) {
    return("")
  }
  rec <- tryCatch(get_character_record(id), error = function(e) NULL)
  if (!is.list(rec)) {
    return("")
  }

  talimat <- as.character(rec$system_prompt_en %||% "")[1]
  ad <- as.character(rec$full_name %||% rec$display_name %||% id)[1]
  if (!nzchar(talimat)) {
    return("")
  }

  paste0(
    "You are '", ad, "', the shared AI persona of this collaborative MERGEN Bilge room. ",
    talimat,
    " Always respond in Turkish."
  )
}

# Ortak oturumda seçilebilir persona listesi (görünen ad -> kimlik). Yapılandırma
# modülü personalarını tek kaynak olarak kullanır; yoksa güvenli sabit listeye düşer.
ortak_persona_secenekleri <- function() {
  gecerli <- c("emre", "selin", "deniz", "can", "ipek")
  etiketler <- vapply(gecerli, function(id) {
    g <- ortak_oturum_persona_gorunumu(id)
    ad <- as.character(g$ad %||% id)[1]
    alt <- if (exists("get_character_record", mode = "function", inherits = TRUE)) {
      rec <- tryCatch(get_character_record(id), error = function(e) NULL)
      as.character((rec$subtitle %||% "")[1])
    } else {
      ""
    }
    if (nzchar(alt)) sprintf("%s · %s", ad, alt) else ad
  }, character(1))
  stats::setNames(gecerli, etiketler)
}
