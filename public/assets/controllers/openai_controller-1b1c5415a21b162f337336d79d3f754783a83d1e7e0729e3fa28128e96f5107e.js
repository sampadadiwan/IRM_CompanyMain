import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    connect() {
        console.log("openai Controller called");
        $("#letter_preview").toggle();
    }

    generate() {
        this.openai_test();
    }

    async openai_test() {
        $("#letter_preview").toggle();
        $("#letter_preview").html("Generating....");

        let open_ai_response;
        var fund_data = $("#fund_data").val();

        var url = "https://api.openai.com/v1/engines/text-davinci-002/completions";

        var xhr = new XMLHttpRequest();
        xhr.open("POST", url);

        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.setRequestHeader("Authorization", "Bearer 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");

        xhr.onreadystatechange = function () {
            if (xhr.readyState === 4) {
                console.log(xhr.status);
                open_ai_response = xhr.response;
                // console.log(open_ai_response);                
                if(xhr.status==200) {
                    $("#letter_preview").html(JSON.parse(xhr.response)["choices"][0]["text"]);
                }
            }
        };

        var data = `{
            "prompt": "${fund_data}",
            "temperature": 0.7,
            "max_tokens": 1000,
            "top_p": 0.8,
            "frequency_penalty": 0.5,
            "presence_penalty": 0
        }`;

        xhr.send(data);
        console.log(`Sent request ${data} to openai`);
    }

};
