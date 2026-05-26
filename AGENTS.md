# AGENTS.md

Bu repo için birincil rehber `CLAUDE.md` dosyasıdır. Bu dosya, özellikle kodlama, test, güvenlik ve operasyonel koruma kurallarında temel kaynaktır.

## Validation before final answer

- Normal validation command remains `bash tools/ai_validate.sh quick`.
- Codex/Claude cloud fallback validation is `bash tools/ai_validate.sh cloud-quick`.
- `cloud-quick` intentionally skips heavy runtime package bootstrap (for example `duckdb`, `arrow`) and app source smoke; agents must explicitly state this mode was used and that full runtime/app boot validation was not performed.
- Final teknik yanıt vermeden önce en az `bash tools/ai_validate.sh quick` çalıştır.
- Riskli/runtime/SSO/DB encoding/source-order/file lifecycle/streaming/frontend asset order/Bilge Yolaç-Claude Code/security-path-download/production-VM etkili değişikliklerde `bash tools/ai_validate.sh full --boot-smoke` çalıştır.
- Uzun teknik yanıt taslağını önce `.ai/proposed_answer.md` içine yaz, sonra `bash tools/ai_validate.sh quick --answer .ai/proposed_answer.md` ile doğrula.
- `Rscript` yoksa doğrudan vazgeçme; önce `bash tools/setup_ai_r_environment.sh` veya `bash tools/ai_validate.sh quick` çalıştırarak ortamı hazırlamayı dene.
- `Rscript` ancak bootstrap betiği de başarısız olursa “kullanılamıyor” denebilir. Bu durumda komutun tam çıktısını ve başarısız adımı belirt.
- Gerekli script eksikse hangisinin eksik olduğunu açıkça belirt; başarılı sonuç uydurma.
- Doğrulama başarısızsa başarısız adımı ve üretilen artifact/log yolunu özetle; hatayı gizleme.
- “tests passed”, “I verified”, “I ran the app”, “the check is green” benzeri ifadeleri yalnızca ilgili komut gerçekten başarıyla bittiğinde ve doğrulama özetinde sıfır failed step olduğunda kullan.