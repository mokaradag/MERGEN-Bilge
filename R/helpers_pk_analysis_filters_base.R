# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_filters_base.R
# Açıklama: Proje/Kaynak Analizi için AI filtre çıkarımı ve veri filtreleme
#           yardımcıları. Bu dosya Shiny observer başlatmaz ve canlı DB
#           bağlantısı açmaz; çağıran akışın verdiği conn/session nesnelerini
#           kullanır.
# ==============================================================================

# Boş filtre sonucunun TİPLİ hâli (Faz 0 / D9).
#
# Bugün zaman aşımı, hata, bozuk yanıt ve "gerçekten filtre gerekmiyordu"
# durumlarının tamamı aynı `list(filters = list(), aggregation = NULL)` değerini
# döndürüyor; bu yüzden kullanıcı tek bir proje sorduğunda uç nokta yavaşsa araç
# 4.000 projenin tamamını hiç söylemeden analiz edebiliyor.
#
# Bu yardımcı YALNIZCA gözlem amaçlıdır: `filters` / `aggregation` alanlarının
# şekli ve içeriği DEĞİŞMEZ, yanına yalnızca `status` eklenir. v1 motorunun
# hangi filtreyi uyguladığı bu değişiklikle aynen korunur.

# Yerelden BAĞIMSIZ ASCII küçük harf (makine/protokol belirteçleri için).
# Ortak yardımcı `R/helpers_pk_text_turkish.R` içindedir; bu dosya izole
# testlerde tek başına source edilebildiği için yerel bir yedeği vardır.
.pk_filter_base_ascii_lower <- function(x) {
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) return(pk_ascii_lower(x))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

.pk_filter_empty_result <- function(status) {
  list(filters = list(), aggregation = NULL, status = status)
}

# AÇIK mantık grubu (`{operator, children}`) şekli mi?
#
# İstem (bkz. system_instruction) modele iç içe VEYA/VE isteğini bu şekilde
# temsil etmesini SÖYLER ve `R/helpers_pk_filter_group.R` bunun inert
# değerlendiricisini sağlar. Bu yüzden doğrulama yaprak ve grup şekillerini
# AYRI ayrı ele almalıdır; grup düğümünü yaprak kuralıyla elemek, modelin
# ürettiği VEYA dalını derleyiciye HİÇ ulaştırmaz.
#
# Tek doğruluk kaynağı yüklüyse o kullanılır; izole test/hata ayıklama
# oturumlarında dosya tek başına source edilebildiği için yerel şekil kontrolü
# yedektir.
# TEK KARAKTER DEĞERE İNDİRGEME (model çıktısı normalleştirmesi).
#
# Filtre yanıtı `simplifyVector = FALSE` ile ayrıştırılır; bu yüzden
# `"aggregation": ["count"]` gibi bir JSON dizisi R tarafına LİSTE olarak
# gelir. Böyle bir değer `tolower()` içinde "non-character argument" hatası,
# skaler `if` karşılaştırmasında ise R 4.3+ "the condition has length > 1"
# hatası üretirdi ve v1 isteği bozulmak yerine ÇÖKERDİ. Tek gövde: hem bu
# dosyadaki hem `helpers_pk_analysis_filters.R` içindeki kopya bunu kullanır.
.pk_filter_scalar_token <- function(x) {
  if (is.null(x)) return(NULL)
  duz <- suppressWarnings(as.character(unlist(x, use.names = FALSE)))
  duz <- duz[!is.na(duz) & nzchar(trimws(duz))]
  if (!length(duz)) return(NULL)
  trimws(duz[1])
}

.pk_filter_base_is_group <- function(f) {
  if (exists(".pk_filter_is_group_node", mode = "function", inherits = TRUE)) {
    return(isTRUE(.pk_filter_is_group_node(f)))
  }
  is.list(f) && !is.null(f$children) && is.list(f$children)
}

# LLM çağrısının hata mesajından zaman aşımını ayırt eder. httr/curl zaman
# aşımı hata olarak yüzeye çıktığı için sınıflandırma mesaj üzerinden yapılır.
.pk_filter_classify_llm_error <- function(message_text) {
  # `timeout`/`timed out` ASCII makine işaretleridir (bkz. aynı gerekçe
  # helpers_pk_query_selection_degraded.R içinde).
  txt <- .pk_filter_base_ascii_lower(as.character(message_text %||% "")[1])
  if (grepl("timeout|timed out|zaman a", txt, useBytes = TRUE)) "timeout" else "error"
}

