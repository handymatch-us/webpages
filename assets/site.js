// HandyMatch — small enhancements. The pages still display without this file.
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

  // Where the visitor came from (e.g. ?utm_source=google), saved with the request.
  function trafficSource() {
    try {
      var params = new URLSearchParams(window.location.search);
      return params.get('utm_source') || params.get('source') || (document.referrer ? new URL(document.referrer).hostname : 'direct');
    } catch (e) { return null; }
  }

  // Homeowner request form: send to the Supabase function.
  var requestForm = document.getElementById('request-form');
  if (requestForm && requestForm.dataset.endpoint) {
    requestForm.addEventListener('submit', function (event) {
      event.preventDefault();
      if (!requestForm.reportValidity()) return;

      var status = requestForm.querySelector('.form-status');
      var button = requestForm.querySelector('button[type="submit"]');
      var consent = requestForm.querySelector('.consent');
      var data = new FormData(requestForm);

      var payload = {
        service: data.get('service'),
        details: data.get('details'),
        zip: data.get('zip'),
        timing: data.get('timing'),
        name: data.get('name'),
        phone: data.get('phone'),
        website: data.get('website'),
        consent: true,
        consent_text: consent ? consent.textContent.replace(/\s+/g, ' ').trim() : '',
        source: trafficSource()
      };

      button.disabled = true;
      button.textContent = 'Sending…';
      status.textContent = '';

      fetch(requestForm.dataset.endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
        .then(function (res) { return res.json().catch(function () { return {}; }).then(function (body) { return { ok: res.ok, body: body }; }); })
        .then(function (result) {
          if (result.ok) {
            status.textContent = 'Thanks! Your matched pro will contact you shortly.';
            requestForm.reset();
          } else if (result.body && result.body.fields) {
            var labels = { service: 'service', name: 'name', zip: 'ZIP code', phone: 'mobile phone (10 digits)', consent: 'consent' };
            status.textContent = 'Please check: ' + result.body.fields.map(function (f) { return labels[f] || f; }).join(', ') + '.';
          } else {
            status.textContent = (result.body && result.body.error) || 'Something went wrong. Please try again or call us.';
          }
        })
        .catch(function () {
          status.textContent = 'We couldn’t send that. Check your connection and try again, or call us.';
        })
        .finally(function () {
          button.disabled = false;
          button.textContent = 'Get matched with a pro';
        });
    });
  }

  // Forms still in demo mode (the pro sign-up form): show a thank-you only.
  document.querySelectorAll('form[data-demo="true"]').forEach(function (form) {
    form.addEventListener('submit', function (event) {
      if (form.getAttribute('action')) return;
      event.preventDefault();
      if (!form.reportValidity()) return;
      var status = form.querySelector('.form-status');
      if (status) status.textContent = 'Thanks! We’ll text you within one business day to finish setup.';
      form.reset();
    });
  });
})();
