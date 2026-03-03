(function () {
  function parseJsonMaybe(value, fallback) {
    if (!value) return fallback
    try { return JSON.parse(value) } catch { return fallback }
  }

  function toNumber(value, fallback) {
    const n = Number(value)
    return Number.isFinite(n) ? n : fallback
  }

  function buildMap(el) {
    // Required
    const imageUrl = el.dataset.image
    const bounds = parseJsonMaybe(el.dataset.bounds, null)
    if (!imageUrl || !bounds) return

    // Optional settings
    const minZoom = toNumber(el.dataset.minzoom, -2)
    const maxZoom = toNumber(el.dataset.maxzoom, 2.5)
    const defaultZoom = toNumber(el.dataset.defaultzoom, undefined)

    const centerLat = toNumber(el.dataset.lat, undefined)
    const centerLng = toNumber(el.dataset.long, undefined)

    // Create map
    const map = L.map(el, {
      crs: L.CRS.Simple,
      minZoom,
      maxZoom,
      zoomControl: true,
    })

    // Base image overlay
    L.imageOverlay(imageUrl, bounds).addTo(map)

    // Fit view
    map.fitBounds(bounds)
    if (Number.isFinite(centerLat) && Number.isFinite(centerLng)) {
      // Optional: if you provided a “lat/long”, set view near it
      const z = Number.isFinite(defaultZoom) ? defaultZoom : map.getZoom()
      map.setView([centerLat, centerLng], z)
    } else if (Number.isFinite(defaultZoom)) {
      map.setZoom(defaultZoom)
    }

    // GeoJSON layers
    const geojsonUrls = parseJsonMaybe(el.dataset.geojson, [])
    const overlays = {}
    let addedControl = false

    geojsonUrls.forEach((url) => {
      // Use filename as layer name
      const name = (url.split("/").pop() || url).replace(/\.json$/i, "")

      fetch(url)
        .then((r) => r.json())
        .then((data) => {
          const layer = L.geoJSON(data, {
            onEachFeature: (feature, layer) => {
              const p = feature && feature.properties ? feature.properties : {}
              if (p.name) layer.bindPopup(String(p.name))
            },
          }).addTo(map)

          overlays[name] = layer

          // Add layer toggle control once, then it will “fill in” as layers load
          if (!addedControl) {
            L.control.layers(null, overlays, { collapsed: false }).addTo(map)
            addedControl = true
          }
        })
        .catch(() => {
          // ignore broken layer files
        })
    })
  }

  function initAll() {
    const nodes = document.querySelectorAll(".leaflet-map")
    nodes.forEach((el) => {
      try {
        buildMap(el)
      } catch {
        // ignore map failures
      }
    })
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initAll)
  } else {
    initAll()
  }
})()