// Picks the page language before anything is drawn: ?lang= (the app sends it), then the browser's
// language, then English. Only blocks marked class="l" in that language are shown (site.css).
(function () {
  var langs = ["ja", "en", "zh-TW"];
  function pick() {
    var q = new URLSearchParams(location.search).get("lang");
    if (q && langs.indexOf(q) >= 0) return q;
    var nav = (navigator.languages || [navigator.language || ""]).map(function (l) {
      return String(l).toLowerCase();
    });
    for (var i = 0; i < nav.length; i++) {
      if (nav[i].indexOf("ja") === 0) return "ja";
      if (nav[i].indexOf("zh") === 0) return "zh-TW";
      if (nav[i].indexOf("en") === 0) return "en";
    }
    return "en";
  }
  var lang = pick();
  var root = document.documentElement;
  root.lang = lang;
  root.setAttribute("data-lang", lang);
  window.CW_LANG = lang;
  document.addEventListener("DOMContentLoaded", function () {
    try {
      var titles = JSON.parse(document.body.getAttribute("data-titles") || "{}");
      if (titles[lang]) document.title = titles[lang] === "CatchWords" ? "CatchWords" : titles[lang] + " — CatchWords";
    } catch (e) {}
    var links = document.querySelectorAll("[data-lang-link]");
    for (var i = 0; i < links.length; i++) {
      if (links[i].getAttribute("data-lang-link") === lang) links[i].setAttribute("aria-current", "page");
    }
  });
})();
