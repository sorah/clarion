"use strict";

document.addEventListener("DOMContentLoaded", async function() {
  let processionElem = document.getElementById("procession");

  let handleUnsupported = () => {
    processionElem.className = 'procession_unsupported';
  };
  if (!navigator.credentials) return handleUnsupported();

  const requestOptions = JSON.parse(processionElem.attributes['data-webauthn-request'].value);
  requestOptions.publicKey.challenge = new Uint8Array(requestOptions.publicKey.challenge).buffer;
  requestOptions.publicKey.allowCredentials = requestOptions.publicKey.allowCredentials.map((v) => ({type: v.type, id: new Uint8Array(v.id).buffer}));
  console.log(requestOptions);
  const authnId = processionElem.attributes['data-authn-id'].value;
  const reqId = processionElem.attributes['data-req-id'].value;

  const cancelRequest = async function (e) {
    if (e) e.preventDefault();
    const payload = JSON.stringify({
      req_id: reqId,
    });

    try {
      const resp = await fetch(`/ui/cancel/${authnId}`, {credentials: 'include', method: 'POST', body: payload});
      console.log(resp);
      if (!resp.ok) {
        processionElem.className = 'procession_error';
        return;
      }
      const json = await resp.json();
      console.log(json);
      if (json.ok) {
        processionElem.className = 'procession_cancel';
      } else {
        processionElem.className = 'procession_error';
      }
    } catch (e) {
      console.log(err);
      processionElem.className = 'procession_error';
    }
  };
  document.getElementById("cancel_link").addEventListener("click", cancelRequest);

  const startAssertionRequest = async function() {
    processionElem.className = 'procession_wait';

    let assertion;
    try {
      assertion = await navigator.credentials.get(requestOptions);
      console.log(assertion);
      if (!assertion) {
        processionElem.className = 'procession_unambigious';
        return;
      }
    } catch (e) {
      document.getElementById("error_message").innerHTML = `WebAuthn (${e.toString()})`;
      processionElem.className = 'procession_error';
      console.log(e);

      if (e instanceof DOMException) {
        if (e.name == 'NotAllowedError') {
          processionElem.className = 'procession_timeout';
          return;
        }
        if (e.name == 'NotSupportedError') {
          handleUnsupported();
          return;
        }
        if (e.name == 'InvalidStateError') {
        processionElem.className = 'procession_invalid';
          return;
        }
      }
      return;
    }

    processionElem.className = 'procession_contact';

    const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
    const payload = JSON.stringify({
      req_id: reqId,
      credential_id: assertion.id,
      authenticator_data: b64(assertion.response.authenticatorData),
      client_data_json: b64(assertion.response.clientDataJSON),
      signature: b64(assertion.response.signature),
      user_handle: b64(assertion.response.userHandle),
      extension_results: assertion.getClientExtensionResults(),
    });

    try {
      const resp = await fetch(`/ui/verify/${authnId}`, {credentials: 'include', method: 'POST', body: payload});
      const json = await resp.json();
      console.log(json);
      if (resp.ok) {
        if (json.ok) {
          processionElem.className = 'procession_ok';
          if (window.opener) {
            window.close();
          } else {
            setTimeout(() => window.close(), 2000);
          }
        } else {
          processionElem.className = 'procession_error';
        }
      } else {
        if (resp.status == 401) {
          processionElem.className = 'procession_invalid';
        } else {
          processionElem.className = 'procession_error';
        }
      }
    } catch (e) {
      document.getElementById("error_message").innerHTML = `Contact Error`;
      console.log(e);
      processionElem.className = 'procession_error';
      return;
    }
  }

  document.getElementById("retry_button").addEventListener("click", (e) => {
    startAssertionRequest();
  });
  return startAssertionRequest();
});
