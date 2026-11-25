# ==============================================================================
# Dosya Yolu: R/utils_log_redact.R
# Açıklama: Log ve hata metinlerinde kazara sızabilecek hassas içeriği (JWT,
# Bearer token, API anahtarı env değerleri, query string parolaları) maskeler.
# Kurumsal Windows VM'de log dosyaları merkezi toplama araçları tarafından
# okunur; gizli verinin "tesadüfen" loglanması kalıcı sızıntı oluşturabilir.
# Bu modül yan etkisiz bir fonksiyon ihraç eder; çağıran taraf kendi log
# fonksiyonunu sarmalayabilir veya metni göndermeden önce redakte edebilir.
# ==============================================================================

# Kontrollü bir liste: hassas değerleri ortam değişkeninden alır ve log içinde
# ham değer geçiyorsa maskeler. Liste üretim ortamına göre genişletilebilir.
.redact_env_var_names <- function() {
  c(
    "AI_KEYS_MASTER",
    # Kurumsal varsayılan API anahtarı. CLAUDE.md gereği asla loglanmamalıdır;
    # prose içinde çıplak geçtiğinde key-value deseni yakalamaz, bu yüzden
    # env-değer redaksiyonuna açıkça eklenir.
    "MERGEN_DEFAULT_API_KEY",
    "LOCAL_LLM_API_KEY",
    # Kaldırılan ikinci LLM uç anahtarı çalışma zamanında kullanılmasa da,
    # sürümden yükseltilmiş VM'lerin .Renviron dosyasında hâlâ bulunabilir.
    # Langflow/LLM hataları gösterilmeden/loglanmadan önce redact_sensitive_text()
    # bu adı görürse çıplak değeri maskeler (key-value desenine uymasa bile).
    "LOCAL_LLM_ENDPOINT_ALT_API_KEY",
    # Kurumsal Langflow akış API anahtarı. Langflow HTTP hata gövdeleri
    # sohbet/toast'a önizlenebildiğinden, anahtarın prose içinde çıplak geçmesi
    # durumunda da maskelenmesi için açıkça eklenir.
    "LANGFLOW_API_KEY",
    "LOCAL_TTS_API_KEY",
    "LOCAL_STT_API_KEY",
    "SERVICE_DESK_API_KEY_URL",
    "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_API_KEY",
    "CLAUDE_API_KEY",
    "OPENAI_API_KEY",

    # DB / ODBC secrets. The current app primarily uses DSN names, but VM
    # profiles may still define password-like env vars for drivers/scripts.
    "DB_PASSWORD",
    "DB_PASS",
    "DB_PWD",
    "ODBC_PASSWORD",
    "ODBC_PWD",
    "SQL_PASSWORD",
    "SQLSERVER_PASSWORD",
    "MSSQL_PASSWORD",

    # SSO / OIDC / Keycloak secrets. The current implicit-flow config does not
    # require one, but this keeps logs safe if a secret is later introduced.
    "SSO_CLIENT_SECRET",
    "SSO_KEYCLOAK_CLIENT_SECRET",
    "KEYCLOAK_CLIENT_SECRET",
    "OIDC_CLIENT_SECRET",
    "SSO_SECRET"
  )
}

# Belirtilen env değerini metin içinde arayıp, bulursa yer değiştirir.
# Çok kısa değerler (örn. boş string) atlanır; aksi halde yanlış pozitif olur.
.redact_literal_values <- function(text) {
  for (var_name in .redact_env_var_names()) {
    var_value <- Sys.getenv(var_name, unset = "")
    if (!nzchar(var_value) || nchar(var_value) < 8L) next
    text <- gsub(var_value, sprintf("<%s:redacted>", var_name), text, fixed = TRUE)
  }
  text
}

