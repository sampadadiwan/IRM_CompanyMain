import { Controller } from "@hotwired/stimulus"
import { CountUp } from 'countup.js';


/* 
<div data-controller="counters" data-counters-target-id-value="countup_id" 
    data-counters-value-value="<%= some_value %>">
    <span id="countup_id"></span>
</div> 
*/

export default class extends Controller {

    static values = {
        targetId: String, // Which select id are we targeting
        value: Number
    }

  connect() {

    console.log(this.targetIdValue);
    console.log(this.valueValue);
    
    const countUp = new CountUp(this.targetIdValue, this.valueValue);
    countUp.start(() => console.log('Complete!'));
  }

}
