// www/js/feedback_modal.js
// Geri bildirim modalı istemci tarafı işlemleri

Shiny.addCustomMessageHandler('updateFeedbackTitle', function(data) {
  const titleEl = document.getElementById(data.ns);
  if (titleEl) {
    titleEl.innerHTML = data.html;
  }
});

Shiny.addCustomMessageHandler('updateFeedbackTags', function(data) {
  const container = document.getElementById(data.target);
  if (container) {
    container.innerHTML = data.html;
  }
});

Shiny.addCustomMessageHandler('toggleFeedbackTag', function(data) {
  const buttons = document.querySelectorAll('.feedback-tag-btn[data-tag="' + data.tag + '"]');
  buttons.forEach(btn => {
    btn.classList.toggle('active');
  });
});