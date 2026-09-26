# ==============================================================================
# Dosya Yolu: R/helpers_health_endpoint_scope.R
# Açıklama: Sağlık uç nokta denetimleri için host çıkarımı ve on-prem/genel
#           internet sınıflandırması (R/helpers_health_checks.R kullanır).
# ==============================================================================

# Host çıkarımı köşeli parantezli IPv6 adresini korur: ":" üzerinden kesmek
# `http://[fd00::1]:8080` adresini `[fd00` yapıp yanlış sınıflandırıyordu.
health_url_host <- function(value) {
  host <- sub("^https?://", "", tolower(as.character(value %||% "")))
  # Yol/sorgu/fragment ATILIR; aksi hâlde yoldaki "@" userinfo sanılır.
  host <- sub("[/?#].*$", "", host)
  # `https://user:pass@public.example.com` için host "user" dönüyor ve
  # noktasız-host kuralı uç noktayı DAHİLİ sayıp genel isteği gönderiyordu.
  host <- sub("^.*@", "", host)
  # Yüzde kodlu host (`public%2eexample%2ecom`) HTTP istemcisince çözülür;
  # noktasız görünüp intranet sayılmasın diye sınıflandırmadan önce çözülür.
  host <- tolower(vapply(host, function(h) tryCatch(utils::URLdecode(h), error = function(e) h),
                         character(1), USE.NAMES = FALSE))
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
  parcalar <- if (nzchar(ham)) unlist(strsplit(tolower(ham), "[;,[:space:]]+")) else character(0)
  parcalar <- parcalar[nzchar(parcalar)]
  if (!length(parcalar)) return(character(0))
  hostlar <- health_url_host(parcalar)
  unique(hostlar[nzchar(hostlar)])
}

health_configured_hosts <- function() {
  degerler <- tolower(trimws(health_configured_endpoint_values()))
  if (!length(degerler)) return(character(0))
  hostlar <- health_url_host(degerler)
  unique(hostlar[nzchar(hostlar)])
}

health_resolve_host_ips <- function(host) {
  if (!requireNamespace("curl", quietly = TRUE)) return(character(0))
  tryCatch(as.character(curl::nslookup(host, multiple = TRUE, error = FALSE) %||% character(0)),
           error = function(e) character(0))
}

# Kurumsal DNS adı taşıyan yapılandırılmış uç nokta (ör. https://tts.kurum.com.tr)
# literal RFC1918 adresi olmadığı için hiç denenmeden "genel internet" sayılıyordu.
# Host yalnız TÜM adresleri özel/loopback olarak çözülürse on-prem sayılır ve
# denetlenen adresler döner (istek bu adreslere sabitlenir; arada DNS yanıtı
# değişse de genel adrese gidilmez). Özel karar önbelleklenmez; her denemede
# yeniden çözülür. Yalnız GERÇEKTEN çözülüp genel çıkan sonuç 10 dk tutulur;
# geçici DNS hatası önbelleğe girmez.
.HEALTH_DNS_CACHE <- new.env(parent = emptyenv())

health_host_private_ips <- function(host, ttl = 600) {
  simdi <- as.numeric(Sys.time())
  kayit <- .HEALTH_DNS_CACHE[[host]]
  # `cozuldu` özniteliği genel sonucu çözülemeyen addan ayırır.
  genel <- structure(character(0), cozuldu = TRUE)
  if (is.list(kayit) && simdi - kayit$t < ttl) return(genel)
  ipler <- health_resolve_host_ips(host)
  if (!length(ipler)) return(structure(character(0), cozuldu = FALSE))
  ozel <- all(vapply(ipler, function(ip) {
    !isTRUE(health_host_unspecified(ip)) && isTRUE(health_ip_literal_internal(ip))
  }, logical(1)))
  if (!ozel) {
    .HEALTH_DNS_CACHE[[host]] <- list(t = simdi)
    return(genel)
  }
  unique(ipler)
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
    # `0:0:0:0:0:0:0:1` gibi genişletilmiş loopback biçimleri de normalize edilir.
    parcalar <- strsplit(host, ":", fixed = TRUE)[[1]]
    parcalar <- parcalar[nzchar(parcalar)]
    # Boş hextet'ler ayıklandığı için `1::` ve `0:1::` de "son hextet 1" gibi
    # görünüyor ve GENEL adresler dahili sınıflanıyordu; kıyas ORİJİNAL host
    # üzerinde yapılır.
    if (length(parcalar) &&
        grepl("(^|:)0*1$", host, perl = TRUE) &&
        all(grepl("^0*1?$", parcalar)) &&
        sum(parcalar != "" & sub("^0+", "", parcalar) == "1") == 1L &&
        identical(sub("^0+", "", parcalar[length(parcalar)]), "1")) {
      return(TRUE)
    }
    # fc00::/7 benzersiz yerel adres aralığı ve bağlantı-yerel fe80::/10.
    if (grepl("^(f[cd][0-9a-f]{2}:|fe[89ab][0-9a-f]:)", host, perl = TRUE)) return(TRUE)
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
health_endpoint_scope <- function(url) {
  url <- tolower(as.character(url %||% ""))
  sonuc <- function(public, neden = "", ipler = character(0)) {
    list(public = public, neden = if (public) neden else "", pin = health_pin_entries(url, host, ipler))
  }
  host <- ""
  # Yalnız HTTP(S) denenir; başka şema (ftp vb.) kapsam denetimini atlatamaz.
  if (!grepl("^https?://", url)) return(sonuc(TRUE, "sema"))
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
  sonuc(TRUE, if (isFALSE(attr(ipler, "cozuldu"))) "cozulmedi" else "genel_dns")
}

# curl `resolve` girdileri ("host:port:adres"); IPv6 adres köşeli parantezlidir.
health_pin_entries <- function(url, host, ipler) {
  if (!length(ipler) || !nzchar(host)) return(character(0))
  port <- regmatches(url, regexec("^https?://(?:[^/?#@]*@)?(?:\\[[^]]*\\]|[^:/?#]*):([0-9]+)", url, perl = TRUE))[[1]]
  port <- if (length(port) == 2L) port[2] else if (startsWith(url, "https")) "443" else "80"
  adres <- ifelse(grepl(":", ipler, fixed = TRUE), paste0("[", ipler, "]"), ipler)
  paste0(host, ":", port, ":", adres)
}

health_is_public_url <- function(url) {
  isTRUE(health_endpoint_scope(url)$public)
}
