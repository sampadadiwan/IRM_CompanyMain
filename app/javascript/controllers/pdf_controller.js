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


    base64ToArrayBuffer(base64) {
        var binary_string = window.atob(base64);
        var len = binary_string.length;
        var bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) {
            bytes[i] = binary_string.charCodeAt(i);
        }
        return bytes.buffer;
    }

    async readDscFile(e) {
        var fileInput = document.getElementById('dscfile');

        var reader = new FileReader();
        reader.readAsDataURL(fileInput.files[0]);

        const base64ToArrayBuffer = this.base64ToArrayBuffer;
        const toDsc = this.dsc;
        const viewer_instance = this.viewer_instance;
        const saveBlob = this.saveBlob;
        const createSignatureField = this.createSignatureField;

        reader.onload = function () {

            // Use a regex to remove data url part
            const base64String = reader.result
                .replace('data:', '')
                .replace(/^.+,/, '');

            // console.log(base64String);
            let arraybuffer = base64ToArrayBuffer(base64String);
            console.log(arraybuffer);

            // createSignatureField(viewer_instance);
            toDsc(arraybuffer, viewer_instance, saveBlob);
        };
        reader.onerror = function (error) {
            console.log('Error: ', error);
        };


        e.preventDefault();
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

                if ($("#sign_document").val() !== "true") {
                    console.log(`############# Signing is NOT turned on`);

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
                            opacity: 40, // from 0 to 100
                            text: viewer_watermark
                        },
    
                        // Draw header watermark
                        header: {
                            fontSize: 8,
                            fontFamily: 'sans-serif',
                            color: 'grey',
                            opacity: 45,
                            // left: 'left watermark',
                            center: viewer_watermark,
                            right: ''
                        }
                    });

                } else {
                    console.log(`############# Signing is turned on`);
                    instance.UI.setToolbarGroup('toolbarGroup-Insert');
                    instance.UI.openElements(['toolbarGroup-Insert']);
                    instance.UI.setHeaderItems(function (header) {
                        header.getHeader('toolbarGroup-Insert').delete(2);
                        header.getHeader('toolbarGroup-Insert').delete(3);
                        header.getHeader('toolbarGroup-Insert').delete(4);
                    });
                                        
                }


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

    add_dsc_field() {
        this.createSignatureField(this.viewer_instance);
        this.save_signed();
    }

    async createSignatureField(viewer_instance) {
        const { PDFNet, documentViewer } = viewer_instance.Core;
        const doc = await documentViewer.getDocument().getPDFDoc();
        console.log(`Got DOC ${doc}`);
        await PDFNet.runWithCleanup(async () => {

            // lock the document before a write operation
            // runWithCleanup will auto unlock when complete
            doc.lock();
            console.log("Document locked");
            
            const certificationFieldName = "SigField";

            const certificationSigField = await doc.createDigitalSignatureField(certificationFieldName);
            console.log(certificationSigField);
            console.log('created certificationSigField for pdf');
        });
    }

    
    async dsc(dsc_signature_buffer, viewer_instance, saveBlob) {

        console.log("dsc called");

        const { PDFNet, documentViewer } = viewer_instance.Core;

        await PDFNet.initialize();
        console.log(`PDFNet.initialized`);

        const doc = await documentViewer.getDocument().getPDFDoc();
        console.log(`got doc ${doc}`);


        // Run PDFNet methods with memory management
        await PDFNet.runWithCleanup(async () => {

            // lock the document before a write operation
            // runWithCleanup will auto unlock when complete
            doc.lock();
            console.log("Document locked");

            // Add an StdSignatureHandler instance to PDFDoc, making sure to keep track of it using the ID returned.
            const sigHandlerId = await doc.addStdSignatureHandlerFromBuffer(dsc_signature_buffer, 'isb2005*');

            console.log("Added sigHandlerId");

            /**
             * Certifying a document requires a digital signature field (can optionally be
             * hidden), hence why the logic below either looks for an existing field in the
             * document, or suggests creating a field in the document
             */

            // Retrieve the unsigned certification signature field.
            /**
             * Note: Replace certificationFieldName with the field name in the
             * document that is being certified
             */

            const certificationFieldName = "SigField";

            const foundCertificationField = await doc.getField(certificationFieldName);
            const certificationSigField = await PDFNet.DigitalSignatureField.createFromField(foundCertificationField);

            // Alternatively, create a new signature form field in the PDFDoc. The name argument is optional;
            // leaving it empty causes it to be auto-generated. However, you may need the name for later.
            // Acrobat doesn't show digsigfield in side panel if it's without a widget. Using a
            // Rect with 0 width and 0 height, or setting the NoPrint/Invisible flags makes it invisible.
            // const certificationSigField = await doc.createDigitalSignatureField(certificationFieldName);
            console.log(certificationSigField);

            // (OPTIONAL) Add more information to the signature dictionary.
            // await certificationSigField.setLocation("Vancouver, BC");
            // await certificationSigField.setReason("Document certification.");
            // await certificationSigField.setContactInfo("www.pdftron.com");
            // Prepare the document locking permission level to be applied upon document certification.
            certificationSigField.setDocumentPermissions(PDFNet.DigitalSignatureField.DocumentPermissions.e_no_changes_allowed);

            console.log('added location to certificationSigField');
            // (OPTIONAL) Add an appearance to the signature field.
            // const img = await PDFNet.Image.createFromURL(doc, "/img/ST041.gif");

            // console.log("Created image for signature");

            const certifySignatureWidget = await PDFNet.SignatureWidget.createWithDigitalSignatureField(
                doc,
                await PDFNet.Rect.init(0, 100, 200, 150),
                certificationSigField
            );

            console.log("Created certifySignatureWidget");
            // await certifySignatureWidget.createSignatureAppearance(img);
            const page1 = await doc.getPage(1);
            page1.annotPushBack(certifySignatureWidget);


            // Prepare the signature and signature handler for certification.
            await certificationSigField.signOnNextSaveWithCustomHandler(sigHandlerId);

            // The actual certification signing will be done during the save operation.
            const buf = await doc.saveMemoryBuffer(0);
            const blob = new Blob([buf], { type: 'application/pdf' });
            console.log(blob);
            // saveAs(blob, 'certified_doc.pdf');

            saveBlob(blob);
        });
        

    }


}
