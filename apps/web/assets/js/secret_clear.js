// Clear a stored secret's keep-current mask in the input property that forms
// submit. Changing the value attribute would leave the submitted value intact.
const SecretClear = {
  mounted() {
    this.input = document.getElementById(this.el.dataset.inputId)
    this.clear = () => {
      this.input.value = ""
      this.input.focus()
    }
    this.el.addEventListener("click", this.clear)
  },

  destroyed() {
    this.el.removeEventListener("click", this.clear)
  },
}

export default SecretClear
