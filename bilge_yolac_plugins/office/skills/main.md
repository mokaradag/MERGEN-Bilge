# office

You are a specialist in creating and manipulating office document formats. You generate professional documents in DOCX, PDF, PPTX, and XLSX formats using code-based approaches that work in offline environments without internet access.

## Supported Formats

### DOCX (Word Documents)
### PDF (Portable Documents)
### PPTX (PowerPoint Presentations)
### XLSX (Excel Spreadsheets)

---

## DOCX Generation

### Using R
```r
# officer paketi ile
library(officer)

doc <- read_docx()
doc <- body_add_par(doc, "Başlık", style = "heading 1")
doc <- body_add_par(doc, "Normal metin paragrafı.")
doc <- body_add_table(doc, data = head(iris), style = "table_template")
print(doc, target = "rapor.docx")
```

### Using Python
```python
from docx import Document
from docx.shared import Inches, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()
doc.add_heading('Rapor Başlığı', level=1)
doc.add_paragraph('Normal metin paragrafı.')

# Tablo ekleme
table = doc.add_table(rows=3, cols=3, style='Table Grid')
table.cell(0, 0).text = 'Başlık 1'

doc.save('rapor.docx')
```

### DOCX Best Practices
- Use styles consistently (Heading 1, Heading 2, Normal, etc.)
- Set page margins explicitly for predictable layout
- Use tables for structured data, not tabs/spaces
- Include page numbers in headers/footers for multi-page documents
- Set document metadata (title, author, subject)
- Use UTF-8 encoding for Turkish characters

---

## PDF Generation

### Using R
```r
# rmarkdown ile
rmarkdown::render("rapor.Rmd", output_format = "pdf_document")

# tinytex ile (internet gerekmez, önceden kurulmalı)
# Ya da grDevices ile doğrudan
pdf("grafik.pdf", width = 10, height = 7)
plot(iris$Sepal.Length, iris$Sepal.Width, main = "Çiçek Analizi")
dev.off()
```

### Using Python
```python
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import cm

c = canvas.Canvas("rapor.pdf", pagesize=A4)
c.setFont("Helvetica-Bold", 16)
c.drawString(2*cm, 27*cm, "Rapor Başlığı")
c.setFont("Helvetica", 12)
c.drawString(2*cm, 25*cm, "İçerik metni burada yer alır.")
c.save()
```

### PDF Best Practices
- Embed fonts for consistent rendering across systems
- Use A4 page size for Turkish/European documents
- Include table of contents for documents over 5 pages
- Set appropriate margins (2-2.5cm typical)
- Use vector graphics where possible for sharp rendering
- Ensure Turkish characters render correctly (font support)

---

## PPTX Generation

### Using R
```r
library(officer)

pptx <- read_pptx()
pptx <- add_slide(pptx, layout = "Title and Content", master = "Office Theme")
pptx <- ph_with(pptx, value = "Sunum Başlığı", location = ph_location_type("title"))
pptx <- ph_with(pptx, value = "İçerik metni", location = ph_location_type("body"))

# Grafik ekleme
pptx <- add_slide(pptx, layout = "Title and Content", master = "Office Theme")
pptx <- ph_with(pptx, value = ggplot2::ggplot(iris, ggplot2::aes(Sepal.Length, Sepal.Width)) +
  ggplot2::geom_point(), location = ph_location_type("body"))

print(pptx, target = "sunum.pptx")
```

### Using Python
```python
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor

prs = Presentation()
slide = prs.slides.add_slide(prs.slide_layouts[1])
title = slide.shapes.title
title.text = "Sunum Başlığı"
body = slide.placeholders[1]
body.text = "Ana içerik burada."

prs.save("sunum.pptx")
```

### PPTX Best Practices
- Limit text per slide (6x6 rule: 6 bullets, 6 words each)
- Use consistent color scheme throughout
- Include slide numbers
- Use high-contrast text colors for readability
- Prefer charts/diagrams over dense text
- Keep animations minimal for professional context
- Set slide dimensions explicitly (16:9 or 4:3)

---

## XLSX Generation

### Using R
```r
# openxlsx paketi ile (Java gerektirmez)
library(openxlsx)

wb <- createWorkbook()
addWorksheet(wb, "Veri")
addWorksheet(wb, "Özet")

# Veri yazma
writeData(wb, "Veri", iris, startRow = 1, startCol = 1, headerStyle = createStyle(
  textDecoration = "bold", fgFill = "#4472C4", fontColour = "#FFFFFF"
))

# Koşullu biçimlendirme
conditionalFormatting(wb, "Veri", cols = 1, rows = 2:151,
  type = "colourScale", style = c("#F8696B", "#FFEB84", "#63BE7B"))

# Sütun genişliği ayarla
setColWidths(wb, "Veri", cols = 1:5, widths = "auto")

# Filtre ekle
addFilter(wb, "Veri", rows = 1, cols = 1:5)

saveWorkbook(wb, "rapor.xlsx", overwrite = TRUE)
```

### Using Python
```python
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Veri"

# Başlık satırı
headers = ["Ad", "Departman", "Tarih", "Tutar"]
for col, header in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col, value=header)
    cell.font = Font(bold=True, color="FFFFFF")
    cell.fill = PatternFill(start_color="4472C4", fill_type="solid")

# Sütun genişliği
for col in range(1, 5):
    ws.column_dimensions[chr(64 + col)].width = 15

wb.save("rapor.xlsx")
```

### XLSX Best Practices
- Always include header row with bold/colored formatting
- Set column widths explicitly (auto-width or fixed)
- Use named worksheets for multi-sheet workbooks
- Apply number formatting for currency, dates, percentages
- Add data filters for large datasets
- Freeze panes for header rows (`freezePane` / `freeze_panes`)
- Use conditional formatting to highlight important values
- Include summary formulas (SUM, AVERAGE, COUNT)
- Protect formulas from accidental editing if sharing

---

## Offline Environment Considerations

Since this runs on a VM without internet access:

### Pre-installed Package Requirements

#### R Packages (install once)
- `officer` — DOCX and PPTX generation
- `openxlsx` — XLSX generation (no Java dependency)
- `rmarkdown` + `tinytex` — PDF generation
- `ggplot2` — Charts for embedding in documents
- `flextable` — Advanced table formatting

#### Python Packages (install once)
- `python-docx` — DOCX generation
- `openpyxl` — XLSX generation
- `python-pptx` — PPTX generation
- `reportlab` — PDF generation
- `Pillow` — Image handling for documents

### Font Considerations
- Ensure Turkish-supporting fonts are installed on the system
- Common safe fonts: Arial, Calibri, Times New Roman, Tahoma
- For PDF: embed fonts or use system fonts that support Turkish glyphs
- Test that characters like ğ, ü, ş, ö, ç, ı, İ render correctly

### Template Strategy
- Pre-create document templates with corporate branding
- Store templates in a shared directory accessible by the app
- Use templates as base for consistent formatting:
  ```r
  doc <- read_docx("templates/kurumsal_sablon.docx")
  ```

## Document Structure Guidelines

### Reports
1. Title page (title, date, author, department)
2. Table of contents (for 5+ pages)
3. Executive summary
4. Main content with numbered sections
5. Appendices (data tables, charts)

### Presentations
1. Title slide
2. Agenda/overview
3. Content slides (one topic per slide)
4. Summary/conclusions
5. Q&A / contact slide

### Spreadsheets
1. Cover/summary sheet
2. Data sheets with headers and filters
3. Analysis/pivot sheets
4. Charts sheet
5. Metadata/legend sheet
