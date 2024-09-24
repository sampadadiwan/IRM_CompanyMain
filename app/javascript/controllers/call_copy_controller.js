import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("call_copy connect");
    this.call_basis_changed();
    this.addApplicableToListener();
  }

  copy_all(e) {
    e.preventDefault();

    let price = $(".price")[0].value;
    $(".price").each(function (index, item) {
      $(item)[0].value = price;
    });
    console.log(`price = ${price}`);

    if ($(".premium").length > 0) {
      let premium = $(".premium")[0].value;
      console.log(`premium = ${premium}`);

      $(".premium").each(function (index, item) {
        $(item)[0].value = premium;
      });
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
      $("#applicable-to-group").show();
    } else if (call_basis === "Upload") {
      $("#amount_to_be_called_group").hide();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").hide();
      $("#applicable-to-group").hide();
    } else {
      $("#amount_to_be_called_group").show();
      $("#percentage_called_group").hide();
      $("#percentage-fields-container").hide();
      $("#applicable-to-group").show();
    }
  }

  addApplicableToListener() {
    const applicableToSelect = $("#capital_call_fund_closes");

    applicableToSelect.on('change', (event) => {
      this.handleApplicableToSelection(event);
    });
  }

  handleApplicableToSelection(event) {
    const selectedCloses = $(event.target).val();
    const container = $("#percentage-fields-container");

    container.empty();

    $("#percentage_called_group").hide();

    selectedCloses.forEach((close) => {
      if (close === "All") {
        return;
      }

      const row = `
        <div class="form-group">
          <label>${close} - Percentage Called</label>
          <input type="number" step="any" name="capital_call[close_percentages][${close}]" class="form-control" required />
          <small class="text-muted">Enter percentage for ${close}</small>
        </div>
      `;
      container.append(row);
    });
  }
}
