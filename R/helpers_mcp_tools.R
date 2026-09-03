# ==============================================================================
# Dosya Yolu: R/helpers_mcp_tools.R
# Açıklama: MCP araçları, dosya çözümleme, tablo okuma ve analiz yardımcıları.
#           Worker bağlamlarında çalışabilmesi için kendi helper ortamını kullanır.
# ==============================================================================

# MCP bootstrap/source-order yardımcıları ayrı dosyada tutulur.
# Bu dosya yalnızca açık manifest sırası doğruysa yüklenmelidir.
if (!exists("mcp_tools_bootstrap_ready", mode = "function", inherits = TRUE) ||
    !isTRUE(mcp_tools_bootstrap_ready())) {
  stop(
    "MCP araçları yükleme sırası hatalı: R/helpers_mcp_bootstrap.R önce yüklenmeli ve başarılı doğrulama yapmalıdır.",
    call. = FALSE
  )
}

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {
  stop("MCP helper ortamı eksik.", call. = FALSE)
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) ||
    !isTRUE(mcp_tools_bootstrap_ready())) {
  stop("MCP bootstrap helper sözleşmesi eksik.", call. = FALSE)
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

# Bu helper ailesi R/helpers_mcp_schema_helpers.R içinde tanımlıdır.
# Geriye dönük uyumluluk için dotted alias korunur.
.normalize_args <- helpers_mcp_tools$normalize_args
 
# ==================================
# Tool 6: get_distinct_values
# ==================================
helpers_mcp_tools$get_distinct_values <- function(file_name, column, limit = 50, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error))
  
  if (is.null(column) || !nzchar(column)) return(list(error = "column parametresi boş"))

  path <- res$path
  dt <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)
  
  if (inherits(dt, "error")) return(list(error = sprintf("Dosya okunamadı: %s", dt$message)))

  if (!(column %in% names(dt))) {
    return(list(error = sprintf("Sütun '%s' bulunamadı. Mevcut: %s", column, paste(names(dt), collapse=", "))))
  }

  vals <- unique(dt[[column]])
  vals <- vals[!is.na(vals)]
  count <- length(vals)
  
  # Return top N
  shown_vals <- head(sort(vals), limit)
  
  display_name <- res$display %||% basename(path)
  
  msg <- paste0(
    "### Benzersiz Değerler: ", column, " (", display_name, ")\n",
    "- **Toplam Benzersiz Sayı:** ", count, "\n",
    "- **Listelenen (İlk ", length(shown_vals), "):** ", paste(shown_vals, collapse = ", ")
  )
  
  if (count > limit) {
    msg <- paste0(msg, "\n\n_(Liste çok uzun olduğu için ilk ", limit, " kayıt gösterildi. Tam liste için SQL kullanabilirsiniz.)_")
  }
  
  list(result = msg)
}

# ============================
# Tool router
# ============================
helpers_mcp_tools$execute_parsed_tool <- function(tc, session = NULL) {
  fn   <- tc$function_name %||% tc$name %||% tc$tool %||% tc$action
  args <- helpers_mcp_tools$normalize_args(tc$arguments %||% tc$parameters %||% list())

  if (is.null(fn) || !nzchar(fn)) return(list(error = "Araç adı boş"))

	switch(tolower(fn),
	  "analyze_uploaded_file"   = helpers_mcp_tools$analyze_uploaded_file(args$file_name, session),
	  "get_column_statistics"   = helpers_mcp_tools$get_column_statistics(args$file_name, args$column, session),
	  "get_distinct_values"     = helpers_mcp_tools$get_distinct_values(args$file_name, args$column, args$limit %||% 50, session),
	  "get_column_stats"        = helpers_mcp_tools$get_column_statistics(args$file_name, args$column, session),
	  "sql_query_uploaded_file" = helpers_mcp_tools$sql_query_uploaded_file(args$file_name, args$sql, session),
	  "analyze_and_visualize"   = helpers_mcp_tools$analyze_and_visualize(
		file_name      = args$file_name,
		analysis_type  = args$analysis_type %||% "summary",
		filter_column  = args$filter_column,
		filter_value   = args$filter_value,
		group_column   = args$group_column,
		stat_column    = args$stat_column,
		stat_function  = args$stat_function %||% "mean",
		chart_type     = args$chart_type,
		session        = session
	  ),
	  "prepare_chart_data"      = helpers_mcp_tools$prepare_chart_data(
		file_name   = args$file_name,
		chart_type  = args$chart_type,
		x           = args$x %||% args$xlabel %||% args$x_col,
		y           = args$y %||% args$ylabel %||% args$y_col,
		group       = args$group %||% args$color %||% args$hue,
		agg         = args$agg,
		bins        = args$bins,
		top_n       = args$top_n,
		stack       = args$stack,        # Türkçe yorum: Yığınlama modu (normal/percent)
		donut       = args$donut,        # Türkçe yorum: Pasta grafiğini halka yap
		orientation = args$orientation,  # Türkçe yorum: Bar grafiği yönü (v/h)
		smooth      = args$smooth,       # Türkçe yorum: Çizgi yumuşatma
		filter_sql  = args$filter_sql,
		limit       = args$limit %||% 5000,
		session     = session
	  ),
	  {
		list(error = sprintf("Bilinmeyen araç: %s", fn))
	  }
	)
}

