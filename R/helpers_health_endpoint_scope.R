# ==============================================================================
# Dosya Yolu: R/helpers_health_endpoint_scope.R
# Açıklama: Sağlık uç nokta denetimleri için host çıkarımı ve on-prem/genel
#           internet sınıflandırması (R/helpers_health_checks.R kullanır).
# ==============================================================================

# ASCII harfler yerelden bağımsız küçültülür: Türkçe yerelde tolower("I") "ı" olurdu.
.health_lower <- function(x) {
  tolower(chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x)))
}

# Host çıkarımı köşeli parantezli IPv6 adresini korur: ":" üzerinden kesmek
# `http://[fd00::1]:8080` adresini `[fd00` yapıp yanlış sınıflandırıyordu.
health_url_host <- function(value) {
  # URLdecode CP1254 oturumunda UTF-8 işaretini düşürür; yeniden işaretlenir.
  utf8 <- function(x) {
    Encoding(x)[!is.na(x) & validUTF8(x)] <- "UTF-8"
    x
  }
  host <- sub("^https?://", "", utf8(.health_lower(enc2utf8(as.character(value %||% "")))))
  # Yol/sorgu/fragment ATILIR; aksi hâlde yoldaki "@" userinfo sanılır.
  host <- sub("[/?#].*$", "", host)
  # `https://user:pass@public.example.com` için host "user" dönüyor ve
  # noktasız-host kuralı uç noktayı DAHİLİ sayıp genel isteği gönderiyordu.
  host <- sub("^.*@", "", host)
  # Yüzde kodlu host (`public%2eexample%2ecom`) HTTP istemcisince çözülür;
  # noktasız görünüp intranet sayılmasın diye sınıflandırmadan önce çözülür.
  host <- utf8(.health_lower(utf8(vapply(host, function(h) tryCatch(utils::URLdecode(h), error = function(e) h),
                                   character(1), USE.NAMES = FALSE))))
  # IDNA nokta eşdeğerleri (U+3002, U+FF0E, U+FF61) libcurl'de "." olur;
  # bu ayırıcılı genel ad noktasız görünüp intranet sayılmasın.
  host <- gsub("[\u3002\uff0e\uff61]", ".", enc2utf8(host), perl = TRUE)
  host <- ifelse(
    grepl("^\\[", host),
    sub("^\\[([^]]*)\\].*$", "\\1", host),
    # Köşeli parantezsiz ÇIPLAK IPv6 (birden fazla ":") ilk iki nokta üstünde
    # kesiliyordu: `2001:db8::1` -> `2001`. Bu biçimde port ayrıştırılamaz.
    ifelse(
      lengths(regmatches(host, gregexpr(":", host, fixed = TRUE))) > 1L,
      host,
      sub(":.*$", "", host)
    )
  )
  sub("\\.$", "", host)  # sondaki DNS kök noktası dahili son ek testini düşürüyordu
}

# Operatörün yapılandırdığı servis uç noktaları (.Renviron.example sözleşmesi):
# LOCAL_*_ENDPOINT, IMAGE_GEN_ENDPOINT, LANGFLOW_BASE_URL, SSO_KEYCLOAK_URL ve
# api_config LLM uç noktaları. Yapılandırılmış olmak tek başına on-prem kanıtı
# DEĞİLDİR (bkz. health_host_resolves_private).
health_configured_endpoint_values <- function() {
  env_adlari <- names(Sys.getenv())
  adlar <- unique(c(
    grep("^LOCAL_[A-Z0-9_]*ENDPOINT[A-Z0-9_]*$", env_adlari, value = TRUE),
    "IMAGE_GEN_ENDPOINT", "LANGFLOW_BASE_URL", "SSO_KEYCLOAK_URL"
  ))
  degerler <- unname(Sys.getenv(adlar, unset = ""))
  if (exists("api_config", inherits = TRUE)) {
    cfg <- get("api_config", inherits = TRUE)
    if (is.list(cfg)) {
      # Model eşlemesindeki doğrudan URL değerleri de çözücünün (resolve_local_llm_endpoint)
      # gerçekten kullandığı uç noktalardır.
      harita <- as.character(unlist(cfg$local_model_endpoint_map, use.names = FALSE))
      degerler <- c(degerler, unlist(
        list(cfg$local_llm_endpoint, cfg$local_llm$endpoint, cfg$local_llm_endpoints),
        use.names = FALSE
      ), harita[grepl("^https?://", harita, ignore.case = TRUE)])
    }
  }
  degerler <- as.character(degerler)
  degerler[!is.na(degerler) & nzchar(trimws(degerler))]
}

