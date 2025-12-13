import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
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

  clickTab(tab) {
    console.log(`tab_controller switching to #${tab}`);
    // $(`a[href="#${tab}"]`).click();

    let tabLink = $(`a[href="#${tab}"]`);
    if (tabLink.length > 0) {
      bootstrap.Tab.getOrCreateInstance(tabLink[0]).show()
    } else {
      let element = document.getElementById(tab);
      if (element) {
        if (element.classList.contains('collapse')) {
          bootstrap.Collapse.getOrCreateInstance(element).show();
        } else {
          let trigger = element.querySelector('[data-bs-toggle="collapse"]');
          if (trigger) {
            trigger.click();
          }
        }
      }
    }
  }

}
