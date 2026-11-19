// HandyMatch — small progressive enhancements. The site works without this file.
(function () {
  // Clicking a "Popular jobs" tile pre-selects that service in the request form.
  var serviceSelect = document.querySelector('#request-form select[name="service"]');
  document.querySelectorAll('[data-service]').forEach(function (tile) {
    tile.addEventListener('click', function () {
      if (!serviceSelect) return;
      serviceSelect.value = tile.getAttribute('data-service');
      setTimeout(function () { serviceSelect.focus(); }, 300);
    });
  });

  // Demo mode: forms with data-demo="true" and no action URL show a thank-you
  // message instead of submitting. Remove data-demo and set action="" to your
  // lead endpoint when it's ready.
  document.querySelectorAll('form[data-demo="true"]').forEach(function (form) {
    form.addEventListener('submit', function (event) {
      if (form.getAttribute('action')) return;
      event.preventDefault();
      if (!form.reportValidity()) return;
      var status = form.querySelector('.form-status');
      if (status) {
        status.textContent = form.id === 'pro-form'
          ? 'Thanks! We’ll text you within one business day to finish setup.'
          : 'Thanks! Your matched pro will contact you shortly.';
      }
      form.reset();
    });
  });
})();
