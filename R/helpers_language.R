# R/helpers_language.R

# --- Centralized Language Mapping ---
# Provides a consistent, user-friendly name for each detected language key.
LANG_MAP <- list(
  r = "R", python = "Python", javascript = "JavaScript", java = "Java", csharp = "C#",
  cpp = "C++", c = "C", php = "PHP", bash = "Bash", ruby = "Ruby", go = "Go", swift = "Swift",
  matlab = "MATLAB", sql = "SQL", html = "HTML", css = "CSS", text = "Text",
  vbnet = "Visual Basic", kotlin = "Kotlin", julia = "Julia", scala = "Scala",
  lisp = "Lisp", fortran = "Fortran", typescript = "TypeScript", powershell = "PowerShell"
)

#' Detect if a block of text is likely code
#'
#' @param text A character string to analyze.
#' @return A logical value: TRUE if the text is likely code, FALSE otherwise.
detect_code_content <- function(text) {
  if (is.null(text) || length(text) == 0 || !nzchar(trimws(text))) return(FALSE)
  text <- paste(text, collapse = "\n")

  # --- 1. Kesin kod göstergeleri (tek eşleşme yeterli) ---
  strong_indicators <- c(
    # R / Shiny
    "observeEvent\\(", "reactiveVal\\(", "reactiveValues\\(", "shinyApp\\(",
    "fluidRow\\(", "renderUI\\(", "renderPlot\\(", "tags\\$",
    "library\\(\\s*\\w+\\s*\\)", "require\\(\\s*\\w+\\s*\\)",
    "%>%", "\\|>",
    # SQL (çok-kelimeli kalıplar - tek kelime yetmez)
    "SELECT\\b[\\s\\S]+?\\bFROM\\b", "INSERT\\s+INTO\\b", "UPDATE\\b[\\s\\S]+?\\bSET\\b",
    "CREATE\\s+(TABLE|VIEW|INDEX|PROCEDURE|FUNCTION)\\b",
    "ALTER\\s+TABLE\\b", "DROP\\s+(TABLE|VIEW|INDEX)\\b",
    "\\bJOIN\\b[\\s\\S]+?\\bON\\b",
    "\\bGROUP\\s+BY\\b", "\\bORDER\\s+BY\\b",
    "WITH\\s+\\w+\\s+AS\\s*\\(",
    # Python
    "^\\s*def\\s+\\w+\\s*\\(.*\\)\\s*:", "^\\s*class\\s+\\w+.*:",
    "^\\s*import\\s+\\w+", "^\\s*from\\s+\\w+\\s+import",
    "\\bself\\.", "__init__|__main__|__name__",
    # JavaScript / TypeScript
    "console\\.(log|error|warn)\\(", "document\\.(getElementById|querySelector)\\(",
    "=>\\s*\\{", "===|!==",
    "export\\s+(default|const|function)",
    # Java / C# / C++
    "public\\s+static\\s+void\\s+main",
    "System\\.out\\.println", "Console\\.WriteLine",
    "#include\\s+<\\w+",
    "using\\s+namespace\\s+",
    # Bash
    "#!/bin/(bash|sh)",
    # PHP
    "<\\?php",
    # Go
    "package\\s+main", "fmt\\.Print",
    # HTML
    "<!DOCTYPE\\s+html>",
    # Genel yapısal göstergeler
    "function\\s*\\([^)]*\\)\\s*\\{",
    "\\bif\\s*\\(.*\\)\\s*\\{",
    "\\bfor\\s*\\(.*\\)\\s*\\{"
  )
  if (any(sapply(strong_indicators, grepl, x = text, ignore.case = TRUE, perl = TRUE))) {
    return(TRUE)
  }

  # --- 2. Markdown tablosu ise kod değil ---
  if (grepl("\\|.*\\|\\n.*-{3,}", text)) return(FALSE)

  # --- 3. Tek satır ve yapısal karakter yoksa kod değil ---
  lines <- strsplit(text, "\n")[[1]]
  if (length(lines) == 1 && !grepl("[\\{\\}\\(\\);=<>]", text)) return(FALSE)

  total_chars <- nchar(text)
  if (total_chars < 40) return(FALSE)

  # --- 4. Satır-bazlı oylama: her satırı kod / metin olarak puanla ---
  non_empty <- lines[nchar(trimws(lines)) > 0]
  if (length(non_empty) < 2) return(FALSE)

  code_votes <- sum(vapply(non_empty, function(line) {
    tl <- trimws(line)
    # Satır sonu noktalı virgül, süslü parantez, atama operatörleri
    if (grepl("[;{}]\\s*$", tl)) return(TRUE)
    # Girinti + parantezli ifade (fonksiyon çağrısı, kontrol yapısı)
    if (grepl("^\\s{2,}.*\\(.*\\)", tl)) return(TRUE)
    # Atama operatörleri
    if (grepl("<-|:=|=>|\\w+\\s*=\\s*[^=]", tl)) return(TRUE)
    # Yorum satırları (çeşitli diller)
    if (grepl("^\\s*(#(?!\\s*(\\w+\\s+){4,})|//|/\\*|--|%[^%])", tl, perl = TRUE)) return(TRUE)
    return(FALSE)
  }, logical(1)))

  code_ratio <- code_votes / length(non_empty)

  # --- 5. Karakter yoğunluğu (yedek kontrol) ---
  code_chars_pattern <- "[\\{\\}\\(\\)<>;=\\[\\]]"
  m <- gregexpr(code_chars_pattern, text)[[1]]
  code_char_count <- if (m[1] == -1) 0 else length(m)
  density <- code_char_count / total_chars

  # Oy oranı VEYA yoğunluk yeterli ise kod say
  return(code_ratio > 0.35 || density > 0.06)
}

