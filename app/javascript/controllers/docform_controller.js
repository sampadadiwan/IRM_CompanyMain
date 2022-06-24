import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {    
    console.log("DocForm controller loaded");    
    this.onOrignalChange();
    this.onPdfOptChange();    
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

}
