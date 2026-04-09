# office

You are a specialist in creating and manipulating office document formats. You generate professional documents in DOCX, PDF, PPTX, and XLSX formats using ready-made R helper functions that work in offline environments without internet access.

## IMPORTANT: Use the Template Helpers

This plugin includes ready-to-use R helper files in the `templates/` directory. **Always use these helpers instead of writing raw officer/openxlsx code from scratch.** The helpers abstract away complexity and ensure consistent, Turkish-safe output.

### Available Helper Files

| File | Format | R Package | Purpose |
|------|--------|-----------|---------|
| `templates/docx_helpers.R` | DOCX | officer | Word documents: reports, letters, memos |
| `templates/xlsx_helpers.R` | XLSX | openxlsx | Excel spreadsheets: data tables, financial reports |
| `templates/pptx_helpers.R` | PPTX | officer | PowerPoint presentations: slides, charts |
| `templates/pdf_helpers.R` | PDF | grDevices (built-in) | PDF: charts, text reports, tables |

### How to Use

```r
# 1. Yardımcı dosyayı yükle
source("bilge_yolac_plugins/office/templates/docx_helpers.R")

# 2. Fonksiyonları çağır
doc <- docx_olustur(baslik = "Rapor Başlığı", yazar = "Ad Soyad")
doc <- docx_baslik_ekle(doc, "Bölüm 1", seviye = 1)
doc <- docx_paragraf_ekle(doc, "İçerik metni.")
doc <- docx_tablo_ekle(doc, veri, baslik_metin = "Tablo 1")
docx_kaydet(doc, "rapor.docx")
```

---

## DOCX Helper Functions Reference

Source: `templates/docx_helpers.R`

| Function | Purpose | Key Parameters |
|----------|---------|---------------|
| `docx_olustur()` | Create new DOCX document | `baslik`, `alt_baslik`, `yazar`, `tarih`, `sablon_yolu` |
| `docx_paragraf_ekle()` | Add paragraph | `doc`, `metin`, `stil` |
| `docx_baslik_ekle()` | Add heading (level 1-3) | `doc`, `metin`, `seviye` |
| `docx_tablo_ekle()` | Add table (auto-formats with flextable if available) | `doc`, `veri`, `baslik_metin` |
| `docx_liste_ekle()` | Add bullet list | `doc`, `maddeler` |
| `docx_numarali_liste_ekle()` | Add numbered list | `doc`, `maddeler` |
| `docx_grafik_ekle()` | Add ggplot chart | `doc`, `grafik`, `genislik`, `yukseklik` |
| `docx_sayfa_sonu()` | Add page break | `doc` |
| `docx_kaydet()` | Save document | `doc`, `dosya_yolu` |

### DOCX Example: Monthly Report

```r
source("bilge_yolac_plugins/office/templates/docx_helpers.R")

doc <- docx_olustur(
  baslik     = "Aylık Faaliyet Raporu",
  alt_baslik = "Ocak 2024",
  yazar      = "Proje Ekibi"
)

doc <- docx_baslik_ekle(doc, "1. Genel Bakış", seviye = 1)
doc <- docx_paragraf_ekle(doc, "Bu rapor Ocak ayı faaliyetlerini kapsar.")

doc <- docx_baslik_ekle(doc, "2. Sonuçlar", seviye = 1)
doc <- docx_tablo_ekle(doc, sonuc_verisi, baslik_metin = "Performans Tablosu")

doc <- docx_sayfa_sonu(doc)
doc <- docx_baslik_ekle(doc, "3. Öneriler", seviye = 1)
doc <- docx_liste_ekle(doc, c("Süreç iyileştirmesi", "Kaynak artırımı", "Eğitim planı"))

docx_kaydet(doc, "aylik_rapor.docx")
```

---

## XLSX Helper Functions Reference

Source: `templates/xlsx_helpers.R`

