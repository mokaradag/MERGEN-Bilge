#!/usr/bin/env bash
# =============================================================================
# tools/pk_phase_status.sh
#
# Proje ve Kaynak Analizi yeniden yapim fazlarinin GERCEK birlesme durumunu
# git gecmisinden turetir. `.ai/pk-rebuild-progress.md` icindeki elle yazilan
# durum tablosu, PR'i ACAN oturum tarafindan yazildigi ve o oturum birlesme
# gerceklesmeden once sona erdigi icin YAPISAL OLARAK bayatlar. Dort ardisik
# fazda bayat kaldi. Bu betik, hatirlamaya dayali adimi tek bir komuta cevirir.
#
# Kullanim:
#   bash tools/pk_phase_status.sh              # origin/pk/rebuild
#   bash tools/pk_phase_status.sh <ref>        # baska bir entegrasyon dali
#
# Betik SALT OKUNURDUR: hicbir dosyayi degistirmez, hicbir sey push etmez.
# Cikti, ilerleme dosyasindaki tabloya elle kopyalanacak referans dogrudur.
#
# ASCII-only: Windows/Turkce yerelde `source`/parse guvenligi icin (depo
# genelindeki operasyonel giris betigi kurali).
# =============================================================================

set -u

REF="${1:-origin/pk/rebuild}"

if ! git rev-parse --verify --quiet "${REF}" >/dev/null; then
  echo "HATA: '${REF}' referansi bulunamadi. Once 'git fetch origin' calistirin." >&2
  exit 1
fi

echo "PK faz birlesme durumu — referans: ${REF} ($(git rev-parse --short "${REF}"))"
echo

# Yalnizca PK FAZ birlesmelerini tara. Depoda yuzlerce ilgisiz PR birlesmesi
# var; hepsini listelemek ciktiyi kullanilamaz hale getirir. Faz dallari
# istisnasiz `phase-<rakam>` kalibini tasir (`pk/phase-0-telemetry`,
# `claude/pk-phase-3a-metadata-...`, `claude/phase-4-entity-resolver-...`).
bulundu=0
while IFS=$'\t' read -r sha subject; do
  case "${subject}" in
    *"Merge pull request"*phase-[0-9]*)
      pr="$(printf '%s\n' "${subject}" | sed -n 's/.*pull request #\([0-9][0-9]*\).*/\1/p')"
      branch="$(printf '%s\n' "${subject}" | sed -n 's/.*from [^/]*\/\(.*\)$/\1/p')"
      faz="$(printf '%s\n' "${branch}" | sed -n 's/.*phase-\([0-9][0-9a-z]*\).*/\1/p')"
      printf 'Faz %-3s  merged_to_rebuild  SHA=%s  PR=#%s  dal=%s\n' \
        "${faz:-?}" "${sha}" "${pr:-?}" "${branch:-?}"
      bulundu=$((bulundu + 1))
      ;;
  esac
done <<EOF
$(git log --merges --format='%h%x09%s' "${REF}")
EOF

if [ "${bulundu}" -eq 0 ]; then
  echo "(bu referansta birlesmis PK faz PR'i yok)"
fi

echo
echo "Not: Burada GORUNMEYEN her faz henuz birlesmemistir (in_review veya"
echo "in_progress). Bu ciktiyi .ai/pk-rebuild-progress.md tablosuyla"
echo "karsilastirin; CAKISMA VARSA GIT KAZANIR (master plan §11)."
