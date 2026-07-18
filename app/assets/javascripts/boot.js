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

document.addEventListener('DOMContentLoaded', initTooltips)