# ============================
# OpenAI tools schema
# ============================
helpers_mcp_tools$get_openai_tools <- function(session = NULL) {
  list(
    tools = list(
      list(
        type = "function",
        `function` = list(
          name = "analyze_uploaded_file",
          description = "Yüklü Excel dosyasının temel özetini çıkarır (satır, sütun, sütun adları, sayısal özet).",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string",
                               description = "Sohbetteki dosya jetonu (file_123...) veya gerçek dosya adı (dummy.xlsx).")
            ),
            required = list("file_name")
          )
        )
      ),
      list(
        type = "function",
        `function` = list(
          name = "get_column_statistics",
          description = "Belirli bir sütunun istatistiklerini döndürür (numeric: ort, medyan, min, max; categorical: frekans).",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya jetonu veya adı."),
              column    = list(type = "string", description = "İstatistikleri istenen sütun adı.")
            ),
            required = list("file_name", "column")
          )
        )
      ),
	  list(
        type = "function",
        `function` = list(
          name = "sql_query_uploaded_file",
          description = "SQL ile filtreleme, sıralama, gruplama ve 'Top N' listeleme yapar. Sıralama (ORDER BY) ve listeleme soruları için bunu kullan. Tablo adı: t.",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya jetonu veya adı."),
              sql       = list(type = "string", description = "DuckDB uyumlu SQL; tablo adı 't'. Örnek: SELECT * FROM t ORDER BY Age DESC LIMIT 10")
            ),
            required = list("file_name", "sql")
          )
        )
      ),
	  list(
        type = "function",
        `function` = list(
          name = "get_distinct_values",
          description = "Bir sütundaki benzersiz (unique) değerleri listeler. Filtreleme yapmadan önce kategori isimlerini öğrenmek için kullan.",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya adı."),
              column    = list(type = "string", description = "Benzersiz değerleri istenen sütun."),
              limit     = list(type = "integer", description = "Maksimum kaç değer dönsün (varsayılan 50).")
            ),
            required = list("file_name", "column")
          )
        )
      ),
      # Türkçe: YENİ - R-First yaklaşımı ile filtrelenmiş analiz ve grafik
      list(
        type = "function",
        `function` = list(
          name = "analyze_and_visualize",
          description = paste0(
            "FİLTRELENMİŞ İSTATİSTİK VE GRAFİK için bu aracı kullan! ",
            "Kullanıcı belirli bir gruba/kategoriye göre ortalama, toplam vb. istiyorsa bu araç ZORUNLU. ",
            "Örnek: 'IT departmanının ortalama maaşı', 'Erkeklerin çalışma saati toplamı'. ",
            "R tarafından GERÇEK hesaplama yapılır, AI değer UYDURAMAZ!"
          ),
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya adı"),
              analysis_type = list(
                type = "string",
                description = paste0(
                  "Analiz tipi: ",
                  "'summary' (genel özet), ",
                  "'filtered_stats' (filtrelenmiş tek istatistik), ",
                  "'grouped_stats' (gruplandırılmış istatistik), ",
                  "'chart' (sadece grafik)"
                )
              ),
              filter_column = list(type = "string", description = "Filtreleme yapılacak sütun (örn: 'Departman', 'Cinsiyet')"),
              filter_value = list(type = "string", description = "Filtreleme değeri (örn: 'IT', 'Erkek')"),
              group_column = list(type = "string", description = "Gruplama sütunu (grouped_stats için). Örn: 'Departman'"),
              stat_column = list(type = "string", description = "İstatistik hesaplanacak sayısal sütun (örn: 'Maas', 'CalismaSaati')"),
              stat_function = list(type = "string", description = "İstatistik fonksiyonu: 'mean', 'sum', 'count', 'median', 'min', 'max'"),
              chart_type = list(type = "string", description = "Grafik eklensin mi? 'bar', 'pie', 'line', 'area', 'scatter', 'pareto', 'hist'. Boş bırakırsan grafik çizilmez.")
            ),
            required = list("file_name", "analysis_type")
          )
        )
      ),
	  list(
        type = "function",
        `function` = list(
          name = "prepare_chart_data",
          description = paste0(
            "GENEL GRAFİK ÇİZER (filtresiz). Dosyanın TAMAMINI görselleştirir. ",
            "Eksenleri OTOMATİK seçer. Sadece file_name ve chart_type ver. ",
            "NOT: Filtrelenmiş grafik istiyorsan analyze_and_visualize kullan!"
          ),
          parameters = list(
            type = "object",
            properties = list(
              file_name  = list(type = "string", description = "Dosya adı (örn: 'veri.xlsx')"),
              chart_type = list(type = "string", description = "Grafik türü: 'hist', 'bar', 'pie', 'donut', 'line', 'area', 'scatter', 'pareto'"),
              x          = list(type = "string", description = "X ekseni sütunu (OPSİYONEL - boş bırakırsan otomatik seçilir)"),
              y          = list(type = "string", description = "Y ekseni sütunu (OPSİYONEL). Çoklu seri için: 'Col1,Col2'"),
              group      = list(type = "string", description = "Gruplama sütunu (OPSİYONEL)"),
              agg        = list(type = "string", description = "Agregasyon: 'sum', 'mean', 'count' (OPSİYONEL - pie/bar için otomatik eklenir)"),
              bins       = list(type = "integer", description = "Histogram kutu sayısı (OPSİYONEL)"),
              top_n      = list(type = "integer", description = "En yüksek N kayıt (OPSİYONEL - pie için otomatik 10)"),
              stack      = list(type = "string", description = "Yığınlama: 'normal' veya 'percent' (OPSİYONEL)"),
              donut      = list(type = "boolean", description = "Pasta yerine halka (OPSİYONEL)"),
              orientation = list(type = "string", description = "Bar yönü: 'v' veya 'h' (OPSİYONEL)"),
              smooth     = list(type = "boolean", description = "Çizgi yumuşatma (OPSİYONEL)"),
              filter_sql = list(type = "string", description = "SQL WHERE filtresi (OPSİYONEL, tercih: analyze_and_visualize kullan)"),
              limit      = list(type = "integer", description = "Maksimum satır (OPSİYONEL)")
            ),
            required = list("file_name", "chart_type")
          )
        )
      )
    )
  )
}

