const { AwsS3 } = Uppy

export function uppyInstance({ id, types, server }) {
  const uppy = new Uppy.Core({
    id: id,
    autoProceed: true,
    restrictions: {
      allowedFileTypes: types,
      // maxNumberOfFiles: 1,
    },
  })

  if (server == 's3') {
    uppy.use(AwsS3, {
      companionUrl: '/', // will call Shrine's presign endpoint mounted on `/s3/params`
    })
  } else if (server == 's3_multipart') {
    uppy.use(AwsS3Multipart, {
      companionUrl: '/' // will call uppy-s3_multipart endpoint mounted on `/s3/multipart`
    })
  } else {
    uppy.use(XHRUpload, {
      endpoint: '/upload', // Shrine's upload endpoint
    })
  }

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
};
