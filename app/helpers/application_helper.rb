module ApplicationHelper

  # A nav/subnav tab. `active` is passed explicitly rather than derived from
  # current_page? because the root path and /assets render the same tab.
  def nav_tab(title, path, active)
    classes = if active
      "border-blue-600 text-blue-600"
    else
      "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700"
    end
    link_to title, path, class: "border-b-2 px-1 py-4 text-sm font-semibold #{classes}"
  end

  # Rebuilds the current list URL with `overrides` applied, so the sort headers,
  # per-page select and pagination links each preserve the others' params (and
  # any :account_id from the nested route).
  def list_url(overrides = {})
    url_for(request.path_parameters.merge(request.query_parameters.symbolize_keys).merge(overrides))
  end

  # A sortable table header. `key` is a StandardAPI order key — a column name,
  # or "relation.column" (e.g. "asset.symbol"). Clicking toggles asc/desc and
  # returns to page 1, since the row at a given offset changes with the sort.
  # `sub` renders a smaller second line under the label (e.g. "Split Adjusted").
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
      class: "flex items-baseline gap-1 font-semibold hover:text-gray-900 #{align == :right ? "justify-end" : ""}" do
        safe_join([
          content_tag(:span) do
            safe_join([label, (content_tag(:span, sub, class: "block text-xs font-normal") if sub)].compact)
          end,
          content_tag(:span, arrow, class: "text-blue-600")
        ])
      end
  end

end
