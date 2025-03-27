const { AwsS3, AwsS3Multipart, XHRUpload } = Uppy;


export function uppyInstance({ id, types, server }) {
  const uppy = new Uppy.Core({
    id: id,
    autoProceed: true,
    restrictions: {
      allowedFileTypes: types,
    },
  })

  if (server == 's3') {
    uppy.use(AwsS3, {
      companionUrl: '/', // will call Shrine's presign endpoint mounted on `/s3/params`
      pretty: true,
    })
  } else if (server == 's3_multipart') {
    uppy.use(AwsS3Multipart, {
      companionUrl: '/', // will call uppy-s3_multipart endpoint mounted on `/s3/multipart`
      pretty: true,
    })
  } else {
    uppy.use(XHRUpload, {
      endpoint: '/upload', // Shrine's upload endpoint
      pretty: true,
    })
  }


  // Get all submit buttons
  const submitBtns = document.querySelectorAll('input[type="submit"]');
  $(".uppy_wait_info").hide();
  
  // Function to disable all submit buttons
  function disableSubmitButtons() {
    submitBtns.forEach(btn => {
      btn.disabled = true;
    });
    $(".uppy_wait_info").show();
  }

  // Function to enable all submit buttons
  function enableSubmitButtons() {
    submitBtns.forEach(btn => {
      btn.disabled = false;
    });
    $(".uppy_wait_info").hide();
  }

  // Disable submit buttons before the file is uploaded
  uppy.on('upload', () => {
    console.log('Before upload');
    disableSubmitButtons();
    // Optionally, you can show a loading indicator here
  });

  // Re-enable submit buttons after the file is uploaded successfully
  uppy.on('upload-success', (file, response) => {
    console.log('Upload complete', file, response);
    enableSubmitButtons();
    // Optionally, hide the loading indicator and show a success message
  });

  // Re-enable submit buttons if the upload fails
  uppy.on('upload-error', (file, error, response) => {
    console.error('Upload error', file, error, response);
    enableSubmitButtons();
    // Optionally, hide the loading indicator and show an error message
  });

  // Handle file addition
  uppy.on('file-added', (file) => {
    console.log('File added', file);
    // Optionally, you can perform any actions upon file addition
  });


  return uppy
}

export function uploadedFileData(file, response, server) {
  if (server == 's3') {
    const id = file.meta['key'].match(/^cache\/(.+)/)[1]; // object key without prefix

    return JSON.stringify(fileData(file, id))
  } else if (server == 's3_multipart') {
    const id = response.uploadURL.match(/\/cache\/([^\?]+)/)[1]; // object key without prefix

    return JSON.stringify(fileData(file, id))
  } else {
    return JSON.stringify(response.body)
  }
}

// constructs uploaded file data in the format that Shrine expects
function fileData(file, id) {
  return {
    id: id,
    storage: 'cache',
    metadata: {
      size:      file.size,
      filename:  file.name,
      mime_type: file.type,
    }
  }
}
