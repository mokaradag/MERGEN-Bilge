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
  # --- THIS IS THE FIX ---
  # Add strong SQL indicators to the initial check. If these are present,
  # we can be confident it's code, regardless of character density.
  strong_indicators <- c(
    "observeEvent\\(", "reactiveVal\\(", "shinyApp\\(", "fluidRow\\(",
    "column\\(", "actionButton\\(", "selectInput\\(", "tags\\$", "library\\(",
    "SELECT\\b.*\\bFROM\\b", "INSERT\\s+INTO\\b", "UPDATE\\b.*\\bSET\\b", "WITH\\s+RECURSIVE"
  )
  # Use ignore.case = TRUE for SQL keywords
  if (any(sapply(strong_indicators, grepl, x = text, ignore.case = TRUE))) {
    return(TRUE)
  }
  # --- END OF FIX ---

  # First, check if the text looks like a Markdown table.
  if (grepl("\\|.*\\|\\n.*-{3,}", text)) {
    return(FALSE) # It's a table, not a code block.
  }

  lines <- strsplit(text, "\n")[[1]]
  if (length(lines) == 1 && !grepl("[\\{\\};=<-]", text)) {
    return(FALSE)
  }

  total_chars <- nchar(text)
  if (total_chars < 40) {
    return(FALSE)
  }

  # Calculate the density of code-specific characters.
  code_chars_pattern <- "[\\{\\}\\(\\)<>;=<-]"
  matches <- gregexpr(code_chars_pattern, text)[[1]]
  code_char_count <- if (matches[1] == -1) 0 else length(matches)
  
  density <- code_char_count / total_chars
  return(density > 0.05)
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
  # Initialize a list to hold scores for each language
  scores <- sapply(names(LANG_MAP), function(x) 0, simplify = FALSE)
  
  # Define patterns and their corresponding weights for each language
  patterns <- list(
    r = list(
      "library\\(" = 10, "require\\(" = 10, "<-" = 8, 
      "function\\s*\\([^)]*\\)\\s*\\{" = 9,
      "ggplot\\(" = 10, "dplyr::" = 10, "tidyr::" = 10,
      "shinyApp\\(" = 12, "observeEvent\\(" = 12, "reactive\\(" = 11,
      "renderUI|renderPlot|renderTable" = 11, "\\$\\w+" = 5, "tags\\$" = 11,
      "%>%" = 9, "\\|>" = 9, "%in%" = 7, "reactiveVal\\(" = 11, 
      "#'" = 8, "\\[\\[.*\\]\\]" = 4, "\\.rds|\\.RData" = 8
    ),
    python = list(
      "def\\s+\\w+\\s*\\([^)]*\\):" = 10, "class\\s+\\w+.*:" = 10,
      "import\\s+\\w+" = 8, "from\\s+\\w+\\s+import" = 8,
      "elif\\s+.*:" = 7, "\\bif\\s+.*:\\s*$" = 5,
      "\\bfor\\s+.*:\\s*$" = 5, "\\bwhile\\s+.*:\\s*$" = 5,
      "@(app|router|property|staticmethod|classmethod)" = 10, 
      "@\\w+\\s*$" = 7, "f[\"']" = 6, "__init__|__main__|__name__" = 9,
      "\\bself\\." = 6, "\\bNone\\b|\\bTrue\\b|\\bFalse\\b" = 5,
      "print\\(" = 4, "#" = 1, "\\blen\\(|\\brange\\(|\\bstr\\(" = 5
    ),
    javascript = list(
      "console\\.(log|error|warn)" = 6, "document\\.(getElementById|querySelector)" = 8,
      "const\\s+\\w+\\s*=" = 7, "let\\s+\\w+\\s*=" = 7, "var\\s+\\w+\\s*=" = 6,
      "=>\\s*\\{?" = 5, "function\\s+\\w*\\s*\\(" = 7,
      "===|!==" = 7, "typeof\\s+" = 6,
      "(import|require).*from" = 8, "export\\s+(default|const)" = 8,
      "//" = 1, "/\\*.*\\*/" = 2, "addEventListener|querySelector" = 7,
      "\\$\\(|jQuery" = 7, "async\\s+function|await\\s+" = 8
    ),
    java = list(
      "public\\s+static\\s+void\\s+main" = 12, "System\\.out\\.println" = 8,
      "import\\s+java\\." = 9, "public\\s+class\\s+" = 10,
      "private|protected|public" = 6, "extends|implements" = 8,
      "new\\s+\\w+\\(" = 6, "@Override|@Deprecated" = 8,
      "//" = 1, "/\\*" = 1
    ),
    csharp = list(
      "using\\s+System;" = 11, "namespace\\s+\\w+" = 10,
      "public\\s+class\\s+" = 10, "Console\\.WriteLine" = 8,
      "public|private|protected|internal" = 6, "=>" = 5,
      "async\\s+Task|await\\s+" = 9, "//" = 1
    ),
    cpp = list(
      "#include\\s+<iostream>" = 11, "std::(cout|cin|endl)" = 9,
      "\\b(int|void)\\s+main\\s*\\(" = 9, "using\\s+namespace\\s+std;" = 10,
      "::|->|\\." = 5, "template\\s*<.*>" = 10, "//" = 1, "/\\*" = 1
    ),
    c = list(
      "#include\\s+<stdio\\.h>" = 12, "printf\\(" = 9, "scanf\\(" = 9,
      "\\b(int|void|char|float|double)\\s+main\\s*\\(" = 10,
      "malloc\\(|free\\(|sizeof\\(" = 8, "struct\\s+\\w+" = 8,
      "/\\*" = 1, "NULL" = 5
    ),
    php = list(
      "<\\?php" = 12, "echo\\s+" = 7, "\\$_GET|\\$_POST|\\$_SESSION" = 9,
      "\\$\\w+\\s*=" = 6, "function\\s+\\w+\\(" = 7, "->" = 5,
      "\\barray\\(|\\[\\]" = 5, "foreach\\s*\\(" = 7, "//" = 1
    ),
    bash = list(
      "#!/bin/(bash|sh)" = 12, "\\b(echo|grep|awk|sed|cut|find)\\b" = 7,
      "\\bif\\s+\\[|\\bfi\\b|\\bthen\\b" = 8, "\\s--?[a-zA-Z]+" = 5,
      "\\$\\{?\\w+\\}?|\\$\\d|\\$\\@" = 6, "\\|\\||&&" = 6, "#" = 1
    ),
    ruby = list(
      "\\bdef\\b[\\s\\S]+\\bend\\b" = 10, "puts\\s+" = 7, "require\\s+" = 8,
      "\\bclass\\s+\\w+|\\bmodule\\s+\\w+" = 9, "@\\w+|@@\\w+" = 6,
      "\\bdo\\b.*\\bend\\b" = 7, "::\\w+" = 6, "#" = 1
    ),
    go = list(
      "package\\s+main" = 12, "import\\s+\"fmt\"" = 10, "fmt\\.Print" = 9,
      "func\\s+\\w+\\(" = 9, ":=" = 7, "\\bgo\\s+\\w+\\(" = 10,
      "\\bchan\\b|\\bdefer\\b" = 8, "//" = 1
    ),
    swift = list(
      "import\\s+UIKit|import\\s+Foundation" = 11, 
      "func\\s+\\w+\\([^)]*\\)\\s*->" = 10,
      "\\b(let|var)\\s+\\w+\\s*:" = 8, "\\bclass\\s+\\w+|\\bstruct\\s+\\w+" = 9,
      "@\\w+|\\bextension\\b" = 7, "//" = 1
    ),
    matlab = list(
      "^\\s*function.*" = 11, "disp\\(|fprintf\\(" = 8, 
      "%.*" = 2, "end\\s*;?\\s*$" = 9,
      "\\bfor\\s+.*\\s*=.*" = 7, "\\.[*/]|\\.[^0-9]" = 6
    ),
    sql = list(
      "SELECT\\s+.*\\s+FROM\\s+" = 12, "INSERT\\s+INTO\\s+" = 11,
      "UPDATE\\s+.*\\s+SET\\s+" = 11, "DELETE\\s+FROM\\s+" = 11,
      "CREATE\\s+(TABLE|INDEX|VIEW)" = 12, "ALTER\\s+TABLE" = 11,
      "\\bJOIN\\b|\\bLEFT\\s+JOIN\\b|\\bINNER\\s+JOIN\\b" = 9,
      "\\bWHERE\\b" = 7, "\\bGROUP\\s+BY\\b" = 9, "\\bORDER\\s+BY\\b" = 9,
      "WITH\\s+(RECURSIVE\\s+)?\\w+\\s+AS" = 11, "UNION\\s+(ALL\\s+)?" = 9,
      "OVER\\s*\\(|PARTITION\\s+BY" = 10, "CASE\\s+WHEN" = 8,
      "--\\s*" = 2, "/\\*.*\\*/" = 2, "\\bLIMIT\\b|\\bOFFSET\\b" = 7
    ),
    html = list(
      "<!DOCTYPE\\s+html>" = 12, "<html\\b" = 11, "<head>" = 10, 
      "<body\\b" = 10, "<div\\b|<span\\b|<p\\b" = 7,
      "<script|<style" = 8, "<!--" = 6, "</\\w+>" = 5
    ),
    css = list(
      "[{};:]\\s*[a-zA-Z-]+\\s*:" = 8, "#[a-zA-Z0-9_-]+\\s*\\{" = 9,
      "\\.[a-zA-Z0-9_-]+\\s*\\{" = 9, "@media|@keyframes|@import" = 10,
      "rgb\\(|rgba\\(|#[0-9a-fA-F]{3,6}" = 7
    ),
    vbnet = list(
      "Module\\s+" = 11, "Sub\\s+Main|Sub\\s+\\w+" = 10, 
      "End\\s+(Sub|Module|Function)" = 9,
      "\\bDim\\s+\\w+\\s+As\\s+" = 8, "Console\\.WriteLine" = 7,
      "Imports\\s+System" = 9, "'" = 1
    ),
    kotlin = list(
      "fun\\s+main|fun\\s+\\w+" = 10, "\\b(val|var)\\s+\\w+:" = 8, 
      "println\\(" = 6, "\\bclass\\s+\\w+|\\bobject\\s+\\w+" = 9,
      "import\\s+\\w+" = 6, "when\\s*\\{" = 8, "//" = 1
    ),
    julia = list(
      "\\bfunction\\b[\\s\\S]+\\bend\\b" = 10, "println\\(" = 7,
      "\\busing\\s+\\w+" = 8, "\\bmodule\\s+\\w+" = 9,
      "\\b(for|if|while)\\b.*\\bend\\b" = 7, "#" = 1
    ),
    scala = list(
      "object\\s+\\w+\\s+extends\\s+App" = 11, "def\\s+main|def\\s+\\w+" = 9,
      "\\b(val|var)\\b\\s+\\w+:" = 7, "println\\(" = 6,
      "import\\s+scala\\." = 8, "=>" = 5, "//" = 1
    ),
    lisp = list(
      "\\(defun\\s+" = 11, "\\(let\\b|\\(lambda\\b" = 9, 
      "\\(format\\s+t" = 7, "\\(setq\\s+" = 7,
      ";;;?" = 2, "\\(\\w+\\s+" = 3
    ),
    fortran = list(
      "program\\s+\\w+" = 12, "implicit\\s+none" = 10, 
      "end\\s+program" = 10, "subroutine\\s+\\w+" = 9,
      "print\\s*\\*,|write\\s*\\(" = 8, "real\\s*\\*|integer\\s*\\*" = 7,
      "!" = 1
    ),
    typescript = list(
      "interface\\s+\\w+" = 11, "type\\s+\\w+\\s*=" = 11,
      ":\\s*(string|number|boolean|any|void)" = 9,
      "public\\s+\\w+\\s*:|private\\s+\\w+\\s*:|protected\\s+\\w+\\s*:" = 9,
      "<.*>\\s*\\(" = 7, "as\\s+(string|number|const)" = 7,
      "enum\\s+\\w+" = 10, "namespace\\s+\\w+" = 10,
      "//" = 1, "import.*from" = 6
    ),
    powershell = list(
      "Write-Host|Write-Output" = 10, "function\\s+\\w+\\s*\\{" = 9,
      "-(eq|ne|gt|lt|like|match)\\b" = 8, "\\$\\w+" = 4,
      "\\bparam\\s*\\(|\\[Parameter" = 9, "Get-|Set-|New-" = 7,
      "#" = 1
    )
  )

  # Iterate through each language and its patterns to calculate scores
  for (lang in names(patterns)) {
    for (pattern in names(patterns[[lang]])) {
      matches <- gregexpr(pattern, code, ignore.case = TRUE, perl = TRUE)
      num_matches <- if(matches[[1]][1] != -1) length(matches[[1]]) else 0
      # Add to the score based on the number of matches and the pattern's weight
      scores[[lang]] <- scores[[lang]] + (num_matches * patterns[[lang]][[pattern]])
    }
  }
  
  # Exclude 'text' from the scoring competition
  scores$text <- NULL
  
  # Return the name of the language with the highest score
  if (max(unlist(scores)) > 0) {
    return(names(which.max(scores)))
  }
  
  # Default to "text" if no patterns were matched
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
    code_pats <- c(
      # SQL anahtar kelimeleri
      "^\\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|WITH|EXEC|DECLARE|MERGE|TRUNCATE)\\b",
      "^\\s*(FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|GROUP|ORDER|HAVING|UNION|LIMIT|OFFSET)\\b",
      "^\\s*(SET|VALUES|INTO|ON|AND|OR|CASE|WHEN|THEN|ELSE|END|BEGIN|COMMIT|ROLLBACK|AS)\\b",
      "^\\s*(OVER\\s*\\(|PARTITION\\s+BY)",
      # Python
      "^\\s*(def |class |import |from .+ import|if .+:|elif .+:|else:|for .+:|while .+:|try:|except|finally:)",
      # R
      "^\\s*(function\\s*\\(|library\\(|require\\(|source\\()",
      "^\\s*\\w+\\s*<-\\s*",
      # Java/C#/JS/TS
      "^\\s*(public |private |protected |static |void |int |string |bool )",
      "^\\s*(var |let |const |console\\.|document\\.|window\\.)",
      # C/C++
      "^\\s*(#include|using\\s+namespace|using\\s+System)",
      # Genel kod yapıları
      "\\{\\s*$",                        # Satır sonunda {
      "^\\s*\\}\\s*;?\\s*$",             # Satır başında }
      "\\);\\s*$",                        # Satır sonunda );
      "^\\s*(--|//|#!)\\s*",             # Yorum satırları
      "^\\s*@(app|router|property|Override|staticmethod)"
    )

    # --- Güçlü doğal dil göstergeleri ---
    text_pats <- c(
      # Türkçe doğal dil kalıpları
      "^\\s*(merhaba|selam|lütfen|rica|teşekkür|bu |şu |nasıl|neden|nerede|bana|benim|bir |ve |ile |için|hakkında|aşağıda|yukarıda|optimize|düzelt|yaz|yap|kontrol|analiz|bakar)",
      # İngilizce doğal dil kalıpları
      "^\\s*(hi |hey |hello|please|can you|could you|how |what |why |where|help|i need|i want|this |here |below|above|fix|write|check|create)",
      # Soru işareti ile biten satır
      "\\?\\s*$",
      # Uzun cümle: büyük harfle başlayıp noktalama ile biten 15+ karakter
      "^[A-ZÀ-ÿĞÜŞİÖÇ][a-zà-ÿğüşıöç].{15,}[.?!:;,]\\s*$"
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