# ============================
# Tool-use instruction prompt
# ============================
# Türkçe: Bu prompt TÜM modellere gönderilir. Açık ve model-agnostik olmalı.
# file_schema parametresi ile dosya şeması da eklenebilir.
helpers_mcp_tools$get_mcp_tools_prompt <- function(file_schema = NULL) {
  # Dosya şeması varsa başta ekle
  schema_section <- ""
  if (!is.null(file_schema) && nzchar(file_schema)) {
    schema_section <- paste0(
      "# \U0001F4CA YÜKLÜ DOSYA BİLGİSİ\n\n",
      file_schema, "\n\n",
      "---\n\n",
      "**ÖNEMLİ:** Yukarıdaki şemada gördüğün GERÇEK sütun isimlerini kullan!\n",
      "Kullanıcı Türkçe terim kullanırsa, şemadaki İngilizce karşılığını bul.\n",
      "Örnek: Kullanıcı 'departman' derse \U2192 şemada 'Department' sütununu kullan.\n\n",
      "---\n\n"
    )
  }

  paste0(
    schema_section,
    "# VERİ ANALİZİ VE GRAFİK ARAÇLARI KULLANIM KILAVUZU\n\n",

    "Sen bir Excel/CSV veri analisti asistanısın. Araçları ZORUNLU olarak kullanmalısın.\n",
    "ASLA kendi başına istatistik HESAPLAMA veya değer UYDURMA! Tüm hesaplamalar R tarafından yapılır.\n\n",

    "## \U000026A0\U0000FE0F SÜTUN İSİMLERİ İÇİN KRİTİK KURAL:\n",
    "1. Yukarıdaki dosya şemasında GERÇEK sütun isimlerini gör\n",
    "2. Kullanıcının Türkçe terimi ile şemadaki İngilizce sütunu eşleştir\n",
    "3. Araç çağrılarında SADECE şemadaki gerçek sütun isimlerini kullan\n",
    "4. Şemada olmayan sütun ismi KULLANMA - hata alırsın!\n\n",

    "## KRİTİK KURAL: HANGİ ARACI NE ZAMAN KULLAN?\n\n",

    "### \U00000031\U0000FE0F\U000020E3 FİLTRELENMİŞ İSTATİSTİK İSTENİYORSA \U2192 `analyze_and_visualize`\n",
    "Kullanıcı belirli bir kategoriye göre ortalama, toplam, sayı istiyorsa BU ARACI KULLAN!\n\n",

    "**Örnekler:**\n",
    "- 'IT departmanının ortalama maaşı' \U2192 analyze_and_visualize(filter_column='Department', filter_value='IT', stat_function='mean')\n",
    "- 'Erkeklerin toplam çalışma saati' \U2192 analyze_and_visualize(filter_column='Gender', filter_value='Male', stat_function='sum')\n",
    "- 'Departman bazında ortalama maaş' \U2192 analyze_and_visualize(analysis_type='grouped_stats', group_column='Departman', stat_function='mean')\n",
    "- 'Satış ekibinin performans grafiği' \U2192 analyze_and_visualize(filter_column='Departman', filter_value='Satış', chart_type='bar')\n\n",
 
    "### \U00000032\U0000FE0F\U000020E3 GENEL GRAFİK İSTENİYORSA (filtresiz) \U2192 `prepare_chart_data`\n",
    "Tüm veriyi görselleştirmek için bu aracı kullan. Eksenler OTOMATİK seçilir.\n\n",
 
    "**Örnekler:**\n",
    "- 'histogram çiz' \U2192 prepare_chart_data(chart_type='hist')\n",
    "- 'bar grafiği' \U2192 prepare_chart_data(chart_type='bar')\n",
    "- 'pasta grafiği' \U2192 prepare_chart_data(chart_type='pie')\n",
    "- 'çizgi grafiği' \U2192 prepare_chart_data(chart_type='line')\n",
    "- 'scatter plot' \U2192 prepare_chart_data(chart_type='scatter')\n\n",
 
    "### \U00000033\U0000FE0F\U000020E3 SQL SORGUSU GEREKİYORSA \U2192 `sql_query_uploaded_file`\n",
    "Karmaşık filtreleme, sıralama, gruplama için SQL kullan. Tablo adı: 't'\n\n",
 
    "**Örnekler:**\n",
    "- 'En yüksek maaşlı 10 kişi' \U2192 sql_query_uploaded_file(sql='SELECT * FROM t ORDER BY Maas DESC LIMIT 10')\n",
    "- '2023 yılı kayıtları' \U2192 sql_query_uploaded_file(sql=\"SELECT * FROM t WHERE Yil = 2023\")\n\n",
 
    "### \U00000034\U0000FE0F\U000020E3 SÜTUN DEĞERLERİNİ ÖĞRENMEK İÇİN \U2192 `get_distinct_values`\n",
    "Hangi kategoriler var bilmiyorsan önce bu aracı çağır.\n\n",
 
    "## GRAFİK TÜRLERİ SÖZLÜĞÜ:\n",
    "| Kullanıcı Terimi | chart_type |\n",
    "|------------------|------------|\n",
    "| histogram, dağılım | 'hist' |\n",
    "| bar, çubuk, sütun | 'bar' |\n",
    "| pasta, pie | 'pie' |\n",
    "| halka, donut | 'donut' |\n",
    "| çizgi, line, trend | 'line' |\n",
    "| alan, area | 'area' |\n",
    "| scatter, saçılım | 'scatter' |\n",
    "| pareto | 'pareto' |\n\n",

    "## GRAFİK TÜRÜ SEÇİMİ İÇİN EK KURALLAR:\n",
    "- Kullanıcı 'çizgi grafiği' diyorsa ASLA 'scatter' seçme; chart_type='line' kullan.\n",
    "- 'scatter' sadece iki sayısal sütun arasındaki ilişki/korelasyon için kullanılmalı.\n",
    "- Kullanıcı 'alan grafiği' diyorsa chart_type='area' kullan.\n",
    "- Kullanıcı 'pareto' diyorsa chart_type='pareto' kullan.\n\n",

    "## ZORUNLU KURALLAR:\n",
    "1. \U0000274C ASLA kendi başına değer UYDURMA! Araç kullan.\n",
    "2. \U0000274C ASLA sütun adı TAHMIN ETME! Araç otomatik seçer veya get_distinct_values ile öğren.\n",
    "3. \U00002705 Filtrelenmiş istatistik = analyze_and_visualize\n",
    "4. \U00002705 Genel grafik = prepare_chart_data\n",
    "5. \U00002705 Her grafik isteği için EN AZ BİR araç çağır\n",
    "6. \U00002705 Birden fazla grafik istenirse birden fazla araç çağır\n\n",
 
    "## ARAÇ ÇAĞIRMA FORMATI:\n",
    "Her araç çağrısı şu formatta olmalı:\n",
    "```json\n",
    "{\"name\": \"araç_adı\", \"arguments\": {\"param1\": \"değer1\", \"param2\": \"değer2\"}}\n",
    "```\n\n",
 
    "ŞİMDİ kullanıcının talebine göre UYGUN ARACI ÇAĞıR!"
  )
}