# Ana redaksiyon fonksiyonu. Girişteki her bir karakter elemanı üzerinde
# sırasıyla aşağıdaki desenleri maskeler. Regex'ler olabildiğince dar
# tutulmuştur; amaç gerçek gizli değeri yakalamak, normal metni değiştirmemektir.
redact_sensitive_text <- function(x) {
  if (is.null(x)) return(x)
  if (!is.character(x)) {
    x <- tryCatch(as.character(x), error = function(e) "")
  }
  if (!length(x)) return(character(0))

  vapply(x, function(elem) {
    if (is.na(elem) || !nzchar(elem)) return(elem)

    metin <- elem

    # 0) PEM özel anahtar blokları: -----BEGIN ... PRIVATE KEY----- ... END.
    # TLS/NODE_EXTRA_CA_CERTS/SSO bağlamında bir hata veya yapılandırma dökümü
    # özel anahtar gövdesini loglara taşıyabilir. (?s) çok satırlı eşleşme sağlar.
    metin <- gsub(
      "(?s)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
      "<private-key-redacted>",
      metin,
      perl = TRUE
    )

    # 1) JWT formatı: header.payload.signature (URL-safe base64 parçaları).
    # Üretimde decode edilmiş token'ların log'a girmesi en yaygın risktir.
    metin <- gsub(
      "eyJ[A-Za-z0-9_\\-]{5,}\\.[A-Za-z0-9_\\-]{5,}\\.[A-Za-z0-9_\\-]{5,}",
      "<jwt-redacted>",
      metin,
      perl = TRUE
    )

    # 2) Authorization header tipi: "Bearer xyz" veya "Basic xyz".
    metin <- gsub(
      "(?i)\\b(Bearer|Basic)\\s+[A-Za-z0-9._\\-=/+]{6,}",
      "\\1 <redacted>",
      metin,
      perl = TRUE
    )

    # 3) URL query string parametreleri: ?token=, &password=, &api_key=, &secret=
    metin <- gsub(
      "(?i)([?&](?:token|password|passwd|pwd|api[_-]?key|apikey|secret|access[_-]?token)=)[^&#\\s]+",
      "\\1<redacted>",
      metin,
      perl = TRUE
    )

    # 3B) Header / key-value biçimindeki sırları maskele:
    # api_key = ..., x-api-key: ..., password: ..., client_secret=...
    # ODBC/SQL Server bağlantı dizeleri "Pwd=..." kullandığı için "pwd" de eklenir;
    # aksi halde loglanan bir DSN-less bağlantı dizesi parolayı sızdırabilir.
    secret_key_pattern <- paste(
      c(
        "api[_-]?key",
        "apikey",
        "x-api-key",
        "token",
        "access[_-]?token",
        "refresh[_-]?token",
        "secret",
        "client[_-]?secret",
        "password",
        "passwd",
        "pwd"
      ),
      collapse = "|"
    )

    metin <- gsub(
      paste0("(?i)\\b(", secret_key_pattern, ")(\\s*[:=]\\s*)\"[^\"]{6,}\""),
      "\\1\\2\"<redacted>\"",
      metin,
      perl = TRUE
    )

    metin <- gsub(
      paste0("(?i)\\b(", secret_key_pattern, ")(\\s*[:=]\\s*)'[^']{6,}'"),
      "\\1\\2'<redacted>'",
      metin,
      perl = TRUE
    )

    # ODBC KÜMELİ PAROLA DEĞERİ (`Pwd={...}`) DE MASKELENİR.
    #
    # Aşağıdaki çıplak-değer sınıfı `{` ve `}` karakterlerini DIŞLAR; bu yüzden
    # `Pwd={A}}B}` biçiminde bir değer sıfır karakter eşleştiriyor ve parola
    # OLDUĞU GİBİ loga gidiyordu. ODBC kümeli değerde `}` karakteri `}}` ile
    # kaçırılır, yani değer İKİLENMEMİŞ ilk `}` ile biter. ATOMİK grup (`(?>)`)
    # ZORUNLUDUR: geri izlemeye izin verilirse `Pwd={A}}B;...` gibi KAPANMAMIŞ
    # bir değerde motor `}}` çiftini bölerek `{A}` eşleşmesi uydurur ve parola
    # kuyruğu (`}}B`) maskesiz kalırdı.
    metin <- gsub(
      # DEĞER SINIFI SATIR SONUNU KAPSAMAZ (PR #705 inceleme, P3): kümeli bir ODBC
      # değeri satır sonu TAŞIMAZ. Sınıf `\r\n` eşlediğinde KAPANMAMIŞ bir küme,
      # SONRAKİ satırdaki kapanış parantezine kadar her şeyi yutuyor ve kalıcı
      # sunucu logundan sürücü/bağlantı tanı bağlamı SİLİNİYORDU (kapanmamış
      # geçiş için aynı koruma aşağıda zaten var).
      paste0("(?i)\\b(", secret_key_pattern, ")(\\s*[:=]\\s*)\\{(?>(?:[^}\\r\\n]|\\}\\})*)\\}"),
      "\\1\\2{<redacted>}",
      metin,
      perl = TRUE
    )

    # KAPANMAMIŞ küme: bozuk bir bağlantı dizesi de sızdırmamalıdır. Değer bir
    # sonraki ayırıcıya (`;`) ya da metin sonuna kadar maskelenir.
    metin <- gsub(
      # DEĞER SINIFI SATIR SONUNU KAPSAMAZ: `[^;]*` `\r`/`\n` de eşlediği için
      # çok satırlı bir sürücü tanılamasında kapanmamış küme, SONRAKİ TÜM
      # satırları yutuyor ve arıza analizi için gereken bağlam siliniyordu.
      paste0("(?i)\\b(", secret_key_pattern, ")(\\s*[:=]\\s*)\\{(?!<redacted>)[^;\\r\\n]*"),
      "\\1\\2{<redacted>",
      metin,
      perl = TRUE
    )

    metin <- gsub(
      paste0("(?i)\\b(", secret_key_pattern, ")(\\s*[:=]\\s*)[^\\s,;}{\"'&#<>]{6,}"),
      "\\1\\2<redacted>",
      metin,
      perl = TRUE
    )

    # 4) Bilinen env değişkeni değerleri.
    metin <- .redact_literal_values(metin)

    metin
  }, character(1), USE.NAMES = FALSE)
}