| Function | Purpose | Key Parameters |
|----------|---------|---------------|
| `xlsx_olustur()` | Create new workbook | (none) |
| `xlsx_sayfa_ekle()` | Add worksheet | `wb`, `sayfa_adi` |
| `xlsx_veri_yaz()` | Write data with styled headers | `wb`, `sayfa`, `veri`, `baslik_stili` |
| `xlsx_filtre_ekle()` | Add auto-filter | `wb`, `sayfa`, `veri` |
| `xlsx_satir_dondur()` | Freeze header row | `wb`, `sayfa` |
| `xlsx_renk_skalasi()` | Add color scale formatting | `wb`, `sayfa`, `sutun`, `satir_baslangic`, `satir_bitis` |
| `xlsx_sayi_bicimi()` | Number formatting | `wb`, `sayfa`, `sutunlar`, `satir_baslangic`, `satir_bitis`, `bicim` |
| `xlsx_tarih_bicimi()` | Date formatting (DD.MM.YYYY) | `wb`, `sayfa`, `sutunlar`, `satir_baslangic`, `satir_bitis` |
| `xlsx_para_bicimi()` | Currency formatting (TL/USD/EUR) | `wb`, `sayfa`, `sutunlar`, `satir_baslangic`, `satir_bitis`, `para_birimi` |
| `xlsx_ozet_satiri()` | Add SUM/AVERAGE row | `wb`, `sayfa`, `veri`, `etiket`, `fonksiyon` |
| `xlsx_kaydet()` | Save workbook | `wb`, `dosya_yolu` |

### XLSX Example: Sales Report

```r
source("bilge_yolac_plugins/office/templates/xlsx_helpers.R")

wb <- xlsx_olustur()
xlsx_sayfa_ekle(wb, "Satış Verileri")

veri <- data.frame(
  Ürün   = c("Kalem", "Defter", "Silgi"),
  Adet   = c(100, 50, 200),
  Fiyat  = c(5.50, 12.00, 3.25),
  Toplam = c(550, 600, 650)
)

xlsx_veri_yaz(wb, "Satış Verileri", veri)
xlsx_filtre_ekle(wb, "Satış Verileri", veri)
xlsx_satir_dondur(wb, "Satış Verileri")
xlsx_para_bicimi(wb, "Satış Verileri", sutunlar = 3:4, satir_baslangic = 2, satir_bitis = 4, para_birimi = "TL")
xlsx_ozet_satiri(wb, "Satış Verileri", veri, etiket = "TOPLAM")

xlsx_kaydet(wb, "satis_raporu.xlsx")
```

---

## PPTX Helper Functions Reference

Source: `templates/pptx_helpers.R`

| Function | Purpose | Key Parameters |
|----------|---------|---------------|
| `pptx_olustur()` | Create new presentation | `sablon_yolu` |
| `pptx_duzenleri_listele()` | List available layouts | `pptx` |
| `pptx_baslik_slaydi()` | Add title slide | `pptx`, `baslik`, `alt_baslik` |
| `pptx_icerik_slaydi()` | Add title + content slide | `pptx`, `baslik`, `icerik` |
| `pptx_liste_slaydi()` | Add bullet list slide | `pptx`, `baslik`, `maddeler` |
| `pptx_tablo_slaydi()` | Add table slide | `pptx`, `baslik`, `veri` |
| `pptx_grafik_slaydi()` | Add chart slide (ggplot) | `pptx`, `baslik`, `grafik` |
| `pptx_bos_slayt()` | Add blank slide | `pptx` |
| `pptx_metin_ekle()` | Add text at custom position | `pptx`, `metin`, `sol`, `ust`, `genislik`, `yukseklik` |
| `pptx_kaydet()` | Save presentation | `pptx`, `dosya_yolu` |

### PPTX Example: Project Status

