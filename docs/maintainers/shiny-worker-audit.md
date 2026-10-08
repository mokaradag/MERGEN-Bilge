# Shiny ve worker yaşam döngüsü denetimi

İncelenen main: `09b26d8aa28d8dfeae6d85a5ff605b5014950ea4` (8 Ekim 2026).
Denetimdeki on bulgu giderildi: sonuçlar istek/sohbet/sahip sınırlarında korunur; Yolaç devam bağları sahip değişiminde temizlenir. Takip üretimi, büyük DOCX kodlaması ve indeks kilidi işçilere taşınır; işçi hataları ana süreçte yeniden yürütülmez. Çalışan Yolaç kayıt kimliği görünümden bağımsız saklanır; LLM işçi ayarları canlı Shiny oturumu taşımaz.

- [`R/server_handler_true_streaming.R:379`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/server_handler_true_streaming.R#L379)
- [`R/module_claude_code.R:207`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/module_claude_code.R#L207)
- [`R/helpers_stream_load_control.R:127`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/helpers_stream_load_control.R#L127)
- [`R/module_file_preview.R:428`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/module_file_preview.R#L428)
- [`R/module_ai_processing.R:169`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/module_ai_processing.R#L169)
- [`R/server_handler_pk_async.R:47`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/server_handler_pk_async.R#L47)
- [`R/helpers_claude_code_session_persistence.R:370`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/helpers_claude_code_session_persistence.R#L370)
- [`R/helpers_file_ingestion_runtime.R:135`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/helpers_file_ingestion_runtime.R#L135)
- [`R/helpers_claude_code_server_setup.R:463`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/helpers_claude_code_server_setup.R#L463)
- [`R/module_ai_processing.R:113`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/module_ai_processing.R#L113)
