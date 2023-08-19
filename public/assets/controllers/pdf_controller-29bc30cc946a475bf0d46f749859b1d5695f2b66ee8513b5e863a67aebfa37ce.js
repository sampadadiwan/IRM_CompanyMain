import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    viewer_instance;

    async save_signed() {

        const { documentViewer, annotationManager } = this.viewer_instance.Core;

        let doc = documentViewer.getDocument();
        let xfdfString = await annotationManager.exportAnnotations();
        let data = await doc.getFileData({
            // saves the document with annotations in it
            xfdfString
        });
        let arr = new Uint8Array(data);
        let blob = new Blob([arr], { type: 'application/pdf' });

        console.log(blob);

        this.saveBlob(blob);

    }

    saveBlob(blob) {
        let file = new File([blob], "signed.pdf", { type: "application/pdf", lastModified: new Date().getTime() });

        let container = new DataTransfer();
        container.items.add(file);

        let fileInputElement = document.getElementById('document_file');

        fileInputElement.files = container.files;
        $("#signed_doc_form").submit();
    }


    connect() {

        Core.setWorkerPath('/lib/core');

        let viewer_link = $("#viewer_link").val();
        let viewer_watermark = $("#viewer_watermark").val();
        let viewer_content_type = $("#viewer_content_type").val();

        // Hide the direct download link
        // $(".document_download_icon").hide();
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
            fullAPI: true,
            licenseKey: 'CapHive Private Limited (altconnects.com):OEM:CapHive::B+:AMS(20230928):70A55F8D0437F80AF360B13AC982537860613F8D8776BD3B95853BA45A955E6D54F2B6F5C7',
            path: '/lib',
        }, document.getElementById('viewer'))
            .then(async (instance) => {
                this.viewer_instance = instance;
                const { PDFNet, documentViewer } = instance.Core;
                await PDFNet.initialize();
                // const docViewer = instance.Core.documentViewer;
                // const annotManager = instance.Core.annotationManager;


                instance.UI.disableElements(['toolbarGroup-Shapes']);
                instance.UI.disableElements(['toolbarGroup-View']);
                instance.UI.disableElements(['toolbarGroup-Edit']);
                instance.UI.disableElements(['toolbarGroup-Annotate']);
                instance.UI.disableElements(['toolbarGroup-Forms']);
                instance.UI.disableElements(['toolbarGroup-FillAndSign']);




                if ($("#download_document").val() !== "true") {
                    instance.UI.disableElements(['downloadButton']);
                }
                if ($("#printing_document").val() !== "true") {
                    instance.UI.disableElements(['printButton']);
                }

                


                instance.UI.loadDocument(viewer_link, {
                    filename: 'myfile.pdf'
                });

                instance.UI.setFitMode(instance.FitMode.FitWidth);

                $("#viewer_label").hide();
                $("#viewer").show();

                

                console.log(`In full screen ${instance.UI.isFullscreen()}`);


                instance.UI.disableElements(['ribbons']);
                instance.UI.disableElements(['toolsHeader']);
                instance.UI.disableElements(['toolbarGroup-Insert']);

                instance.UI.openElements(['menuOverlay']);

                $(".document_download_icon").hide();

                documentViewer.setWatermark({
                    // Draw diagonal watermark in middle of the document
                    diagonal: {
                        fontSize: 20, // or even smaller size
                        fontFamily: 'sans-serif',
                        color: 'grey',
                        opacity: 30, // from 0 to 100
                        text: viewer_watermark
                    },

                    // Draw header watermark
                    header: {
                        fontSize: 4,
                        fontFamily: 'sans-serif',
                        color: 'grey',
                        opacity: 40,
                        // left: 'left watermark',
                        center: viewer_watermark,
                        right: ''
                    }
                });

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

};
