// Taiwan Air — official site behaviour: mobile menu, scroll reveals, tagline word reveal.
(function () {
  "use strict";
  var doc = document.documentElement;
  doc.classList.remove("no-js");
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Mobile menu: full height panel, links arrive in reading order (60 ms apart, 400 ms cap).
  var btn = document.querySelector(".menu-btn");
  var panel = document.getElementById("menu");
  if (btn && panel) {
    var links = Array.prototype.slice.call(panel.querySelectorAll("a"));
    var setOpen = function (open) {
      btn.setAttribute("aria-expanded", String(open));
      panel.classList.toggle("open", open);
      panel.setAttribute("aria-hidden", String(!open));
      if ("inert" in panel) panel.inert = !open;
      document.body.style.overflow = open ? "hidden" : "";
      var step = Math.min(60, links.length > 1 ? 400 / (links.length - 1) : 0);
      links.forEach(function (a, i) { a.style.transitionDelay = open && !reduce ? i * step + "ms" : "0ms"; });
      if (open && links[0]) links[0].focus({ preventScroll: true });
    };
    setOpen(false);
    btn.addEventListener("click", function () { setOpen(btn.getAttribute("aria-expanded") !== "true"); });
    links.forEach(function (a) { a.addEventListener("click", function () { setOpen(false); }); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && panel.classList.contains("open")) { setOpen(false); btn.focus(); }
    });
    window.matchMedia("(min-width: 900px)").addEventListener("change", function (m) { if (m.matches) setOpen(false); });
  }

  // Sections rise and fade in once.
  var reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -10% 0px", threshold: 0.1 });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add("in"); });
  }

  // Tagline: each word (each character for Chinese) lights up as it crosses 65% of the viewport.
  var tag = document.querySelector("[data-reveal-words]");
  if (tag) {
    var zh = /^zh/.test(tag.closest("[lang]").getAttribute("lang"));
    var parts = [];
    Array.prototype.slice.call(tag.childNodes).forEach(function (node) {
      if (node.nodeType === 1 && node.tagName === "BR") { parts.push(node.cloneNode()); return; }
      var text = node.textContent;
      var tokens = zh ? Array.from(text.replace(/\s+/g, "")) : text.split(/(\s+)/);
      tokens.forEach(function (t) {
        if (!t) return;
        if (/^\s+$/.test(t)) { parts.push(document.createTextNode(" ")); return; }
        var s = document.createElement("span");
        s.className = "w";
        s.textContent = t;
        parts.push(s);
      });
    });
    tag.textContent = "";
    parts.forEach(function (p) { tag.appendChild(p); });
    var words = tag.querySelectorAll(".w");
    if (reduce) {
      words.forEach(function (w) { w.classList.add("on"); });
    } else {
      var ticking = false;
      var update = function () {
        ticking = false;
        var r = tag.getBoundingClientRect();
        var line = window.innerHeight * 0.65;
        // Progress from the block's top reaching the line to its bottom reaching it.
        var p = (line - r.top) / Math.max(r.height, 1);
        var lit = Math.round(Math.max(0, Math.min(1, p)) * words.length);
        for (var i = 0; i < words.length; i++) words[i].classList.toggle("on", i < lit);
      };
      var onScroll = function () { if (!ticking) { ticking = true; requestAnimationFrame(update); } };
      window.addEventListener("scroll", onScroll, { passive: true });
      window.addEventListener("resize", onScroll);
      update();
    }
  }
})();
