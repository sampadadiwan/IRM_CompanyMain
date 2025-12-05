import { Controller } from "@hotwired/stimulus"
import { CountUp } from 'countup.js';


/*
<div data-controller="counters"
     data-counters-value-value="<%= 1234.56 %>"
     data-counters-formatted-value-value="<%= number_to_currency(1234.56) %>">
    <span data-counters-target="output"></span>
</div>
*/

export default class extends Controller {

    static targets = [ "output" ]
    static values = {
        value: Number,
        formattedValue: String // The final formatted string (e.g., currency)
    }

  connect() {
    const element = this.outputTarget;
    const endVal = this.valueValue;
    const formattedVal = this.formattedValueValue;
    const duration = 2;

    if (isNaN(endVal)) {
      if (this.hasFormattedValueValue) element.innerHTML = formattedVal;
      return;
    }

    const options = {
      useGrouping: true,
      separator: ',',
      decimal: '.',
      decimalPlaces: 0,
      duration: duration,
    };

    const countUp = new CountUp(element, endVal, options);

    if (!countUp.error) {
      countUp.start();
      if (this.hasFormattedValueValue) {
        setTimeout(() => {
          element.innerHTML = formattedVal;
        }, duration * 1000 + 100); // 100ms buffer
      }
    } else {
      console.error(countUp.error);
      if (this.hasFormattedValueValue) {
        element.innerHTML = formattedVal;
      }
    }
  }

}
