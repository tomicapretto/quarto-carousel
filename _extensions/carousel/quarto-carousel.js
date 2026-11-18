// Show the carousel item containing a figure reached through a reference.
(() => {
  function showTarget(hash) {
    const id = decodeURIComponent(hash.replace(/^#/, ""));
    const target = document.getElementById(id);
    const item = target?.closest(".carousel-item");
    const carousel = item?.closest(".carousel");
    if (!carousel || !window.bootstrap?.Carousel) return;
    const items = [...carousel.querySelector(".carousel-inner").children];
    bootstrap.Carousel.getOrCreateInstance(carousel).to(items.indexOf(item));
  }

  document.addEventListener("click", (event) => {
    const link = event.target.closest("a[href]");
    if (!link) return;
    const url = new URL(link.href, window.location.href);
    if (url.origin === location.origin && url.pathname === location.pathname) {
      showTarget(url.hash);
    }
  });
  window.addEventListener("hashchange", () => showTarget(location.hash));
  window.addEventListener("load", () => showTarget(location.hash));
})();
