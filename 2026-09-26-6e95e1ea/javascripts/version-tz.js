// Rewrites ISO 8601 UTC timestamps anywhere in the Material header (notably
// the version selector emitted by docs.yaml as "<ISO> · <sha>") into a
// locale-independent local-time format like "2026-05-15 13:30 CDT".
//
// Why so aggressive? Material renders the current-version button into the
// header via inline text content updates that don't always fire a
// childList MutationObserver; and the version dropdown list is built lazily
// when first clicked. Polling + a wide DOM sweep catches all of:
//   - first-paint render of the current-version button
//   - lazy build of the dropdown list on click
//   - any later text mutations
//
// The format is fixed (24hr, ISO date) instead of toLocaleString() so it
// reads the same way regardless of the viewer's browser locale.

(function () {
  const ISO_RE = /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?Z)/;

  function pad(n) {
    return String(n).padStart(2, "0");
  }

  function tzAbbrev(d) {
    try {
      const parts = new Intl.DateTimeFormat(undefined, {
        timeZoneName: "short",
      }).formatToParts(d);
      const p = parts.find((x) => x.type === "timeZoneName");
      return p ? p.value : "";
    } catch (_) {
      return "";
    }
  }

  function formatLocal(iso) {
    const d = new Date(iso);
    if (isNaN(d)) return iso;
    const date = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    const time = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    const tz = tzAbbrev(d);
    return tz ? `${date} ${time} ${tz}` : `${date} ${time}`;
  }

  function rewriteWithin(root) {
    if (!root) return;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walker.nextNode())) {
      const text = n.nodeValue;
      if (!text || !ISO_RE.test(text)) continue;
      // .replace with a regex executes only the first match — fine, we only
      // ever emit one ISO per node.
      n.nodeValue = text.replace(ISO_RE, (m) => formatLocal(m));
    }
  }

  // Wide sweep: the page header is small, scanning it is cheap.
  function sweep() {
    rewriteWithin(document.querySelector(".md-header"));
    rewriteWithin(document.querySelector(".md-version")); // fallback if not in header
  }

  // Start observing as early as possible (Material may have already
  // populated the header before DOMContentLoaded fires on a fast load).
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", sweep);
  }
  sweep();

  new MutationObserver(sweep).observe(document.documentElement, {
    childList: true,
    subtree: true,
    characterData: true,
  });

  // Aggressive early polling: 100ms intervals for the first 2 seconds, then
  // every second for the next 8 seconds, then stop. Catches anything the
  // observer misses on initial render.
  let ticks = 0;
  const fast = setInterval(() => {
    sweep();
    if (++ticks >= 20) {
      clearInterval(fast);
      const slow = setInterval(sweep, 1000);
      setTimeout(() => clearInterval(slow), 8000);
    }
  }, 100);
})();
