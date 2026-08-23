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
          'z-40 overflow-hidden rounded-lg border border-gray-200 bg-white text-gray-900 shadow-lg',
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

  const updatePortfolioTotal = () => {
    const totalEl = document.querySelector('[data-portfolio-total]')
    if (!totalEl) return
    let total = 0
    // Debts are negative rows, so the total is a net worth and the assets half
    // of the breakdown beside it is the positive rows on their own.
    let assets = 0
    document.querySelectorAll('[data-quote-value]').forEach((el) => {
      const amount = parseFloat(el.textContent.replace(/[^0-9.-]/g, ''))
      if (!Number.isFinite(amount)) return
      total += amount
      if (amount > 0) assets += amount
    })
    totalEl.textContent = formatCurrency(total)
    const assetsEl = document.querySelector('[data-portfolio-assets]')
    if (assetsEl) assetsEl.textContent = formatCurrency(assets)
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

// Plaid Link, on the connections/link page. Link has to run from Plaid's own
// CDN — it is the sign-in for the institution, and Plaid won't let it be
// vendored — so the script is loaded on demand rather than bundled, and only on
// the one page that carries a link token.
//
// The token authorizes a single run. On success Link hands back a one-time
// public_token, which goes to the server to be traded for the connection's
// permanent credentials; an update-mode run (reconnecting an expired
// institution) returns none, because the credentials already stored start
// working again, so the form is submitted either way.
const PLAID_LINK_SRC = 'https://cdn.plaid.com/link/v2/stable/link-initialize.js'

function initPlaidLink() {
  const root = document.querySelector('[data-plaid-link]')
  if (!root) return

  const form = document.getElementById('plaid-link-form')
  const tokenField = document.getElementById('plaid-public-token')
  const button = document.querySelector('[data-plaid-open]')
  const status = document.querySelector('[data-plaid-status]')

  const say = (message) => {
    if (status) status.textContent = message
  }

  const script = document.createElement('script')
  script.src = PLAID_LINK_SRC
  script.onerror = () => say("Couldn't load Plaid Link. Check the connection and reload.")
  script.onload = () => {
    const handler = window.Plaid.create({
      token: root.dataset.plaidLink,
      onSuccess: (publicToken) => {
        if (publicToken) tokenField.value = publicToken
        say('Finishing up…')
        form.submit()
      },
      onExit: (error) => {
        say(
          (error && (error.display_message || error.error_message)) ||
            'Closed without connecting.'
        )
        button.disabled = false
      },
    })

    const open = () => {
      button.disabled = true
      say('Opening…')
      handler.open()
    }

    button.addEventListener('click', open)
    // Nobody navigates here to look at it, so skip the extra click.
    open()
  }

  document.head.appendChild(script)
}

document.addEventListener('DOMContentLoaded', () => {
  initFilterDropdowns()
  initTooltips()
  initDropzone()
  initAutoSubmit()
  initQuoteRefresh()
  initPlaidLink()
})
