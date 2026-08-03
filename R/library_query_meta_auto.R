# ==============================================================================
# Dosya Yolu: R/library_query_meta_auto.R
# Açıklama: BOŞ İSKELET. Yeni bir checkout'ta Tier-0 boot yolunun çalışabilmesi
#           için vardır; Git'te ASLA doldurulmaz.
#
# NEDEN BOŞ:
#   Üretim metadata'sı gerçek sütun adları, kardinalite, null oranları ve
#   tespit edilmiş tanımlayıcılar içerir. Bunlar GitHub checkout'unda bilinçli
#   olarak bulunmayan kurumsal şema istatistikleridir. Üretici (generator)
#   çıktısını izlenen (tracked) bir dosyaya yazarsa, sonraki tek bir
#   `git add -A` bu bilgiyi yayınlar. Bu yüzden üretici YALNIZCA gitignore'lu
#   R/library_query_meta_local.R dosyasına yazar.
#
# BU DOSYAYI DOLDURMAYIN. Üretici çıktısı buraya değil, yerel katmana gider.
# Master plan §5.1 "Four files — generated, local aliases and curated".
# ==============================================================================

# Sorgu id -> metadata listesi. Git'te daima boş.
pk_query_meta_auto <- list()
