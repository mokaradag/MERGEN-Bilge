# ==============================================================================
# Dosya Yolu: R/config_seam_guard_tests.R
# Açıklama: Seam başına ODAKLI GUARD TESTLERİ ve odaklı doğrulama komutları.
#
#           R/config_seam_registry.R içinden AYRILDI. Gerekçe: kayıt defteri
#           SAHİPLİK verisidir (bölüm -> seam, manifest dışı dosyalar) ve
#           uzunluğu seam sayısıyla artar; guard test listesi ise KOD
#           BÜYÜDÜKÇE her seam içinde ayrı ayrı büyür. İkisi aynı dosyada
#           tutulduğunda sabit bakım tavanı, YENİ BİR TESTİN SEAM'E
#           KAYDEDİLMESİNİ engeller hâle geldi: dosya tam 580/580 idi ve
#           Faz 4 guard testleri bu yüzden sahipsiz kaldı.
#
#           Bu dosya SALT VERİDİR. Genel API değişmedi: birleştirme
#           `mergen_seam_registry()` içinde yapılır ve çağıranlar aynı
#           `guard_tests` / `focused_validation` alanlarını görür.
#
#           Koruyan sözleşme testi: tests/testthat/test-seam-registry-contract.R
# ==============================================================================

mergen_seam_guard_tests <- function() {
  list(
    temel_altyapi = list(
      guard_tests = c(
        "tests/testthat/test-global-source-manifest-contract.R",
        "tests/testthat/test-source-manifest-contract.R",
        "tests/testthat/test-source-manifest-sections-contract.R",
        "tests/testthat/test-safe-source-encoding-contract.R",
        "tests/testthat/test-production-contracts.R",
        "tests/testthat/test-maintainability-ratchet.R",
        "tests/testthat/test-secret-leak-contract.R",
        "tests/testthat/test-runtime-network-boundary-contract.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-source-manifest-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-source-manifest-sections-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-seam-registry-contract.R\")",
        "source(\"tests/scripts/parse_sanity_check.R\", encoding = \"UTF-8\")"
      )
    ),

    veritabani_kodlama = list(
      guard_tests = c(
        "tests/testthat/test-db-refactor-contract.R",
        "tests/testthat/test-db-normalization-contract.R",
        "tests/testthat/test-text-encoding-utils.R",
        "tests/testthat/test-db-user-visible-encoding-boundaries.R",
        "tests/testthat/test-chat-message-formatting-refactor-contract.R",
        "tests/testthat/test-db-chat-read-queries-contract.R",
        "tests/testthat/test-db-pool-behavior.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-db-normalization-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-db-refactor-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-text-encoding-utils.R\")",
        "source(\"tests/scripts/run_vm_encoding_preflight_real.R\", encoding = \"UTF-8\")"
      )
    ),

    kimlik_sso = list(
      guard_tests = c(
        "tests/testthat/test-sso-jwt-signature.R",
        "tests/testthat/test-sso-authorization-failclosed.R",
        "tests/testthat/test-sso-session-identity-smoke.R",
        "tests/testthat/test-e2e-sso-identity-readiness-regression.R",
        "tests/testthat/test-e2e-boot-welcome-regression.R",
        "tests/testthat/test-startup-screen-ui-refactor-contract.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-sso-jwt-signature.R\")",
        "testthat::test_file(\"tests/testthat/test-sso-authorization-failclosed.R\")",
        "testthat::test_file(\"tests/testthat/test-e2e-sso-identity-readiness-regression.R\")"
      )
    ),

    api_anahtar_model = list(
      guard_tests = c(
        "tests/testthat/test-config-api-split-contract.R",
        "tests/testthat/test-api-model-config-refactor-contract.R",
        "tests/testthat/test-api-key-choice-modal-contract.R",
        "tests/testthat/test-config-api-key-crypto-behavior.R",
        "tests/testthat/test-api-key-effective-resolution-behavior.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-config-api-split-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-api-key-choice-modal-contract.R\")"
      )
    ),

    sohbet_llm_akis = list(
      guard_tests = c(
        "tests/testthat/test-send-message-prompting-contract.R",
        "tests/testthat/test-send-message-request-lifecycle-contract.R",
        "tests/testthat/test-server-handler-streaming-tts-contract.R",
        "tests/testthat/test-true-streaming-worker-globals-contract.R",
        "tests/testthat/test-llm-stream-io-contract.R",
        "tests/testthat/test-streaming-poll-lifecycle-contract.R",
        "tests/testthat/test-streaming-markdown-safety-contract.R",
        "tests/testthat/test-true-streaming-reset-ui-contract.R",
        "tests/testthat/test-e2e-quick-actions-streaming-regression.R",
        "tests/testthat/test-langflow-runtime-behavior.R",
        "tests/testthat/test-ortak-oturum-permissions-behavior.R",
        "tests/testthat/test-ortak-oturum-db-behavior.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-send-message-request-lifecycle-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-llm-stream-io-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-streaming-markdown-safety-contract.R\")"
      )
    ),

    mcp_analiz = list(
      guard_tests = c(
        "tests/testthat/test-mcp-excel-resolve.R",
        "tests/testthat/test-mcp-bootstrap-refactor-contract.R",
        "tests/testthat/test-mcp-session-user-id-contract.R",
        "tests/testthat/test-chartlab-spec-refactor-contract.R",
        "tests/testthat/test-pk-analysis-security-summary-contract.R",
        "tests/testthat/test-pk-text-turkish-behavior.R",
        "tests/testthat/test-pk-query-meta-contract.R",
        "tests/testthat/test-pk-analysis-packet-behavior.R",
        "tests/testthat/test-pk-numeric-provenance-contract.R",
        "tests/testthat/test-pk-export-xlsx-behavior.R",
        # Teslim/doğrulama sözleşmeleri de bu seam'e aittir: paket doğru kurulsa
        # bile yanıt teslimi veya sayısal köken bozuksa seam YEŞİL olmamalıdır.
        "tests/testthat/test-pk-provenance-delivery-contract.R",
        "tests/testthat/test-pk-observation-accuracy-contract.R",
        # Faz 4 (§5.4) varlık çözümleme. Bu testler bu seam'e AİTTİR: kayıtlı
        # olmadıklarında normalleştirme/puanlama/karar/geçmiş bozulsa bile
        # değişiklik kapsamlı seam doğrulaması YEŞİL raporlar ve kusuru
        # yalnızca çok daha yavaş tam suite yakalar.
        "tests/testthat/test-pk-entity-normalize-behavior.R",
        "tests/testthat/test-pk-entity-score-behavior.R",
        "tests/testthat/test-pk-entity-resolver-contract.R",
        "tests/testthat/test-pk-entity-history-behavior.R",
        "tests/testthat/test-pk-entity-apply-behavior.R",
        # Faz 5 (§5.2) iki geçişli sorgu seçimi. Bu seam'e AİTTİR: seçim
        # bozulursa analiz doğru veriyi YANLIŞ soruya karşı çalıştırır ve
        # aşağı akıştaki hiçbir kontrol bunu yakalayamaz.
        "tests/testthat/test-pk-query-retrieval-behavior.R",
        "tests/testthat/test-pk-query-selection-contract.R",
        "tests/testthat/test-pk-golden-set-behavior.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-mcp-excel-resolve.R\")",
        "testthat::test_file(\"tests/testthat/test-pk-entity-resolver-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-pk-entity-score-behavior.R\")",
        "testthat::test_file(\"tests/testthat/test-pk-entity-history-behavior.R\")",
        "testthat::test_file(\"tests/testthat/test-pk-analysis-security-summary-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-pk-query-meta-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-pk-analysis-packet-behavior.R\")",
        "testthat::test_file(\"tests/testthat/test-pk-export-xlsx-behavior.R\")",
        "testthat::test_file(\"tests/testthat/test-pk-numeric-provenance-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-pk-provenance-delivery-contract.R\")"
      )
    ),

    dosya_yasam_dongusu = list(
      guard_tests = c(
        "tests/testthat/test-file-lifecycle-hardening-contract.R",
        "tests/testthat/test-file-manager-display-name-contract.R",
        "tests/testthat/test-file-resolution-security-contract.R",
        "tests/testthat/test-resolve-uploaded-file.R",
        "tests/testthat/test-upload-validator.R",
        "tests/testthat/test-upload-size-policy.R",
        "tests/testthat/test-image-generation-ui-refactor-contract.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-file-lifecycle-hardening-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-file-resolution-security-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-upload-validator.R\")"
      )
    ),

    medya_ses = list(
      guard_tests = c(
        "tests/testthat/test-e2e-media-audio-state-regression.R",
        "tests/testthat/test-audio-lifecycle-owner-smoke.R",
        "tests/testthat/test-saved-chat-reload-no-tts-contract.R",
        "tests/testthat/test-generated-image-card-html-contract.R",
        "tests/testthat/test-speech-asset-tree-contract.R",
        "tests/testthat/test-speech-voice-profiles-behavior.R",
        "tests/testthat/test-speech-playback-policy-behavior.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-e2e-media-audio-state-regression.R\")",
        "testthat::test_file(\"tests/testthat/test-audio-lifecycle-owner-smoke.R\")"
      )
    ),

    bilge_yolac = list(
      guard_tests = c(
        "tests/testthat/test-claude-code-security-policy-contract.R",
        "tests/testthat/test-claude-code-run-lifecycle-contract.R",
        "tests/testthat/test-claude-code-stream-html-safety-contract.R",
        "tests/testthat/test-claude-code-process-refactor-contract.R",
        "tests/testthat/test-claude-code-runtime-workdir-contract.R",
        "tests/testthat/test-claude-code-document-download-link-encoding.R",
        "tests/testthat/test-bilge-savunmasi-db-behavior.R",
        "tests/testthat/test-bilge-savunmasi-lifecycle-contract.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-claude-code-security-policy-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-claude-code-run-lifecycle-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-claude-code-stream-html-safety-contract.R\")"
      )
    ),

    destek_yonetici_saglik = list(
      guard_tests = c(
        "tests/testthat/test-admin-hata-analizi-refactor-contract.R",
        "tests/testthat/test-admin-geri-bildirim-refactor-contract.R",
        "tests/testthat/test-admin-geri-bildirim-outputs-behavior.R",
        "tests/testthat/test-admin-geri-bildirim-output-tables-behavior.R",
        "tests/testthat/test-admin-yanit-analizi-refactor-contract.R",
        "tests/testthat/test-admin-yanit-analizi-outputs-behavior.R",
        "tests/testthat/test-e2e-health-dashboard-regression.R",
        "tests/testthat/test-health-check-env-contract.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-e2e-health-dashboard-regression.R\")",
        "testthat::test_file(\"tests/testthat/test-admin-hata-analizi-refactor-contract.R\")"
      )
    ),

    shiny_calisma_zamani = list(
      guard_tests = c(
        "tests/testthat/test-server-runtime-context.R",
        "tests/testthat/test-server-runtime-auth-ready-split-contract.R",
        "tests/testthat/test-server-core-interaction-runtime.R",
        "tests/testthat/test-server-core-observer-runtime-contract.R",
        "tests/testthat/test-server-module-wiring-contract.R",
        "tests/testthat/test-server-live-user-provider-contract.R",
        "tests/testthat/test-session-user-data-store.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-server-runtime-context.R\")",
        "testthat::test_file(\"tests/testthat/test-server-core-interaction-runtime.R\")",
        "testthat::test_file(\"tests/testthat/test-server-module-wiring-contract.R\")"
      )
    ),

    frontend_varlik = list(
      guard_tests = c(
        "tests/testthat/test-ui-asset-manifest-contract.R",
        "tests/testthat/test-ui-asset-config-split-contract.R",
        "tests/testthat/test-ui-asset-zones-contract.R",
        "tests/testthat/test-ui-asset-zone-validators-split-contract.R",
        "tests/testthat/test-frontend-selector-contract.R",
        "tests/testthat/test-frontend-maintainability-ratchet.R",
        "tests/testthat/test-browser-smoke-harness-contract.R",
        "tests/testthat/test-ux-smoke-browser-contract.R",
        "tests/testthat/test-smoke-probes-contract.R"
      ),
      focused_validation = c(
        "testthat::test_file(\"tests/testthat/test-ui-asset-manifest-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-ui-asset-zones-contract.R\")",
        "testthat::test_file(\"tests/testthat/test-frontend-selector-contract.R\")",
        "source(\"tests/scripts/frontend_maintainability_report.R\", encoding = \"UTF-8\")"
      )
    )
  )
}
