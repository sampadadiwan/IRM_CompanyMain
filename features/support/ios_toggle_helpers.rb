# iOS-style toggles (custom/scaffolds.scss .ios-toggle, e.g. the document form's switches) hide the real
# checkbox at 1px under the slider, so Playwright can't click it and `check('id')` times out. Turn one on
# by clicking its switch instead - only when it is off, so this is as idempotent as `check`.
module IosToggleHelpers
  def toggle_on(id)
    box = find("##{id}", visible: :all)
    find("label.ios-toggle:has(##{id})").click unless box.checked?
  end
end
World(IosToggleHelpers)
