"use strict";

document.addEventListener("DOMContentLoaded", async function() {
  let processionElem = document.getElementById("procession");

  let handleUnsupported = () => {
    processionElem.className = 'procession_unsupported';
  };
  if (!navigator.credentials) return handleUnsupported();

  const regId = processionElem.attributes['data-reg-id'].value;
  const state = processionElem.attributes['data-state'].value;
  const callbackUrl = processionElem.attributes['data-callback'].value;

  const creationOptions = JSON.parse(processionElem.attributes['data-webauthn-creation'].value);
  creationOptions.publicKey.challenge = new Uint8Array(creationOptions.publicKey.challenge).buffer;
  creationOptions.publicKey.user.id = new Uint8Array(creationOptions.publicKey.user.id).buffer;
  console.log(creationOptions);

  let attestation;

  const startCreationRequest = async function() {
    processionElem.className = 'procession_wait';

    try {
      attestation = await navigator.credentials.create(creationOptions);
      console.log(attestation);
    } catch (e) {
      document.getElementById("error_message").innerHTML = `WebAuthn (${e.toString()})`;
      processionElem.className = 'procession_error';
      console.log(e);

      if (e instanceof DOMException) {
        if (e.name == 'NotAllowedError' || e.name == 'AbortError') {
          processionElem.className = 'procession_timeout';
          return;
        }
        if (e.name == 'NotSupportedError') {
          handleUnsupported();
          return;
        }
      }
      return;
    }

    processionElem.className = 'procession_edit';
    document.getElementById("key_name").focus();
  };

  const submitAttestation = async function() {
    processionElem.className = 'procession_contact';

    const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
    const payload = JSON.stringify({
      reg_id: regId,
      name: document.getElementById("key_name").value,
      attestation_object: b64(attestation.response.attestationObject),
      client_data_json: b64(attestation.response.clientDataJSON),
    });
    try {
      const resp = await fetch(`/ui/register`, {credentials: 'include', method: 'POST', body: payload});
      console.log(resp);
      if (!resp.ok) {
        processionElem.className = 'procession_error';
        return;
      }

      const json = await resp.json();
      console.log(json);
      if (json.ok) {
        processCallback(json);
      } else {
        processionElem.className = 'procession_error';
      }
    } catch (e) {
      console.log(e);
      processionElem.className = 'procession_error';
    };
  };

  document.getElementById("key_name_form").addEventListener("submit", (e) => {
    e.preventDefault();
    if (attestation) submitAttestation();
  });

  const processCallback = function (json) {
    processionElem.className = 'procession_ok';

    if (callbackUrl.match(/^js:/)) {
      if (!window.opener) {
        console.log("window.opener is not truthy")
        processionElem.className = 'procession_error';
        return;
      }
      window.opener.postMessage({clarion_key: {state: state, name: json.name, data: json.encrypted_key}}, callbackUrl.slice(3));
      window.close();
    } else {
      let form = document.getElementById("callback_form");
      form.action = callbackUrl;
      form.querySelector('[name=data]').value = json.encrypted_key;
      form.submit();
    }
  };

  document.getElementById("retry_button").addEventListener("click", (e) => {
    startCreationRequest();
  });
  return startCreationRequest();
});
