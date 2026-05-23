# AGENTS.md

Bu repo için birincil rehber `CLAUDE.md` dosyasıdır. Bu dosya, özellikle kodlama, test, güvenlik ve operasyonel koruma kurallarında temel kaynaktır.

## Validation before final answer
- Final teknik yanıt vermeden önce en az `Rscript tests/scripts/ai_repo_check.R --profile quick` çalıştır.
- Riskli/runtime/SSO/DB encoding/source-order/file lifecycle/streaming/frontend asset order/Bilge Yolaç-Claude Code/security-path-download/production-VM etkili değişikliklerde `Rscript tests/scripts/ai_repo_check.R --profile full --boot-smoke` çalıştır.
- Uzun teknik yanıt taslağını önce `.ai/proposed_answer.md` içine yaz, sonra `Rscript tests/scripts/ai_repo_check.R --profile quick --answer .ai/proposed_answer.md` ile doğrula.
- `Rscript` yoksa bunu açıkça belirt; repository doğrulandı iması yapma.
- Gerekli script eksikse hangisinin eksik olduğunu açıkça belirt; başarılı sonuç uydurma.
- Doğrulama başarısızsa başarısız adımı ve üretilen artifact/log yolunu özetle; hatayı gizleme.
- “tests passed”, “I verified”, “I ran the app”, “the check is green” benzeri ifadeleri yalnızca ilgili komut gerçekten başarıyla bittiğinde ve doğrulama özetinde sıfır failed step olduğunda kullan.
