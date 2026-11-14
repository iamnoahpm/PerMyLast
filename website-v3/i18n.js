// Per My Last — Vietnamese language suggestion banner (English pages only).
//
// This does NOT redirect anyone. Google explicitly advises against
// auto-redirecting by geo-IP/language on multi-regional sites: it can trap
// crawlers in one locale and breaks the experience for anyone who explicitly
// wanted this exact URL. Real Vietnamese content lives at stable URLs
// (/vi/...) with hreflang annotations, so it's independently indexable —
// this banner is just a courtesy nudge for a first-time visitor who looks
// like they're browsing from Vietnam.
(function () {
  var DISMISS_KEY = 'pml-lang-banner-dismissed';
  var GEO_TIMEOUT_MS = 1200;
  var GEO_ENDPOINT = 'https://ipapi.co/json/';

  var banner = document.getElementById('lang-banner');
  if (!banner) return;

  var dismissed = false;
  try { dismissed = localStorage.getItem(DISMISS_KEY) === '1'; } catch (e) { /* ignore */ }
  if (dismissed) return;

  function showBanner() {
    banner.hidden = false;
  }

  function dismiss() {
    banner.hidden = true;
    try { localStorage.setItem(DISMISS_KEY, '1'); } catch (e) { /* ignore */ }
  }

  var dismissBtn = banner.querySelector('.lang-banner__dismiss');
  if (dismissBtn) dismissBtn.addEventListener('click', dismiss);

  var viLink = banner.querySelector('.lang-banner__link');
  if (viLink) viLink.addEventListener('click', function () {
    // Following the link means the visitor made an explicit choice — don't
    // show this again on their next visit to the English page.
    try { localStorage.setItem(DISMISS_KEY, '1'); } catch (e) { /* ignore */ }
  });

  var settled = false;
  var timer = setTimeout(function () { settled = true; }, GEO_TIMEOUT_MS);

  fetch(GEO_ENDPOINT, { cache: 'no-store' })
    .then(function (res) { return res.ok ? res.json() : null; })
    .then(function (data) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (data && data.country_code === 'VN') showBanner();
    })
    .catch(function () {
      settled = true;
      clearTimeout(timer);
      // Fails silent — no banner, no error surfaced to the visitor.
    });
})();
