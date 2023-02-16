import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("call_copy_all connect");
  }

  copy_all(e) {
    e.preventDefault();

    let price = $(".price")[0].value;
    $(".price").each(function( index, item ) {
      $( item )[0].value = price;
    });
    console.log(`price = ${price}`);

    if ($(".premium").length > 0) {
      let premium = $(".premium")[0].value;      
      console.log(`premium = ${premium}`);

      $(".premium").each(function( index, item ) {
        $( item )[0].value = premium;
      });
    }

    
    
  }

}
