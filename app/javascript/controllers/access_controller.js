import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {

    const hideCategory = this.hideCategory
    const hideEmployee = this.hideEmployee
    $(document).on('turbo:frame-load', function () {

      console.log("Access javascript loaded");
      $('.select2-multiple').select2();

      $(".select2-multiple").on('select2:select', function () {
        let event = new Event('change', { bubbles: true }) // fire a native event
        this.dispatchEvent(event);
      });

      hideCategory();
      hideEmployee();
    });

  }

  onChange(event) {
    console.log("onChange");
    console.log("change");
    let selected = $("#access_right_email_or_cat").val();
    switch (selected) {
      case "All Users for Specific Investor":
        // hide category & disable
        this.hideCategory();
        this.hideEmployee();
        this.showInvestor();
        break;
      case "All Investors of Specific Category":
        // hide category & disable
        this.showCategory();
        this.hideEmployee();        
        this.hideInvestor();
        break;

      case "Employee":
        // hide category & disable
        this.hideCategory();
        this.hideInvestor();
        this.showEmployee();
        break;
      default:
    }
  }

  close(event) {
    console.log("closeForm");
    $(".dynamic_form").remove();
  }


  // Prevent form from submitting if required fields are not filled
  checkRequiredFilled(event) {
    
    let required_missing = false;
    $('#access_rights_form .required').each(function () {
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
    $('#access_rights_form .required').each(function () {
      if ($(this).val().length == 0) {
        console.log("Its blank");
        $(this).closest('.form-group').addClass('field_with_errors');
      } else {
        $(this).closest('.form-group').removeClass('field_with_errors');
      }
    });
  }

  hideCategory() {
    $("#category_form_group").hide();
    $('#access_right_access_to_category').prop('disabled', 'disabled');
    $('#access_right_access_to_category').removeClass('required');
  }
  showCategory() {
    $("#category_form_group").show();
    $('#access_right_access_to_category').prop('disabled', '');
    $('#access_right_access_to_category').addClass('required');
  }

  hideInvestor() {
    $("#investor_form_group").hide();
    $('#access_right_access_to_investor_id').prop('disabled', "disabled");
    $('#access_right_access_to_investor_id').removeClass('required');        
  }

  showInvestor() {
    $("#investor_form_group").show();
    $('#access_right_access_to_investor_id').prop('disabled', "");
    $('#access_right_access_to_investor_id').addClass('required');
  }


  showEmployee() {
    $("#employee_form_group").show();
    $('#access_right_user_id').prop('disabled', "");
    $('#access_right_user_id').addClass('required');
    $("#metadata_form_group").hide();        
    $('#access_right_metadata').prop('disabled', "disabled");

  }

  hideEmployee() {
    $("#employee_form_group").hide();
    $('#access_right_user_id').prop('disabled', "disabled");
    $('#access_right_user_id').removeClass('required');
    $("#metadata_form_group").show();        
    $('#access_right_metadata').prop('disabled', "");

  }


}
