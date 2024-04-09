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
    bootstrap.Tab.getOrCreateInstance($(`a[href="#${tab}"]`)).show()


    if( $(`#${tab} .load_data_link`).length > 0 ) {
      // We need a small delay here, oterwise when the tab is programtically clicked,
      // the below link is not yet ready for a click, so without the delay the tab does not load
      this.delay(1000).then(() =>  {
          console.log(`Clicking #${tab} .load_data_link`);
          $(`#${tab} .load_data_link`).find('span').trigger('click'); // Works
          $(`#${tab} .load_data_link`).hide();  // Select tab by name
        }
      );

    }
  }


  delay(time) {
    return new Promise(resolve => setTimeout(resolve, time));
  }
}
