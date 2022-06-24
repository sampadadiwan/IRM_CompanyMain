import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    var urlParams = new URLSearchParams(window.location.search);
    let tab = urlParams.get('tab');
    console.log(`tab_controller switching to #${tab}`);
    $(`a[href="#${tab}"]`).click();
    
    if( $(`#${tab} .load_data_link`).length > 0 ) {
      $(`#${tab} .load_data_link`).find('span').trigger('click'); // Works
      $(`#${tab} .load_data_link`).hide();  // Select tab by name
    }
  }
}
