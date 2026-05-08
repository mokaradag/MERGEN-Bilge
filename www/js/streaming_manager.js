// www/js/streaming_manager.js

$(document).ready(function() {

    function getStreamingState(messageDiv) {
        if (!messageDiv.__streamingState) {
            messageDiv.__streamingState = {
                accumulatedText: '',
                renderTimer: null,
                requestId: '',
                finalized: false
            };
        }
        return messageDiv.__streamingState;
    }

    function normalizeRequestId(value) {
        return (typeof value === 'string') ? value : '';
    }

    function isStaleStreamingPayload(state, data) {
        const payloadRequestId = normalizeRequestId(data && data.requestId);
        return !!(state.requestId && payloadRequestId && state.requestId !== payloadRequestId);
    }

    function getStreamingContentDiv(messageDiv) {
        let contentDiv = messageDiv.querySelector('.streaming-content');
        if (!contentDiv) {
            contentDiv = messageDiv;
        }
        return contentDiv;
    }

    function renderStreamingBuffer(messageDiv) {
        const state = getStreamingState(messageDiv);
        const contentDiv = getStreamingContentDiv(messageDiv);

        const formattedHtml = typeof parseStreamingMarkdown === 'function'
            ? parseStreamingMarkdown(state.accumulatedText)
            : state.accumulatedText;

        contentDiv.innerHTML = formattedHtml;
        state.renderTimer = null;

        if (typeof window.smartScrollToBottom === 'function') {
            window.smartScrollToBottom(false);
        }
    }

    function scheduleStreamingRender(messageDiv, immediate) {
        const state = getStreamingState(messageDiv);

        if (state.renderTimer) {
            clearTimeout(state.renderTimer);
            state.renderTimer = null;
        }

        if (immediate === true) {
            renderStreamingBuffer(messageDiv);
            return;
        }

        state.renderTimer = window.setTimeout(function() {
            renderStreamingBuffer(messageDiv);
        }, 16);
    }

    // Akış (Streaming) mesajını başlat - Mesaj kutusunu hazırlar
    Shiny.addCustomMessageHandler('initStreamingMessage', function(data) {
        const messageDiv = document.getElementById(data.id);
        if (messageDiv) {
            messageDiv.innerHTML = '<div class="streaming-content" data-streaming="true"></div>';
            messageDiv.dataset.streaming = 'true';

            const state = getStreamingState(messageDiv);
            state.accumulatedText = data.content || '';
            state.requestId = normalizeRequestId(data.requestId);
            state.finalized = false;
            if (state.renderTimer) {
                clearTimeout(state.renderTimer);
                state.renderTimer = null;
            }

            const wrapper = document.getElementById('message_wrapper_' + data.id);
            if (wrapper) {
                const actionButtons = wrapper.querySelectorAll('.streaming-hidden');
                actionButtons.forEach(btn => {
                    btn.style.display = 'none';
                });
            }
        }
    });

    // Hızlı delta ekleme işleyicisi
    Shiny.addCustomMessageHandler('streamingDelta', function(data) {
        const messageDiv = document.getElementById(data.id);
        if (!messageDiv) return;

        const state = getStreamingState(messageDiv);
        if (state.finalized || isStaleStreamingPayload(state, data)) return;

        const delta = typeof data.delta === 'string' ? data.delta : '';

        if (!delta.length) return;

        state.accumulatedText += delta;
        scheduleStreamingRender(messageDiv, false);
    });

    // Geriye dönük uyumlu tam içerik güncelleme işleyicisi
    Shiny.addCustomMessageHandler('streamingUpdate', function(data) {
        const messageDiv = document.getElementById(data.id);
        if (!messageDiv) return;

        const state = getStreamingState(messageDiv);
        if (state.finalized || isStaleStreamingPayload(state, data)) return;

        state.accumulatedText = typeof data.text === 'string' ? data.text : (state.accumulatedText || '');

        if (data.isPartial) {
            scheduleStreamingRender(messageDiv, false);
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

        const state = getStreamingState(messageDiv);
        if (isStaleStreamingPayload(state, data) || state.finalized) return;

        state.finalized = true;

        if (state.renderTimer) {
            clearTimeout(state.renderTimer);
            state.renderTimer = null;
        }

        messageDiv.dataset.streaming = "false";

        const wrapper = document.getElementById('message_wrapper_' + data.id);
        if (wrapper) {
            const aiMessage = wrapper.querySelector('.ai-message');
            if (aiMessage) {
                aiMessage.classList.remove('streaming-message');
            }

            const actionButtons = wrapper.querySelectorAll('.streaming-hidden');
            actionButtons.forEach(btn => {
                btn.classList.remove('streaming-hidden');
                btn.style.display = 'inline-flex';
                btn.disabled = false;
            });
        }

        messageDiv.innerHTML = data.html;

        if (typeof window.wrapMessageTables === 'function') {
            window.wrapMessageTables(messageDiv);
        }

        if (window.initializeCodeMirrorInElement) {
            setTimeout(() => window.initializeCodeMirrorInElement('message_wrapper_' + data.id), 0);
        }

        const followupBox = document.getElementById('followup_container_' + data.id);
        if (followupBox) {
            followupBox.classList.remove('pending');
        }

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