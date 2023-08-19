import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("call_copy connect");
    this.call_basis_changed();
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

  call_basis_changed() {
    let call_basis = $("#capital_call_call_basis").val();
    console.log(`call_basis = ${call_basis}`);

    if ( call_basis == "Percentage of Commitment" ) {
      $("#amount_to_be_called_group").hide();
      $("#percentage_called_group").show();
    } else if ( call_basis == "Amount allocated on Investable Capital" ) {
      $("#amount_to_be_called_group").show();
      $("#percentage_called_group").hide();
    } else if ( call_basis == "Upload" ) {
      $("#amount_to_be_called_group").hide();
      $("#percentage_called_group").hide();
    }
  }

};
