import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        console.log("login controller connect");

        // Sometimes people leave the login window open, and invalidauthenticitytoken happens as server is restarted
        // Hence we reload the page every 5 mins
        setTimeout("location.reload();", 300000);


        $("#togglePassword").on('click',function() {
            if ($("#user_password").attr('type') === 'password') {
                $("#user_password").attr('type', 'text');
            } else {
                $("#user_password").attr('type', 'password');
            }
          });
    }
    
}