# Operatörün açıkça on-prem ilan ettiği hostlar (MERGEN_HEALTH_INTERNAL_ENDPOINTS);
# değer host ya da tam URL olabilir; ";", "," veya boşlukla ayrılır.
health_internal_hosts <- function() {
  ham <- Sys.getenv("MERGEN_HEALTH_INTERNAL_ENDPOINTS", "")
  parcalar <- if (nzchar(ham)) unlist(strsplit(.health_lower(ham), "[;,[:space:]]+")) else character(0)
  parcalar <- parcalar[nzchar(parcalar)]
  if (!length(parcalar)) return(character(0))
  hostlar <- health_url_host(parcalar)
  unique(hostlar[nzchar(hostlar)])
}

health_configured_hosts <- function() {
  degerler <- .health_lower(trimws(health_configured_endpoint_values()))
  if (!length(degerler)) return(character(0))
  hostlar <- health_url_host(degerler)
  unique(hostlar[nzchar(hostlar)])
}

# DNS işlemi ana olay döngüsünden ayrı ve süre sınırlı çalışır.
.HEALTH_DNS_JOBS <- new.env(parent = emptyenv())
health_resolve_host_ips <- function(host) {
  if (!requireNamespace("callr", quietly = TRUE) || !requireNamespace("later", quietly = TRUE)) {
    return(character(0))
  }
  is <- .HEALTH_DNS_JOBS[[host]]
  if (is.null(is)) {
    is <- tryCatch(callr::r_bg(function(host) {
      as.character(curl::nslookup(host, multiple = TRUE, error = FALSE))
    }, args = list(host = host), supervise = TRUE,
       user_profile = FALSE, system_profile = FALSE), error = function(e) NULL)
    if (is.null(is)) return(character(0))
    .HEALTH_DNS_JOBS[[host]] <- is
    later::later(function() {
      if (isTRUE(is$is_alive())) try(is$kill(), silent = TRUE)
    }, delay = 3)
  }
  if (isTRUE(is$is_alive())) return(structure(character(0), pending = TRUE))
  .HEALTH_DNS_JOBS[[host]] <- NULL
  tryCatch(is$get_result(), error = function(e) character(0))
}

# Kurumsal DNS adı taşıyan yapılandırılmış uç nokta (ör. https://tts.kurum.com.tr)
# literal RFC1918 adresi olmadığı için hiç denenmeden "genel internet" sayılıyordu.
# Host yalnız TÜM adresleri özel/loopback olarak çözülürse on-prem sayılır ve
# denetlenen adresler döner (istek bu adreslere sabitlenir; arada DNS yanıtı
# değişse de genel adrese gidilmez). Genel sonuç 10 dk, diğer sonuçlar
# bir yenileme aralığı tutulur. Süren çözümleme önbelleğe alınmaz.
.HEALTH_DNS_CACHE <- new.env(parent = emptyenv())

health_host_private_ips <- function(host, ttl = 600, kisa_ttl = 300) {
  simdi <- as.numeric(Sys.time())
  kayit <- .HEALTH_DNS_CACHE[[host]]
  if (is.list(kayit) && simdi - kayit$t < (if (isTRUE(kayit$genel)) ttl else kisa_ttl)) {
    return(kayit$sonuc)
  }
  ipler <- health_resolve_host_ips(host)
  if (isTRUE(attr(ipler, "pending"))) {
    if (is.list(kayit)) return(kayit$sonuc)
    return(structure(character(0), cozuldu = FALSE, pending = TRUE))
  }
  ozel <- length(ipler) > 0L && all(vapply(ipler, function(ip) {
    !isTRUE(health_host_unspecified(ip)) && isTRUE(health_ip_literal_internal(ip))
  }, logical(1)))
  # `cozuldu` özniteliği genel sonucu çözülemeyen addan ayırır.
  sonuc <- if (ozel) unique(ipler) else structure(character(0), cozuldu = length(ipler) > 0L)
  .HEALTH_DNS_CACHE[[host]] <- list(t = simdi, sonuc = sonuc, genel = length(ipler) > 0L && !ozel)
  sonuc
}

