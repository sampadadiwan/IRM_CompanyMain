import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        console.log("login controller connect");

        $("#togglePassword").on('click',function() {
            if ($("#user_password").attr('type') === 'password') {
                $("#user_password").attr('type', 'text');
            } else {
                $("#user_password").attr('type', 'password');
            }
          });
    }

    no_password() {
        console.log("no_password");
        $("#user_password").removeAttr('required');
        $('#new_user').attr('action', "/users/magic_link").submit();
    }
    
}