#' Detect Programming Language
#'
#' Analyzes a string of code and scores it against a list of patterns
#' specific to various programming languages. Returns the language with the highest score.
#'
#' @param code A character string containing the code to analyze.
#' @return A character string representing the detected language key (e.g., "r", "python").
#'         Returns "text" if no language scores above zero.
detect_language <- function(code) {
  # Skor tablosunu başlat
  scores <- sapply(names(LANG_MAP), function(x) 0, simplify = FALSE)

  # ============================================================
  # Dile özgü kalıplar ve ağırlıklar
  # NOT: Jenerik yorum karakterleri (#, //) ÇIKARILDI.
  #      Her dilin sadece kendine özgü yapısal kalıpları puanlanır.
  # ============================================================
  patterns <- list(
    r = list(
      "library\\(\\s*\\w+" = 10, "require\\(\\s*\\w+" = 10,
      "<-" = 8,
      "function\\s*\\([^)]*\\)\\s*\\{" = 9,
      "ggplot\\(" = 10, "dplyr::" = 10, "tidyr::" = 10,
      "shinyApp\\(" = 12, "observeEvent\\(" = 12, "reactive\\(" = 11,
      "renderUI|renderPlot|renderTable|renderText" = 11,
      "tags\\$" = 11, "%>%" = 9, "\\|>" = 9, "%in%" = 7,
      "reactiveVal\\(|reactiveValues\\(" = 11,
      "#'\\s+" = 6, "\\[\\[.*\\]\\]" = 4,
      "\\.rds|\\.RData" = 8,
      "\\bNULL\\b" = 3, "\\bTRUE\\b|\\bFALSE\\b" = 4,
      "tryCatch\\(|withCallingHandlers\\(" = 9,
      "lapply\\(|sapply\\(|vapply\\(|tapply\\(" = 8,
      "data\\.frame\\(|tibble\\(" = 9,
      "setwd\\(|getwd\\(" = 8
    ),
    python = list(
      "def\\s+\\w+\\s*\\([^)]*\\)\\s*:" = 10, "class\\s+\\w+.*:" = 10,
      "import\\s+\\w+" = 8, "from\\s+\\w+\\s+import" = 8,
      "elif\\s+.*:" = 7,
      "@(app|router|property|staticmethod|classmethod)" = 10,
      "@\\w+\\s*$" = 5, "f[\"']\\{" = 6,
      "__init__|__main__|__name__" = 9,
      "\\bself\\." = 6, "\\bNone\\b" = 5,
      "\\blen\\(|\\brange\\(|\\bstr\\(|\\bint\\(" = 5,
      "\\bif\\s+.*:\\s*$" = 4, "\\bfor\\s+\\w+\\s+in\\s+" = 7,
      "\\bwhile\\s+.*:\\s*$" = 4,
      "print\\(" = 3, "\\bTrue\\b|\\bFalse\\b" = 4,
      "\\basync\\s+def\\b|\\bawait\\s+" = 8,
      "\\blambda\\s+" = 6,
      "\\braise\\s+\\w+" = 6, "\\bwith\\s+.*\\bas\\s+" = 6,
      "\\blist\\(|\\bdict\\(|\\btuple\\(" = 5
    ),
    javascript = list(
      "console\\.(log|error|warn)\\(" = 6,
      "document\\.(getElementById|querySelector)" = 8,
      "const\\s+\\w+\\s*=" = 7, "let\\s+\\w+\\s*=" = 7, "var\\s+\\w+\\s*=" = 6,
      "=>\\s*\\{?" = 5, "function\\s+\\w*\\s*\\(" = 6,
      "===|!==" = 7, "typeof\\s+" = 6,
      "(import|require).*from" = 8, "export\\s+(default|const)" = 8,
      "addEventListener|querySelector" = 7,
      "\\$\\(|jQuery" = 7, "async\\s+function|\\bawait\\s+" = 8,
      "window\\.|document\\." = 5,
      "new\\s+Promise\\(" = 8, "\\.then\\(|\\bcatch\\(" = 5
    ),
    java = list(
      "public\\s+static\\s+void\\s+main" = 12, "System\\.out\\.println" = 8,
      "import\\s+java\\." = 9, "public\\s+class\\s+" = 10,
      "extends|implements" = 8,
      "new\\s+\\w+\\(" = 5, "@Override|@Deprecated" = 8,
      "private\\s+\\w+\\s+\\w+\\s*;" = 7,
      "\\bthrows\\s+" = 7,
      "public|private|protected" = 4
    ),
    csharp = list(
      "using\\s+System;" = 11, "namespace\\s+\\w+" = 10,
      "public\\s+class\\s+" = 9, "Console\\.WriteLine" = 8,
      "internal" = 5, "=>" = 4,
      "async\\s+Task|\\bawait\\s+" = 9,
      "\\bvar\\s+\\w+\\s*=\\s*new\\s+" = 8,
      "\\[Serializable\\]|\\[HttpGet\\]|\\[HttpPost\\]" = 10,
      "public|private|protected" = 3
    ),
    cpp = list(
      "#include\\s+<\\w+>" = 11, "std::(cout|cin|endl|string|vector)" = 9,
      "\\b(int|void)\\s+main\\s*\\(" = 9, "using\\s+namespace\\s+std;" = 10,
      "::" = 4, "->" = 4,
      "template\\s*<.*>" = 10, "std::" = 6,
      "nullptr" = 7, "cout\\s*<<|cin\\s*>>" = 9
    ),
    c = list(
      "#include\\s+<stdio\\.h>" = 12, "#include\\s+<stdlib\\.h>" = 11,
      "printf\\(" = 9, "scanf\\(" = 9,
      "\\b(int|void|char|float|double)\\s+main\\s*\\(" = 10,
      "malloc\\(|free\\(|sizeof\\(" = 8, "struct\\s+\\w+" = 7,
      "NULL" = 4
    ),
    php = list(
      "<\\?php" = 12, "echo\\s+" = 7, "\\$_GET|\\$_POST|\\$_SESSION" = 9,
      "\\$\\w+\\s*=" = 6, "function\\s+\\w+\\(" = 6, "->" = 4,
      "\\barray\\(|\\[\\]" = 5, "foreach\\s*\\(" = 7,
      "namespace\\s+\\w+\\\\\\w+" = 9
    ),
    bash = list(
      "#!/bin/(bash|sh)" = 12,
      "\\b(echo|grep|awk|sed|cut|find|xargs|chmod|chown)\\b" = 6,
      "\\bif\\s+\\[|\\bfi\\b|\\bthen\\b|\\bdone\\b" = 8,
      "\\s--?[a-zA-Z]+" = 4,
      "\\$\\{\\w+\\}" = 7, "\\$\\(" = 5,
      "\\|\\||&&" = 5, "\\beval\\b|\\bexport\\b" = 6
    ),
    ruby = list(
      "\\bdef\\s+\\w+[\\s\\S]+?\\bend\\b" = 9, "puts\\s+" = 7,
      "require\\s+['\"]" = 8, "require_relative" = 9,
      "\\bclass\\s+\\w+|\\bmodule\\s+\\w+" = 9, "@\\w+|@@\\w+" = 6,
      "\\bdo\\s*\\|" = 8, "::\\w+" = 5, "\\.each\\b|\\.map\\b" = 7
    ),
    go = list(
      "package\\s+main" = 12, "import\\s+\"fmt\"" = 10, "fmt\\.Print" = 9,
      "func\\s+\\w+\\(" = 9, ":=" = 7, "\\bgo\\s+\\w+\\(" = 10,
      "\\bchan\\b|\\bdefer\\b" = 8, "\\bmake\\(|\\bappend\\(" = 7
    ),
    swift = list(
      "import\\s+UIKit|import\\s+Foundation|import\\s+SwiftUI" = 11,
      "func\\s+\\w+\\([^)]*\\)\\s*->" = 10,
      "\\b(let|var)\\s+\\w+\\s*:" = 8,
      "\\bclass\\s+\\w+|\\bstruct\\s+\\w+" = 8,
      "@\\w+|\\bextension\\b" = 7,
      "guard\\s+let" = 9, "\\bweak\\s+var" = 8
    ),

    # ============================================================
    # MATLAB - Sadece MATLAB'a özgü kalıplar (SQL ile çakışma YOK)
    # ============================================================
    matlab = list(
      # MATLAB fonksiyon bildirimi: function [out] = name(args) veya function name(args)
      "^\\s*function\\s+\\[?\\w+.*=\\s*\\w+\\s*\\(" = 13,
      "^\\s*function\\s+\\w+\\s*\\(" = 10,
      # MATLAB'a özgü komutlar
      "\\bdisp\\(" = 8, "\\bfprintf\\(" = 7,
      # MATLAB hücre modu (%% başlık)
      "^\\s*%%\\s+" = 6,
      # MATLAB'a özgü kontrol yapısı (elseif - Python'da elif, SQL'de yok)
      "\\belseif\\b" = 7,
      # Sadece MATLAB'da bulunan yerleşik fonksiyonlar
      "\\bnargin\\b|\\bnargout\\b" = 12,
      "\\bzeros\\(|\\bones\\(|\\blinspace\\(|\\blogspace\\(" = 10,
      "\\bsubplot\\(|\\bfigure\\(|\\bhold\\s+on" = 9,
      "\\breshape\\(|\\brepmat\\(|\\bcell\\(" = 8,
      # Eleman-bazlı operatörler (.* ./ .^ - sadece MATLAB)
      "\\.\\*|\\.\\/|\\.\\^" = 8,
      # MATLAB satır sonu noktalı virgül (çıktı bastırma)
      ";\\s*$" = 1,
      # end - çok düşük ağırlık (SQL/Ruby/Python ile çakışır)
      "\\bend\\b" = 1
    ),

    # ============================================================
    # SQL - Güçlendirilmiş kalıplar
    # ============================================================
    sql = list(
      # Çok-kelimeli bileşik kalıplar (en güvenilir)
      "SELECT\\s+.*\\s+FROM\\s+" = 14,
      "INSERT\\s+INTO\\s+" = 13,
      "UPDATE\\s+\\w+\\s+SET\\s+" = 13,
      "DELETE\\s+FROM\\s+" = 13,
      "CREATE\\s+(TABLE|VIEW|INDEX|PROCEDURE|FUNCTION|TRIGGER|SCHEMA)" = 14,
      "ALTER\\s+TABLE\\s+" = 12,
      "DROP\\s+(TABLE|VIEW|INDEX)" = 12,
      # JOIN yapıları
      "\\b(INNER|LEFT|RIGHT|FULL|CROSS)\\s+JOIN\\b" = 11,
      "\\bJOIN\\b\\s+\\w+\\s+ON\\b" = 10,
      # Gruplama ve sıralama
      "\\bGROUP\\s+BY\\b" = 10, "\\bORDER\\s+BY\\b" = 10,
      "\\bHAVING\\b" = 9,
      # CTE ve alt sorgu yapıları
      "WITH\\s+\\w+\\s+AS\\s*\\(" = 12,
      "\\bUNION\\s+(ALL\\s+)?" = 10,
      # Pencere fonksiyonları
      "OVER\\s*\\(" = 10, "PARTITION\\s+BY" = 10,
      "ROW_NUMBER\\(|RANK\\(|DENSE_RANK\\(|LEAD\\(|LAG\\(" = 10,
      # CASE ifadesi
      "CASE\\s+WHEN" = 9,
      # Veri tipleri ve kısıtlamalar
      "\\bNOT\\s+NULL\\b|\\bPRIMARY\\s+KEY\\b|\\bFOREIGN\\s+KEY\\b" = 10,
      "\\bDECLARE\\s+@" = 11, "\\bEXEC\\s+" = 9,
      "\\bBEGIN\\b[\\s\\S]+?\\bEND\\b" = 8,
      # SQL yorum
      "^\\s*--\\s+" = 3,
      # Tek kelimelik ama SQL bağlamında anlamlı
      "\\bWHERE\\b" = 5, "\\bDISTINCT\\b" = 7,
      "\\bLIMIT\\b|\\bOFFSET\\b|\\bTOP\\s+\\d+" = 8,
      "\\bCOALESCE\\(|\\bISNULL\\(|\\bNULLIF\\(" = 9,
      "\\bCAST\\(|\\bCONVERT\\(" = 8,
      "\\bCOUNT\\(|\\bSUM\\(|\\bAVG\\(|\\bMIN\\(|\\bMAX\\(" = 7,
      "\\bAS\\s+\\[?\\w+\\]?" = 4,
      "\\bIN\\s*\\(" = 4
    ),

    html = list(
      "<!DOCTYPE\\s+html>" = 12, "<html\\b" = 11, "<head>" = 10,
      "<body\\b" = 10, "<div\\b|<span\\b|<p\\b" = 6,
      "<script|<style" = 8, "<!--" = 6, "</\\w+>" = 4,
      "class=\"|id=\"" = 5
    ),
    css = list(
      "\\{[^}]*:[^}]*;[^}]*\\}" = 8,
      "#[a-zA-Z0-9_-]+\\s*\\{" = 9,
      "\\.[a-zA-Z0-9_-]+\\s*\\{" = 9,
      "@media|@keyframes|@import" = 10,
      "rgb\\(|rgba\\(|#[0-9a-fA-F]{3,6}" = 7,
      "!important" = 8, "\\bvar\\(--" = 9,
      "font-size:|margin:|padding:|display:" = 6
    ),
    vbnet = list(
      "Module\\s+" = 11, "Sub\\s+Main|Sub\\s+\\w+" = 10,
      "End\\s+(Sub|Module|Function|If|Class)" = 9,
      "\\bDim\\s+\\w+\\s+As\\s+" = 8, "Console\\.WriteLine" = 7,
      "Imports\\s+System" = 9
    ),
    kotlin = list(
      "fun\\s+main|fun\\s+\\w+" = 10, "\\b(val|var)\\s+\\w+:" = 8,
      "println\\(" = 5, "\\bclass\\s+\\w+|\\bobject\\s+\\w+" = 8,
      "import\\s+\\w+" = 5, "when\\s*\\{" = 8,
      "\\bdata\\s+class" = 10, "\\bcompanion\\s+object" = 10
    ),
    julia = list(
      "\\bfunction\\s+\\w+[\\s\\S]+?\\bend\\b" = 9, "println\\(" = 6,
      "\\busing\\s+\\w+" = 8, "\\bmodule\\s+\\w+" = 9,
      "\\bstruct\\s+\\w+" = 8, "\\bmutable\\s+struct" = 10,
      "\\b(for|if|while)\\b.*\\bend\\b" = 6
    ),
    scala = list(
      "object\\s+\\w+\\s+extends\\s+App" = 11, "def\\s+main|def\\s+\\w+" = 8,
      "\\b(val|var)\\b\\s+\\w+:" = 7, "println\\(" = 5,
      "import\\s+scala\\." = 8, "=>" = 4,
      "\\bcase\\s+class" = 10, "\\btrait\\s+\\w+" = 10
    ),
    lisp = list(
      "\\(defun\\s+" = 11, "\\(let\\b|\\(lambda\\b" = 9,
      "\\(format\\s+t" = 7, "\\(setq\\s+" = 7,
      ";;;?" = 2, "\\(\\w+\\s+" = 2, "\\(defvar\\b|\\(defmacro\\b" = 10
    ),
    fortran = list(
      "program\\s+\\w+" = 12, "implicit\\s+none" = 10,
      "end\\s+program" = 10, "subroutine\\s+\\w+" = 9,
      "print\\s*\\*,|write\\s*\\(" = 8,
      "real\\s*\\*|integer\\s*\\*" = 7,
      "\\bcall\\s+\\w+" = 7,
      "\\bINTENT\\s*\\(IN|OUT|INOUT\\)" = 10
    ),
    typescript = list(
      "interface\\s+\\w+" = 11, "type\\s+\\w+\\s*=" = 11,
      ":\\s*(string|number|boolean|any|void)" = 9,
      "public\\s+\\w+\\s*:|private\\s+\\w+\\s*:" = 8,
      "<.*>\\s*\\(" = 6, "as\\s+(string|number|const)" = 7,
      "enum\\s+\\w+" = 10, "namespace\\s+\\w+" = 9,
      "import.*from" = 5, "===|!==" = 5
    ),
    powershell = list(
      "Write-Host|Write-Output" = 10, "function\\s+\\w+\\s*\\{" = 8,
      "-(eq|ne|gt|lt|like|match)\\b" = 8, "\\$\\w+" = 3,
      "\\bparam\\s*\\(|\\[Parameter" = 9, "Get-|Set-|New-|Remove-" = 7,
      "\\[CmdletBinding\\(\\)" = 11
    )
  )

  # ============================================================
  # Puanlama döngüsü - tüm diller için kalıpları uygula
  # ============================================================
  for (lang in names(patterns)) {
    for (pattern in names(patterns[[lang]])) {
      matches <- gregexpr(pattern, code, ignore.case = TRUE, perl = TRUE)
      num_matches <- if (matches[[1]][1] != -1) length(matches[[1]]) else 0
      scores[[lang]] <- scores[[lang]] + (num_matches * patterns[[lang]][[pattern]])
    }
  }

  # ============================================================
  # Büyük/küçük harf duyarlılığı düzeltmesi:
  # R'de "<-" sadece küçük harfle yazılır ama ignore.case sorun olmaz.
  # MATLAB'ın "end" kalıbı SQL END ile çakışırsa ceza uygula.
  # ============================================================

  # --- Çakışma giderme (disambiguation) aşaması ---
  # SQL vs MATLAB: SQL güçlü sinyalleri varsa MATLAB'dan ceza kes
  sql_strong <- grepl("SELECT\\b.*\\bFROM\\b|INSERT\\s+INTO|UPDATE\\b.*\\bSET\\b|CREATE\\s+(TABLE|VIEW)|GROUP\\s+BY|ORDER\\s+BY|\\bJOIN\\b.*\\bON\\b",
                       code, ignore.case = TRUE, perl = TRUE)
  if (sql_strong) {
    # SQL net ise MATLAB skorunu bastır
    scores$matlab <- as.integer(scores$matlab * 0.2)
  }

  # R vs Python: "<-" R'ye özgüdür, "self." Python'a özgüdür
  has_r_assign  <- grepl("<-", code, fixed = TRUE)
  has_py_self   <- grepl("\\bself\\.", code, perl = TRUE)
  if (has_r_assign && !has_py_self) {
    scores$python <- as.integer(scores$python * 0.7)
  }
  if (has_py_self && !has_r_assign) {
    scores$r <- as.integer(scores$r * 0.7)
  }

  # JavaScript vs TypeScript: Tip anotasyonları varsa TS'yi tercih et
  has_type_annot <- grepl(":\\s*(string|number|boolean|any|void)\\b", code, perl = TRUE)
  if (has_type_annot && scores$typescript > 0 && scores$javascript > 0) {
    scores$javascript <- as.integer(scores$javascript * 0.6)
  }

  # Java vs C#: System.out vs Console.WriteLine ile ayır
  if (grepl("System\\.out\\.", code) && scores$csharp > 0) {
    scores$csharp <- as.integer(scores$csharp * 0.5)
  }
  if (grepl("Console\\.Write", code) && scores$java > 0) {
    scores$java <- as.integer(scores$java * 0.5)
  }

  # C vs C++: std:: veya iostream varsa C'yi bastır
  if (grepl("std::|iostream|cout|cin", code) && scores$c > 0) {
    scores$c <- as.integer(scores$c * 0.3)
  }

  # ============================================================
  # Sonuç: En yüksek puanlı dili döndür
  # ============================================================
  scores$text <- NULL

  # which.max() liste üzerinde güvenilir değildir; sayısal vektöre indirgenir.
  puanlar <- unlist(scores, use.names = TRUE)
  puanlar <- suppressWarnings(as.numeric(puanlar))
  names(puanlar) <- names(scores)
  puanlar[is.na(puanlar)] <- 0

  if (length(puanlar) && max(puanlar) > 0) {
    return(names(puanlar)[which.max(puanlar)])
  }

  return("text")
}

