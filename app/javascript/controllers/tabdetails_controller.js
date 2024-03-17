import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {

    // // Sometimes we want to load a tab on load of the page
    // // This tab is stored in a hidden field #clickOnLoad 
    if( $("#clickOnLoad").length > 0 ) {
      let link = $("#clickOnLoad").val();
      console.log(`#clickOnLoad ${link}`);
      // setTimeout(() => {
        $(`${link} .load_data_link`).find('span').trigger('click'); // Works
        $(`${link} .load_data_link`).hide();  
      // }, 1000);
    }
  }

  // Find the load_data_link and click it to load the html into the 
  // turboframe inside the tab

  // If the load_data_link is inside the turboframe, then the load_data_link
  // will be replaced by the server html, and subsequent tab clicks will NOT reload the tab
  
  // If the load_data_link is outside the turboframe, then the load_data_link
  // will NOT be replaced by the server html, and subsequent tab clicks will reload the tab
  loadData(event) {
    console.log(`${event.target.hash} .load_data_link`);
    $(`${event.target.hash} .load_data_link`).find('span').trigger('click'); 
    $(`${event.target.hash} .load_data_link`).hide();
  }
  
}
