import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("Sale price javascript loaded");
    this.onChange(null);    
  }

  onChange(event) {
    
    let selected = $("#secondary_sale_price_type").val();
    console.log(`onChange ${selected}`);
    switch (selected) {
      case "Price Range":
        if($('#secondary_sale_id').val()) {
         // If its a new sale & its price range, then hide fixed price 
         $(".fixed_price_group").show();
        } else {
          $(".fixed_price_group").hide();
        }
        $(".price_range_group").show();

        break;
      case "Fixed Price":
        $(".fixed_price_group").show();
        $(".price_range_group").hide();

        break;
      default:
    }
  }

  onShowQuantityChange(event) {
    
    let selected = $("#secondary_sale_show_quantity").val();
    console.log(`onShowQuantityChange ${selected}`);
    switch (selected) {
      case "Indicative":
        $(".indicative_quantity_group").show();

        break;
      case "Actual":
        $(".indicative_quantity_group").hide();

        break;
      default:
    }
  }



  // Prevent form from submitting if required fields are not filled
  checkRequiredFilled(event) {
    
    let required_missing = false;
    $('#secondary_sale_form .required').each(function () {
      if ($(this).val().length == 0) {
        console.log("Its blank");
        $(this).closest('.form-group').addClass('field_with_errors');
        required_missing = true;
      } else {
        $(this).closest('.form-group').removeClass('field_with_errors');
      }
    });

    if(required_missing) {
      event.preventDefault();
    }
  }

  // Clear error css if required field is filled
  addErrorCheck() {
    $('#secondary_sale_form .required').each(function () {
      if ($(this).val().length == 0) {
        console.log("Its blank");
        $(this).closest('.form-group').addClass('field_with_errors');
      } else {
        $(this).closest('.form-group').removeClass('field_with_errors');
      }
    });
  }

}
