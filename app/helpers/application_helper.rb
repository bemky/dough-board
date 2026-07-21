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

end