# Runtime hatalarını yapılandırılmış, sır-redakteli ve yan etkisiz bir kayda
# çevirir. Çağıran taraf bu kaydı tek satır halinde loglayabilir veya bir olay
# izleme akışına gönderebilir. Bilinçli olarak Shiny/DB/dosya/HTTP içermez;
# böylece izole test edilebilir ve hata yolunda kendisi yeni hata üretmez.
mergen_build_runtime_error_record <- function(error,
                                              context = "unknown",
                                              redact_fn = NULL,
                                              now = Sys.time()) {
  # Redaksiyon fonksiyonu verilmediyse aynı modüldeki güvenli redaktörü kullan.
  if (is.null(redact_fn) && exists("redact_sensitive_text", mode = "function")) {
    redact_fn <- get("redact_sensitive_text", mode = "function")
  }

  # Hata mesajını koşula göre güvenli biçimde çöz.
  error_msg <- tryCatch({
    if (inherits(error, "condition")) {
      conditionMessage(error)
    } else if (is.null(error)) {
      ""
    } else {
      paste(as.character(error), collapse = " ")
    }
  }, error = function(e) "")

  # Hata sınıfı (R sınıf adları) tanılama için saklanır; sır taşımaz.
  error_class <- tryCatch({
    cls <- class(error)
    if (length(cls)) paste(cls, collapse = ",") else "unknown"
  }, error = function(e) "unknown")

  # Hem bağlam hem mesaj redakte edilir; hata metni token/DSN/parola taşıyabilir.
  redact_one <- function(value) {
    value <- as.character(value)[1]
    if (is.na(value)) value <- ""
    if (is.function(redact_fn)) {
      value <- tryCatch(as.character(redact_fn(value))[1], error = function(e) value)
      if (is.na(value)) value <- ""
    }
    enc2utf8(value)
  }

  captured_at <- tryCatch(
    format(now, "%Y-%m-%dT%H:%M:%S%z"),
    error = function(e) ""
  )
  if (length(captured_at) != 1L || is.na(captured_at)) {
    captured_at <- ""
  }

  list(
    type = "runtime_error",
    context = redact_one(context),
    message = redact_one(error_msg),
    error_class = enc2utf8(error_class),
    captured_at = captured_at
  )
}
# ==============================================================================
# ODBC/SQL Server BAĞLANTI TANIMLAYICILARI (AYRI, OPT-IN katman)
#
# `redact_sensitive_text()` KİMLİK BİLGİSİ alanlarını maskeler; `Uid`/`Server`
# gibi alanları BİLEREK KORUR (bkz. test-log-redact-connection-string-behavior.R:
# "kullanıcı adı sır değildir"). Bu genel sözleşme DEĞİŞMEZ.
#
# Ancak PK/asenkron çalışma zamanı, sürücü istisnalarını KALICI sunucu log'una
# yazar ve sıradan bir ODBC hatası `DSN=PrivateProd`, `UID=alice`,
# `Server=corp-internal\SQL01` taşır. Depo sözleşmesi özel DSN'lerin
# log'lanmasını AÇIKÇA yasaklar; bu alanlar tek başına gizli değer olmasa da
# iç altyapıyı yeniden kurmaya yeter. Bu yüzden AYRI ve AÇIKÇA çağrılan bir
# katman uygulanır; genel redaktörün davranışına dokunulmaz.
#
# Değer maskelenir, ALAN ADI korunur: tanı için "hangi alan" bilgisi yeterlidir.
# ==============================================================================

