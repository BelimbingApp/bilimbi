// Reports the browser's own time zone to the view that mounted this.
//
// Under the local display mode every instant is formatted in the browser
// (see `date_time.js`), so only the browser knows which calendar day a row
// is shown on. A screen whose date filters bound displayed days mounts this
// on the region that holds them and receives one `browser_timezone` event;
// the server proves the name against its own time zone database and keeps
// bounding UTC, the text it rendered itself, when it cannot honor it.
//
// The zone is the same expression `date_time.js` formats with, so the day a
// row displays on and the day the server bounds are read from one source.
const BrowserTimeZone = {
  mounted() {
    const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"
    this.pushEvent("browser_timezone", {timezone: timeZone})
  },
}

export default BrowserTimeZone
