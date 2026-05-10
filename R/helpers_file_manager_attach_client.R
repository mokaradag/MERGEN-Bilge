# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_attach_client.R
# Açıklama: Dosya Yönetimi model bağlamı checkbox durumunu istemci tarafında
#           sessizce güncelleyen küçük JS kayıt yardımcısını içerir.
# ==============================================================================

fm_register_attach_state_client_handler <- function(session, ns) {
  session$onFlushed(function() {
    shinyjs::runjs(sprintf("
      (function(){
        window.__attachHandlerInit = window.__attachHandlerInit || {};
        var nsPrefix = '%s';
        if (window.__attachHandlerInit[nsPrefix]) return;
        window.__attachHandlerInit[nsPrefix] = true;
        Shiny.addCustomMessageHandler('initAttachHandlerOnce', function(x){ /* no-op; gate */ });
        Shiny.addCustomMessageHandler(nsPrefix + 'setAttachState', function(msg){
          var ids = Array.isArray(msg.ids) ? msg.ids : [msg.ids];
          ids.forEach(function(fid){
            var el = document.getElementById(nsPrefix + 'attach_' + fid);
            if(el){ el.checked = !!msg.checked; }
          });
        });
      })();
    ", ns("")))
  }, once = TRUE)

  invisible(TRUE)
}