.REDACT_CONN_KEYS <- paste(
  c("dsn", "uid", "user[_ ]?id", "server", "address", "addr", "network",
    "data[ _]?source", "database", "initial[ _]?catalog", "host",
    "hostname", "port", "driver", "app", "application[ _]?name",
    "workstation[ _]?id", "trusted[_ ]?connection",
    # SIR ALANLARI: genel redaktör `Password=abc` gibi TIRNAKSIZ değerleri
    # maskeler ama SÜSLÜ (`Pwd={...}`) biçimi yakalamaz; ODBC sürücü hataları
    # ise tam bağlantı dizesini bu biçimde yazar. Anahtarlar burada da yer
    # alınca aşağıdaki süslü-parantez kuralı şifreyi de maskeler.
    "password", "passwd", "pwd"),
  collapse = "|"
)

#' Bağlantı tanımlayıcılarını da maskele (log sınırı için)
#'
#' Önce tırnaklı değerler, sonra genel `redact_sensitive_text()`, ardından
#' bağlantı tanımlayıcı DEĞERLERİ maskelenir. Yalnızca LOG yolunda çağrılır; kullanıcıya
#' dönen metinler için `pk_safe_error_message()` zaten genel mesaja düşer.
redact_connection_identifiers <- function(x) {
  # TIRNAKLI DEĞERLER GENEL REDAKTÖRDEN ÖNCE işlenir: genel redaktör kaçışlı
  # tırnağı (`\"`) kapanış sayıp `"<redacted>"kuyruk"` üretiyor, kuyruk da
  # sonraki geçişlerde maskelenmeden kalıyordu.
  on_isle <- tryCatch(.redact_quoted_log_values(x), error = function(e) NULL)
  if (is.null(on_isle) && !is.null(x)) return("<redaksiyon uygulanamadi>")
  # Bağımsız Bearer kimlik bilgisi RFC 6750 b64token karakterlerinin TAMAMIYLA
  # (`~` dahil) genel redaktörden önce maskelenir; kuyruk açıkta kalmaz.
  if (is.character(on_isle)) {
    # Şemadan sonra yalnızca YATAY boşluk: boş kimlik bilgisinde sonraki satır yutulmaz.
    on_isle <- gsub("(?i)(?<![A-Za-z0-9_])(Bearer[ \\t]+)[A-Za-z0-9._~+/-]+=*", "\\1<redacted>", on_isle, perl = TRUE)
  }
  metin <- tryCatch(redact_sensitive_text(on_isle), error = function(e) NULL)
  if (is.null(metin)) return("<redaksiyon uygulanamadi>")
  if (!is.character(metin) || length(metin) == 0L) return(metin)

  # ÇOK ÖGELİ GİRDİDE MASKELEME ÖGE BAŞINA UYGULANIR. `redact_sensitive_text()`
  # vektöreldir ve uzunluğu korur; uzunluk 1 değilse ERKEN dönmek `DSN=`,
  # `UID=` ve `Server=` değerlerini OLDUĞU GİBİ bırakıyordu (ör. bir sürücü
  # tanılamasının `capture.output()` çıktısı). Genel redaktör çalıştığı için
  # kayıp SESSİZDİ: yalnızca bağlantı katmanı düşüyordu.
  if (length(metin) > 1L) {
    return(vapply(metin, redact_connection_identifiers, character(1), USE.NAMES = FALSE))
  }
  if (is.na(metin)) return(metin)

  # SÜSLÜ PARANTEZLİ DEĞER: KAÇIŞLI VE KAPANMAMIŞ BİÇİMLER DE MASKELENİR.
  #
  # ODBC bağlantı dizesinde `}` karakteri `}}` ile kaçırılır. Eski `\{[^}]*\}`
  # deseni `Pwd={A}}B}` girdisinde ERKEN durup yalnızca `{A}` kısmını maskeliyor,
  # `}B}` kuyruğu logda GÖRÜNÜR kalıyordu. Kapanış parantezi hiç yoksa desen
  # eşleşmiyor, ikinci geçişteki `(?!\{)` de devreye girmediği için değerin
  # TAMAMI görünür kalıyordu. Önce kaçışlı biçim, sonra kapanmamış biçim.
  # ATOMİK GRUP ZORUNLUDUR (`redact_sensitive_text()` ile AYNI kurgu).
  #
  # Geri izlemeye izin verilirse motor `Driver={ODBC Driver 17}}x` girdisinde
  # yalnızca `{ODBC Driver 17}` kısmını eşler; çıktı `Driver={<redacted>}x`
  # olur ve `x` kuyruğu KALICI logda MASKESİZ kalır. İkinci geçiş de
  # yakalayamaz (değer artık kapanmamış değildir), üçüncü geçiş ise `(?!\{)`
  # yüzünden atlar. `(?>...)` geri izlemeyi kapatarak `}}` çiftinin
  # bölünmesini engeller.
  metin <- gsub(
    # DEĞER SINIFI SATIR SONUNU KAPSAMAZ (PR #705 inceleme, P3): yukarıdaki
    # `redact_sensitive_text()` geçişiyle AYNI gerekçe -- kapanmamış bir küme
    # sonraki satırların kapanışına kadar her şeyi yutup tanı bağlamını siliyordu.
    # Sır anahtarları (`auth_token={...}`, `authToken={...}`) da kapsanır.
    paste0("(?i)(^|[;{(\\[,\\s])(", .REDACT_CONN_KEYS, "|", .REDACT_LOG_SECRET_KEYS,
           ")(\\s*=\\s*)\\{(?>(?:[^}\\r\\n]|\\}\\})*)\\}"),
    "\\1\\2\\3{<redacted>}",
    metin,
    perl = TRUE
  )

  # Kapanmamış süslü parantez: satır sonuna kadar maskelenir.
  #
  # `(?m)` ZORUNLUDUR: karakter sınıfı satır sonlarını dışladığı için `$`
  # çok satırlı bir mesajda YALNIZCA dizenin sonunda eşleşiyordu; ODBC sürücü
  # tanıları çoğunlukla TEK çok satırlı dizedir ve ortadaki `Pwd={gizli`
  # hiç maskelenmiyordu. Üçüncü geçiş de `(?!\{)` yüzünden değeri atlıyordu.
  #
  # KAÇIŞLI `}}` DA KAPANMAMIŞ DEĞERİN İÇİNDE OLABİLİR. `Pwd={A}}B` biçimi
  # birinci desende eşleşmez (son kapanış `}` yoktur), eski ikinci desen ise
  # `[^{}]` yüzünden ilk `}` karakterinde durup HİÇ eşleşmiyordu: kesilmiş bir
  # ODBC tanısında parola kuyruğu kalıcı loga yazılırdı.
  metin <- gsub(
    paste0("(?im)(^|[;{(\\[,\\s])(", .REDACT_CONN_KEYS, "|", .REDACT_LOG_SECRET_KEYS,
           ")(\\s*=\\s*)\\{(?:[^}\r\n]|\\}\\})*(?=\r|\n|\\z)"),
    "\\1\\2\\3{<redacted>}",
    metin,
    perl = TRUE
  )

  # Kapanmış süslü değerin hemen ardından ayırıcısız kuyruk gelirse (geçersiz
  # `DSN={Ozel{Ad}Kuyruk}` gibi) kuyruk da maskelenir: değerin parçası açıkta kalmaz.
  metin <- gsub("\\{<redacted>\\}[^;,\\s)\\]]+", "{<redacted>}", metin, perl = TRUE)

  # Noktalı virgülle ayrılan boşluklu ODBC tanımlayıcıları (ör. DSN=Ozel Rapor;UID=x)
  # alan ayırıcısına kadar eksiksiz maskelenir.
  metin <- gsub(
    paste0("(?i)(^|[;{(\\[,\\s])(", .REDACT_CONN_KEYS,
           ")(\\s*=\\s*)(?!<redacted>)(?!\\{)[^;,}\\])\\r\\n\"'<>]+(?=;)"),
    "\\1\\2\\3<redacted>",
    metin,
    perl = TRUE
  )
  # Noktalı virgüllü ODBC dizesinin son alanındaki boşluklu tanımlayıcı
  # (sonunda `;` olmasa da) satır sonuna ya da yapısal ayırıcıya kadar
  # maskelenir. Değer içinde ` - ` ya da `: ` olabilir (ör. `DSN=Ozel - Bordro`);
  # alan sınırı bilinmediğinden tanı düzyazısı uğruna değer açıkta bırakılmaz.
  metin <- gsub(
    paste0("(?im)(;\\s*)(", .REDACT_CONN_KEYS,
           ")(\\s*=\\s*)(?!<redacted>)(?!\\{)[^;,}\\])\\r\\n\"'<>]+"),
    "\\1\\2\\3<redacted>",
    metin,
    perl = TRUE
  )
  # Tek alanlı (noktalı virgülsüz) bağlantı tanımlayıcısı da bütün olarak
  # maskelenir: DSN/sunucu/veritabanı adı boşluk içerebilir ve kısmi ad loga
  # yazılmaz (`Database=Ozel Rapor` -> `Database=<redacted>`).
  metin <- gsub(
    paste0("(?im)(^|[;{(\\[,\\s])(", .REDACT_CONN_KEYS,
           ")(\\s*=\\s*)(?!\\{)[^;,}\\])\\r\\n\"'<>]*[^;,}\\])\\r\\n\"'<>\\s]"),
    "\\1\\2\\3<redacted>",
    metin,
    perl = TRUE
  )
  # Zaten maskelenmiş ya da süslü parantezli değerler İKİNCİ KEZ işlenmez.
  metin <- gsub(
    paste0("(?i)(^|[;{(\\[,\\s])(", .REDACT_CONN_KEYS,
           ")(\\s*=\\s*)(?!<redacted>)(?!\\{)[^;,}\\])\\s\"']+"),
    "\\1\\2\\3<redacted>",
    metin,
    perl = TRUE
  )
  # JSON-tırnaklı bağlantı anahtarının çıplak değeri (`{"uid":12345}`) de
  # maskelenir. İki nokta yalnızca anahtar TIRNAKLIYKEN kabul edilir; düzyazıdaki
  # `Database: bağlantı başarısız` tanı bağlamı korunur.
  metin <- gsub(
    paste0("(?i)(^|[;{(\\[,\\s])([\"'])(", .REDACT_CONN_KEYS,
           ")\\2(\\s*[:=]\\s*)(?!<redacted>)(?![{\"'])[^;,}\\])\\s\"']+"),
    "\\1\\2\\3\\2\\4<redacted>",
    metin,
    perl = TRUE
  )
  # Authorization başlığı (ön geçişin yakalamadığı biçimler için yedek): şema
  # korunur, kimlik bilgisi satır sonuna kadar maskelenir.
  metin <- gsub(
    paste0(.REDACT_LOG_KEY_ONU, "((?:proxy-)?authorization)([\"']?)([ \\t]*[:=][ \\t]*)",
           "(?=\\S)(?![{\"'])(?>((?:Bearer|Basic|Digest|Negotiate|NTLM|Token)[ \\t]+)?)(?!<redacted>)[^\\r\\n]+"),
    "\\1\\2\\3\\4\\5<redacted>",
    metin,
    perl = TRUE
  )
  # Çıplak SIR değerleri (`secret=abcde`, `"token": 12345`) uzunluktan bağımsız
  # maskelenir; genel redaktörün eşiği değişmez, bu yalnızca log katmanıdır.
  # Genel geçişin başını maskelediği değerin kuyruğu (`<redacted>&kuyruk`) da
  # bütünüyle maskelenir; zaten maskeli değer değişmez.
  gsub(
    paste0(.REDACT_LOG_KEY_ONU, "(", .REDACT_LOG_SECRET_KEYS, ")", .REDACT_LOG_KEY_SONU,
           "(?![{\"'])[^;,}\\])\\s\"']+"),
    "\\1\\2\\3\\4<redacted>",
    metin,
    perl = TRUE
  )
}

