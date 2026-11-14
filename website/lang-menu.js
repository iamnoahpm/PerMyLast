// Per My Last — language dropdown: close on outside click or Escape.
(function () {
  var menus = document.querySelectorAll('.lang-menu, .contact-menu');
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

// Per My Last — mobile nav: a hamburger button opens the page links.
(function () {
  var nav = document.querySelector('.nav');
  if (!nav) return;
  var right = nav.querySelector('.nav__right');
  var group = nav.querySelector('.nav__group');
  if (!right || !group) return;

  var btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'nav__burger';
  btn.setAttribute('aria-label', 'Menu');
  btn.setAttribute('aria-expanded', 'false');
  btn.setAttribute('aria-controls', 'nav-menu');
  btn.innerHTML = '<span></span><span></span>';
  right.appendChild(btn);

  var panel = document.createElement('div');
  panel.id = 'nav-menu';
  panel.className = 'nav__menu';
  panel.hidden = true;
  Array.prototype.forEach.call(group.children, function (child) {
    if (child.tagName === 'A') {
      var l = child.cloneNode(true);
      l.className = 'nav__menu-link';
      panel.appendChild(l);
    } else if (child.classList.contains('contact-menu')) {
      var label = document.createElement('span');
      label.className = 'nav__menu-label';
      label.textContent = child.querySelector('summary').textContent;
      panel.appendChild(label);
      child.querySelectorAll('.contact-menu__panel a').forEach(function (a) {
        var c = a.cloneNode(true);
        c.className = 'nav__menu-sub';
        panel.appendChild(c);
      });
    }
  });
  nav.appendChild(panel);

  function setOpen(open) {
    panel.hidden = !open;
    nav.classList.toggle('is-open', open);
    btn.setAttribute('aria-expanded', open ? 'true' : 'false');
  }
  btn.addEventListener('click', function () { setOpen(panel.hidden); });
  panel.addEventListener('click', function (e) { if (e.target.closest('a')) setOpen(false); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') setOpen(false); });
  window.addEventListener('resize', function () { if (window.innerWidth > 520) setOpen(false); });
})();