health_host_resolves_private <- function(host, ttl = 600) {
  length(health_host_private_ips(host, ttl)) > 0L
}

# Sayısal IPv4 host'u libcurl'ün (httr) çözdüğü gibi kanonik noktalı dörtlüye
# çevirir: noktasız ondalık (`134744072`), onaltılık (`0x8080808`), sekizlik
# (`010.010.010.010`) ve kısa (`127.1`) biçimler. Sayısal değilse NULL,
# sayısal ama geçersizse NA döner (çağıran kapalı-başarısız davranır).
health_ipv4_canonical <- function(host) {
  parcalar <- strsplit(tolower(as.character(host %||% "")), ".", fixed = TRUE)[[1]]
  if (!length(parcalar) || length(parcalar) > 4L ||
      !all(grepl("^(0x[0-9a-f]+|[0-9]+)$", parcalar, perl = TRUE))) {
    return(NULL)
  }
  deger <- vapply(parcalar, function(p) {
    taban <- if (startsWith(p, "0x")) 16 else if (nchar(p) > 1L && startsWith(p, "0")) 8 else 10
    rakam <- if (taban == 16) substring(p, 3L) else p
    d <- match(strsplit(rakam, "", fixed = TRUE)[[1]], c(0:9, letters[1:6])) - 1
    if (anyNA(d) || any(d >= taban)) return(NA_real_)
    sum(d * taban^(rev(seq_along(d)) - 1))
  }, numeric(1), USE.NAMES = FALSE)
  n <- length(deger)
  if (anyNA(deger) || any(deger > c(rep(255, n - 1L), 256^(5L - n) - 1))) return(NA_character_)
  toplam <- sum(deger[-n] * 256^(3:(5L - n))[seq_len(n - 1L)]) + deger[n]
  paste(c(toplam %/% 256^3, (toplam %/% 256^2) %% 256, (toplam %/% 256) %% 256, toplam %% 256),
        collapse = ".")
}

# Geçerli IPv6 literalinin sekiz hextet'i (en fazla bir "::"); geçersizse NULL.
.health_ipv6_hextets <- function(host) {
  if (grepl(":::", host, fixed = TRUE) || grepl("(^:[^:])|([^:]:$)", host, perl = TRUE)) return(NULL)
  konum <- gregexpr("::", host, fixed = TRUE)[[1]]
  konum <- konum[konum > 0L]
  if (length(konum) > 1L) return(NULL)
  bol <- function(x) if (nzchar(x)) strsplit(x, ":", fixed = TRUE)[[1]] else character(0)
  gruplar <- if (length(konum)) {
    sol <- bol(substr(host, 1L, konum - 1L))
    sag <- bol(substr(host, konum + 2L, nchar(host)))
    if (length(sol) + length(sag) > 7L) return(NULL)
    c(sol, rep("0", 8L - length(sol) - length(sag)), sag)
  } else {
    bol(host)
  }
  if (length(gruplar) != 8L || !all(grepl("^[0-9a-f]{1,4}$", gruplar))) return(NULL)
  gruplar
}

# Joker bağlama adresi: 0.0.0.0 (ve kısa/sayısal yazımları) ile IPv6 `::`
# (`0:0:0:0:0:0:0:0` gibi her GEÇERLİ yazımı; `0:::0` gibi bozuk literal değil).
health_host_unspecified <- function(host) {
  host <- tolower(as.character(host %||% ""))
  if (grepl(":", host, fixed = TRUE)) {
    gruplar <- .health_ipv6_hextets(host)
    return(!is.null(gruplar) && all(grepl("^0+$", gruplar)))
  }
  identical(health_ipv4_canonical(host), "0.0.0.0")
}

