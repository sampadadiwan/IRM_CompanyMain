import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Fields that only mean something for a formula that writes account entries
  // (entry type, generate YTD/quarterly, roll up) -- hidden for pre/post-run checks.
  static targets = ["entryOnly"]
  static values = { checkTypes: Array }

  connect() {
    console.log("fund_formula connect");
    this.ruleTypeChanged();
  }

  ruleTypeChanged()  {
    let val = $("#fund_formula_rule_type").val();
    console.log(`ruleTypeChanged ${val}`);
    $(".explanation").hide();
    $(`.${val}`).show();

    const isCheck = this.checkTypesValue.includes(val);
    this.entryOnlyTargets.forEach((el) => {
      el.hidden = isCheck;
      // A check rejects generate_ytd_qtly/roll_up on save; clear them so a formula switched
      // to a check type does not fail validation on a box the user can no longer see.
      if (isCheck) el.querySelectorAll("input[type=checkbox]").forEach((box) => { box.checked = false; });
    });
  }

}
