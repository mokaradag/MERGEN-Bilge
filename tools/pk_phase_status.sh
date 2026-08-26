#!/usr/bin/env bash
# =============================================================================
# tools/pk_phase_status.sh
#
# Proje ve Kaynak Analizi yeniden yapım fazlarının GERÇEK birleşme durumunu
# git geçmişinden türetir. `.ai/pk-rebuild-progress.md` içindeki elle yazılan
# durum tablosu, PR'i AÇAN oturum tarafından yazıldığı ve o oturum birleşme
# gerçekleşmeden önce sona erdiği için YAPISAL OLARAK bayatlar. Dört ardışık
# fazda bayat kaldı. Bu betik, hatırlamaya dayalı adımı tek bir komuta çevirir.
#
# Kullanım:
#   bash tools/pk_phase_status.sh              # origin/pk/rebuild
#   bash tools/pk_phase_status.sh <ref>        # baska bir entegrasyon dali
#
# Ortam degiskenleri:
#   PK_PHASE_SKIP_REMOTE_CHECK=1  uzak tazelik dogrulamasini atla (cevrimdisi)
#
# Betik SALT OKUNURDUR: hicbir dosyayi degistirmez, hicbir sey push etmez.
#
# WINDOWS-1254 GUVENLI (CLAUDE.md §1G): Turkce harfler (ç ğ ı İ ö ş ü ...)
# CP1254'te TEMSIL EDILEBILIR ve operator ciktisinda korunur; CP1254'te
# KARSILIGI OLMAYAN karakterler (uzun tire, paragraf isareti, emoji) BULUNMAZ.
# Onceki "bayt duzeyi ASCII" kurali Turkce metni Latinlestirmeye zorluyordu;
# oysa bu bir bash betigidir, R hicbir zaman `source()` etmez ve Turkce
# Windows konsolunun kod sayfasi zaten CP1254'tur. Iddia
# tests/testthat/test-pk-phase-status-contract.R tarafindan korunur.
#
# DOGRULUK SINIRI (bilerek acik yazilmistir): bu betik BIRLESME COMMIT'lerini
# ve GitHub squash birlesme konusunu tanir. Rebase birlesmesi gecmiste ayirt
# edilebilir bir iz birakmaz; bu yuzden "gorunmeyen faz birlesmemistir"
# SONUCU CIKARILAMAZ. Betik bu ayrimi ciktida acikca soyler.
# =============================================================================

set -u
set -o pipefail

REF="${1:-origin/pk/rebuild}"

# Git, tire ile baslayan bir argumani SECENEK olarak yorumlar. `--all` gecirmek
# `git log ... --all` etkisi yaratir ve YALNIZCA ozellik dalinda kalan
# birlesmeler entegre olmus gibi raporlanir.
case "${REF}" in
  -*)
    echo "HATA: '<ref>' bir seçenek olamaz ('${REF}'). Geçerli bir commit referansı verin." >&2
    exit 2
    ;;
esac

if ! git rev-parse --verify --quiet "${REF}^{commit}" >/dev/null 2>&1; then
  echo "HATA: '${REF}' bir commit referansına çözülemedi. Önce 'git fetch origin' çalıştırın." >&2
  exit 1
fi

# Sig (shallow) klonda eski faz birlesmeleri gecmiste HIC BULUNMAZ; o halde
# "birlesmemis" ciktisi tamamen yaniltici olur.
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
  echo "HATA: Depo sığ (shallow) klondur; faz geçmişi eksik olabilir." >&2
  echo "      Önce 'git fetch --unshallow' çalıştırın." >&2
  exit 1
fi