# Log katmanının SIR anahtarları. Genel redaktör listesine ek olarak camelCase
# kimlik alanları (`authToken`, `idToken`) da kapsanır; sözcük içi anahtar
# (`mytoken`) için önek sınırı korunur.
.REDACT_LOG_SECRET_KEYS <- paste(
  c("password", "passwd", "pwd", "api[_-]?key", "apikey", "x-api-key", "token",
    "access[_-]?token", "refresh[_-]?token", "auth[_-]?token", "id[_-]?token",
    "session[_-]?token", "bearer[_-]?token", "secret", "client[_-]?secret"),
  collapse = "|"
)
# Ortak anahtar sözdizimi: anahtar JSON'daki gibi tırnaklı olabilir; tırnak
# karakteri sınır sayılır, anahtarı kapatan tırnak isteğe bağlıdır.
.REDACT_LOG_KEY_ONU <- "(?i)(^|[;{(\\[,\\s\"'])"
.REDACT_LOG_KEY_SONU <- "([\"']?)(\\s*[:=]\\s*)"

#' Tırnaklı kimlik/bağlantı değerlerini kaçış belirsizliğinde KAPALI maskele
#'
#' `DSN="Ozel"`, `PWD='abc'`, `{"authToken":"..."}` gibi değerler uzunluktan
#' bağımsız maskelenir. Değerin İLK tırnağından önce ters bölü varsa (`\'`)
#' kaçış mı, değerin sonundaki düz ters bölü mü olduğu bilinemez
#' (`Server='db\';PWD='abcde'`). Bu durumda satırdaki SON kaçışsız tırnağa kadar,
#' kapanış tırnağı yoksa satır sonuna kadar her şey maskelenir.
#' Kapanmamış değer (kesilmiş tanı) CR/LF ya da metin sonuna kadar maskelenir;
#' satır sonu karakteri tüketilmez, sonraki satır korunur.
.redact_quoted_log_values <- function(x) {
  if (is.null(x)) return(x)
  if (!is.character(x)) x <- tryCatch(as.character(x), error = function(e) "")
  anahtarlar <- paste(c(.REDACT_CONN_KEYS, .REDACT_LOG_SECRET_KEYS,
                        "(?:proxy-)?authorization"), collapse = "|")
  onek <- paste0(.REDACT_LOG_KEY_ONU, "(", anahtarlar, ")", .REDACT_LOG_KEY_SONU)
  # Ham HTTP Authorization başlığı genel redaktörden ÖNCE satır sonuna kadar
  # maskelenir: RFC 6750 `~` karakteri veya Digest tırnaklı parametreleri
  # (`username="...", response="..."`) kısmen açıkta kalmaz.
  x <- gsub(
    paste0(.REDACT_LOG_KEY_ONU, "((?:proxy-)?authorization)([ \\t]*[:=][ \\t]*)",
           "(?=\\S)(?![{\"'])(?>((?:Bearer|Basic|Digest|Negotiate|NTLM|Token)[ \\t]+)?)(?!<redacted>)[^\\r\\n]+"),
    "\\1\\2\\3\\4<redacted>",
    x,
    perl = TRUE
  )
  # Çıplak ODBC parola değeri boşluk içerebilir (`PWD=abc ikinci;UID=x`): değer
  # noktalı virgül ya da satır sonuna dek maskelenir; sonraki alan ayrıca işlenir.
  x <- gsub("(?i)(^|[;{(\\[,\\s])(pwd|password|passwd)(\\s*=\\s*)(?!<redacted>)(?![{\"'\\s])[^;\r\n]+",
            "\\1\\2\\3<redacted>", x, perl = TRUE)
  for (q in c("\"", "'")) {
    # Belirsizlik taraması çift ayırıcıyı ('' / "") kapalı kalıpla AYNI biçimde
    # değer içi kaçış sayar: `"ab""cd\"kuyruk"` gibi değerde sonraki ters bölülü
    # tırnak gözden kaçmaz ve kuyruk açıkta kalmaz. Kapanış tırnağı ters bölülü
    # tırnaktan SONRA aranır; yoksa değer satır sonuna dek (açık kalıp) maskelenir.
    belirsiz_kapali <- paste0(q, "(?:[^", q, "\r\n]|", q, q, ")*(?<=\\\\)", q, "[^\r\n]*(?<!\\\\)", q)
    belirsiz_acik <- paste0(q, "(?=(?:[^", q, "\r\n]|", q, q, ")*(?<=\\\\)", q, ")[^\r\n]*(?=\r|\n|\\z)")
    # Değer içinde çift ayırıcının hemen ardından alan ayırıcı (`"abc"";UID="x"`)
    # geliyorsa sınır belirsizdir: çift ayırıcı kaçış mı, kapanış + boş değer mi
    # bilinemez. Kapalı-başarısız: değer satır sonuna dek maskelenir (sonraki
    # aynı tırnaklı alanın değeri açıkta kalmaz).
    belirsiz_cift <- paste0(q, "(?=(?:[^", q, "\r\n]|", q, q, ")*?", q, q, "\\s*[;,])[^\r\n]*(?=\r|\n|\\z)")
    # Çift ayırıcı ('' veya "") değer içi kaçış sayılır; komşu alan tüketilmez.
    kapali <- paste0(q, "(?!<redacted>", q, ")(?>(?:[^", q, "\r\n]|", q, q, ")*)", q)
    acik <- paste0(q, "(?!<redacted>)(?>(?:[^", q, "\r\n]|", q, q, ")*)(?=\r|\n|\\z)")
    yerine <- paste0("\\1\\2\\3\\4", q, "<redacted>")
    x <- gsub(paste0(onek, belirsiz_kapali), paste0(yerine, q), x, perl = TRUE)
    x <- gsub(paste0(onek, belirsiz_acik), yerine, x, perl = TRUE)
    x <- gsub(paste0(onek, belirsiz_cift), yerine, x, perl = TRUE)
    x <- gsub(paste0(onek, kapali), paste0(yerine, q), x, perl = TRUE)
    x <- gsub(paste0(onek, acik), yerine, x, perl = TRUE)
  }
  x
}