#' Kullanıcı Mesajındaki Metin ve Kod Kısımlarını Ayır
#'
#' Backtick kullanmadan yapıştırılan kod içeren kullanıcı mesajlarını analiz eder.
#' Metin kısmını ve kod kısmını ayrı ayrı döndürür.
#'
#' @param text Analiz edilecek karakter dizisi.
#' @return Eğer ayrım yapılabiliyorsa list(text_before, code, text_after), aksi halde NULL.
split_text_and_code <- function(text) {
  # Backtick varsa normal ayrıştırıcıya bırak
  if (grepl("```", text, fixed = TRUE)) return(NULL)

  lines <- strsplit(text, "\n")[[1]]
  if (length(lines) <= 2) return(NULL)

  # Her satırı puanla: kod satırı mı değil mi?
  line_is_code <- vapply(lines, function(line) {
    trimmed <- trimws(line)
    if (nchar(trimmed) == 0) return(NA) # Boş satır = nötr

	# --- Güçlü kod göstergeleri (satır bazında) ---
    # NOT: Yalın İngilizce ile çakışan kelimeler (AND, OR, ON, AS, SET, END)
    #      buradan çıkarıldı. Sadece bağlam içinde anlamlı olan kalıplar var.
    code_pats <- c(
      # SQL - sadece bileşik/bağlamsal kalıplar (yalın kelimeler YOK)
      "^\\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|EXEC|DECLARE|MERGE|TRUNCATE)\\b",
      "^\\s*FROM\\s+[\\[\\w]",               # FROM tablo_adi veya FROM [tablo]
      "^\\s*WHERE\\s+\\w+\\s*(=|<|>|IN|LIKE|IS|BETWEEN)\\b",  # WHERE kolon = deger
      "^\\s*(INNER|LEFT|RIGHT|FULL|CROSS)\\s+JOIN\\b",
      "^\\s*JOIN\\s+\\w+\\s+ON\\b",           # JOIN tablo ON
      "^\\s*(GROUP|ORDER)\\s+BY\\b",
      "^\\s*HAVING\\b",
      "^\\s*SET\\s+\\w+\\s*=",                # SET kolon = deger (yalın SET değil)
      "^\\s*VALUES\\s*\\(",                   # VALUES (
      "^\\s*INTO\\s+\\w+",                    # INTO tablo
      "^\\s*AND\\s+\\w+\\s*(=|<|>|IN|LIKE|IS|BETWEEN)\\b",  # AND kolon = deger
      "^\\s*OR\\s+\\w+\\s*(=|<|>|IN|LIKE|IS|BETWEEN)\\b",   # OR kolon = deger
      "^\\s*CASE\\s+WHEN\\b",                # CASE WHEN (yalın CASE değil)
      "^\\s*(OVER\\s*\\(|PARTITION\\s+BY)",
      "^\\s*WITH\\s+\\w+\\s+AS\\s*\\(",      # CTE: WITH isim AS (
      "^\\s*BEGIN\\b|^\\s*END\\s*;?\\s*$",    # BEGIN...END blok yapısı
      "^\\s*COMMIT\\b|^\\s*ROLLBACK\\b",
      # Python
      "^\\s*(def |class |import |from .+ import|if .+:|elif .+:|else:|for .+:|while .+:|try:|except|finally:)",
      "^\\s*@\\w+",                           # Python dekoratörleri
      # R
      "^\\s*(function\\s*\\(|library\\(|require\\(|source\\()",
      "^\\s*\\w+\\s*<-\\s*",
      # Java/C#/JS/TS
      "^\\s*(public |private |protected |static |void |int |string |bool )",
      "^\\s*(var |let |const |console\\.|document\\.|window\\.)",
      # C/C++
      "^\\s*#include\\b",
      "^\\s*#define\\b",
      # Bash
      "^\\s*#!/",
      # PHP
      "^\\s*<\\?php",
      # Genel yapısal satırlar
      "^\\s*(return|throw|catch|switch|break|continue)\\b\\s*[({;]?",
      "^\\s*\\}\\s*(else|catch|finally)?",
      "[;{}]\\s*$"                            # Satır sonu ; veya { veya }
    )

	# --- Güçlü metin göstergeleri (satır bazında) ---
    text_pats <- c(
      # Türkçe cümle yapıları
      "\\b(bir|bu|şu|ve|ile|için|olan|gibi|ancak|fakat|çünkü|ama|daha|nasıl|neden|lütfen|merhaba|selam)\\b",
      # İngilizce cümle yapıları
      "\\b(the|this|that|these|those|which|where|when|because|however|therefore|please|hello|could|would|should)\\b",
      "\\b(I|you|we|they|he|she|it|is|are|was|were|have|has|had|will|can|may|might|shall)\\b",
      # Soru kalıpları
      "\\?\\s*$",
      # Uzun doğal dil cümleleri (5+ kelime, kod karakteri az)
      "^\\s*(\\w+\\s+){5,}\\w+[.!?]?\\s*$",
      # Madde işareti ile başlayan metin
      "^\\s*[-*\U2022]\\s+[A-Za-zÇçĞğİıÖöŞşÜü]",
      # Numaralı liste
      "^\\s*\\d+[.):]\\s+[A-Za-zÇçĞğİıÖöŞşÜü]",
      # Sadece harf ve boşluktan oluşan satır (noktalama hariç)
      "^[A-Za-zÇçĞğİıÖöŞşÜü\\s,.:;!?'\"()-]+$"
    )

    is_code <- any(vapply(code_pats, grepl, logical(1), x = trimmed, ignore.case = TRUE, perl = TRUE))
    is_text <- any(vapply(text_pats, grepl, logical(1), x = trimmed, ignore.case = TRUE, perl = TRUE))

    if (is_code && !is_text) return(TRUE)
    if (is_text && !is_code) return(FALSE)

    # Belirsiz - kod karakter yoğunluğuna bak
    code_chars <- nchar(gsub("[^\\{\\}\\(\\)<>;=\\[\\]\\|]", "", trimmed))
    if (code_chars / max(nchar(trimmed), 1) > 0.08) return(TRUE)
    return(FALSE)
  }, logical(1), USE.NAMES = FALSE)

  # Anlamlı (NA olmayan) satırları kontrol et
  non_na_idx <- which(!is.na(line_is_code))
  if (length(non_na_idx) < 2) return(NULL)
  if (all(line_is_code[non_na_idx]))  return(NULL) # Tamamı kod
  if (all(!line_is_code[non_na_idx])) return(NULL) # Tamamı metin

  # İlk kod satırını bul
  first_code_idx <- min(which(!is.na(line_is_code) & line_is_code == TRUE))

  # Eğer ilk satır zaten kod ise ayırma yapma (tamamı kod muamelesi)
  first_non_na <- min(non_na_idx)
  if (first_code_idx == first_non_na) return(NULL)

  # Sınırı belirle: ilk kod satırından geriye doğru bitişik kod satırlarını dahil et
  boundary <- first_code_idx
  if (boundary > 1) {
    for (j in seq(boundary - 1, 1, by = -1)) {
      if (is.na(line_is_code[j])) next            # Boş satır, atla
      if (isTRUE(line_is_code[j])) {
        boundary <- j                               # Bitişik kod satırı
      } else {
        break                                        # Metin satırına ulaştık, dur
      }
    }
  }

  # Sınır çok erken ise ayıramayız
  if (boundary <= 1) return(NULL)

  # Metin ve kod parçalarını oluştur
  text_before <- trimws(paste(lines[1:(boundary - 1)], collapse = "\n"))
  code_part   <- trimws(paste(lines[boundary:length(lines)], collapse = "\n"))

  # Parçaların anlamlı uzunlukta olduğunu doğrula
  if (nchar(text_before) < 3 || nchar(code_part) < 10) return(NULL)

  list(
    text_before = text_before,
    code        = code_part,
    text_after  = ""
  )
}