# Lightweight SQL extractor (so plain SELECT blocks are still executed)
helpers_mcp_tools$extract_sql_from_text <- function(text) {
  if (is.null(text) || !nzchar(text)) return(NULL)

  # Prefer fenced sql blocks
  block_rgx <- "```sql\\s*([\\s\\S]*?)```"
  m <- regexpr(block_rgx, text, perl = TRUE)
  if (m[1] != -1) {
    sql <- regmatches(text, m)[1]
    sql <- gsub("^```sql", "", sql)
    sql <- gsub("```$", "", sql)
    return(trimws(sql))
  }

  # Fallback: first SELECT ... pattern
  plain_sel <- regexpr("(?is)select\\s+[\\s\\S]+?($|;)", text, perl = TRUE)
  if (plain_sel[1] != -1) {
    sql <- regmatches(text, plain_sel)[1]
    sql <- sub(";+$", "", sql)
    return(trimws(sql))
  }

  NULL
}

# ============================
# Parse textual tool calls
# ============================
helpers_mcp_tools$parse_tool_calls_from_text <- function(text) {
  if (is.null(text) || !nzchar(text)) return(list())
  out <- list()

  # 1) <tool_call> ... </tool_call>
  tc_blocks <- gregexpr("<tool_call>(.*?)</tool_call>", text, perl = TRUE)
  if (tc_blocks[[1]][1] != -1) {
    blocks <- regmatches(text, tc_blocks)[[1]]
    blocks <- gsub("^<tool_call>|</tool_call>$", "", blocks)
    for (blk in blocks) {
      try({
        obj  <- jsonlite::fromJSON(blk, simplifyVector = FALSE)
        fn   <- obj$name %||% obj$tool %||% obj$action
        args <- obj$arguments %||% obj$parameters %||% list()
        if (is.character(args)) {
          args <- tryCatch(jsonlite::fromJSON(args, simplifyVector = FALSE), error = function(e) list())
        }
        out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
      }, silent = TRUE)
    }
  }

  # 2) Inline JSON {"name|tool|action": "...", "arguments|parameters": {...}}
  json_pat <- paste0(
    "\\{\\s*\"(tool|name|action)\"\\s*:\\s*\"[^\"]+\"[\\s\\S]*?",
    "\"(arguments|parameters)\"\\s*:\\s*\\{[\\s\\S]*?\\}\\s*\\}"
  )
  rgx <- gregexpr(json_pat, text, perl = TRUE)
  if (rgx[[1]][1] != -1) {
    objs <- regmatches(text, rgx)[[1]]
    for (o in objs) {
      try({
        obj  <- jsonlite::fromJSON(o, simplifyVector = FALSE)
        fn   <- obj$name %||% obj$tool %||% obj$action
        args <- obj$arguments %||% obj$parameters %||% list()
        if (is.character(args)) {
          args <- tryCatch(jsonlite::fromJSON(args, simplifyVector = FALSE), error = function(e) list())
        }
        out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
      }, silent = TRUE)
    }
  }

  # 3) Whole message is JSON
  if (length(out) == 0) {
    try({
      obj <- jsonlite::fromJSON(text, simplifyVector = FALSE)
      if (is.list(obj) && (!is.null(obj$name) || !is.null(obj$tool) || !is.null(obj$action))) {
        fn   <- obj$name %||% obj$tool %||% obj$action
        args <- obj$arguments %||% obj$parameters %||% list()
        if (is.character(args)) {
          args <- tryCatch(jsonlite::fromJSON(args, simplifyVector = FALSE), error = function(e) list())
        }
        out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
      }
    }, silent = TRUE)
  }

  # 4) Plain SQL without explicit tool markup
  if (length(out) == 0) {
    sql_candidate <- helpers_mcp_tools$extract_sql_from_text(text)
    if (!is.null(sql_candidate) && nzchar(sql_candidate)) {
      out[[length(out) + 1]] <- list(
        function_name = "sql_query_uploaded_file",
        arguments = list(sql = sql_candidate)
      )
    }
  }
  
  out
}

