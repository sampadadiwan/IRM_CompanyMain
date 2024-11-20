import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("call_copy connect");
    this.call_basis_changed();
  }

  copy_all(e) {
    e.preventDefault();

    function copyFieldValues(fieldClass) {
      let firstValue = $(`.${fieldClass}`)[0].value;
      console.log(`${fieldClass} = ${firstValue}`);

      $(`.${fieldClass}`).each(function (index, item) {
        $(item)[0].value = firstValue;
      });
    }

    if ($(".price").length > 0) {
      copyFieldValues('price');
    }

    if ($(".premium").length > 0) {
      copyFieldValues('premium');
    }

    if ($(".percentage").length > 0) {
      copyFieldValues('percentage');
    }
  }


  copy_all_percentage_changes(e) {
    e.preventDefault();

    let percentage_change = $(".percentage_change")[0].value;
    $(".percentage_change").each(function (index, item) {
      $(item)[0].value = percentage_change;
    });
    console.log(`percentage_change = ${percentage_change}`);
  }

  call_basis_changed() {
    let call_basis = $("#capital_call_call_basis").val();
    console.log(`call_basis = ${call_basis}`);

    if (call_basis === "Percentage of Commitment") {
      $("#amount_to_be_called_group").hide();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").show();
      $("#close-percentages-container").show(); 
      $("#applicable-to-group").hide();
    } else if (call_basis === "Upload") {
      $("#amount_to_be_called_group").hide();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").hide();
      $("#close-percentages-container").hide();
      $("#applicable-to-group").hide();

      $(".percentage").each(function () {
        $(this).val("");
      });
    } else {
      $("#amount_to_be_called_group").show();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").hide();
      $("#close-percentages-container").hide();
      $("#applicable-to-group").show();

      $(".percentage").each(function () {
        $(this).val("");
      });
    }
  }

}
