import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("DocForm controller loaded");
    this.onOrignalChange();
    this.onPdfOptChange();
    this.checkOtherName();
    this.showSignature();
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

  showSignature() {
    console.log("showSignature");
    console.log($("#document_template").val());
    if($("#document_template").is(':checked')) {
      $("#add_signature_btn").show();
      $("#sign_display_on_page").show();
      $("#add_stamp_paper_btn").show();
      $("#stamp_papers").show();
      $("#e_signatures").show();
      $("#template_docs_to_append_div").show();
    } else {
      $("#add_signature_btn").hide();
      $("#sign_display_on_page").hide();
      $("#add_stamp_paper_btn").hide();
      $("#stamp_papers").hide();
      $("#e_signatures").hide();
      $("#template_docs_to_append_div").hide();
    }
  }

}
