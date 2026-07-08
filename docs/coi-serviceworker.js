/*! coi-serviceworker v0.1.7 - Guido Zuidhof, licensed under MIT */
// Injects COOP/COEP headers via service worker so SharedArrayBuffer
// (required by ffmpeg.wasm) works on GitHub Pages.
let coepCredentialless = false;

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));

function getHeader(headers, name) {
  return headers.get(name) || "";
}

self.addEventListener("fetch", function(event) {
  const r = event.request;
  if (r.cache === "only-if-cached" && r.mode !== "same-origin") return;

  event.respondWith(
    fetch(r).then(function(response) {
      if (response.status === 0) return response;
      const newHeaders = new Headers(response.headers);
      newHeaders.set("Cross-Origin-Opener-Policy", "same-origin");
      newHeaders.set("Cross-Origin-Embedder-Policy",
        coepCredentialless ? "credentialless" : "require-corp");
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: newHeaders,
      });
    })
  );
});
