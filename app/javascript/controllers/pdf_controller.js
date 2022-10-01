import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {

        Core.setWorkerPath('/lib/core');

        let viewer_link = $("#viewer_link").val();
        let viewer_watermark = $("#viewer_watermark").val();
        let viewer_content_type = $("#viewer_content_type").val();

        // Hide the direct download link
        $(".document_download_icon").hide();
        $("#viewer").hide();

        console.log(`pdf_controller connected: ${viewer_link}`);

        if (viewer_content_type == "application/pdf") {
            this.viewPDF(viewer_link, viewer_watermark);
        } else {
            this.officeToPDF(viewer_link, viewer_watermark);
        }

        this.init();

    }

    viewPDF(viewer_link, viewer_watermark) {
        WebViewer({
            licenseKey: 'CapHive Private Limited (altconnects.com):OEM:CapHive::B+:AMS(20230928):70A55F8D0437F80AF360B13AC982537860613F8D8776BD3B95853BA45A955E6D54F2B6F5C7',
            path: '/lib', 
        }, document.getElementById('viewer'))
            .then(instance => {
                instance.UI.disableElements(['ribbons']);
                instance.UI.disableElements(['toolsHeader']);
                instance.UI.openElements([ 'menuOverlay' ]);
                if($("#download_document").val() !== "true") { 
                    instance.UI.disableElements([ 'downloadButton' ]);
                }
                if($("#printing_document").val() !== "true") { 
                    instance.UI.disableElements([ 'printButton' ]);
                }


                const docViewer = instance.Core.documentViewer;
                const annotManager = instance.Core.annotationManager;

                instance.UI.loadDocument(viewer_link, {
                    filename: 'myfile.pdf'
                });

                instance.UI.setFitMode(instance.FitMode.FitPage);
                
                $("#viewer_label").hide();
                $("#viewer").show();
        

                const { documentViewer } = instance.Core;
                


                documentViewer.setWatermark({
                    // Draw diagonal watermark in middle of the document
                    diagonal: {
                        fontSize: 20, // or even smaller size
                        fontFamily: 'sans-serif',
                        color: 'grey',
                        opacity: 18, // from 0 to 100
                        text: viewer_watermark
                    },

                    // Draw header watermark
                    header: {
                        fontSize: 8,
                        fontFamily: 'sans-serif',
                        color: 'grey',
                        opacity: 40,
                        // left: 'left watermark',
                        center: viewer_watermark,
                        right: ''
                    }
                });

                $(".document_download_icon").hide();
                console.log(`In full screen ${instance.UI.isFullscreen()}`);

            });
    }

    init() {
        PDFNet.runWithCleanup(this.initCompleted, "CapHive Private Limited (altconnects.com):OEM:CapHive::B+:AMS(20230928):70A55F8D0437F80AF360B13AC982537860613F8D8776BD3B95853BA45A955E6D54F2B6F5C7");
    }

    initCompleted() {
        console.log("initCompleted");
    }

    officeToPDF(viewer_link, viewer_watermark) {
        
        this.convertOfficeToPDF(viewer_link, `converted.pdf`, viewer_watermark);

        // PDFNet.initialize()
        //     .then(() =>  {
        //         this.convertOfficeToPDF(viewer_link, `converted.pdf`, viewer_watermark)                
        //      })            
        //     .catch(err => {
        //         console.log('An error was encountered! :(', err);
        //         $(".document_download_icon").show();
        //     });
    }

    convertOfficeToPDF(inputUrl, outputName, viewer_watermark, l) {

        Core.officeToPDFBuffer(inputUrl, { l }).then(buffer => {
            this.viewPDF(buffer, viewer_watermark);
        }).catch(err => {
            console.log('An error was encountered! :(', err);
            $(".document_download_icon").show();
            $("#pdf_viewer").remove();
        });
    }


}
