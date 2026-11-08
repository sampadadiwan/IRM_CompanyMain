import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Dropdown tabs: show the picked screen's name on the dropdown's own label
    this.element.addEventListener('shown.bs.tab', this.syncDropdownLabel)
    // Phones: the tab bar collapses into one dropdown tab (before any ?tab= switch, so it follows that too)
    this.buildMobileTabs()

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
    // The collapsed phone bar's listeners on the full bar (see buildMobileTabs)
    this.mobileTabsListeners?.abort()
  }

  // Phones only: a wrapped bar of pills (7 tabs → 4 rows on the fund page) collapses into one tab bar of the
  // same look - the same card, one active pill showing the open screen with a ▾, and a menu (the
  // layouts/_dropdown_tab look) listing every screen, dropdown-tab screens under their group's heading.
  // Nothing is built on wider screens, so the normal app's DOM is untouched; d-md-none / d-md-flex also
  // restore the full bar if a phone-built page is later widened (e.g. a tablet rotated)
  buildMobileTabs() {
    // A bar built before Turbo cached the page comes back without its listeners: drop it and rebuild
    this.element.querySelectorAll('[data-tabs-mobile-nav]').forEach(built => {
      if (built.closest('[data-controller~="tabs"]') === this.element) built.remove()
    })
    // Listeners a previous build left on the full bar would update the dropped copy: remove them too
    this.mobileTabsListeners?.abort()
    this.mobileTabsListeners = new AbortController()
    const { signal } = this.mobileTabsListeners
    if (!window.matchMedia('(max-width: 767.98px)').matches) return

    this.element.querySelectorAll('.nav-pills[role="tablist"]').forEach(nav => {
      // A bar inside a nested tabs controller is that controller's job
      if (nav.closest('[data-controller~="tabs"]') !== this.element) return

      // The bar's own screen links: plain tabs and dropdown-tab items (not dropdown toggles, not disabled
      // rows, which are spans; not links of a tab bar nested inside one of this bar's panes)
      const links = [...nav.querySelectorAll('a[data-bs-toggle="pill"], a[data-bs-toggle="tab"]')]
        .filter(link => link.closest('.nav') === nav)
      if (links.length < 2) return

      // Each screen's icon, name and (for a dropdown-tab screen) group name, as the full bar shows them
      const screens = links.map(link => {
        const group = link.closest('.dropdown')?.querySelector('[data-bs-toggle="dropdown"]')
        return {
          link,
          // Just the Tabler glyph classes - the source icon's own margins differ between pills and menu rows
          icon: [...(link.querySelector('i.ti')?.classList || [])].filter(c => c.startsWith('ti')).join(' '),
          // A pill's text can carry the template's line breaks and indentation: collapse them
          label: link.dataset.tabLabel || link.textContent.replace(/\s+/g, ' ').trim(),
          // The group's own label, without the "· screen" suffix syncDropdownLabel appends
          group: group ? [...group.childNodes].filter(n => n.nodeType === Node.TEXT_NODE)
            .map(n => n.textContent).join('').trim() : null,
          // The group tab's own icon, for its heading row in the menu
          groupIcon: [...(group?.querySelector('i.ti')?.classList || [])].filter(c => c.startsWith('ti')).join(' ')
        }
      })

      // The same card and pill classes as the full bar, phones only; no role="tablist", so this copy is
      // never mistaken for a real tab bar (here or by syncDropdownLabel)
      const mobileNav = document.createElement('nav')
      // (without the d-none / d-md-flex a cached, already-collapsed page's full bar still carries, or the copy
      // would be hidden on phones too)
      mobileNav.className = [...nav.classList].filter(c => c !== 'd-none' && c !== 'd-md-flex').concat('d-md-none').join(' ')
      mobileNav.dataset.tabsMobileNav = ''
      mobileNav.innerHTML = `
        <div class="nav-item dropdown w-100">
          <a class="nav-link active dropdown-toggle w-100" data-bs-toggle="dropdown" data-bs-offset="0,8" href="#" role="button" aria-expanded="false"></a>
          <ul class="dropdown-menu" style="min-width: 100%"></ul>
        </div>`
      const toggle = mobileNav.querySelector('.dropdown-toggle')
      const menu = mobileNav.querySelector('.dropdown-menu')

      // One menu row per screen (fixed-width icon slot, as in _dropdown_tab). A group (Cash Flows, Manage) is a
      // top-level tab too, so it gets a row of the same size and icon as the others - just not clickable - and
      // its screens sit indented under it, their icons lined up with the group's label
      const iconSlot = '<i class="text-center" style="width: 1.25rem"></i><span></span>'
      let lastGroup = null
      const rows = screens.map(screen => {
        if (screen.group && screen.group !== lastGroup) {
          const heading = document.createElement('li')
          heading.innerHTML = `<span class="dropdown-item-text d-flex align-items-center gap-2">${iconSlot}</span>`
          heading.querySelector('i').className = `${screen.groupIcon} text-center`
          heading.querySelector('span span').textContent = screen.group
          menu.append(heading)
        }
        lastGroup = screen.group

        const item = document.createElement('li')
        item.innerHTML = `<a class="dropdown-item d-flex align-items-center gap-2" href="#">${iconSlot}</a>`
        const row = item.firstChild
        // Indent a group's screen by the icon slot + gap, so it reads as part of the row above
        if (screen.group) row.style.paddingLeft = 'calc(var(--bs-dropdown-item-padding-x, 1rem) + 1.75rem)'
        row.querySelector('i').className = `${screen.icon} text-center`
        row.querySelector('span').textContent = screen.label
        // Picking a row shows that screen exactly as clicking its pill / menu row in the full bar would
        row.addEventListener('click', (event) => {
          event.preventDefault()
          bootstrap.Tab.getOrCreateInstance(screen.link).show()
          // A dropdown item shown programmatically leaves its (hidden) menu marked open
          this.closeDropdownMenu(screen.link)
        })
        menu.append(item)
        return row
      })

      // The pill shows the open screen ("Cash Flows · Remittances" for a grouped one) and its row is ticked
      const showCurrent = (index) => {
        const screen = screens[index]
        toggle.innerHTML = '<i class="me-1"></i><span></span>'
        toggle.querySelector('i').className = `${screen.icon} me-1`
        toggle.querySelector('span').textContent = screen.group ? `${screen.group} · ${screen.label}` : screen.label
        rows.forEach((row, i) => row.classList.toggle('active', i === index))
      }
      showCurrent(Math.max(links.findIndex(link => link.classList.contains('active')), 0))

      // A screen switched any way (a row here, ?tab= deep link, #click_tab, a link on the page) updates the pill
      nav.addEventListener('shown.bs.tab', (event) => {
        const index = links.indexOf(event.target)
        if (index >= 0) showCurrent(index)
      }, { signal })

      // Hide the full bar on phones only, and put the collapsed one where it was
      nav.classList.add('d-none', 'd-md-flex')
      nav.before(mobileNav)
    })
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

  // Bootstrap's Tab#show on a dropdown item (layouts/_dropdown_tab) marks the group tab active and also
  // adds "show" to the menu, as if it had been picked from an open menu. A user's click closes the menu
  // through the Dropdown plugin; a ?tab= deep link has no click, so the menu stayed open over the pane.
  // Close it here, leaving the group tab active so the bar still shows which screen is open.
  closeDropdownMenu(link) {
    const dropdown = link.closest('.dropdown')
    const menu = link.closest('.dropdown-menu')
    if (!dropdown || !menu) return

    // The menu and both places Bootstrap records "expanded" (the .dropdown and its toggle)
    menu.classList.remove('show')
    dropdown.setAttribute('aria-expanded', 'false')
    dropdown.querySelector('[data-bs-toggle="dropdown"]')?.setAttribute('aria-expanded', 'false')
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
      // Showing a dropdown screen this way leaves its menu open over the page (see closeDropdownMenu)
      if (outerLink) this.closeDropdownMenu(outerLink)
      this.closeDropdownMenu(tabLink[0])
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