# Host'un DAHİLİ bir IP literali olup olmadığını söyler. NA => IP literali değil.
# Önek eşleşmesi tek başına yetmez: `10.example.com` geçerli bir genel DNS adıdır
# ve dört oktetli IPv4 doğrulaması yapılmadan "dahili" sayılıyordu.
health_ip_literal_internal <- function(host) {
  # Joker bağlama adresleri yerel dinleyicidir; `LOCAL_*_ENDPOINT` değeri
  # `http://0.0.0.0:...` / `http://[::]:...` iken kontrol hiç yapılmıyordu.
  if (isTRUE(health_host_unspecified(host))) return(TRUE)

  if (grepl(":", host, fixed = TRUE)) {
    # IPv4-EŞLEMELİ IPv6 (`::ffff:10.0.0.1` ve onaltılık `::ffff:7f00:1`) gömülü
    # IPv4 kuralıyla sınıflandırılır.
    esleme <- sub("^(0*:)*0*ffff:", "", tolower(host), perl = TRUE)
    if (!identical(esleme, tolower(host)) && grepl("^[0-9a-f]{1,4}:[0-9a-f]{1,4}$", esleme)) {
      h <- strtoi(strsplit(esleme, ":", fixed = TRUE)[[1]], 16L)
      esleme <- paste(c(h[1] %/% 256L, h[1] %% 256L, h[2] %/% 256L, h[2] %% 256L), collapse = ".")
    }
    if (!grepl(":", esleme, fixed = TRUE)) return(health_ip_literal_internal(esleme))
    # Loopback yalnız GEÇERLİ IPv6 literali `::1`e (her yazımıyla) eşitse kabul
    # edilir; yedi hextet'li `0:0:0:0:0:0:1` gibi bozuk literal dahili sayılmaz.
    gruplar <- .health_ipv6_hextets(tolower(host))
    if (!is.null(gruplar) && all(grepl("^0+$", gruplar[1:7])) && grepl("^0*1$", gruplar[8])) {
      return(TRUE)
    }
    # fc00::/7 benzersiz yerel adres aralığı ve bağlantı-yerel fe80::/10;
    # yalnız GEÇERLİ literalin ilk hextet'i sınanır (`fd00:zzzz::1` dahili değil).
    # Bölge kimliği (`%eth0`) yalnız bağlantı-yerel adreste kabul edilir.
    bolge <- grepl("%", host, fixed = TRUE)
    yalin <- .health_ipv6_hextets(sub("%[^%]+$", "", tolower(host)))
    if (!is.null(yalin)) {
      ilk <- strtoi(yalin[1], 16L)
      if (bitwAnd(ilk, 0xFFC0L) == 0xFE80L) return(TRUE)
      if (!bolge && bitwAnd(ilk, 0xFE00L) == 0xFC00L) return(TRUE)
    }
    return(NA)
  }
  # Sayısal host libcurl gibi çözülür; `010.010.010.010` 10.10.10.10 değil
  # 8.8.8.8'dir. Geçersiz sayısal host genel sayılır (kapalı-başarısız).
  kanonik <- health_ipv4_canonical(host)
  if (is.null(kanonik)) return(NA)
  if (is.na(kanonik)) return(FALSE)
  oktet <- as.integer(strsplit(kanonik, ".", fixed = TRUE)[[1]])
  # 10/8, 172.16/12, 192.168/16, 127/8 (loopback), 169.254/16 (bağlantı-yerel).
  oktet[1] == 10L ||
    oktet[1] == 127L ||
    (oktet[1] == 172L && oktet[2] >= 16L && oktet[2] <= 31L) ||
    (oktet[1] == 192L && oktet[2] == 168L) ||
    (oktet[1] == 169L && oktet[2] == 254L)
}

# Joker bağlama adresi (0.0.0.0 / [::], her yazımıyla) istemci hedefi değildir
# (Windows'ta bağlantı kurulamaz); deneme aynı porttaki yerel döngü adresine yapılır.
health_probe_url <- function(url) {
  url <- as.character(url %||% "")
  m <- regmatches(url, regexec("^(https?://(?:[^/?#@]*@)?)(\\[[^]/?#]*\\]|[^:/?#]*)(.*)$",
                               url, perl = TRUE, ignore.case = TRUE))[[1]]
  if (length(m) != 4L) return(url)
  # Sınıflandırmadaki gibi yüzde kodu çözülür (`%30.0.0.0` libcurl için 0.0.0.0'dır).
  host <- sub("^\\[(.*)\\]$", "\\1", m[3])
  host <- tryCatch(utils::URLdecode(host), error = function(e) host)
  if (!health_host_unspecified(host)) return(url)
  paste0(m[2], if (startsWith(m[3], "[")) "[::1]" else "127.0.0.1", m[4])
}

