import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("filter connect");
    $('form').on('click', '.remove_fields', function(event) {
        $(this).closest('.row').remove();
        event.preventDefault();
    });
    $('form').on('click', '.add_fields', function(event) {
        var time = new Date().getTime();
        var regexp = new RegExp($(this).data('id'), 'g');
        
        // console.log(`regexp: ${regexp}`);
        // console.log(`$(this).data('fields'): ${$(this).data('fields')}`);

        $(this).parent().before($(this).data('fields').replace(regexp, time));
        event.preventDefault();
    });
  }

 
}


