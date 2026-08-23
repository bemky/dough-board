import Dropdown from 'komps/dropdown'

// Column filter dropdowns: each `[data-filter-button]` gets a Komps.Dropdown
// whose content is the sibling `<template>`'s markup (a checkbox form rendered
// server-side). Built lazily on first click so a long symbol list costs nothing
// until it's opened.
function initFilterDropdowns() {
  document.querySelectorAll('[data-filter-button]').forEach((button) => {
    const template = button.parentElement.querySelector('[data-filter-content]')
    if (!template) return

    let dropdown
    button.addEventListener('click', () => {
      if (dropdown) return
      dropdown = new Dropdown({
        anchor: button,
        placement: 'bottom-start',
        autoPlacement: false,
        content: template.content.cloneNode(true),
        class:
          'z-40 overflow-hidden rounded-2xl border border-line bg-surface text-ink shadow-xl',
      })
      dropdown.show()
    })
  })
}

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
      'pointer-events-none fixed z-50 rounded-lg bg-ink px-2 py-1 text-xs text-white shadow-lg'
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
      zone.classList.add('border-ink', 'text-ink')
    })
  )

  ;['dragleave', 'drop'].forEach((evt) =>
    zone.addEventListener(evt, (e) => {
      e.preventDefault()
      zone.classList.remove('border-ink', 'text-ink')
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

// A `[data-navigate]` select carries a URL per option — the phone's stand-in
// for the sort headers, which only exist on a screen wide enough for a table.
function initNavigateSelects() {
  document.querySelectorAll('[data-navigate]').forEach((el) => {
    el.addEventListener('change', () => {
      if (el.value) window.location.href = el.value
    })
  })
}

// Portfolio/transactions pages render with cached-only prices (so they never
// block on Finnhub). Each distinct `[data-quote-symbol]` on the page gets a
// fetch to /assets/:symbol/quote; the server paces the underlying Finnhub
// calls, so it's safe to fire all of them at once here. Each cell's price
// and computed value (quantity × price) update in place as responses land,
// and the portfolio total is resummed from the updated rows.
function initQuoteRefresh() {
  const cellsBySymbol = new Map()
  document.querySelectorAll('[data-quote-symbol]').forEach((cell) => {
    const symbol = cell.dataset.quoteSymbol
    if (!cellsBySymbol.has(symbol)) cellsBySymbol.set(symbol, [])
    cellsBySymbol.get(symbol).push(cell)
  })
  if (!cellsBySymbol.size) return

  const formatCurrency = (amount) =>
    amount.toLocaleString('en-US', { style: 'currency', currency: 'USD' })

  const applyQuote = (cell, price) => {
    const priceTarget = cell.querySelector('[data-quote-price]')
    if (priceTarget) priceTarget.textContent = formatCurrency(price)

    const quantity = parseFloat(cell.dataset.quantity)
    if (!Number.isFinite(quantity)) return
    const value = quantity * price

    const amountTarget = cell.querySelector('[data-quote-amount]')
    if (amountTarget) amountTarget.textContent = formatCurrency(value)

    const valueCell = cell.closest('tr')?.querySelector('[data-quote-value]')
    if (valueCell) valueCell.textContent = formatCurrency(value)
  }

  // A headline figure sets its cents in gray (see ApplicationHelper#display_amount),
  // so rewriting one means rebuilding both halves rather than assigning text.
  const renderAmount = (el, value) => {
    const formatted = formatCurrency(value)
    const split = formatted.length - 3
    el.textContent = formatted.slice(0, split)
    const fraction = document.createElement('span')
    fraction.className = 'amount-fraction'
    fraction.textContent = formatted.slice(split)
    el.appendChild(fraction)
  }

  const updatePortfolioTotal = () => {
    const totalEl = document.querySelector('[data-portfolio-total]')
    if (!totalEl) return
    let total = 0
    document.querySelectorAll('[data-quote-value]').forEach((el) => {
      const amount = parseFloat(el.textContent.replace(/[^0-9.-]/g, ''))
      if (Number.isFinite(amount)) total += amount
    })
    if (totalEl.dataset.amount) renderAmount(totalEl, total)
    else totalEl.textContent = formatCurrency(total)
  }

  cellsBySymbol.forEach((cells, symbol) => {
    fetch(`/quotes/${encodeURIComponent(symbol)}`)
      .then((response) => response.json())
      .then(({ price }) => {
        if (price == null) return
        cells.forEach((cell) => applyQuote(cell, price))
        updatePortfolioTotal()
      })
      .catch(() => {})
  })
}

document.addEventListener('DOMContentLoaded', () => {
  initFilterDropdowns()
  initTooltips()
  initDropzone()
  initAutoSubmit()
  initNavigateSelects()
  initQuoteRefresh()
})
