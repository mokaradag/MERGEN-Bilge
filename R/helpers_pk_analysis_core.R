# ==============================================================================
# Proje/Kaynak Analizi çekirdeği yükleyicisi.
# ==============================================================================
source("R/helpers_pk_analysis_core_impl.R", encoding = "UTF-8", local = environment())

if (exists("pk_async_run_analysis", mode = "function", inherits = TRUE) &&
    exists("execute_single_deep_query", mode = "function", inherits = TRUE)) {
  source("R/helpers_pk_p1_runtime_guards.R", encoding = "UTF-8", local = environment())
}
