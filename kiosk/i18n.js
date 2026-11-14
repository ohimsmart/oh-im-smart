/*
 * Translations for the kiosk's welcome page (spec §6.2). The page's text is its Simplified Chinese
 * source; zh-Hant.js and en.js translate it. The kiosk says which language (page_status lang: in the
 * address and in every thinksmartStatus); this page never stores one and never reloads itself.
 * The page's own text is remembered on the first apply(), so the page can switch again in place.
 */
window.KioskI18n = (() => {
  const LOCALES = ['zh-Hans', 'zh-Hant', 'en'];
  const ATTRS = ['title', 'aria-label', 'placeholder', 'data-kb-enter'];
  const has = (obj, k) => Object.prototype.hasOwnProperty.call(obj, k);
  let locale = 'zh-Hans', catalog = {}, sources = null;
  // Plain string parameters (names, versions, third-party text) are shown as given; an object
  // parameter is another {msg_key, msg_params} and is translated first.
  const param = v => (v && typeof v === 'object' ? text(v) : v === null || v === undefined ? '' : String(v));
  // t(key) translates; t(key, params) also fills {name} placeholders after translating the template.
  const t = (source, params) => {
    const s = has(catalog, source) ? catalog[source] : source;
    return params ? s.replace(/\{(\w+)\}/g, (whole, name) => (has(params, name) ? param(params[name]) : whole)) : s;
  };
  // A backend value: a string (translated if it is ours) or a {msg_key, msg_params} object.
  const text = v => (v && typeof v === 'object' && typeof v.msg_key === 'string' ? t(v.msg_key, v.msg_params || {})
    : v === null || v === undefined ? '' : t(String(v)));
  function collect() {
    sources = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: n => (n.parentElement.closest('script,style,[data-no-i18n]') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    for (let n = walker.nextNode(); n; n = walker.nextNode()) if (n.textContent.trim()) sources.push([n, null, n.textContent]);
    for (const el of document.querySelectorAll(ATTRS.map(a => `[${a}]`).join(','))) {
      if (el.closest('[data-no-i18n]')) continue;
      for (const a of ATTRS) if (el.hasAttribute(a)) sources.push([el, a, el.getAttribute(a)]);
    }
  }
  // Switch to value ('zh-Hans' for anything unknown) and translate the page's own text from its source.
  function apply(value) {
    locale = LOCALES.includes(value) ? value : 'zh-Hans';
    catalog = (locale === 'zh-Hant' ? window.UI_ZH_HANT : locale === 'en' ? window.UI_EN : null) || {};
    document.documentElement.lang = locale;
    if (!sources) collect();
    for (const [node, attr, src] of sources) {
      const s = src.trim();
      if (attr) node.setAttribute(attr, t(s));
      else node.textContent = src.replace(s, () => t(s));   // a function: no $& patterns
    }
    return locale;
  }
  return { t, text, apply, get locale() { return locale; } };
})();
