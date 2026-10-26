// Per My Last — language dropdown: close on outside click or Escape.
(function () {
  var menus = document.querySelectorAll('.lang-menu');
  if (!menus.length) return;
  document.addEventListener('click', function (e) {
    menus.forEach(function (m) { if (!m.contains(e.target)) m.removeAttribute('open'); });
  });
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    menus.forEach(function (m) { m.removeAttribute('open'); });
  });
})();

// Per My Last — nav: a translucent bar appears once the page is scrolled.
(function () {
  var nav = document.querySelector('.nav');
  if (!nav) return;
  function update() { nav.classList.toggle('is-scrolled', window.scrollY > 8); }
  window.addEventListener('scroll', update, { passive: true });
  update();
})();
