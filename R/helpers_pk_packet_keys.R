# ==============================================================================
# Dosya Yolu: R/helpers_pk_packet_keys.R
# Açıklama: Paket gruplama ANAHTARI ve grup ETİKETİ üreten saf yardımcılar.
#
#           NEDEN AYRI DOSYA: `R/helpers_pk_analysis_packet.R` bakım
#           ratchet'inin satır tavanındadır (global 796 satır). Anahtar/etiket
#           üretimi kendi başına bütün bir sorumluluktur: birleşik anahtarın
#           ENJEKTİF olması, boş metnin `NA` sayılması ve etiketin anahtarla
#           AYNI ayrımı koruması köken doğrulamasının doğruluk sınırıdır.
#
#           Dosya saftır: Shiny/reaktif/DB/ağ bağımlılığı YOKTUR ve işçi
#           sürecinde çalışabilir. Kaynak manifesti bu dosyayı
#           `helpers_pk_analysis_packet.R` dosyasından ÖNCE yükler.
# ==============================================================================

# Boş/yalnızca boşluk metin, SQL sonuçlarında yaygın bir "eksik" biçimidir.
# `NA` sayılmazsa kapsama raporu eksikliği olduğundan az gösterir ve boş dize
# kategorik dağılımda gerçek (çoğu zaman ilk sıradaki) bir değer olur.
.pk_blank_to_na <- function(x) {
  # FAKTOR SUTUNU DA METINDIR: seviye olarak saklanan bos/bosluk degeri `pk_packet_categorical()` icinde NA sayilirken kapsama raporunda DOLU gorunuyor, ayni sutun icin IKI CELISKILI sayi yayimlaniyordu.
  if (is.factor(x)) x <- as.character(x)
  if (!is.character(x)) return(x)
  x[!is.na(x) & !nzchar(trimws(x))] <- NA_character_
  x
}

# Ayraç çakışmasız birleşik anahtar: her parça bayt uzunluğu ön ekiyle yazılır,
# eksik değer ayrı bir jetonla kodlanır.
.pk_join_key <- function(data, columns) {
  parcalar <- lapply(columns, function(s) {
    v <- data[[s]]
    # KESİRLİ SANİYE KAYBEDİLEMEZ.
    #
    # `format.POSIXct()` varsayılanı kesirli saniyeyi YAZMAZ; aynı saniye
    # içindeki FARKLI damgalar tek anahtara düşüyor, bu da ya sahte "tanecik
    # mükerrerliği" (geçerli toplulaştırmayı bloklar) ya da iki ayrı
    # `default_group_by` kovasının BİRLEŞMESİ (yanlış grup olgusu) demekti.
    # Kayıpsız temsil: sayısal an (epoch saniye, tam basamakla).
    # `%.6f` MİKROSANİYEDE KESERDİ: aynı mikrosaniye penceresine düşen FARKLI
    # damgalar tek anahtar parçası üretip iki ayrı grubu BİRLEŞTİRİYORDU.
    # `%.17g` bir `double` değerini kayıpsız (round-trip) yazar.
    ch <- if (inherits(v, "POSIXt")) {
      sprintf("%.17g", as.numeric(v))
    } else if (inherits(v, "Date")) {
      format(v)
    } else {
      as.character(v)
    }
    ch[is.na(v)] <- NA_character_
    out <- paste0(nchar(ch, type = "bytes"), ":", ch)
    out[is.na(ch)] <- "<NA>:"
    out
  })
  do.call(paste, c(parcalar, list(sep = "|")))
}

# Okunabilir ama ENJEKTİF zaman damgası etiketi. `%OS6` kesirli saniyeyi
# MİKROSANİYEDE KESER; `.pk_join_key()` mikrosaniye altındaki iki damgayı AYIRIR
# ama etiket onları birleştirir, iki farklı grup AYNI `fact_id`yi alır ve doğru
# alıntılanan bir değer DİĞER grubun olgusuna karşı doğrulanırdı. Mikrosaniye
# altı artık YALNIZCA gerçekten varsa eklenir; olağan durumda etiket DEĞİŞMEZ.
.pk_posix_label <- function(v) {
  metin <- format(v, "%Y-%m-%d %H:%M:%OS6")
  mikro <- suppressWarnings(as.numeric(v) * 1e6)
  if (length(mikro) != 1L || is.na(mikro) || !is.finite(mikro)) return(metin)
  artik <- mikro - floor(mikro)  # `%OS6` KESER, bu yüzden `floor()` ile hizalanır.
  if (artik <= 0) return(metin)
  sprintf("%s+%.0fns", metin, artik * 1000)
}

# Kullanıcıya/model paketine görünen grup etiketi. ENJEKTİF olmak ZORUNDADIR:
# `group_keys` olarak olgu kayıtlarına geçer, yani OLGU KİMLİĞİNİN parçasıdır.
# Düz `" | "` birleşimi `("A | B", "C")` ile `("A", "B | C")` gruplarını AYNI
# gösterirdi; kaçışsız tırnak ise `ProjeAdi = 'A", Yil="1'` + `Yil = 2` ile
# `ProjeAdi = "A"` + `Yil = 1` çiftini tek dizeye çökertir; köken doğrulaması o
# zaman geçerli bir olguyu reddeder ya da değeri YANLIŞ gruba bağlar. Ters bölü
# ÖNCE kaçışlanır; aksi hâlde `\"` dizisi belirsiz kalırdı.
.pk_group_label <- function(data, columns, index) {
  paste(vapply(columns, function(s) {
    v <- data[[s]][index]
    # KESIRLI SANIYE ETIKETTE DE KORUNUR: `.pk_join_key()` ayni saniyedeki iki damgayi AYIRIR; etiket birlestirirse iki grup AYNI `fact_id`yi alir ve dogru alintilanan bir deger DIGER grubun olgusuna karsi dogrulanirdi.
    ch <- if (inherits(v, "POSIXt")) .pk_posix_label(v) else if (inherits(v, "Date")) format(v) else as.character(v)
    if (length(ch) != 1L || is.na(ch)) return(sprintf("%s=(bos)", s))
    ch <- gsub("\"", "\\\"", gsub("\\", "\\\\", ch, fixed = TRUE), fixed = TRUE)
    sprintf("%s=\"%s\"", s, ch)
  }, character(1)), collapse = ", ")
}
