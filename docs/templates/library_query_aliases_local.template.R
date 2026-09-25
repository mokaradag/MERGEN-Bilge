# ==============================================================================
# ŞABLON: R/library_query_aliases_local.R (Proje ve Kaynak Analizi alias'ları)
# ==============================================================================
# Bu dosya bir ŞABLONDUR. Windows VM'de uygulama klasörüne şu adla kopyalayın:
#
#   R/library_query_aliases_local.R
#
# Hedef dosya .gitignore içindedir ve GitHub'a GÖNDERİLMEZ; gerçek kurum,
# proje ve birim adları YALNIZCA orada durur. Bu şablona gerçek ad yazmayın.
#
# NE İŞE YARAR?
#   Kullanıcılar istemde bir değeri kısaltma ya da gündelik adıyla yazabilir
#   ("PYB'nin projeleri", "kampüs işi"). Alias, bu yazımı sorgu sonucundaki
#   GERÇEK (kanonik) değere bağlar ("Proje Yönetim Birimi", "Merkez Kampüs
#   Yapım İşi"). Eşleştirme, filtre değeri çözülürken bulanık aramadan ÖNCE
#   denenir.
#
# KURALLAR (başlangıç doğrulaması bunları denetler; ihlal açılışta raporlanır):
#   1) Sorgu kimliği query_library içinde bulunmalıdır ("gen_00", "q042" ...).
#   2) Sütun adı sorgu sonucundaki GERÇEK sütun adıdır ve column_meta içinde
#      beyan edilmiş olmalıdır (metadata üreticisinin yazdığı
#      R/library_query_meta_local.R ya da küre edilen R/library_query_meta.R).
#   3) Kod/kimlik sütunları (role = "id" ya da match = "exact") alias alamaz;
#      gerekiyorsa o sütuna gözden geçirilmiş allow_aliases = TRUE beyanı
#      eklenmelidir.
#   4) Kanonik değer, veritabanındaki yazımla BİREBİR aynı olmalıdır (büyük/
#      küçük harf ve Türkçe karakterler dahil). Sonuçta bulunmayan kanonik
#      değer eşleşmez; analiz yanlış satırla devam etmez.
#   5) Bir alias yalnızca TEK kanonik değere gidebilir. Alias karşılaştırması
#      Türkçe küçük harfe katlanır ve boşluklar sadeleşir: "PYB", "pyb" ve
#      " Pyb " aynı alias sayılır.
#   6) Dosyayı UTF-8 kaydedin; emoji kullanmayın. Değişiklikten sonra
#      uygulamayı YENİDEN BAŞLATIN (tarayıcı yenilemesi yetmez).
#
# DOĞRULAMA (VM'de R konsolunda, uygulama klasöründeyken):
#   source("R/library_query_aliases_local.R", encoding = "UTF-8")
#   str(pk_query_aliases_local)
#   Açılışta "alias bindirmesi" içeren log satırı varsa kural ihlali vardır.
# ==============================================================================

pk_query_aliases_local <- local({

  # Yardımcı: "kanonik değer" = c("alias 1", "alias 2", ...) biçimini doğrulayıcının
  # beklediği c("alias 1" = "kanonik", "alias 2" = "kanonik") biçimine çevirir.
  alias_haritasi <- function(...) {
    tanimlar <- list(...)
    if (!length(tanimlar)) return(structure(character(0), names = character(0)))
    kanonikler <- names(tanimlar)
    if (is.null(kanonikler) || any(!nzchar(kanonikler))) {
      stop("alias_haritasi(): her grup \"Kanonik Deger\" = c(...) biçiminde adlandırılmalıdır.",
           call. = FALSE)
    }
    aliaslar <- unlist(lapply(tanimlar, as.character), use.names = FALSE)
    hedefler <- rep(kanonikler, lengths(tanimlar))
    stats::setNames(hedefler, aliaslar)
  }

  # --------------------------------------------------------------------------
  # 1) ORTAK ALIAS SÖZLÜKLERİ
  #    Solda veritabanındaki kanonik değer, sağda kullanıcıların yazabileceği
  #    biçimler. Örnekleri kendi değerlerinizle değiştirip başlarındaki #
  #    işaretini kaldırın.
  # --------------------------------------------------------------------------
  projeler <- alias_haritasi(
    # "Merkez Kampüs Yapım İşi"         = c("merkez kampüs", "MKY", "kampüs inşaatı"),
    # "Kuzey Lojistik Depo Genişletme"  = c("kuzey depo", "lojistik depo", "KLDG")
  )

  birimler <- alias_haritasi(
    # "Proje Yönetim Birimi"            = c("PYB", "proje yönetimi"),
    # "Planlama ve Proje Destek Birimi" = c("PPDB", "planlama birimi", "proje destek")
  )

  programlar <- alias_haritasi(
    # "Altyapı Programı"                = c("altyapı", "AP")
  )

  # --------------------------------------------------------------------------
  # 2) SÖZLÜKLERİ SORGU / SÜTUN ÇİFTLERİNE BAĞLAYIN
  #    Aynı sözlük birden çok sorguya bağlanabilir. "sutun" değeri sorgu
  #    sonucundaki gerçek sütun adıdır (boşluk/Türkçe karakter içerebilir).
  # --------------------------------------------------------------------------
  baglamalar <- list(
    # list(sorgu = "gen_00", sutun = "Proje Adı",           harita = projeler),
    # list(sorgu = "gen_00", sutun = "Program Müdürlüğü",   harita = birimler),
    # list(sorgu = "q042",   sutun = "Program Direktörlüğü", harita = programlar)
  )

  # --------------------------------------------------------------------------
  # 3) DOĞRULAYICININ BEKLEDİĞİ BİÇİME ÇEVİRME (değiştirmeyin)
  #    Sonuç: list("<sorgu>" = list("<sütun>" = c("<alias>" = "<kanonik>")))
  # --------------------------------------------------------------------------
  sonuc <- list()
  for (baglama in baglamalar) {
    if (!length(baglama$harita)) next
    sorgu <- as.character(baglama$sorgu)[1]
    sutun <- as.character(baglama$sutun)[1]
    if (is.null(sonuc[[sorgu]])) sonuc[[sorgu]] <- list()
    sonuc[[sorgu]][[sutun]] <- c(sonuc[[sorgu]][[sutun]], baglama$harita)
  }
  sonuc
})
