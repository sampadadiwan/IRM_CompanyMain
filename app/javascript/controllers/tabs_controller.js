import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Dropdown tabs: show the picked screen's name on the dropdown's own label
    this.element.addEventListener('shown.bs.tab', this.syncDropdownLabel)

    var urlParams = new URLSearchParams(window.location.search);
    let tab = urlParams.get('tab');

    if(tab) {
      this.clickTab(tab);
    } else {
      tab = $("#click_tab").val();
      console.log(tab);
      if(tab) {
        this.clickTab(tab);
      }
    }
  }

  disconnect() {
    this.element.removeEventListener('shown.bs.tab', this.syncDropdownLabel)
  }

  // A tab picked from a dropdown menu (e.g. the commitment page's Cash Flows ▾ → Remittances) appends
  // its name to the dropdown's group label ("Cash Flows · Remittances"), so the bar shows which
  // screen is open without losing the group
  syncDropdownLabel = (event) => {
    const item = event.target
    // Only this tab bar's own dropdowns, not those of a nested tab bar inside one of its panes
    const nav = item.closest('.nav')
    const current = item.closest('.dropdown')?.querySelector('[data-tab-dropdown-current]')
    // Any other dropdown in the bar is no longer selected, so it drops its "· screen" suffix
    nav?.querySelectorAll('[data-tab-dropdown-current]').forEach(el => { if (el !== current) el.textContent = '' })
    if (current && item.closest('.dropdown-menu')) current.textContent = ` · ${item.dataset.tabLabel}`
  }

  clickTab(tab) {
    console.log(`tab_controller switching to #${tab}`);
    // $(`a[href="#${tab}"]`).click();

    let tabLink = $(`a[href="#${tab}"]`);
    if (tabLink.length > 0) {
      // A tab nested inside another tab's pane (e.g. the evergreen fund page's Dealing → Redemptions):
      // show the outer tab first, or the inner one is switched on inside a hidden pane
      const outerPane = tabLink[0].closest('.tab-pane');
      const outerLink = outerPane && document.querySelector(`a[href="#${outerPane.id}"]`);
      if (outerLink) bootstrap.Tab.getOrCreateInstance(outerLink).show()
      bootstrap.Tab.getOrCreateInstance(tabLink[0]).show()
    } else {
      let element = document.getElementById(tab);
      if (element) {
        if (element.classList.contains('collapse')) {
          bootstrap.Collapse.getOrCreateInstance(element).show();
        } else {
          let trigger = element.querySelector('[data-bs-toggle="collapse"]');
          // The trigger toggles: clicking an already-open section (e.g. Commitments, open by
          // default) would close it, so only click when its target is closed
          const target = trigger && document.querySelector(trigger.getAttribute('data-bs-target'));
          if (trigger && !target?.classList.contains('show')) {
            trigger.click();
          }
        }
      }
    }
  }

}
