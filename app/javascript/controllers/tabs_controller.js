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
    $(`a[href="#${tab}"]`).click();
    
    if( $(`#${tab} .load_data_link`).length > 0 ) {
      $(`#${tab} .load_data_link`).find('span').trigger('click'); // Works
      $(`#${tab} .load_data_link`).hide();  // Select tab by name
    }
  }
}
