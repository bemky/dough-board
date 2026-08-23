module ApplicationHelper

  # A nav/subnav tab. `active` is passed explicitly rather than derived from
  # current_page? because the root path and /assets render the same tab.
  def nav_tab(title, path, active)
    link_to title, path, class: "tab #{"tab-active" if active}"
  end

  # The app's destinations, in one list, because two navigations render them:
  # a row of tabs on a desk and a tab bar at the bottom of a phone. `short` is
  # what fits under an icon in a fifth of a narrow screen.
  def nav_destinations
    [
      {title: "Assets", short: "Assets", icon: :assets, path: assets_path, controller: "assets"},
      {title: "Accounts", short: "Accounts", icon: :accounts, path: accounts_path, controller: "accounts"},
      {title: "Positions", short: "Holdings", icon: :positions, path: positions_path, controller: "positions"},
      {title: "Transactions", short: "Activity", icon: :transactions, path: transactions_path, controller: "transactions"},
      {title: "Connections", short: "Links", icon: :connections, path: connections_path, controller: "connections"}
    ].map { |destination| destination.merge(active: controller_name == destination[:controller]) }
  end

  NAV_ICONS = {
    assets: "M21 12a9 9 0 1 1-9-9v9h9",
    accounts: "M3 8a2 2 0 0 1 2-2h13a1 1 0 0 1 1 1v2M3 8v9a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-3M3 8h16M16 13h5",
    positions: "M4 19h4V9H4v10ZM10 19h4V5h-4v14ZM16 19h4v-6h-4v6Z",
    transactions: "M4 8h13m0 0-3-3m3 3-3 3M20 16H7m0 0 3-3m-3 3 3 3",
    connections: "M10 13a5 5 0 0 0 7 0l2-2a5 5 0 0 0-7-7l-1 1M14 11a5 5 0 0 0-7 0l-2 2a5 5 0 0 0 7 7l1-1"
  }.freeze

  def nav_icon(name)
    content_tag(:svg, viewBox: "0 0 24 24", class: "h-5 w-5", fill: "none", stroke: "currentColor",
      "stroke-width": 1.75, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true) do
      tag.path(d: NAV_ICONS.fetch(name))
    end
  end

  # A headline figure with its cents set in gray — the shape a balance takes
  # everywhere it leads a screen. Splitting it is what keeps the dollars legible
  # at a glance on a phone, and `data-amount` lets the quote refresh in boot.js
  # rewrite one without flattening it back to a single run of text.
  def display_amount(value, css_class: nil, **options)
    whole, fraction = number_to_currency(value).split(/(?=\.\d+\z)/)
    options = options.deep_merge(class: "amount #{css_class}".strip, data: {amount: true})
    content_tag(:span, **options) do
      safe_join([whole, (content_tag(:span, fraction, class: "amount-fraction") if fraction)])
    end
  end

  # Rebuilds the current list URL with `overrides` applied, so the sort headers,
  # per-page select and pagination links each preserve the others' params (and
  # any :account_id from the nested route).
  def list_url(overrides = {})
    url_for(request.path_parameters.merge(request.query_parameters.symbolize_keys).merge(overrides))
  end

  # The sort headers are a desk affordance — a phone's rows are cards with no
  # header row to click. `choices` are [label, key, direction] triples, and each
  # option carries the list URL it sorts by, so picking one is a navigation and
  # nothing has to know how to build an order param client-side.
  def sort_select(choices)
    order = params[:order]
    current = case order
    when ActionController::Parameters then order.to_unsafe_h
    when Hash then order
    else {}
    end
    selected = nil
    pairs = choices.map do |label, key, direction|
      url = list_url(order: {key.to_s => direction}, page: 1)
      selected ||= url if current[key.to_s] == direction
      [label, url]
    end

    select_tag :sort, options_for_select(pairs, selected),
      id: nil, "aria-label": "Sort", data: {navigate: true},
      class: "field h-11 w-auto py-2 pr-8 text-sm md:hidden"
  end

  # A sortable table header. `key` is a StandardAPI order key — a column name,
  # or "relation.column" (e.g. "asset.symbol"). Clicking toggles asc/desc and
  # returns to page 1, since the row at a given offset changes with the sort.
  # `sub` renders a smaller second line under the label (e.g. "Split Adjusted").
  # Headers only ever show on a desk: a phone's rows are cards, not columns.
  def sort_header(label, key, align: :left, sub: nil)
    order = params[:order]
    current = order.respond_to?(:[]) && !order.is_a?(String) ? order[key.to_s] : nil
    next_direction = current == "asc" ? "desc" : "asc"
    arrow = case current
    when "asc" then " ↑"
    when "desc" then " ↓"
    else ""
    end

    link_to list_url(order: {key.to_s => next_direction}, page: 1),
      class: "flex items-baseline gap-1 font-semibold hover:text-ink #{align == :right ? "justify-end" : ""}" do
        safe_join([
          content_tag(:span) do
            safe_join([label, (content_tag(:span, sub, class: "block text-xs font-normal") if sub)].compact)
          end,
          content_tag(:span, arrow, class: "text-ink")
        ])
      end
  end

end
