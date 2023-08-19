import { Controller } from "@hotwired/stimulus"
// import { initRecordVideo } from 'custom/initRecordVideo'

export default class extends Controller {
    connect() {
        console.log("videokyc connect");  
        if($("#live")) {
            this.initRecordVideo();
        }    
    }

    initRecordVideo() {  
        let start = $("#start");
        let stop = $("#stop");
        let live = $("#live");

        

        let stopVideo = (e) => {
          live.srcObject.getTracks().forEach(track => track.stop());
          e.preventDefault();
          console.log("Stopped Video Recording");
        }

        stop.click(stopVideo);
   
        start.click((e) => {
          
          console.log("Started Video Recording");
          e.preventDefault();

          navigator.mediaDevices.getUserMedia({
            video: true,
            audio: true
          })
          .then(stream => {
            console.log(stream);
            live.attr('src', stream);
            live.attr('captureStream', live.captureStream || live.mozCaptureStream);
            return new Promise(resolve => live.onplaying = resolve);
          });


          e.preventDefault();
          
        });
    }

};
