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

    let authnId = processionElem.attributes['data-authn-id'].value;
    let appId = processionElem.attributes['data-app-id'].value;
    let reqId = processionElem.attributes['data-req-id'].value;
    let requests = JSON.parse(processionElem.attributes['data-requests'].value);
    let challenge = JSON.parse(processionElem.attributes['data-challenge'].value);

    let requestCancel  = (e) => {
      if (e) e.preventDefault();
      let payload = JSON.stringify({
        req_id: reqId,
      });

      let handleError = (err) => {
        console.log(err);
        processionElem.className = 'procession_error';
      };

      fetch(`/ui/cancel/${authnId}`, {credentials: 'include', method: 'POST', body: payload}).then((resp) => {
        console.log(resp);
        if (!resp.ok) {
          processionElem.className = 'procession_error';
          return;
        }
        return resp.json().then((json) => {
          console.log(json);
          if (json.ok) {
            processionElem.className = 'procession_cancel';
          } else {
            processionElem.className = 'procession_error';
          }
        });
      }).catch(handleError);
    };
    document.getElementById("cancel_link").addEventListener("click", requestCancel);

    let processCallback = (json) => {
      processionElem.className = 'procession_ok';
      if (window.opener) window.close();
    }

    let cb = (response) => {
      console.log(response);

      if (response.errorCode == window.u2f.ErrorCodes.TIMEOUT) {
        processionElem.className = 'procession_timeout';
        return;
      } else if (response.errorCode) {
        document.getElementById("error_message").innerHTML = `U2F Client Error ${response.errorCode}`;
        processionElem.className = 'procession_error';
        return;
      }
      processionElem.className = 'procession_contact';

      let payload = JSON.stringify({
        req_id: reqId,
        response: JSON.stringify(response),
      });

      let handleError = (err) => {
        console.log(err);
        processionElem.className = 'procession_error';
      };

      fetch(`/ui/verify/${authnId}`, {credentials: 'include', method: 'POST', body: payload}).then((resp) => {
        console.log(resp);
        if (!resp.ok) {
          return resp.json().then((json) => {
            console.log(json);
            processionElem.className = 'procession_error';
          },(jsonErr) => {
            console.log(jsonErr);
            processionElem.className = 'procession_error';
            document.getElementById("error_message").innerHTML = `Error ${resp.status}`;
            throw jsonErr;
          });
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

    let startRequest = () => {
      processionElem.className = 'procession_wait';
      window.u2f.sign(appId, challenge, requests, cb);
    };
    document.getElementById("retry_button").addEventListener("click", (e) => {
      startRequest();
    });
    startRequest();
  });


});
