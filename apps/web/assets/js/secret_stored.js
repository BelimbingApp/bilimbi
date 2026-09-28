// Only a successful server-side reauthentication sends plaintext to this hook.
// No plaintext is rendered in initial HTML or kept in a hook field. The input
// property is reset locally even if the LiveView disconnects before timeout.
const SecretStored = {
  mounted() {
    this.mask = this.el.value
    this.cleared = () => {
      clearTimeout(this.timer)
      this.el.type = "password"
    }
    this.el.addEventListener("secret:cleared", this.cleared)
    this.handleEvent("secret:reveal", ({id, value, duration_ms}) => {
      if (id !== this.el.id) return
      clearTimeout(this.timer)
      this.el.value = value
      this.el.type = "text"
      this.timer = setTimeout(() => this.hide(), duration_ms)
    })
  },

  hide() {
    this.el.value = this.mask
    this.el.type = "password"
  },

  destroyed() {
    clearTimeout(this.timer)
    this.el.removeEventListener("secret:cleared", this.cleared)
    this.hide()
  },
}

export default SecretStored
