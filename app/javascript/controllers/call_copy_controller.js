import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("call_copy connect");
    this.call_basis_changed();
  }

  copy_all(event) {
    event.preventDefault();

    function copyFieldValues(fieldClass) {
      let firstValue = $(`.${fieldClass}`)[0].value;
      console.log(`${fieldClass} = ${firstValue}`);

      $(`.${fieldClass}`).each(function (index, item) {
        $(item)[0].value = firstValue;
      });
    }

    if (event.target.closest(".field-group").id == "price-container") {
      if ($(".price").length > 0) {
        copyFieldValues('price');
      }

      if ($(".premium").length > 0) {
        copyFieldValues('premium');
      }
    }

    if (event.target.closest(".field-group").id == "close-percentages-container") {
      if ($(".percentage").length > 0) {
        copyFieldValues('percentage');
      }
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
      // Default fund_closes to "All" when nothing is selected (new call with no prior value).
      // Skipped on edit forms and mid-form call_basis switches where the user has already
      // chosen specific closes, so existing values are never overwritten.
      const fundClosesSelect = $("#capital_call_fund_closes");
      const currentVal = fundClosesSelect.val();
      if (!currentVal || currentVal.length === 0) {
        fundClosesSelect.find("option[value='All']").prop("selected", true);
        fundClosesSelect.trigger("change");
      }
      $("#applicable-to-group").hide();
    } else if (call_basis === "Upload") {
      $("#amount_to_be_called_group").hide();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").hide();
      $("#close-percentages-container").hide();
      $("#applicable-to-group").hide();
      // Clear fund_closes so the hidden field doesn't get submitted with a stale "All" value
      // (which gets set when switching from Percentage of Commitment basis).
      $("#capital_call_fund_closes").val([]).trigger("change");

      $(".percentage").each(function () {
        $(this).val("");
      });
    } else {
      $("#amount_to_be_called_group").show();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").hide();
      $("#close-percentages-container").hide();
      // Deselect "All" when switching to a basis that requires specific closes.
      // "All" is only a valid default for "Percentage of Commitment"; keeping it
      // selected while the user picks specific closes produces an invalid combination.
      const fundClosesSelect = $("#capital_call_fund_closes");
      const currentVal = fundClosesSelect.val() || [];
      if (currentVal.includes("All")) {
        fundClosesSelect.find("option[value='All']").prop("selected", false);
        fundClosesSelect.trigger("change");
      }
      $("#applicable-to-group").show();

      $(".percentage").each(function () {
        $(this).val("");
      });
    }
  }

}