extract_filter_criteria_from_prompt <- function(user_prompt, data_context, available_columns, conn, session = NULL, stop_check = NULL) {

  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[FILTER_AI] Durdurma talebi alindi (AI filtreleme oncesi)\n")
    return(.pk_filter_empty_result("stopped"))
  }

  cols_summary <- summarize_columns_for_ai(data_context)

  system_instruction <- paste0(
    "Sen Primavera P6 ve SAP Project System verileri konusunda uzman, kıdemli bir veri analistisin. ",
    "Kullanıcının Türkçe sorduğu doğal dil sorularını analiz ederek yapılandırılmış bir JSON filtreleme sorgusuna dönüştürmekle görevlisin.\n\n",

    "### KRİTİK: GENEL SORULAR VS SPESİFİK FİLTRELER\n",
    "\U00002757\U00002757\U00002757 ÇOĞU SORGU ZATEN BELİRLİ BİR KONUYA ÖZELDIR - GEREKSİZ FİLTRE EKLEME!\n",
    "Örnek: 'Rolden kaynağa çevrilmemiş aktiviteler' sorgusu zaten bu konuya özgüdür. 'çevrilmemiş' kelimesini filtre olarak kullanma!\n",
    "Örnek: 'Bütçesi aşan projeler' sorgusu zaten bütçe aşımı içerir. 'aşan' kelimesini filtre olarak kullanma!\n\n",

    "\U00002757 Kullanıcı GENEL bir analiz istiyorsa (tüm projeler, tüm kaynaklar, özet istatistikler), FİLTRE KULLANMA!\n",
    "\U00002705 Sadece kullanıcı BELİRLİ bir VARLIK belirtirse filtre ekle:\n",
    "   - Proje kodu: 'P1234', 'PROJE-001'\n",
    "   - Proje adı: 'Malzeme Üretim Projesi', 'Elektronik Tasarım'\n",
    "   - Kişi adı: 'Ahmet Yılmaz', 'Mehmet'\n",
    "   - Departman: 'Elektronik Tasarım Müdürlüğü', 'PGRM'\n",
    "   - Masraf yeri kodu: '12345678'\n",
    "   - Tarih aralığı: '2024', 'Ocak', 'son 3 ay'\n\n",

    "\U0000274C FİLTRE YAPILMAMASI GEREKEN DURUMLAR:\n",
    "- Kullanıcı sorgu konusunu tekrar ediyor: 'aktiviteler', 'kaynaklar', 'projeler' gibi genel terimler\n",
    "- Kullanıcı analiz türü belirtiyor: 'özetle', 'listele', 'kaç tane', 'var mı'\n",
    "- Kullanıcı sorgu kriterini tekrar ediyor: Sorgu zaten 'çevrilmemiş aktiviteler'i getiriyorsa, 'çevrilmemiş' filtresiz bırak\n\n",

    "**GENEL SORU ÖRNEKLERİ (FİLTRE YOK):**\n",
    "- 'Kaç proje var?', 'Toplam kaç kaynak?', 'Hangi departmanlarda çalışma var?'\n",
    "- 'Projelerin dağılımı nedir?', 'En büyük projeler hangileri?', 'Aktif proje sayısı?'\n",
    "- 'Yıllara göre proje dağılımı', 'Departman bazında kaynak analizi'\n",
    "- 'Ortalama proje süresi', 'Toplam bütçe', 'Maliyet özeti'\n\n",

    "**SPESİFİK SORU ÖRNEKLERİ (FİLTRE EKLE):**\n",
    "- 'P1234 projesinin durumu nedir?' -> filter: ProjeKodu='P1234'\n",
    "- 'Malzeme Üretim projesinin durumu nedir?' -> filter: ProjeAdi='Malzeme Üretim'\n",
    "- 'Ahmet Yılmaz hangi projelerde?' -> filter: KaynakAdi contains 'Ahmet Yılmaz'\n",
    "- 'PGRM program müdürlüğündeki projeler' -> filter: ProgMdlKodu='4_PGRM'\n",
    "- 'Elektronik Tasarım Müdürlüğündeki çalışanlar' -> filter: MasrafYeri='Elektronik Tasarım Müdürlüğü'\n",
    "- '12345678 masraf yerindeki çalışanlar' -> filter: MasrafYeriKodu='12345678'\n",
    "- 'Aktif durumdaki projeler' -> filter: Durum='1'\n\n",

    "### ANALİZ EVRENİ VE TERMİNOLOJİ\n",
    "**Proje Yönetimi Terimleri:**\n",
    "- **Projeler:** Proje Kodu, Proje Adı, Durum, EPS, Program Müdürlüğü, Program Direktörlüğü, İDA, İş Dağılım Ağacı, WBS\n",
    "- **Kaynaklar:** Kaynak Adı, Kaynak Kodu, Çalışan, Personel, Rol, Unvan, Sicil Numarası, Sicil No\n",
    "- **Organizasyon:** Masraf Yeri, Masraf Yeri Kodu, Bölüm, Müdürlük, Direktörlük, Birim\n",
    "- **Finansal:** Bütçe, Gerçekleşen, Kalan, Maliyet Merkezi\n",
    "- **Zaman:** Başlangıç/Bitiş Tarihleri, Süre, Planlanan/Gerçekleşen\n",
    "- **Durum Kodları:** 1=Aktif, 0=Pasif\n\n",

    "### MEVCUT SÜTUNLAR VE DEĞER ÖZETLERİ (Filtre degerlerini buradaki gercek verilere gore sec):\n",
    cols_summary, "\n\n",

    "### GÖREV KURALLARI:\n",
    "1. **GENEL SORULARDA FİLTRE KULLANMA:** \n",
    "   - Kullanıcı 'kaç proje var', 'toplam', 'tüm', 'hepsi', 'dağılım', 'liste' gibi kelimeler kullanıyorsa,\n",
    "   - VE spesifik bir kod/isim BELİRTMİYORSA,\n",
    "   - -> filters: [] (BOŞ DİZİ döndür)\n",
    "   - Aggregation olarak 'count' veya 'group_by' kullanabilirsin.\n\n",

    "2. **SPESİFİK SORULARDA FİLTRE EKLE:**\n",
    "   - Proje kodu (P123), masraf yeri (M1), kişi adı (Ahmet Yılmaz) gibi BELİRLİ varlıklar belirtilmişse,\n",
    "   - -> Bu varlıkları filters dizisine ekle.\n\n",

    "3. **Çoklu Filtreleme:** Kullanıcı birden fazla koşul belirtirse (örn: 'M1 masraf yerinde unvanı mühendis olanlar'), bunların hepsini 'filters' listesine ekle.\n",
    "4. **Esnek Eşleştirme:** Kullanıcının 'Mühendisler' dediği şeyi veride 'Mühendis' veya 'Engineer' olarak bulabilirsin. 'operation' alanını buna göre seç.\n",
    "5. **Büyük/Küçük Harf Duyarsız:** Filtre değerlerini olduğu gibi al, kod tarafında case-insensitive arama yapılacaktır.\n\n",

    "### MANTIKSAL OPERATÖRLER (VE / VEYA):\n",
    "Standart 'filters' listesi her zaman 'AND' (VE) ile birleştirilir. VEYA gerektiğinde AŞAĞIDAKİ İKİ YOLDAN birini kullan:\n",
    "1. **Aynı sütunda birden çok değer** -> TEK bir filtre yaz ve 'value' alanına DİZİ ver.\n",
    "   Örn: {\"column\":\"Durum\",\"value\":[\"Aktif\",\"Beklemede\"],\"operation\":\"exact_match\"}\n",
    "2. **Farklı sütunlar arasında VEYA / parantezli mantık** -> 'filters' içine bir GRUP nesnesi koy:\n",
    "   {\"operator\":\"or\",\"children\":[ {<filtre>}, {<filtre>} ]}\n",
    "   Gruplar iç içe olabilir ve 'operator' yalnızca \"and\" veya \"or\" alır.\n",
    "\U000026A0\U0000FE0F ASLA R kodu, ifade metni, fonksiyon çağrısı veya 'filter_expression' ÜRETME.\n",
    "   Yalnızca yukarıdaki JSON yapıları kabul edilir; kod içeren yanıt REDDEDİLİR.\n\n",

    "### ÇIKTI FORMATI (JSON):\n",
    "{\n",
    "  \"filters\": [ ... ], \n",
    "  \"aggregation\": \"count\",\n",
    "  \"group_column\": null\n",
    "}\n\n",

    "### ALAN DEĞERLERİ (DOMAIN MAPPINGS):\n",
    "Bazı alanlar sayısal veya kodlanmış değerler kullanır:\n",
    "- **AktifKaynak, Durum, Status**: 1 (aktif/yes), 0 (pasif/no)\n",
    "- **Onay, Approval**: 1 (onaylı), 0 (onaysız)\n",
    "Kullanıcı 'aktif', 'Y', 'yes' derse -> value: '1' kullan.\n",
    "Kullanıcı 'pasif', 'N', 'no' derse -> value: '0' kullan.\n\n",

    "### OPERATÖRLER ('operation'):\n",
    "- 'exact_match': Kodlar ve ID'ler için (örn: P101, M1).\n",
    "- 'contains': İsimler, açıklamalar ve metin aramaları için (örn: 'İnşaat içeren projeler').\n",
    "- 'greater_than', 'less_than': Sayısal değerler ve tarihler için (örn: 'Bütçesi 1000'den büyük').\n\n",

    "### AGGREGATION TİPLERİ ('aggregation'):\n",
    "- 'list': Kayıtları listele (Varsayılan).\n",
    "- 'count': Kayıt sayısını ver (Kaç adet?).\n",
    "- 'sum': Sayısal sütunu topla (Toplam bütçe).\n",
    "- 'group_by': Gruplayarak özetle (Departman bazında dağılım).\n\n",

    "### ÖRNEKLER:\n",
    "Soru: 'P1111 proje kodlu projeyi özetle'\n",
    "-> {\"filters\":[{\"column\":\"ProjeKodu\",\"value\":\"P1111\",\"operation\":\"exact_match\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "Soru: 'M1 masraf yerinde unvanı mühendis olan çalışanları listele'\n",
    "-> {\"filters\":[{\"column\":\"MasrafYeri\",\"value\":\"M1\",\"operation\":\"exact_match\"}, {\"column\":\"Unvan\",\"value\":\"Mühendis\",\"operation\":\"contains\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "Soru: 'Hangi departmanlarda kaç proje var?'\n",
    "-> {\"filters\":[], \"aggregation\":\"group_by\", \"group_column\":\"Departman\"}\n\n",

    "Soru: 'Ali Demir hangi projeleri yönetiyor?'\n",
    "-> {\"filters\":[{\"column\":\"ProjeYoneticisi\",\"value\":\"Ali Demir\",\"operation\":\"contains\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "Soru: 'Aktif kaynakları göster'\n",
    "-> {\"filters\":[{\"column\":\"AktifKaynak\",\"value\":\"1\",\"operation\":\"exact_match\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "Soru: 'Pasif projeleri listele'\n",
    "-> {\"filters\":[{\"column\":\"Durum\",\"value\":\"0\",\"operation\":\"exact_match\"}], \"aggregation\":\"list\", \"group_column\":null}\n\n",

    "SADECE GEÇERLİ JSON DÖNDÜR. YORUM EKLEME."
  )

  messages <- list(
    list(role = "system", content = system_instruction),
    list(role = "user", content = user_prompt)
  )

  # LLM çağrısı başarısız olursa nedeni (timeout/error) burada tutulur.
  llm_failure_status <- "error"

  tryCatch({
    if (is.function(stop_check) && isTRUE(stop_check())) {
      cat("[FILTER_AI] Durdurma talebi alindi (LLM cagrisinin hemen oncesi)\n")
      return(.pk_filter_empty_result("stopped"))
    }

    filter_model <- getOption("mergen.filter_model", api_config$local_models[1])
    creds <- resolve_local_llm_credentials(filter_model)

    # SAHİPLİK DENETİMLİ ANAHTAR ÇÖZÜMLEMESİ (§1F): `session$userData$ai_api_key`
    # doğrudan okunamaz; SSO kimlik değişimi sonrasında o yuva BAŞKA bir
    # kullanıcının kişisel anahtarını taşıyor olabilir.
    api_key_val <- if (exists("mb_api_key_get_feature_key_value", mode = "function", inherits = TRUE)) {
      tryCatch(
        mb_api_key_get_feature_key_value(
          session = session, fallback_key = creds$default_api_key %||% ""
        ),
        error = function(e) NULL
      )
    } else {
      NULL
    }

    if (length(api_key_val) != 1L || is.na(api_key_val) || !nzchar(as.character(api_key_val)[1])) {
      default_key <- creds$default_api_key %||% ""
      api_key_val <- if (nzchar(default_key)) as.character(default_key)[1] else NULL
    }

	# D9: v1'in sabit 8 saniyesi fazla agresifti ve zaman asimi "filtre
	# gerekmedi" ile ayirt edilemiyordu. Yapilandirilabilir deger YALNIZCA
	# v2'de tuketilir; v1 karari degismesin diye 8 saniye korunur (§10).
	filter_timeout <- 8
	if (exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
		isTRUE(pk_engine_is_v2()) &&
		exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
	  # SORGU BAZLI GEÇERSİZ KILMA ONURLANDIRILIR: `pk_config_resolve()` ikinci
	  # argüman olarak sorgu metadata'sını alır; verilmezse SEÇİLİ sorgunun
	  # `meta$MERGEN_PK_FILTER_TIMEOUT_SEC` değeri sessizce yok sayılıyordu.
	  # Yavaş/karmaşık bir sorgu için tanımlanan daha uzun filtre süresi hiç
	  # uygulanmıyor, global varsayılan kullanılıyordu. Kalan-bütçe üst sınırı
	  # bunun ARDINDAN uygulanır; sert son tarih hâlâ bağlayıcıdır.
	  .filter_meta <- tryCatch(
		if (exists("pk_active_query_meta", mode = "function", inherits = TRUE)) {
		  pk_active_query_meta()
		} else NULL,
		error = function(e) NULL
	  )
	  filter_timeout <- tryCatch(
		pk_config_resolve("MERGEN_PK_FILTER_TIMEOUT_SEC", query_meta = .filter_meta),
		error = function(e) 8
	  )
	}

	# Faz 6 (§5.10): bloklayan filtre çağrısı KALAN analiz bütçesini AŞAMAZ.
	# `MERGEN_PK_FILTER_TIMEOUT_SEC` üst sınırı yoktur; asılı bir uç nokta
	# aksi hâlde işçiyi (ve açık DB bağlantısını) Durdur'un ve sert son tarihin
	# çok ötesinde tutabilirdi.
	.filter_deadline <- getOption("mergen.pk.async.deadline_at", NULL)
	if (!is.null(.filter_deadline) &&
		exists("pk_sql_timeout_plan", mode = "function", inherits = TRUE) &&
		exists("pk_deadline_remaining_sec", mode = "function", inherits = TRUE)) {
	  .filter_plan <- tryCatch(
		pk_sql_timeout_plan(filter_timeout, pk_deadline_remaining_sec(.filter_deadline)),
		error = function(e) list(dispatch = TRUE, timeout_sec = filter_timeout)
	  )
	  if (!isTRUE(.filter_plan$dispatch)) {
		cat("[FILTER_AI] Kalan analiz butcesi yok; filtre planlamasi yapilmadi.\n")
		return(.pk_filter_empty_result("timeout"))
	  }
	  filter_timeout <- as.numeric(.filter_plan$timeout_sec)
	}

	result <- tryCatch({
	  call_local_llm(messages, list(
		model_selection = filter_model,
		temperature = 0.0,
		max_output_tokens = 4000,
		enable_mcp_tools = FALSE,
		shiny_session = session,
		api_key_override = api_key_val,
		request_timeout_sec = filter_timeout
	  ))
	}, error = function(e) {
	  llm_failure_status <<- .pk_filter_classify_llm_error(conditionMessage(e))
	  cat(sprintf(
		"[FILTER_AI] Timeout veya hata (%s), AI filtreleme atlanıyor: %s\n",
		llm_failure_status,
		conditionMessage(e)
	  ))
	  NULL
	})

    if (is.function(stop_check) && isTRUE(stop_check())) {
      cat("[FILTER_AI] Durdurma talebi alindi (LLM cagrisi sonrasinda)\n")
      return(.pk_filter_empty_result("stopped"))
    }

    if (is.null(result)) return(.pk_filter_empty_result(llm_failure_status))

    ai_content <- if (is.list(result)) result$content else result
    if (is.null(ai_content) || length(ai_content) == 0) return(.pk_filter_empty_result("malformed"))

    ai_text <- as.character(ai_content)[1]
    ai_text <- gsub("```json|```", "", ai_text)
    ai_text <- trimws(ai_text)

    # UZUNLUK BİR DOĞRULUK ÖLÇÜTÜ DEĞİLDİR. Eski 50 karakterlik alt sınır,
    # `{"filters":[],"aggregation":"count"}` (36 karakter) gibi TAMAMEN
    # geçerli bir sayım yanıtını `malformed` yapıyordu; v2'de bu statü REDde
    # dönüştüğü için meşru istek reddediliyordu. Geçerlilik kararını şema
    # doğrulaması ve `jsonlite::fromJSON()` verir.
    if (!nzchar(ai_text)) {
      cat("[FILTER_AI] Yanıt boş, iptal ediliyor.\n")
      return(.pk_filter_empty_result("malformed"))
    }

    # `.` satır sonunu EŞLEŞTİRMEZ: çok satırlı (pretty-print) JSON —ki istem
    # örneği de böyle— bu kapıda düşerdi. Yapısal denetim satır sonuna
    # duyarsız yapılır; nihai kararı yine ayrıştırıcı verir.
    if (!grepl("\\{[\\s\\S]*\\}", ai_text, perl = TRUE)) {
      cat("[FILTER_AI] JSON format algilanamadi.\n")
      return(.pk_filter_empty_result("malformed"))
    }

    parsed <- tryCatch({
      temp_parse <- jsonlite::fromJSON(ai_text, simplifyVector = FALSE)
      if (is.null(temp_parse)) {
        ai_text_fixed <- paste0(ai_text, ']}' )
        jsonlite::fromJSON(ai_text_fixed, simplifyVector = FALSE)
      } else {
        temp_parse
      }
    }, error = function(e) {
      cat(sprintf("[FILTER_AI] JSON parse hatasi: %s\n", e$message))
      NULL
    })

    if (is.null(parsed)) return(.pk_filter_empty_result("malformed"))

    # ŞEMA KAPISI (eski uzunluk kapısının yerine).
    #
    # Doğruluk ölçütü artık yanıtın UZUNLUĞU değil, TANINAN ŞEMA ALANLARINDAN
    # en az birini taşıyıp taşımadığıdır. Böylece `{"filters":[],
    # "aggregation":"count"}` (36 karakter) gibi TAMAMEN geçerli kısa yanıtlar
    # kabul edilirken, hiçbir sözleşme alanı taşımayan `{}` gibi içi boş bir
    # nesne `malformed` olarak kalır.
    if (!is.list(parsed) ||
        !any(c("filters", "aggregation", "group_column", "filter_column",
               "filter_expression") %in% names(parsed))) {
      cat("[FILTER_AI] Yanit taninan filtre alanlarindan hicbirini tasimiyor.\n")
      return(.pk_filter_empty_result("malformed"))
    }

    filters <- parsed$filters
    if (is.null(filters) || !is.list(filters)) filters <- list()

    if (length(filters) > 0) {
      filters <- lapply(filters, function(f) {
        # Grup düğümünde `column`/`value` yoktur; durum kısayolu YALNIZCA
        # yapraklar içindir.
        if (.pk_filter_base_is_group(f)) return(f)

        # YERELDEN BAĞIMSIZ KATLAMA: Türkçe yerelde `tolower("I")` NOKTASIZ
        # `ı` üretir. `AKTIFKAYNAK` sütunu bu yüzden Windows VM'de
        # `aktıfkaynak` olur, `aktif|active|durum|status` deseni EŞLEŞMEZ ve
        # `EVET` metni `1` alanına karşı derlenip HİÇBİR satırı tutmaz.
        # Sütun adları makine belirtecidir; ASCII katlama doğru sözleşmedir.
        col_lower <- .pk_filter_base_ascii_lower(f$column %||% "")
        val_raw <- f$value %||% ""

        # ÇOK DEĞERLİ YAPRAK (aynı sütun içi VEYA) bu kısayoldan MUAFTIR.
        #
        # `value` bir dizi olabilir (`["Aktif","Beklemede"]`); `simplifyVector
        # = FALSE` altında bu bir listedir. Eskiden `as.character(val_raw)`
        # uzunluğu >1 bir vektör üretiyor, `val_lower %in% c(...)` de vektör
        # dönüyordu; skaler `if` bunun üzerinde HATA yükseltir ("the condition
        # has length > 1") ve dış tryCatch geçerli yanıtı `error` durumuna
        # çevirirdi. Ayrıca tek bir "1"/"0" ataması çok değerli VEYA isteğinin
        # anlamını da bozardı. Kısayol bu yüzden tek değerli yaprakla sınırlıdır.
        val_flat <- as.character(unlist(val_raw, use.names = FALSE))
        if (length(val_flat) != 1L) return(f)

        # KISAYOL SÜTUN TÜRÜYLE SINIRLIDIR.
        #
        # Sütun adı `aktif|active|durum|status` desenine uyduğunda değer
        # KOŞULSUZ olarak `"1"`/`"0"` yazılıyordu. `Durum` gibi METİN bir sütun
        # `Aktif`/`Beklemede`/`Kapali` etiketlerini saklarken bu yeniden yazım
        # tam eşleşmeyi SIFIR satıra düşürür: model doğru etiketi yazmış olsa
        # bile filtre hiçbir kaydı tutmaz. Kısayol yalnızca değerin GERÇEKTEN
        # mantıksal ya da 0/1 kodlandığı sütunlarda anlamlıdır.
        sutun_adi <- as.character(f$column %||% "")[1]
        sutun_degerleri <- if (is.data.frame(data_context) &&
                               !is.na(sutun_adi) && nzchar(sutun_adi) &&
                               sutun_adi %in% names(data_context)) {
          data_context[[sutun_adi]]
        } else {
          NULL
        }
        ikili_sutun <- if (is.logical(sutun_degerleri)) {
          TRUE
        } else if (is.numeric(sutun_degerleri)) {
          gecerli <- sutun_degerleri[!is.na(sutun_degerleri)]
          length(gecerli) == 0L || all(gecerli %in% c(0, 1))
        } else {
          FALSE
        }

        if (isTRUE(ikili_sutun) &&
            grepl("aktif|active|durum|status", col_lower, perl = TRUE)) {
          # DEĞER TARAFI TÜRKÇE OLABİLİR: hem ASCII hem Türkçe-farkında katlama
          # denenir. Yalnızca ASCII katlamak `HAYIR -> hayir` üretir ve Türkçe
          # `hayır` karşılığını kaçırırdı; yalnızca `tolower()` ise yerele
          # bağımlı kalırdı.
          val_ascii <- .pk_filter_base_ascii_lower(val_flat)
          val_tr <- if (exists("pk_tr_fold", mode = "function", inherits = TRUE)) {
            as.character(pk_tr_fold(val_flat))[1]
          } else {
            val_ascii
          }
          val_adaylari <- unique(c(val_ascii, val_tr))
          if (any(val_adaylari %in% c("y", "yes", "evet", "aktif", "active", "1", "true"))) {
            f$value <- "1"
            f$operation <- "exact_match"
          } else if (any(val_adaylari %in% c("n", "no", "hayır", "hayir", "pasif",
                                             "passive", "inactive", "0", "false"))) {
            f$value <- "0"
            f$operation <- "exact_match"
          }
        }

        f
      })
    }

    # ESKİ `filter_column` BİÇİMİ YAPISAL DİZİYİ SESSİZCE EZMEZ.
    # Model her iki gösterimi birlikte döndürdüğünde eski dal doğrulanmış
    # `filters` dizisinin TAMAMINI atıp tek bir eski filtre bırakıyordu; yanıt
    # yine `ok_filtered` raporlandığı için çok ölçütlü istek, farklı tek
    # sütunlu bir filtreye dönüşüp BAŞKA bir soruyu yanıtlıyordu. İki gösterim
    # artık birbirini dışlar: `filters` doluyken eski alanlar yok sayılır ve
    # durum tanıya yazılır.
    if (!is.null(parsed$filter_column)) {
      if (length(filters) > 0L) {
        cat("[FILTER_AI] Eski `filter_column` alani yok sayildi: yapisal `filters` dizisi mevcut.\n")
      } else {
        filters <- list(list(
          column = parsed$filter_column,
          value = parsed$filter_value,
          operation = parsed$operation
        ))
      }
    }

    if (length(filters) > 0) {
      # YAPRAK ve GRUP şekilleri AYRI doğrulanır.
      #
      # Grup düğümünde `column`/`value` bulunmaz; yalnızca yaprak kuralı
      # uygulandığında her `{operator, children}` düğümü derleyiciye
      # ULAŞMADAN elenirdi. Sonuç: grup-yalnız yanıt "malformed" olur,
      # yaprakla karışık yanıt ise VEYA dalını SESSİZCE kaybedip farklı bir
      # alt kümeyi analiz ederdi. Grup, en az bir çocuğu olduğunda geçerlidir;
      # çocukların kendisi `.pk_filter_eval_group()` içinde doğrulanır.
      valid_filters <- Filter(function(f) {
        if (.pk_filter_base_is_group(f)) return(length(f$children) > 0L)
        !is.null(f$column) && nzchar(f$column) && !is.null(f$value)
      }, filters)

      if (length(valid_filters) == 0) {
        cat("[FILTER_AI] Tum filtreler gecersiz, iptal ediliyor.\n")
        return(.pk_filter_empty_result("malformed"))
      }

      cat(sprintf("[FILTER_AI] %d gecerli filtre algilandi.\n", length(valid_filters)))
      filters <- valid_filters
    }

    # Başarılı yol: model çalıştı. Filtre üretmemesi MEŞRU bir sonuçtur ve
    # zaman aşımı/hatadan ayırt edilebilir olmalıdır.
    return(list(
      filters = filters,
      filter_expression = parsed$filter_expression,
      aggregation = parsed$aggregation,
      group_column = parsed$group_column,
      status = if (length(filters) > 0) "ok_filtered" else "ok_no_filter"
    ))

  }, error = function(e) {
    cat(sprintf("[FILTER_AI] Error: %s\n", e$message))
    return(.pk_filter_empty_result(.pk_filter_classify_llm_error(conditionMessage(e))))
  })
}

apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  cat(sprintf("[SMART_FILTER] Baslangic satir: %d\n", nrow(data)))

  if (nrow(data) == 0) return(data.frame())

  dt <- data.table::as.data.table(data)

  filters <- filter_instructions$filters
  # TOPLULAŞTIRMA DA TEK KARAKTER DEĞERE İNDİRGENİR (grup sütunuyla aynı gerekçe).
  aggregation <- .pk_filter_scalar_token(filter_instructions$aggregation)
  # GRUPLAMA SÜTUNU TEK BİR KARAKTER DEĞERE İNDİRGENİR.
  #
  # `simplifyVector = FALSE` ile ayrıştırılan model çıktısında birden çok grup
  # sütunu LİSTE olarak gelir. `group_col %in% names(dt)` o zaman uzunluğu
  # birden büyük bir vektör üretir ve R 4.3+ `&&` içinde HATA fırlatır; ayrıca
  # `by =` argümanına liste geçmek data.table tarafında tanımsız davranıştır.
  # `helpers_pk_analysis_filters.R` içindeki gövdeyle AYNI olmalıdır.
  group_col <- local({
    ham <- filter_instructions$group_column
    if (is.null(ham)) return(NULL)
    duz <- unlist(ham, use.names = FALSE)
    duz <- as.character(duz)
    duz <- duz[!is.na(duz) & nzchar(trimws(duz))]
    if (!length(duz)) return(NULL)
    trimws(duz[1])
  })

  genel_soru_kaliplari <- c(
    "kaç", "toplam", "sayı", "adet", "hangi", "dağılım", "özet",
    "analiz", "liste", "göster", "tüm", "hepsi", "en fazla",
    "en az", "ortalama", "maksimum", "minimum"
  )

  prompt_lower <- tolower(user_prompt)
  genel_soru_mu <- any(sapply(genel_soru_kaliplari, function(pattern) {
    grepl(pattern, prompt_lower, fixed = TRUE)
  }))

  spesifik_varlik_var <- grepl("\\b[A-Z][0-9]{3,}\\b|\\b[A-Z]{1,3}[0-9]{1,}\\b", user_prompt, perl = TRUE) ||
    grepl("[A-ZÜĞIŞÖÇ][a-züğışöç]+ [A-ZÜĞIŞÖÇ][a-züğışöç]+", user_prompt, perl = TRUE)

  if (genel_soru_mu && !spesifik_varlik_var && (is.null(filters) || length(filters) == 0)) {
    cat("[SMART_FILTER] GENEL SORU tespit edildi, filtre UYGULANMAYACAK.\n")
    filters <- list()
  }

  cat(sprintf(
    "[SMART_FILTER] Filtre sayisi: %d (Genel soru: %s, Spesifik varlik: %s)\n",
    length(filters %||% list()),
    genel_soru_mu,
    spesifik_varlik_var
  ))

  cat(sprintf("[SMART_FILTER] Filtre sayisi: %d\n", length(filters %||% list())))
  if (length(filters) > 0) {
    for (i in seq_along(filters)) {
      f <- filters[[i]]
      cat(sprintf(
        "[SMART_FILTER] Filtre #%d: sutun='%s', deger='%s', islem='%s'\n",
        i,
        f$column %||% "NULL",
        # Çok değerli yaprakta `sprintf` vektörleşip filtre başına birden çok
        # satır basardı; günlük tek satır kalsın diye değerler birleştirilir.
        paste(as.character(unlist(f$value %||% "NULL", use.names = FALSE)), collapse = "|"),
        f$operation %||% "NULL"
      ))
    }
  }

  # GÜVENLİK SINIRI — model üretimi ifade ASLA çalıştırılmaz (bkz.
  # R/helpers_pk_analysis_filters.R içindeki aynı sınır). Bu gövde çalışma
  # zamanında `helpers_pk_analysis_filters.R` tarafından gölgelenir, ancak
  # izole test/hata ayıklama oturumlarında doğrudan source edilebildiği için
  # `eval(parse())` yolu BURADA DA bulunmamalıdır.
  applied_expression_success <- FALSE

  if (!is.null(filter_instructions$filter_expression) && nzchar(filter_instructions$filter_expression)) {
    cat("[SMART_FILTER] filter_expression yok sayildi (calistirilabilir ifade kabul edilmez).\n")
  }

  if (!applied_expression_success) {
    if (!is.null(filters) && length(filters) > 0) {
      cat("[SMART_FILTER] Standart filtre listesi uygulanıyor (AND mantığı)...\n")

      for (f in filters) {
        # MANTIK GRUBU (`{operator, children}`) YAPRAK DEĞİLDİR: yalnızca v2
        # motoru değerlendirebilir. Bu izole gövdede sessizce yaprak gibi
        # işlenip "sütun yok" dalına düşmek yerine AÇIKÇA atlanır ve kayda
        # geçer (`helpers_pk_analysis_filters.R` gövdesi aynı düğümü tipli
        # `dropped` bildirimiyle raporlar).
        if (.pk_filter_base_is_group(f)) {
          cat("[SMART_FILTER] Mantik grubu (VEYA) v1 motorunda degerlendirilemiyor, atlandi.\n")
          next
        }

        col <- f$column
        val <- f$value
        op <- f$operation %||% "exact_match"

        if (!is.null(col) && nzchar(as.character(col)[1]) && col %in% names(dt)) {
          col_vals <- dt[[col]]

          # v1 ÇOK DEĞERLİ YAPRAĞI BİLİNÇLİ OLARAK KIRPAR. Aynı sütun içi VEYA
          # v2 motorunun (`helpers_pk_filter_compile.R`) sözleşmesidir; v1 geri
          # dönüş şeridi olduğu için davranışı BİT BAZINDA sabit kalmalıdır
          # (`test-pk-v1-compatibility-contract.R` D2 bunu kilitler).
          # `helpers_pk_analysis_filters.R` içindeki gövdeyle AYNI olmalıdır.
          val_str <- as.character(val)[1]

          if (is.character(col_vals) || is.factor(col_vals)) {
            val_regex <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", val_str)
            col_vals_char <- as.character(col_vals)

            if (op == "exact_match") {
              dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
            } else if (op == "contains") {
              dt <- dt[grepl(val_regex, col_vals_char, ignore.case = TRUE), ]
            } else {
              dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
            }
          } else if (is.numeric(col_vals)) {
            val_num <- suppressWarnings(as.numeric(val_str))
            if (!is.na(val_num)) {
              if (op == "greater_than") {
                dt <- dt[col_vals > val_num, ]
              } else if (op == "less_than") {
                dt <- dt[col_vals < val_num, ]
              } else {
                dt <- dt[col_vals == val_num, ]
              }
            }
          }
        }
      }
    } else {
      if (is.null(aggregation) || !tolower(aggregation) %in% c("count", "sum", "group_by")) {
        cat(sprintf(
          "[SMART_FILTER] Ne filtre ne aggregation var. GENEL SORU olarak işleniyor - tüm veri döndürülecek (%d satır).\n",
          nrow(dt)
        ))
      } else {
        cat("[SMART_FILTER] Aggregation mevcut, filtre yok - tüm veri üzerinde aggregation yapılacak\n")
      }
    }
  }

  if (!is.null(aggregation)) {
    agg_str <- tolower(aggregation)

    if (agg_str == "count") {
      aciklama <- if (length(filters) > 0) "Filtrelenen Kayıt Sayısı" else "Toplam Kayıt Sayısı"
      return(data.frame(Sonuc = aciklama, Adet = nrow(dt)))
    } else if (agg_str == "sum") {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        sums <- lapply(num_cols, function(nc) sum(dt[[nc]], na.rm = TRUE))
        return(as.data.frame(sums))
      }
    } else if (agg_str == "group_by" && !is.null(group_col) && group_col %in% names(dt)) {
      return(as.data.frame(dt[, .N, by = group_col]))
    }
  }

  as.data.frame(dt)
}
