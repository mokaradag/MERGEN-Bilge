// www/js/streaming_manager.js

$(document).ready(function() {
    const streamingState = new Map();
    
    // Akış (Streaming) mesajını başlat - Mesaj kutusunu hazırlar
    Shiny.addCustomMessageHandler('initStreamingMessage', function(data) {
        const messageDiv = document.getElementById(data.id);
        if (messageDiv) {
            // İçeriği temizle ve streaming işaretini koy
            messageDiv.innerHTML = '<div class="streaming-content" data-streaming="true"></div>';
            messageDiv.dataset.streaming = 'true';
            streamingState.set(data.id, { rawText: '', raf: null });
            
            // Aksiyon butonlarını (kopyala, beğen vb.) akış bitene kadar gizle
            const wrapper = document.getElementById('message_wrapper_' + data.id);
            if (wrapper) {
            const actionButtons = wrapper.querySelectorAll('.streaming-hidden');
            actionButtons.forEach(btn => {
                btn.style.display = 'none';
            });
            }
        }
    });

    // Gelişmiş akış güncelleme işleyicisi - Parça parça gelen metni işler
    Shiny.addCustomMessageHandler('streamingUpdate', function(data) {
        const messageDiv = document.getElementById(data.id);
        if (!messageDiv) return;
        
        let contentDiv = messageDiv.querySelector('.streaming-content');
        if (!contentDiv) {
            contentDiv = messageDiv;
        }
        
        if (data.isPartial) {
            // Performans için ara aşamada sade metin gösteriyoruz.
            // Markdown biçimleme sadece finalizeStreamingMessage aşamasında yapılır.
            const state = streamingState.get(data.id) || { rawText: '', raf: null };
            if (typeof data.delta === 'string' && data.delta.length > 0) {
                state.rawText += data.delta;
            } else if (typeof data.text === 'string') {
                state.rawText = data.text;
            }

            if (!state.raf) {
                state.raf = window.requestAnimationFrame(function() {
                    contentDiv.textContent = state.rawText;
                    state.raf = null;
                    if (typeof window.smartScrollToBottom === 'function') {
                        window.smartScrollToBottom(false);
                    }
                });
            }

            streamingState.set(data.id, state);
        }
    });

    // Eski tip akış işleyicisi (Geriye dönük uyumluluk için)
    Shiny.addCustomMessageHandler('streamUpdate', function(message) {
        try {
            const message_div = $('#' + message.id);
            if (message_div.length > 0) {
            let content_area = message_div.find('.message-content-body');
            if (content_area.length === 0) {
                message_div.html('<div class="message-content-body"></div>');
                content_area = message_div.find('.message-content-body');
            }
            content_area.text(content_area.text() + message.text);
            }
        } catch (e) {
            console.error('Eski streamUpdate işleyicisinde hata:', e);
        }
    });

    // Akış mesajını sonlandırma ve temizleme
    Shiny.addCustomMessageHandler('finalizeStreamingMessage', function(data) {
        const messageDiv = document.getElementById(data.id);
        if (!messageDiv) return;
        
        // Akış durumunu kapat
        messageDiv.dataset.streaming = "false";
        
        // Sınıfları temizle ve butonları göster
        const wrapper = document.getElementById('message_wrapper_' + data.id);
        if (wrapper) {
            const aiMessage = wrapper.querySelector('.ai-message');
            if (aiMessage) {
                aiMessage.classList.remove('streaming-message');
            }
            
            // Gizlenen butonları tekrar görünür yap
            const actionButtons = wrapper.querySelectorAll('.streaming-hidden');
            actionButtons.forEach(btn => {
                btn.classList.remove('streaming-hidden');
                btn.style.display = 'inline-flex';
                btn.disabled = false;
            });
        }
        
        // Son içerik yazıldıktan sonra geçici akış durumunu temizle
        const state = streamingState.get(data.id);
        if (state && state.raf) {
            window.cancelAnimationFrame(state.raf);
        }
        streamingState.delete(data.id);

        // Final HTML içeriğini yerleştir
        messageDiv.innerHTML = data.html;

        // Tabloları kaydırılabilir sarmalayıcıya al
        if (typeof window.wrapMessageTables === 'function') {
            window.wrapMessageTables(messageDiv);
        }

        // CodeMirror (Kod blokları) başlat
        if (window.initializeCodeMirrorInElement) {
            setTimeout(() => window.initializeCodeMirrorInElement('message_wrapper_' + data.id), 0);
        }

        // Takip eden sorular kutusundaki "bekliyor" durumunu kaldır
        const followupBox = document.getElementById('followup_container_' + data.id);
        if (followupBox) {
            followupBox.classList.remove('pending');
        }

        // Son bir kez en alta kaydır (yalnızca kullanıcı zaten alta yakınsa)
        const kullaniciAltaYakinMi = (typeof window.isNearBottom === 'function')
            ? window.isNearBottom()
            : false;
        if (kullaniciAltaYakinMi && typeof window.smartScrollToBottom === 'function') {
            window.smartScrollToBottom();
        }
    });

    // Akış bitti sinyali (Alternatif bitiş)
    Shiny.addCustomMessageHandler('streamEnd', function(message) {
        try {
            const message_div = $('#' + message.id);
            if (message_div.length > 0) {
                if (window.initializeCodeMirror) {
                    window.initializeCodeMirror();
                } else if (window.initializeCodeMirrorInElement) {
                    window.initializeCodeMirrorInElement('message_wrapper_' + message.id);
                }
            }
        } catch(e) {
            console.error("streamEnd hatası:", e);
        }
    });
});