# Uzak takip referansi YALNIZCA en son yerel fetch'in degeridir. Baska bir faz
# uzakta birlesmisse, fetch yapilmadan calistirilan betik onu 'birlesmemis'
# gosterir; bu, tam olarak bu yardimcinin ortadan kaldirmasi gereken bayatlik
# sorunudur.
case "${REF}" in
  origin/*)
    if [ "${PK_PHASE_SKIP_REMOTE_CHECK:-0}" = "1" ]; then
      echo "UYARI: Uzak tazelik doğrulaması atlandı; çıktı BAYAT olabilir." >&2
    else
      uzak_dal="${REF#origin/}"
      # SÜRE SINIRI: askıda kalan bir bağlantı (VPN kopması, kapalı port,
      # yanıtsız vekil) betiği SÜRESİZ bekletiyordu; operatör hangi durumda
      # olduğunu göremiyordu. Zaman aşımı mevcut çevrimdışı hata yoluna düşer.
      uzak_sha="$(GIT_TERMINAL_PROMPT=0 timeout 20 git ls-remote origin "refs/heads/${uzak_dal}" 2>/dev/null | awk '{print $1}' | head -n 1)"
      if [ -z "${uzak_sha}" ]; then
        echo "HATA: 'origin/${uzak_dal}' uzak referansı doğrulanamadı (ağsız olabilirsiniz)." >&2
        echo "      Çevrimdışı çalışıyorsanız PK_PHASE_SKIP_REMOTE_CHECK=1 ile çalıştırın." >&2
        exit 1
      fi
      yerel_sha="$(git rev-parse "${REF}")"
      if [ "${uzak_sha}" != "${yerel_sha}" ]; then
        echo "HATA: '${REF}' bayat. Uzak=${uzak_sha} Yerel=${yerel_sha}." >&2
        echo "      Önce 'git fetch origin' çalıştırın." >&2
        exit 1
      fi
    fi
    ;;
esac

echo "PK faz birleşme durumu - referans: ${REF} ($(git rev-parse --short "${REF}"))"
echo

# BIRINCI EBEVEYN gecmisi. Birinci ebeveyn kisiti olmadan `git log` bir ozellik
# dalinin ICINDEKI birlesmeleri de dolasir; Faz 4 dalinin icinde 'phase-5'
# adini tasiyan bir birlesme varsa Faz 4'un entegrasyonu Faz 5'i de birlesmis
# gosterir ve yeniden yapim hatali ilerler.
if ! gecmis="$(git log --first-parent --format='%h%x1f%s%x1f%P' "${REF}" 2>/dev/null)"; then
  echo "HATA: '${REF}' gecmisi taranamadi (eksik/bozuk nesne olabilir)." >&2
  exit 1
fi

# Geri alinan (revert) birlesmeler. Birlesme commit'i gecmiste KALIR; kodun
# hala dalda oldugu SONUCU CIKARILAMAZ.
geri_alinanlar="$(printf '%s\n' "${gecmis}" | awk -F '\037' '{print $2}' | sed -n 's/^Revert "\(.*\)"$/\1/p')" || true

bulundu=0
gorulenler=""
belirsiz=0

while IFS=$'\037' read -r sha subject parents; do
  [ -n "${sha}" ] || continue

  dal=""
  pr=""
  birlesme_tipi=""

  # Birlesme commit'i (birden fazla ebeveyn). GitHub'in varsayilan konusuna
  # BAGLI KALINMAZ: kaynak dal konu satirindan cikarilamasa bile birlesme
  # oldugu ebeveyn sayisindan bilinir.
  case "${parents}" in
    *" "*)
      birlesme_tipi="merge"
      dal="$(printf '%s\n' "${subject}" | sed -n 's/.*[Ff]rom [^/]*\/\(.*\)$/\1/p')"
      pr="$(printf '%s\n' "${subject}" | sed -n 's/.*#\([0-9][0-9]*\).*/\1/p')"
      if [ -z "${dal}" ]; then
        # Konusu duzenlenmis birlesme: dal adi yok. Faz cikarilamiyorsa bu
        # SESSIZCE atlanamaz; belirsiz sayilir ve sonda bildirilir.
        case "${subject}" in
          *phase-[0-9]*) dal="${subject}" ;;
          *) belirsiz=$((belirsiz + 1)); continue ;;
        esac
      fi
      ;;
    *)
      # Squash birlesme: tek ebeveyn, konu sonunda '(#N)'. GitHub squash
      # konusu KAYNAK DAL ADINI TASIMAZ; bu yuzden faz kimligi ya konudaki
      # `phase-<N>` isaretinden ya da deponun kendi `Faz <N>` yazim
      # kuralindan cikarilir. Ikisi de yoksa commit ATLANIR ve kapanis
      # notundaki "yokluk kanit degildir" uyarisi gecerlidir.
      case "${subject}" in
        *"(#"[0-9]*")")
          birlesme_tipi="squash"
          pr="$(printf '%s\n' "${subject}" | sed -n 's/.*(#\([0-9][0-9]*\)).*/\1/p')"
          dal="${subject}"
          case "${subject}" in
            *phase-[0-9]*) ;;
            [Ff]az\ [0-9]*|*\ [Ff]az\ [0-9]*)
              faz_sq="$(printf '%s\n' "${subject}" | sed -n 's/.*[Ff]az \([0-9][0-9a-z]*\).*/\1/p')"
              [ -n "${faz_sq}" ] && dal="pk/phase-${faz_sq}-squash"
              ;;
            *) ;;
          esac
          ;;
        *) continue ;;
      esac
      ;;
  esac

  # PK FAZ AD ALANI. `phase-<rakam>` iceren HER dal kabul edilemez:
  # `ui/phase-2-redesign` gibi ilgisiz bir birlesme, bu cikti bir sonraki fazi
  # acmak icin kullanildiginda yanlis pozitif uretir.
  case "${dal}" in
    pk/phase-[0-9]*|pk-phase-[0-9]*|claude/pk-phase-[0-9]*|claude/phase-[0-9]*) ;;
    *phase-[0-9]*)
      # Squash konusu dal adini tasimayabilir; PK ad alani DOGRULANAMADIGI
      # icin sessizce kabul edilmez.
      if [ "${birlesme_tipi}" = "squash" ]; then
        belirsiz=$((belirsiz + 1))
      fi
      continue
      ;;
    *) continue ;;
  esac

  # Faz numarasi DOGRULANMIS onekten SONRAKI ILK isaretten okunur.
  # `${dal#*phase-}` EN KISA on eki atar; acgozlu bir `.*phase-` kalibi
  # `claude/pk-phase-4-fix-phase-5-prep` dalini Faz 5 sanirdi.
  faz_kuyruk="${dal#*phase-}"
  faz="$(printf '%s\n' "${faz_kuyruk}" | sed -n 's/^\([0-9][0-9a-z]*\).*/\1/p')"
  [ -n "${faz}" ] || continue

  # Geri alinmis birlesme entegre SAYILMAZ.
  if [ -n "${geri_alinanlar}" ] && printf '%s\n' "${geri_alinanlar}" | grep -Fxq "${subject}"; then
    continue
  fi

  # Faz basina TEK yetkili satir. `git log` en yeniden eskiye yurudugu icin
  # ilk gorulen kayit en guncel entegrasyondur; sonraki (eski) kopyalar
  # atlanir, aksi halde operator eski SHA'yi tabloya kopyalayabilir.
  case " ${gorulenler} " in
    *" ${faz} "*) continue ;;
  esac
  gorulenler="${gorulenler} ${faz}"

  printf 'Faz %-4s merged_to_rebuild  tip=%-6s SHA=%s  PR=#%s  dal=%s\n' \
    "${faz}" "${birlesme_tipi}" "${sha}" "${pr:-?}" "${dal}"
  bulundu=$((bulundu + 1))
done <<EOF
${gecmis}
EOF

if [ "${bulundu}" -eq 0 ]; then
  echo "(bu referansta birlesmis PK faz PR'i bulunamadi)"
fi

if [ "${belirsiz}" -gt 0 ]; then
  echo
  echo "UYARI: ${belirsiz} commit icin faz/dal kimligi dogrulanamadi;"
  echo "       bunlar taranan kumeye GIRMEDI."
fi

echo
echo "Not: Burada GORUNEN her faz birlesmistir. Burada GORUNMEYEN bir faz icin"
echo "     'birlesmemistir' SONUCU CIKARILAMAZ: rebase birlesmesi ayirt"
echo "     edilebilir bir iz birakmaz. Kesin durum icin PR durumuna bakin."
echo "     Bu ciktiyi .ai/pk-rebuild-progress.md tablosuyla karsilastirin;"
echo "     CAKISMA VARSA GIT KAZANIR (master plan bolum 11)."
