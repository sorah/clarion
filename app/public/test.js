"use strict";

document.addEventListener("DOMContentLoaded", function() {
  let elem = document.getElementById('authn_test');
  let key = JSON.parse(elem.attributes['data-key'].value);
  var authnId = null;

  var status = {};
  let updateView = function () {
    elem.innerHTML = JSON.stringify(status, null, 2);
  }

  setInterval(function() {
    if (!authnId) return;

    let handleError = (err) => {
      status.error = 'authn get error (fetch)';
      updateView();
      console.log(err);
    };

    fetch(status.authn.url, {credentials: 'include'}).then((resp) => {
      console.log(resp);
      if (!resp.ok) {
        status.error = 'authn get error (!ok)';
        updateView();
        return;
      }
      return resp.json().then((json) => {
        console.log(json);
        if (json.authn) {
          status.authn = json.authn;
          if (status.authn.status == 'verified') {
            authnId = null;
          }
        } else {
          status.error = 'authn get error';
        }
        updateView();
      });
    }).catch(handleError);
  }, 1000);

  document.getElementById("open_authn_button").addEventListener("click", function() {
    window.open(status.authn.html_url, '_blank');
  });

  document.getElementById("start_authn_button").addEventListener("click", function() {
    let payload = JSON.stringify({
      name: "testuser",
      comment: "test authn",
      keys: [key],
    });

    let handleError = (err) => {
      status.error = 'authn create error (fetch)';
      updateView();
      console.log(err);
    };

    fetch(`/api/authn`, {credentials: 'include', method: 'POST', body: payload}).then((resp) => {
      console.log(resp);
      if (!resp.ok) {
        status.error = 'authn create error (!ok)';
        updateView();
        return;
      }
      return resp.json().then((json) => {
        console.log(json);
        if (json.authn) {
          status.authn = json.authn;
          authnId = json.authn.id;
          document.getElementById("open_authn_button").className = '';
        } else {
          status.error = 'authn create error';
        }
        updateView();
      });
    }).catch(handleError);
  });
});
