# Opening a tab that may sit inside a dropdown tab (layouts/_dropdown_tab) - e.g. the fund page's
# Calls lives under "Cash Flows ▾". A screen in a dropdown is hidden until its menu is open, so open
# the menu first; a plain tab is just clicked.
module TabHelpers
  # By the screen's label, e.g. click_tab("Calls"). Falls back to click_on for a plain tab/link
  def click_tab(label)
    item = first(".dropdown-menu a[data-tab-label='#{label}']", visible: :all, minimum: 0)
    return click_on(label) unless item

    open_dropdown_of(item)
    item.click
  end

  # By the pane id the tab shows, e.g. open_tab_pane("capital-calls-tab")
  def open_tab_pane(pane)
    link = find("a[href='##{pane}']", visible: :all)
    open_dropdown_of(link) if link.has_ancestor?(".dropdown-menu", visible: :all, wait: 0)
    link.click
  end

  private

  # Clicks the dropdown's own tab unless its menu is already open
  def open_dropdown_of(item)
    return if item.visible?

    item.find(:xpath, "ancestor::div[contains(concat(' ', @class, ' '), ' dropdown ')][1]")
        .find("a.dropdown-toggle").click
  end
end

World(TabHelpers)