# ============================
# Public wrappers (used by global.R)
# ============================
get_openai_tools              <- function(session = NULL) helpers_mcp_tools$get_openai_tools(session)
get_mcp_tools_prompt          <- function(file_schema = NULL) helpers_mcp_tools$get_mcp_tools_prompt(file_schema)
extract_mcp_file_schema       <- function(file_name, session = NULL) helpers_mcp_tools$extract_mcp_file_schema(file_name, session)
find_matching_column          <- function(search_term, available_columns, context = NULL) helpers_mcp_tools$find_matching_column(search_term, available_columns, context)
parse_tool_calls_from_text    <- function(x)              helpers_mcp_tools$parse_tool_calls_from_text(x)
execute_parsed_tool           <- function(tc, session=NULL) helpers_mcp_tools$execute_parsed_tool(tc, session)
register_session_file         <- function(session, token, path, nm=NULL) helpers_mcp_tools$register_uploaded_file(session, token, path, nm)
reset_session_file_registry   <- function(session = NULL) helpers_mcp_tools$reset_session_file_registry(session)
environment(helpers_mcp_tools$analyze_uploaded_file)   <- helpers_mcp_tools
environment(helpers_mcp_tools$get_column_statistics)   <- helpers_mcp_tools
environment(helpers_mcp_tools$sql_query_uploaded_file) <- helpers_mcp_tools
environment(helpers_mcp_tools$prepare_chart_data)      <- helpers_mcp_tools
environment(helpers_mcp_tools$analyze_and_visualize)   <- helpers_mcp_tools
environment(helpers_mcp_tools$resolve_file_argument)   <- helpers_mcp_tools
environment(helpers_mcp_tools$normalize_excel_path)    <- helpers_mcp_tools
environment(helpers_mcp_tools$safe_read_excel_table)   <- helpers_mcp_tools
environment(helpers_mcp_tools$safe_read_table_generic) <- helpers_mcp_tools
environment(helpers_mcp_tools$get_default_file_name)   <- helpers_mcp_tools
environment(helpers_mcp_tools$auto_file_name)          <- helpers_mcp_tools
environment(helpers_mcp_tools$extract_mcp_file_schema) <- helpers_mcp_tools
environment(helpers_mcp_tools$find_matching_column)    <- helpers_mcp_tools