const DateTime = {
  mounted() {
    this.renderDateTime()
  },

  updated() {
    this.renderDateTime()
  },

  renderDateTime() {
    const value = new Date(this.el.dateTime)

    if (Number.isNaN(value.getTime())) return

    const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC"
    const format = this.el.dataset.format
    const options = {timeZone}

    if (format !== "time") {
      Object.assign(options, {day: "2-digit", month: "2-digit", year: "numeric"})
    }

    if (format !== "date") {
      Object.assign(options, {hour: "2-digit", minute: "2-digit", hourCycle: "h23"})
    }

    if (format === "datetime") options.timeZoneName = "short"

    this.el.textContent = new Intl.DateTimeFormat("en-GB", options).format(value)
    this.el.dataset.timezone = timeZone
    this.el.title = `Rendered in ${timeZone}`
  },
}

export default DateTime
