import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("CK Controller connect");
    
    CKEDITOR.ClassicEditor.create( document.querySelector( '#editor' ), {
        // https://ckeditor.com/docs/ckeditor5/latest/features/toolbar/toolbar.html#extended-toolbar-configuration-format
        toolbar: {
            items: [
                'ckbox', 'uploadImage', '|',
                'exportPDF','exportWord', '|',
                'comment', 'trackChanges', 'revisionHistory', '|',
                'findAndReplace', 'selectAll', '|',
                'bold', 'italic', 'strikethrough', 'underline', 'removeFormat', '|',
                'bulletedList', 'numberedList', 'todoList', '|',
                'outdent', 'indent', '|',
                'undo', 'redo',
                '-',
                'heading', '|',
                'fontSize', 'fontFamily', 'fontColor', 'fontBackgroundColor', 'highlight', '|',
                'alignment', '|',
                'link', 'blockQuote', 'insertTable', 'mediaEmbed', 'codeBlock', 'htmlEmbed', '|',
                'specialCharacters', 'horizontalLine', 'pageBreak', '|',
                // Intentionally skipped buttons to keep the toolbar smaller, feel free to enable them:
                // 'code', 'subscript', 'superscript', 'textPartLanguage', '|',
                // ** To use source editing remember to disable real-time collaboration plugins **
                // 'sourceEditing'
            ],
            shouldNotGroupWhenFull: true
        },
        // Changing the language of the interface requires loading the language file using the <script> tag.
        // language: 'es',
        list: {
            properties: {
                styles: true,
                startIndex: true,
                reversed: true
            }
        },
        // https://ckeditor.com/docs/ckeditor5/latest/features/headings.html#configuration
        heading: {
            options: [
                { model: 'paragraph', title: 'Paragraph', class: 'ck-heading_paragraph' },
                { model: 'heading1', view: 'h1', title: 'Heading 1', class: 'ck-heading_heading1' },
                { model: 'heading2', view: 'h2', title: 'Heading 2', class: 'ck-heading_heading2' },
                { model: 'heading3', view: 'h3', title: 'Heading 3', class: 'ck-heading_heading3' },
                { model: 'heading4', view: 'h4', title: 'Heading 4', class: 'ck-heading_heading4' },
                { model: 'heading5', view: 'h5', title: 'Heading 5', class: 'ck-heading_heading5' },
                { model: 'heading6', view: 'h6', title: 'Heading 6', class: 'ck-heading_heading6' }
            ]
        },
        // https://ckeditor.com/docs/ckeditor5/latest/features/font.html#configuring-the-font-family-feature
        fontFamily: {
            options: [
                'default',
                'Arial, Helvetica, sans-serif',
                'Courier New, Courier, monospace',
                'Georgia, serif',
                'Lucida Sans Unicode, Lucida Grande, sans-serif',
                'Tahoma, Geneva, sans-serif',
                'Times New Roman, Times, serif',
                'Trebuchet MS, Helvetica, sans-serif',
                'Verdana, Geneva, sans-serif'
            ],
            supportAllValues: true
        },
        // https://ckeditor.com/docs/ckeditor5/latest/features/font.html#configuring-the-font-size-feature
        fontSize: {
            options: [ 10, 12, 14, 'default', 18, 20, 22 ],
            supportAllValues: true
        },
        // Be careful with the setting below. It instructs CKEditor to accept ALL HTML markup.
        // https://ckeditor.com/docs/ckeditor5/latest/features/general-html-support.html#enabling-all-html-features
        // htmlSupport: {
        // 	allow: [
        // 		{
        // 			name: /.*/,
        // 			attributes: true,
        // 			classes: true,
        // 			styles: true
        // 		}
        // 	]
        // },
        // Be careful with enabling previews
        // https://ckeditor.com/docs/ckeditor5/latest/features/html-embed.html#content-previews
        htmlEmbed: {
            showPreviews: true
        },
        // https://ckeditor.com/docs/ckeditor5/latest/features/mentions.html#configuration
        mention: {
            feeds: [
                {
                    marker: '@',
                    feed: [
                        '@apple', '@bears', '@brownie', '@cake', '@cake', '@candy', '@canes', '@chocolate', '@cookie', '@cotton', '@cream',
                        '@cupcake', '@danish', '@donut', '@dragée', '@fruitcake', '@gingerbread', '@gummi', '@ice', '@jelly-o',
                        '@liquorice', '@macaroon', '@marzipan', '@oat', '@pie', '@plum', '@pudding', '@sesame', '@snaps', '@soufflé',
                        '@sugar', '@sweet', '@topping', '@wafer'
                    ],
                    minimumCharacters: 1
                }
            ]
        },
        // https://ckeditor.com/docs/ckeditor5/latest/features/editor-placeholder.html#using-the-editor-configuration
        placeholder: 'Welcome to CKEditor 5!',
        // Used by real-time collaboration
        cloudServices: {
            // Be careful - do not use the development token endpoint on production systems!
            tokenUrl: 'https://94538.cke-cs.com/token/dev/dRUSJgwJGbiL6z0cxq5oiDlaf6r3Zh7fSROs?limit=10',
            webSocketUrl: 'wss://94538.cke-cs.com/ws'
        },
        collaboration: {
            // Modify the channelId to simulate editing different documents
            // https://ckeditor.com/docs/ckeditor5/latest/features/collaboration/real-time-collaboration/real-time-collaboration-integration.html#the-channelid-configuration-property
            channelId: 'document-id-2'
        },
        // https://ckeditor.com/docs/ckeditor5/latest/features/collaboration/annotations/annotations-custom-configuration.html#sidebar-configuration
        sidebar: {
            container: document.querySelector( '#sidebar' )
        },
        // https://ckeditor.com/docs/ckeditor5/latest/features/collaboration/real-time-collaboration/users-in-real-time-collaboration.html#users-presence-list
        presenceList: {
            container: document.querySelector( '#presence-list-container' )
        },
        // Add configuration for the comments editor if the Comments plugin is added.
        // https://ckeditor.com/docs/ckeditor5/latest/features/collaboration/annotations/annotations-custom-configuration.html#comment-editor-configuration
        comments: {
            editorConfig: {
                extraPlugins: CKEDITOR.ClassicEditor.builtinPlugins.filter( plugin => {
                    // Use e.g. Ctrl+B in the comments editor to bold text.
                    return [ 'Bold', 'Italic', 'Underline', 'List', 'Autoformat', 'Mention' ].includes( plugin.pluginName );
                } ),
                // Combine mentions + Webhooks to notify users about new comments
                // https://ckeditor.com/docs/cs/latest/guides/webhooks/events.html
                mention: {
                    feeds: [
                        {
                            marker: '@',
                            feed: [
                                '@Baby Doe', '@Joe Doe', '@Jane Doe', '@Jane Roe', '@Richard Roe'
                            ],
                            minimumCharacters: 1
                        }
                    ]
                },
            }
        },
        // Do not include revision history configuration if you do not want to integrate it.
        // Remember to remove the 'revisionHistory' button from the toolbar in such a case.
        revisionHistory: {
            editorContainer: document.querySelector( '#editor-container' ),
            viewerContainer: document.querySelector( '#revision-viewer-container' ),
            viewerEditorElement: document.querySelector( '#revision-viewer-editor' ),
            viewerSidebarContainer: document.querySelector( '#revision-viewer-sidebar' ),
        },
        // https://ckeditor.com/docs/ckeditor5/latest/features/images/image-upload/ckbox.html
        ckbox: {
            // Be careful - do not use the development token endpoint on production systems!
            tokenUrl: 'https://94538.cke-cs.com/token/dev/dRUSJgwJGbiL6z0cxq5oiDlaf6r3Zh7fSROs?limit=10'
        },
        // License key is required only by the Pagination plugin and non-realtime Comments/Track changes.
        licenseKey: '3xR3Fe5dynawzNocMwZxGLPnZZOIMdip0Q7tO+HmOrLl5rS6w025F0ftAQ==',
        removePlugins: [
            // Before enabling Pagination plugin, make sure to provide proper configuration and add relevant buttons to the toolbar
            // https://ckeditor.com/docs/ckeditor5/latest/features/pagination/pagination.html
            'Pagination',
            // Intentionally disabled, file uploads are handled by CKBox
            'Base64UploadAdapter',
            // Intentionally disabled, file uploads are handled by CKBox
            'CKFinder',
            // Intentionally disabled, file uploads are handled by CKBox
            'EasyImage',
            // Requires additional license key
            'WProofreader',
            // Incompatible with real-time collaboration
            'SourceEditing',
            // Careful, with the Mathtype plugin CKEditor will not load when loading this sample
            // from a local file system (file://) - load this site via HTTP server if you enable MathType
            'MathType'
            // If you would like to adjust enabled collaboration features:
            // 'RealTimeCollaborativeComments',
            // 'RealTimeCollaborativeTrackChanges',
            // 'RealTimeCollaborativeRevisionHistory',
            // 'PresenceList',
            // 'Comments',
            // 'TrackChanges',
            // 'TrackChangesData',
            // 'RevisionHistory',
        ]
    } )
        .then( editor => {
            window.editor = editor;

            // Example implementation to switch between different types of annotations according to the window size.
            // https://ckeditor.com/docs/ckeditor5/latest/features/collaboration/annotations/annotations-display-mode.html
            const annotationsUIs = editor.plugins.get( 'AnnotationsUIs' );
            const sidebarElement = document.querySelector( '.sidebar' );
            let currentWidth;

            function refreshDisplayMode() {
                // Check the window width to avoid the UI switching when the mobile keyboard shows up.
                if ( window.innerWidth === currentWidth ) {
                    return;
                }
                currentWidth = window.innerWidth;

                if ( currentWidth < 1000 ) {
                    sidebarElement.classList.remove( 'narrow' );
                    sidebarElement.classList.add( 'hidden' );
                    annotationsUIs.switchTo( 'inline' );
                }
                else if ( currentWidth < 1300 ) {
                    sidebarElement.classList.remove( 'hidden' );
                    sidebarElement.classList.add( 'narrow' );
                    annotationsUIs.switchTo( 'narrowSidebar' );
                }
                else {
                    sidebarElement.classList.remove( 'hidden', 'narrow' );
                    annotationsUIs.switchTo( 'wideSidebar' );
                }
            }

            editor.ui.view.listenTo( window, 'resize', refreshDisplayMode );
            refreshDisplayMode();

            return editor;
        } )
        .catch( error => {
            console.error( 'There was a problem initializing the editor.', error );
        } );
    
  }

}
