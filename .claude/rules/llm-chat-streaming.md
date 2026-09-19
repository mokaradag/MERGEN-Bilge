---
paths:
  - "R/helpers_llm*.R"
  - "R/helpers_chat*.R"
  - "R/helpers_messaging.R"
  - "R/helpers_send_message*.R"
  - "R/helpers_followup_questions.R"
  - "R/helpers_langflow*.R"
  - "R/**/*vision*.R"
  - "R/module_chat*.R"
  - "R/module_saved_chats.R"
  - "R/server_*chat*.R"
  - "R/server_send_message.R"
  - "R/server_llm_response_handlers.R"
  - "www/**/*stream*.js"
  - "tests/**/*llm*.R"
  - "tests/**/*chat*.R"
  - "tests/**/*stream*.R"
  - "tests/**/*reasoning*.R"
  - "tests/**/*vision*.R"
---

# LLM, chat, reasoning and streaming

- Request lifecycle/current-request guards prevent stale async results from
  mutating newer chat state. Preserve them across every promise/callback path.
- Worker payloads must contain serializable, intentional dependencies; explicit
  future globals must stay complete.
- SSE/stream readers preserve event boundaries, UTF-8 chunks, incremental
  reasoning/content, stop-file checks and final-result semantics.
- Do not reconstruct final text from a truncated live display buffer when a
  canonical final result exists.
- Tool-result dataframe formatting preserves real-data headings/table/counts,
  source-table warnings and preview helper ownership; do not silently fall back
  to JSON when a valid dataframe preview exists.
- Reasoning visibility/persistence and model request overrides must remain
  aligned across streaming and non-streaming paths.
- Raw model/user HTML is escaped before browser hydration; markdown/code-block
  integrity must survive long responses and saved-chat restore.
- Quick-action/follow-up behavior is deterministic where designed and must not
  trigger unnecessary LLM work.
- Do not duplicate model capability/config snapshots in Claude memory; inspect
  the current model/config helpers.
- Logging of LLM/reasoning paths must remain redacted and gated.
- Consult archived streaming/reasoning/tool-result/request-lifecycle headings
  only when current tests do not capture the rationale.