#' Hata koşulunun günlüğe yazılabilir (maskelenmiş) metni
#'
#' Sürücü/ODBC hataları DSN, sunucu ya da kullanıcı adı taşıyabilir; metin
#' `redact_connection_identifiers()` sınırından geçirilir. Maskeleme
#' uygulanamazsa ham metin YAZILMAZ, genel bir ifade döner.
redacted_condition_message <- function(e) {
  ham <- tryCatch(conditionMessage(e), error = function(x) "")
  temiz <- tryCatch(redact_connection_identifiers(ham), error = function(x) NULL)
  if (is.character(temiz) && length(temiz) == 1L && !is.na(temiz)) temiz else "(ayrıntı gizlendi)"
}

# DB okuma hatasının günlüğe yazılabilir özeti. Bütçeli okumalar doğrulanmış
# kimlikleri SQL metnine gömer ve sürücü tanısı deyimi içerebilir; bağlantı
# maskelemesinin ardından deyim gövdesi (sürücünün "<SQL>" eki ya da ilk SQL
# anahtar sözcüğünden sonrası) atılır, yalnızca hata sınıflaması kalır.
mergen_db_error_log_summary <- function(e) {
  sinif <- tryCatch(class(e)[1], error = function(x) "error")
  metin <- if (exists("redacted_condition_message", mode = "function", inherits = TRUE)) {
    redacted_condition_message(e)
  } else "(ayrıntı gizlendi)"
  metin <- sub("(?is)(<SQL>|\\b(SELECT|WITH|INSERT|UPDATE|DELETE|EXEC|MERGE)\\b).*$", "<SQL gizlendi>", metin, perl = TRUE)
  sprintf("[%s] %s", sinif, substr(metin, 1L, 300L))
}

# DB hatasını maskelenmiş özetle uyarı olarak yazar. Uyarı hataya çevrilirse
# (options(warn = 2)) çağıranın kurtarma yolu kesilmez; metin stderr'e düşer.
mergen_db_error_warn <- function(etiket, e) {
  metin <- sprintf("%s: %s", etiket, mergen_db_error_log_summary(e))
  sonuc <- try(warning(metin, call. = FALSE), silent = TRUE)
  if (inherits(sonuc, "try-error")) try(cat(metin, "
", file = stderr()), silent = TRUE)
  invisible(NULL)
}
