// The password e-mail's link (Supabase Auth, type=recovery) lands here with the session in the URL
// fragment: #access_token=…&type=recovery. The new password is sent straight to Supabase Auth
// (PUT /auth/v1/user) with that token; nothing is stored in the browser and the fragment is cleared.
(function () {
  var cfg = window.CW_AUTH;
  var hash = new URLSearchParams(location.hash.replace(/^#/, ""));
  var query = new URLSearchParams(location.search);
  var token = hash.get("access_token");
  var failed = hash.get("error") || hash.get("error_description") || query.get("error");
  if (location.hash) history.replaceState(null, "", location.pathname + location.search);

  function show(id) {
    ["m-short", "m-mismatch", "m-done", "m-expired", "m-failed"].forEach(function (m) {
      document.getElementById(m).hidden = m !== id;
    });
  }

  var form = document.getElementById("reset");
  if (!token || failed || hash.get("type") !== "recovery") {
    show("m-expired");
    return;
  }
  form.hidden = false;
  form.addEventListener("submit", function (e) {
    e.preventDefault();
    var a = document.getElementById("pw1").value;
    var b = document.getElementById("pw2").value;
    if (a.length < 8) return show("m-short");
    if (a !== b) return show("m-mismatch");
    var button = form.querySelector("button");
    button.disabled = true;
    fetch(cfg.url + "/auth/v1/user", {
      method: "PUT",
      headers: {
        apikey: cfg.key,
        Authorization: "Bearer " + token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ password: a }),
    })
      .then(function (res) {
        if (res.ok) {
          form.hidden = true;
          token = null;
          show("m-done");
        } else if (res.status === 401 || res.status === 403) {
          form.hidden = true;
          show("m-expired");
        } else {
          show("m-failed");
        }
      })
      .catch(function () {
        show("m-failed");
      })
      .finally(function () {
        button.disabled = false;
      });
  });
})();
