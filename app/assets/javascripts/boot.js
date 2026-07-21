// Lightweight tooltip: shows the value of a `data-tooltip` attribute in a
// floating element positioned above the anchor on hover/focus.
function initTooltips() {
  let tip

  const show = (el) => {
    const content = el.dataset.tooltip
    if (!content) return

    tip = document.createElement('div')
    tip.textContent = content
    tip.className =
      'pointer-events-none fixed z-50 rounded bg-gray-900 px-2 py-1 text-xs text-white shadow-lg'
    document.body.appendChild(tip)

    const rect = el.getBoundingClientRect()
    const tipRect = tip.getBoundingClientRect()
    tip.style.left = `${rect.left + rect.width / 2 - tipRect.width / 2}px`
    tip.style.top = `${rect.top - tipRect.height - 6}px`
  }

  const hide = () => {
    if (tip) {
      tip.remove()
      tip = null
    }
  }

  document.querySelectorAll('[data-tooltip]').forEach((el) => {
    el.addEventListener('mouseenter', () => show(el))
    el.addEventListener('mouseleave', hide)
    el.addEventListener('focus', () => show(el))
    el.addEventListener('blur', hide)
  })
}

// CSV import drop zone: accepts a dropped `.csv` file onto the `[data-dropzone]`
// label, assigns it to the hidden file input, and reflects the filename. Clicking
// the label falls through to the native file picker (it wraps the input).
function initDropzone() {
  const zone = document.querySelector('[data-dropzone]')
  if (!zone) return

  const input = zone.querySelector('[data-dropzone-input]')
  const label = zone.querySelector('[data-dropzone-label]')
  const defaultLabel = label ? label.textContent : ''

  const reflect = () => {
    if (label) {
      label.textContent = input.files.length ? input.files[0].name : defaultLabel
    }
  }

  input.addEventListener('change', reflect)

  ;['dragenter', 'dragover'].forEach((evt) =>
    zone.addEventListener(evt, (e) => {
      e.preventDefault()
      zone.classList.add('border-blue-400', 'bg-blue-50')
    })
  )

  ;['dragleave', 'drop'].forEach((evt) =>
    zone.addEventListener(evt, (e) => {
      e.preventDefault()
      zone.classList.remove('border-blue-400', 'bg-blue-50')
    })
  )

  zone.addEventListener('drop', (e) => {
    const file = e.dataTransfer.files[0]
    if (!file) return
    const dt = new DataTransfer()
    dt.items.add(file)
    input.files = dt.files
    reflect()
  })
}

// Submits the enclosing form as soon as a `[data-auto-submit]` control changes,
// so selects like the pagination per-page picker need no Apply button.
function initAutoSubmit() {
  document.querySelectorAll('[data-auto-submit]').forEach((el) => {
    el.addEventListener('change', () => el.form && el.form.requestSubmit())
  })
}

document.addEventListener('DOMContentLoaded', () => {
  initTooltips()
  initDropzone()
  initAutoSubmit()
})
