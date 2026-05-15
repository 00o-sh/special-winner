// Rewrites ISO 8601 UTC timestamps in the Material version dropdown to the
// viewer's local timezone.
//
// docs.yaml emits version titles like "2026-05-15T18:30Z · 5b34e32".
// This script finds those ISO timestamps in version-selector elements and
// replaces them with a local-time string, e.g. "2026-05-15 1:30 PM CDT · 5b34e32".
//
// Material renders the version selector both on initial page load (the
// current-version button) and lazily when the dropdown is first opened (the
// menu items). Plain DOM-ready isn't enough; we MutationObserver + poll the
// version selector container to catch all of:
//   - initial population of the current-version text
//   - in-place text updates by Material's JS
//   - menu items added when the dropdown opens

(function () {
  const ISO_RE = /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?Z)/;

  function formatLocal(iso) {
    const d = new Date(iso);
    if (isNaN(d)) return iso;
    return d.toLocaleString(undefined, {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "numeric",
      minute: "2-digit",
      timeZoneName: "short",
    });
  }

  function rewriteOne(node) {
    if (!node) return false;
    // walk text nodes under this element
    let changed = false;
    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walker.nextNode())) {
      const m = n.nodeValue && n.nodeValue.match(ISO_RE);
      if (m) {
        n.nodeValue = n.nodeValue.replace(m[1], formatLocal(m[1]));
        changed = true;
      }
    }
    return changed;
  }

  function sweep() {
    // Hit every plausible Material version-selector node.
    document
      .querySelectorAll(
        ".md-version, .md-version__current, .md-version__title, .md-version__item"
      )
      .forEach(rewriteOne);
  }

  // Initial sweep (covers the case where Material has already populated).
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", sweep);
  } else {
    sweep();
  }

  // Catch later renders (dropdown lazy-opens, text replaced in-place).
  new MutationObserver(sweep).observe(document.body, {
    childList: true,
    subtree: true,
    characterData: true,
  });

  // Poll a few times in case the observer misses the very first Material
  // render. Stops after ~3 seconds.
  let ticks = 0;
  const poll = setInterval(() => {
    sweep();
    if (++ticks > 6) clearInterval(poll);
  }, 500);
})();
