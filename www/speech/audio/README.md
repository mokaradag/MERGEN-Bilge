# Persona WAV Kayıtları

Ses klasörü ağacı, her persona için ortak konuşma metni ağacını yansıtır.

PCM WAV dosyalarını karşılık gelen dizine yerleştirin ve konuşma metninin temel
dosya adını koruyun. Örnek:

```text
scripts/pages/history/history_04.txt
audio/emre/pages/history/history_04.wav
audio/selin/pages/history/history_04.wav
```

`.gitkeep` dosyaları yalnızca boş kayıt dizinlerinin depoda korunmasını sağlar ve
WAV dosyaları eklendikten sonra da kalabilir. Altyazı metni `../scripts`
dizininden okunur; `audio` altında yinelenen `.txt` dosyaları oluşturmayın.