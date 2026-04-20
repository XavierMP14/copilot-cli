/* KRUMAQ — main.js
   Progressive enhancement: nav toggle, FAQ accordion, form feedback
*/

(function () {
  'use strict';

  /* ── Mobile navigation toggle ──────────────────────────── */
  const toggle = document.querySelector('.nav-toggle');
  const navLinks = document.querySelector('.nav-links');
  if (toggle && navLinks) {
    toggle.addEventListener('click', function () {
      const open = navLinks.classList.toggle('open');
      toggle.setAttribute('aria-expanded', open);
    });
    // Close when a link is clicked
    navLinks.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        navLinks.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    });
  }

  /* ── Mark active nav link ──────────────────────────────── */
  const currentPage = window.location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-links a').forEach(function (a) {
    const href = a.getAttribute('href');
    if (href && (href === currentPage || href.endsWith('/' + currentPage))) {
      a.classList.add('active');
    }
  });

  /* ── FAQ accordion ─────────────────────────────────────── */
  document.querySelectorAll('.faq-item').forEach(function (item) {
    const q = item.querySelector('.faq-q');
    if (!q) return;
    q.addEventListener('click', function () {
      const isOpen = item.classList.contains('open');
      // Close all
      document.querySelectorAll('.faq-item.open').forEach(function (o) {
        o.classList.remove('open');
        o.querySelector('.faq-q').setAttribute('aria-expanded', 'false');
      });
      // Open this one if it was closed
      if (!isOpen) {
        item.classList.add('open');
        q.setAttribute('aria-expanded', 'true');
      }
    });
    q.setAttribute('aria-expanded', 'false');
    q.setAttribute('role', 'button');
    q.setAttribute('tabindex', '0');
    q.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); q.click(); }
    });
  });

  /* ── Contact form — client-side feedback ───────────────── */
  const form = document.querySelector('form.contact-form');
  if (form) {
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      const btn = form.querySelector('[type=submit]');
      const original = btn.textContent;
      btn.disabled = true;
      btn.textContent = 'Enviando…';
      // Simulated async submit — replace with real fetch() to your backend/API
      setTimeout(function () {
        const msg = document.createElement('p');
        msg.style.cssText = 'color:#25a244;font-weight:600;margin-top:.8rem;';
        msg.textContent = '✅ ¡Mensaje enviado! Le contactaremos pronto.';
        form.appendChild(msg);
        form.reset();
        btn.disabled = false;
        btn.textContent = original;
      }, 900);
    });
  }

  /* ── Smooth-scroll for anchor links ────────────────────── */
  document.querySelectorAll('a[href^="#"]').forEach(function (a) {
    a.addEventListener('click', function (e) {
      const target = document.querySelector(a.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });

})();
