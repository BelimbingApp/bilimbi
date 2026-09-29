// Only a successful server-side reauthentication sends plaintext to this hook.
// No plaintext is rendered in initial HTML or kept in a hook field. The input
// property is reset locally even if the LiveView disconnects before timeout.
// A value the user types or clears during the window is kept, never re-masked.
const SecretStored = {
  mounted() {
    this.mask = this.el.value
    this.stop = () => {
      clearTimeout(this.timer)
      this.revealing = false
      this.el.type = "password"
    }
    this.el.addEventListener("secret:cleared", this.stop)
    this.el.addEventListener("input", this.stop)
    this.handleEvent("secret:reveal", ({id, value, duration_ms}) => {
      if (id !== this.el.id) return
      clearTimeout(this.timer)
      this.el.value = value
      this.el.type = "text"
      this.revealing = true
      this.timer = setTimeout(() => this.hide(), duration_ms)
    })
  },

  hide() {
    if (this.revealing) this.el.value = this.mask
    this.stop()
  },

  destroyed() {
    this.hide()
    this.el.removeEventListener("secret:cleared", this.stop)
    this.el.removeEventListener("input", this.stop)
  },
}

export default SecretStored