# Uç nokta kapsam kararı. `public` TRUE ise istek gönderilmez; `neden`
# ("sema", "genel_ip", "genel_dns", "cozulmedi") atlama açıklamasını belirler.
# DNS adı yalnız operatör ilanıyla (MERGEN_HEALTH_INTERNAL_ENDPOINTS) ya da tüm
# adresleri özel ağa çözülünce denenir: noktasız adlar ve `.local/.corp` gibi
# son ekler adlandırma alışkanlığıdır, adres kapsamı kanıtı değildir. Genel
# görünümlü adlar ayrıca yapılandırılmış olmalıdır. `pin` isteği denetlenen
# adreslere sabitleyen curl `resolve` girdileridir.
# DNS adıyla sabitlenen istekte `hedef`, URL'deki host'un denetlenen kanonik
# adla değiştirilmiş hâlidir (sondaki kök noktası, yüzde kodu, IDNA noktası
# temizlenir); curl `resolve` anahtarı istek host'uyla birebir eşleşir, yeni
# DNS sorgusu yapılıp sabitleme atlanmaz.
health_endpoint_scope <- function(url) {
  ham <- as.character(url %||% "")[1]
  url <- .health_lower(ham)
  sonuc <- function(public, neden = "", ipler = character(0)) {
    pin <- health_pin_entries(url, host, ipler)
    hedef <- if (length(pin)) {
      sub("^(https?://(?:[^/?#@]*@)?)(\\[[^]/?#]*\\]|[^:/?#]*)", paste0("\\1", host), ham,
          perl = TRUE, ignore.case = TRUE)
    }
    list(public = public, neden = if (public) neden else "", pin = pin, hedef = hedef)
  }
  host <- ""
  # Yalnız HTTP(S) denenir; başka şema (ftp vb.) kapsam denetimini atlatamaz.
  if (!grepl("^https?://", url)) return(sonuc(TRUE, "sema"))
  if (grepl("^http:[/]{2}[^/?#]*@", url)) return(sonuc(TRUE, "kimlik_bilgisi"))
  host <- health_url_host(url)
  if (identical(host, "localhost")) return(sonuc(FALSE))
  ilan <- host %in% health_internal_hosts()
  ip_dahili <- health_ip_literal_internal(host)
  if (!is.na(ip_dahili)) return(sonuc(!isTRUE(ip_dahili) && !ilan, "genel_ip"))
  # IPv6 adresi tek etiket gibi görünür; ad çözümlemesi uygulanamaz.
  if (grepl(":", host, fixed = TRUE)) return(sonuc(!ilan, "genel_ip"))
  if (ilan) return(sonuc(FALSE))
  intranet_adi <- !grepl(".", host, fixed = TRUE) ||
    grepl("\\.(local|internal|intranet|lan|corp)$", host, perl = TRUE)
  if (!intranet_adi && !(host %in% health_configured_hosts())) return(sonuc(TRUE, "genel_dns"))
  ipler <- health_host_private_ips(host)
  if (length(ipler)) return(sonuc(FALSE, ipler = ipler))
  sonuc(TRUE, if (isTRUE(attr(ipler, "pending"))) "bekliyor" else
    if (isFALSE(attr(ipler, "cozuldu"))) "cozulmedi" else "genel_dns")
}

# curl `resolve` girdisi ("host:port:adres1,adres2"); IPv6 adres köşeli
# parantezlidir. Aynı host:port için ikinci girdi öncekini ezdiğinden tüm
# denetlenen adresler TEK girdide verilir (libcurl >= 7.59); curl bunlar
# arasında yedekli bağlanır.
health_pin_entries <- function(url, host, ipler) {
  if (!length(ipler) || !nzchar(host)) return(character(0))
  port <- regmatches(url, regexec("^https?://(?:[^/?#@]*@)?(?:\\[[^]]*\\]|[^:/?#]*):([0-9]+)", url, perl = TRUE))[[1]]
  port <- if (length(port) == 2L) port[2] else if (startsWith(url, "https")) "443" else "80"
  adres <- ifelse(grepl(":", ipler, fixed = TRUE), paste0("[", ipler, "]"), ipler)
  paste0(host, ":", port, ":", paste(adres, collapse = ","))
}

health_is_public_url <- function(url) {
  isTRUE(health_endpoint_scope(url)$public)
}
