// www/js/app_loading_snippets.js
// Dosya Yolu: www/js/app_loading_snippets.js
// Açıklama: Açılış yükleme ekranındaki akan kod katmanı için kod parçası
//   havuzu. Parçalar çeşitli programlama dillerinden seçilmiştir ve
//   değişken adları Türkçedir; ekranda dekoratif olarak gösterilir.
//   Bu dosya R/module_app_loading.R tarafından satır içine gömülür.

(function () {
  "use strict";

  // Her parça: { lang: görünen etiket, lines: kod satırları }
  window.MergenLoadingSnippets = [
    { lang: "R", lines: [
      "# Gelir verisinin ortalamasini hesapla",
      "ortalama_gelir <- function(veri) {",
      "  toplam <- sum(veri$gelir, na.rm = TRUE)",
      "  toplam / nrow(veri)",
      "}"
    ] },
    { lang: "Python", lines: [
      "def faktoriyel(sayi):",
      "    if sayi <= 1:",
      "        return 1",
      "    return sayi * faktoriyel(sayi - 1)"
    ] },
    { lang: "JavaScript", lines: [
      "function aktifKullanicilar(liste) {",
      "  return liste.filter(function (kullanici) {",
      "    return kullanici.durum === 'aktif';",
      "  });",
      "}"
    ] },
    { lang: "SQL", lines: [
      "SELECT musteri_id, SUM(tutar) AS toplam",
      "FROM siparisler",
      "WHERE durum = 'tamamlandi'",
      "GROUP BY musteri_id",
      "ORDER BY toplam DESC;"
    ] },
    { lang: "C++", lines: [
      "double vektorToplami(const vector<double>& dizi) {",
      "    double toplam = 0.0;",
      "    for (double deger : dizi) toplam += deger;",
      "    return toplam;",
      "}"
    ] },
    { lang: "Go", lines: [
      "func isciCalistir(gorevler chan int, sonuc chan int) {",
      "    for gorev := range gorevler {",
      "        sonuc <- gorev * gorev",
      "    }",
      "}"
    ] },
    { lang: "Rust", lines: [
      "fn guvenli_bolme(pay: f64, payda: f64) -> Option<f64> {",
      "    if payda == 0.0 { return None; }",
      "    Some(pay / payda)",
      "}"
    ] },
    { lang: "Java", lines: [
      "public class Kullanici {",
      "    private String ad;",
      "    private int yas;",
      "    public String getAd() { return ad; }",
      "}"
    ] },
    { lang: "Julia", lines: [
      "function matris_carp(birinci, ikinci)",
      "    sonuc = birinci * ikinci",
      "    return sonuc",
      "end"
    ] },
    { lang: "Python", lines: [
      "import numpy as np",
      "# Standart sapmayi hesapla",
      "veri = np.array([12, 18, 24, 30, 42])",
      "sapma = np.std(veri)",
      "print('Sapma:', sapma)"
    ] },
    { lang: "TypeScript", lines: [
      "interface Siparis {",
      "  urunAdi: string;",
      "  miktar: number;",
      "  fiyat: number;",
      "}"
    ] },
    { lang: "R", lines: [
      "# Basit dogrusal regresyon modeli",
      "model <- lm(satislar ~ reklam, data = veri)",
      "tahmin <- predict(model, yeni_veri)",
      "ozet <- summary(model)"
    ] },
    { lang: "C#", lines: [
      "var aktifMusteriler = musteriler",
      "    .Where(m => m.Bakiye > 0)",
      "    .OrderByDescending(m => m.Bakiye)",
      "    .ToList();"
    ] },
    { lang: "Bash", lines: [
      "#!/bin/bash",
      "# Gunluk dosyalari yedekle",
      "for dosya in /veri/*.csv; do",
      "  cp \"$dosya\" /yedek/",
      "done"
    ] },
    { lang: "Kotlin", lines: [
      "data class Urun(",
      "    val ad: String,",
      "    val fiyat: Double,",
      "    val stok: Int",
      ")"
    ] },
    { lang: "Python", lines: [
      "class SinirAgiKatmani:",
      "    def __init__(self, giris, cikis):",
      "        self.agirliklar = rastgele(giris, cikis)",
      "        self.onyargi = sifirlar(cikis)"
    ] },
    { lang: "SQL", lines: [
      "SELECT u.ad, COUNT(s.id) AS siparis_sayisi",
      "FROM kullanicilar u",
      "LEFT JOIN siparisler s ON s.kullanici_id = u.id",
      "GROUP BY u.ad;"
    ] },
    { lang: "JavaScript", lines: [
      "async function veriGetir(adres) {",
      "  const yanit = await fetch(adres);",
      "  const sonuc = await yanit.json();",
      "  return sonuc;",
      "}"
    ] },
    { lang: "Lisp", lines: [
      "(defun listeyi-topla (liste)",
      "  (if (null liste)",
      "      0",
      "      (+ (car liste) (listeyi-topla (cdr liste)))))"
    ] },
    { lang: "Fortran", lines: [
      "real function dizi_ortalamasi(dizi, boyut)",
      "  integer :: i, boyut",
      "  real :: toplam, dizi(boyut)",
      "  toplam = 0.0",
      "end function"
    ] },
    { lang: "MATLAB", lines: [
      "% Veri kumesini normalize et",
      "ortalama = mean(veri);",
      "sapma = std(veri);",
      "normalize = (veri - ortalama) ./ sapma;"
    ] },
    { lang: "PHP", lines: [
      "function indirimUygula($fiyat, $oran) {",
      "    $indirim = $fiyat * $oran;",
      "    return $fiyat - $indirim;",
      "}"
    ] },
    { lang: "Ruby", lines: [
      "satislar.each do |kayit|",
      "  vergi = kayit.tutar * 0.18",
      "  puts \"Vergi: #{vergi}\"",
      "end"
    ] },
    { lang: "Swift", lines: [
      "func enBuyuk(_ dizi: [Int]) -> Int? {",
      "    guard !dizi.isEmpty else { return nil }",
      "    return dizi.max()",
      "}"
    ] },
    { lang: "Python", lines: [
      "# Gradyan inisi ile agirlik guncelle",
      "for adim in range(donem_sayisi):",
      "    egim = gradyan(veri, agirliklar)",
      "    agirliklar -= ogrenme_orani * egim"
    ] },
    { lang: "R", lines: [
      "# Sutun bazli ortalama al",
      "sonuclar <- sapply(veri[, sayisal], mean)",
      "siralanmis <- sort(sonuclar, decreasing = TRUE)",
      "head(siralanmis, 5)"
    ] },
    { lang: "Go", lines: [
      "deger, hata := dosyaOku(yol)",
      "if hata != nil {",
      "    log.Fatal(hata)",
      "}",
      "fmt.Println(deger)"
    ] },
    { lang: "SQL", lines: [
      "SELECT ad, tutar,",
      "  RANK() OVER (ORDER BY tutar DESC) AS sira",
      "FROM gelirler",
      "WHERE yil = 2025;"
    ] },
    { lang: "JavaScript", lines: [
      "const toplam = siparisler.reduce(function (biriken, s) {",
      "  return biriken + s.fiyat * s.miktar;",
      "}, 0);"
    ] },
    { lang: "Rust", lines: [
      "let cift_sayilar: Vec<i32> = sayilar",
      "    .iter()",
      "    .filter(|&deger| deger % 2 == 0)",
      "    .cloned()",
      "    .collect();"
    ] },
    { lang: "Python", lines: [
      "def zamanli(fonksiyon):",
      "    def sarmalayici(*args):",
      "        baslangic = simdi()",
      "        return fonksiyon(*args)",
      "    return sarmalayici"
    ] },
    { lang: "Julia", lines: [
      "# Vektore toplu islem uygula",
      "katsayilar = [1.0, 2.5, 4.0]",
      "olceklenmis = katsayilar .* 2.0",
      "println(sum(olceklenmis))"
    ] },
    { lang: "PowerShell", lines: [
      "# Buyuk dosyalari listele",
      "Get-ChildItem -Path $klasor |",
      "  Where-Object { $_.Length -gt 1MB } |",
      "  Sort-Object Length -Descending"
    ] },
    { lang: "Java", lines: [
      "double ortalama = notlar.stream()",
      "    .mapToInt(Integer::intValue)",
      "    .average()",
      "    .orElse(0.0);"
    ] },
    { lang: "C++", lines: [
      "class Dugum {",
      "public:",
      "    int deger;",
      "    Dugum* sonraki = nullptr;",
      "};"
    ] },
    { lang: "Python", lines: [
      "sozluk = {",
      "    'ad': 'Mergen',",
      "    'puan': 98,",
      "    'aktif': True",
      "}"
    ] },
    { lang: "R", lines: [
      "# Kosula gore satirlari filtrele",
      "filtreli <- subset(veri, gelir > 1000)",
      "gruplu <- aggregate(gelir ~ bolge, filtreli, sum)",
      "print(gruplu)"
    ] },
    { lang: "TypeScript", lines: [
      "function ilkEleman<T>(dizi: T[]): T | undefined {",
      "  return dizi.length > 0 ? dizi[0] : undefined;",
      "}"
    ] },
    { lang: "SQL", lines: [
      "SELECT kategori, AVG(fiyat) AS ortalama_fiyat",
      "FROM urunler",
      "GROUP BY kategori",
      "HAVING COUNT(*) > 3;"
    ] },
    { lang: "Kotlin", lines: [
      "fun String.tersCevir(): String {",
      "    return this.reversed()",
      "}",
      "val sonuc = \"merhaba\".tersCevir()"
    ] },
    { lang: "Ruby", lines: [
      "def asal_mi?(sayi)",
      "  return false if sayi < 2",
      "  (2...sayi).none? { |b| sayi % b == 0 }",
      "end"
    ] },
    { lang: "Python", lines: [
      "# Kosinus benzerligi hesapla",
      "def benzerlik(birinci, ikinci):",
      "    nokta = sum(a * b for a, b in zip(birinci, ikinci))",
      "    return nokta / (norm(birinci) * norm(ikinci))"
    ] },
    { lang: "Go", lines: [
      "type Olcum struct {",
      "    Zaman  time.Time",
      "    Deger  float64",
      "    Etiket string",
      "}"
    ] },
    { lang: "JavaScript", lines: [
      "const benzersiz = [...new Set(etiketler)];",
      "const sirali = benzersiz.sort();",
      "console.log('Etiket sayisi:', sirali.length);"
    ] }
  ];
})();
