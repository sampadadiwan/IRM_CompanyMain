import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("DocForm controller loaded");
    this.onOrignalChange();
    this.onPdfOptChange();
    this.checkOtherName();
    this.showSignature();
    this.toggleReminderPeriod();
  }

  onOrignalChange(event) {
    console.log("onOrignalChange");
    if($("#document_orignal").is(':checked')) {
        $('.pdfopts input:checkbox').removeAttr('checked');
        $(".pdfopts").hide();
    }
    else  {
        $(".pdfopts").show();
    }
  }

  onPdfOptChange(event) {
    console.log("onPdfOptChange");
    if($("#document_download").is(':checked') || $("#document_printing").is(':checked')) {
        $('.nonpdf input:checkbox').removeAttr('checked');
        $(".nonpdf").hide();
    }
    else  {
        $(".nonpdf").show();
    }
  }

  checkOtherName(event) {

    if($("#doc_name_select").length > 0) {
      let selected = $("#doc_name_select").val();
      console.log(`other_name = ${$("#other_name").val().length}`);

      if (selected == "Other" || $("#other_name").val().length > 0) {
        $("#doc_name_select").remove();
        $("#other_name").prop("disabled", "")
        $("#other_name").show();
      } else {
        $("#other_name").hide();
      }
    }
  }

  toggleReminderPeriod(event) {
    if($("#document_esign_email_reminders").length > 0 && !$("#document_esign_email_reminders").is(':checked')) {
      $("#esign_reminder_period_div").hide();
    } else {
      $("#esign_reminder_period_div").show();
    }
  }

  showSignature() {
    console.log("showSignature");
    console.log($("#document_template").val());
    if($("#document_template").is(':checked')) {
      $("#esign_section").show();
      $("#add_signature_btn").show();
      $("#sign_display_on_page").show();
      $("#add_stamp_paper_btn").show();
      $("#stamp_papers").show();
      $("#e_signatures").show();
      $("#template_docs_to_append_div").show();
    } else {
      // The whole eSignatures card, not just its fields, so no empty card header is left behind
      $("#esign_section").hide();
      $("#add_signature_btn").hide();
      $("#sign_display_on_page").hide();
      $("#add_stamp_paper_btn").hide();
      $("#stamp_papers").hide();
      $("#e_signatures").hide();
      $("#template_docs_to_append_div").hide();
    }
  }

}
