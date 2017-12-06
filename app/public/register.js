"use strict";

document.addEventListener("DOMContentLoaded", function() {
  let processionElem = document.getElementById("procession");

  let handleUnsupported = () => {
    processionElem.className = 'procession_unsupported';
  };
  let unsupportedTimer = setTimeout(handleUnsupported, 3000);

  window.u2f.getApiVersion((ver) => {
    console.log(ver);
    clearTimeout(unsupportedTimer);
    let appId = processionElem.attributes['data-app-id'].value;
    let regId = processionElem.attributes['data-reg-id'].value;
    let requests = JSON.parse(processionElem.attributes['data-requests'].value);
    let state = processionElem.attributes['data-state'].value;
    let callbackUrl = processionElem.attributes['data-callback'].value;

    var u2fResponse;

    let processCallback = (json) => {
      processionElem.className = 'procession_ok';

      if (callbackUrl.match(/^js:/)) {
        if (!window.opener) {
          console.log("window.opener is not truthy")
          processionElem.className = 'procession_error';
          return;
        }
        window.opener.postMessage({clarion_key: {state: state, data: json.encrypted_key}}, callbackUrl.slice(3));
        window.close();
      } else {
        let form = document.getElementById("callback_form");
        form.action = callbackUrl;
        form.querySelector('[name=data]').value = json.encrypted_key;
        form.submit();
      }
    }

    let submitKey = () => {
      processionElem.className = 'procession_contact';

      let payload = JSON.stringify({
        reg_id: regId,
        response: JSON.stringify(u2fResponse),
        name: document.getElementById("key_name").value,
      });

      let handleError = (err) => {
        console.log(err);
        processionElem.className = 'procession_error';
      };

      fetch(`/ui/register`, {credentials: 'include', method: 'POST', body: payload}).then((resp) => {
        console.log(resp);
        if (!resp.ok) {
          processionElem.className = 'procession_error';
          return;
        }
        return resp.json().then((json) => {
          console.log(json);
          if (json.ok) {
            processCallback(json);
          } else {
            processionElem.className = 'procession_error';
          }
        });
      }).catch(handleError);
    };
    document.getElementById("key_name_form").addEventListener("submit", (e) => {
      e.preventDefault();
      if (u2fResponse) submitKey();
    });

    let u2fCallback = (response) => {
      console.log(response);

      if (response.errorCode == window.u2f.ErrorCodes.TIMEOUT) {
        processionElem.className = 'procession_timeout';
        return;
      } else if (response.errorCode) {
        processionElem.className = 'procession_error';
        return;
      }
      u2fResponse = response;
      processionElem.className = 'procession_edit';
      document.getElementById("key_name").focus();
    };

    let startRequest = () => {
      processionElem.className = 'procession_wait';
      window.u2f.register(appId, requests, [], u2fCallback);
    };

    document.getElementById("retry_button").addEventListener("click", (e) => {
      startRequest();
    });

    startRequest();
  });


});