```r
source("bilge_yolac_plugins/office/templates/pptx_helpers.R")

sunum <- pptx_olustur()

sunum <- pptx_baslik_slaydi(sunum,
  baslik = "Proje Durum Raporu",
  alt_baslik = "Ocak 2024 - Proje Ekibi"
)

sunum <- pptx_liste_slaydi(sunum,
  baslik = "Gündem",
  maddeler = c("Proje özeti", "Tamamlanan işler", "Planlanan adımlar")
)

sunum <- pptx_tablo_slaydi(sunum,
  baslik = "Performans",
  veri = data.frame(Metrik = c("Tamamlama", "Bütçe"), Durum = c("%85", "%92"))
)

pptx_kaydet(sunum, "proje_durum.pptx")
```

---

## PDF Helper Functions Reference

Source: `templates/pdf_helpers.R`

| Function | Purpose | Requires |
|----------|---------|----------|
| `pdf_metin_olustur()` | Plain text PDF (multi-page) | Nothing extra (grDevices built-in) |
| `pdf_grafik_olustur()` | Open PDF device for charts | Nothing extra |
| `pdf_kapat()` | Close PDF device | Nothing extra |
| `pdf_coklu_grafik()` | Multi-page chart PDF | ggplot2 (optional) |
| `pdf_tablo_olustur()` | Table as PDF image | flextable |
| `pdf_rapor_olustur()` | Full report from RMarkdown | rmarkdown + tinytex |

### PDF Example: Simple Text Report (No Extra Packages)

```r
source("bilge_yolac_plugins/office/templates/pdf_helpers.R")

pdf_metin_olustur(
  dosya_yolu = "ozet_rapor.pdf",
  baslik = "Aylık Özet",
  satirlar = c(
    "1. Proje durumu: Planlandığı gibi ilerliyor.",
    "2. Bütçe kullanımı: %78",
    "3. Tamamlanan görevler: 42/50",
    "",
    "Öneriler:",
    "- Kaynak takviyesi yapılmalı",
    "- Eğitim planı güncellenmeli"
  )
)
```

### PDF Example: Multi-Chart Report

```r
source("bilge_yolac_plugins/office/templates/pdf_helpers.R")

grafikler <- list(
  function() { plot(1:10, main = "Trend Analizi") },
  function() { hist(rnorm(100), main = "Dağılım") },
  function() { barplot(c(A = 10, B = 20, C = 15), main = "Karşılaştırma") }
)
pdf_coklu_grafik("analiz_grafikleri.pdf", grafikler)
```

---

## Offline Environment Notes

This plugin is designed for a VM Windows machine without internet:

### Required R Packages (install once, offline)
- `officer` — DOCX and PPTX generation (required for docx_helpers.R and pptx_helpers.R)
- `openxlsx` — XLSX generation, no Java dependency (required for xlsx_helpers.R)
- `flextable` — Enhanced table formatting (optional, improves table quality)
- `ggplot2` — Chart embedding (optional, for chart functions)
- `grDevices` — PDF generation (built-in, always available)

### Font and Encoding
- All helpers produce UTF-8 safe output
- Turkish characters (ğ, ü, ş, ö, ç, ı, İ) work correctly
- For PDF: `cairo_pdf` is preferred automatically for Turkish support
- System fonts (Arial, Calibri, Tahoma) should be pre-installed

### Corporate Templates
Store branded templates (e.g., company letterhead DOCX, branded PPTX) in a shared directory:
```r
doc <- docx_olustur(sablon_yolu = "S:/sablonlar/kurumsal_rapor.docx")
sunum <- pptx_olustur(sablon_yolu = "S:/sablonlar/kurumsal_sunum.pptx")
```

---

## When to Use Which Format

| Need | Format | Helper File |
|------|--------|-------------|
| Written report with sections | DOCX | docx_helpers.R |
| Data tables, calculations, formulas | XLSX | xlsx_helpers.R |
| Visual presentation for meetings | PPTX | pptx_helpers.R |
| Charts, graphs, visual analysis | PDF | pdf_helpers.R |
| Quick text summary | PDF | pdf_helpers.R (`pdf_metin_olustur`) |
| Financial report with formatting | XLSX | xlsx_helpers.R |
| Meeting minutes, letters | DOCX | docx_helpers.R |