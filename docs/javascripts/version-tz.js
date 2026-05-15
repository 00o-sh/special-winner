// Rewrites ISO 8601 UTC timestamps in the Material version dropdown titles
// to the viewer's local timezone.
//
// The docs.yaml workflow emits dropdown titles like:
//   "2026-05-15T18:30Z (commit subject)"
// This script finds those ISO timestamps in version-selector menu items and
// replaces them with a human-readable local-time string, e.g.:
//   "2026-05-15 1:30 PM CDT (commit subject)"
//
// The Material theme populates the dropdown asynchronously after fetching
// versions.json, so we use a MutationObserver to catch entries as they're
// added to the DOM.

(function () {
  const ISO_RE = /\b(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?Z)\b/;

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

  function rewriteNode(node) {
    if (!node || node.nodeType !== Node.ELEMENT_NODE) return;
    if (node.dataset && node.dataset.tzRewritten === "true") return;
    const text = node.textContent;
    const m = text && text.match(ISO_RE);
    if (!m) return;
    node.textContent = text.replace(m[1], formatLocal(m[1]));
    if (node.dataset) node.dataset.tzRewritten = "true";
  }

  function sweep(root) {
    (root || document)
      .querySelectorAll(".md-version__item, .md-version__current")
      .forEach(rewriteNode);
  }

  // Initial sweep in case the dropdown is already populated.
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => sweep());
  } else {
    sweep();
  }

  // Material lazy-renders the version list on first dropdown open; observe.
  new MutationObserver((mutations) => {
    for (const m of mutations) {
      for (const n of m.addedNodes) {
        if (n.nodeType === Node.ELEMENT_NODE) sweep(n);
      }
    }
  }).observe(document.body, { childList: true, subtree: true });
})();
