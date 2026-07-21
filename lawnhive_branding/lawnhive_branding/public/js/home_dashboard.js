(function () {
  function renderDashboard() {
    if (!window.location.pathname.startsWith("/app/home")) return;

    frappe.call({
      method: "license_control.tasks.get_dashboard_shortcuts",
      callback: function (r) {
        if (!r.message || !r.message.length) return;

        var existing = document.getElementById("lh-dashboard");
        if (existing) existing.remove();

        var container = document.createElement("div");
        container.id = "lh-dashboard";

        var html =
          '<div class="lh-dash-header">' +
          '<span class="lh-dash-title">Your Modules</span>' +
          "</div>" +
          '<div class="lh-dash-grid">';

        r.message.forEach(function (s) {
          html +=
            '<a class="lh-dash-card" href="' +
            s.route +
            '">' +
            '<div class="lh-dash-icon"><i class="fa ' +
            s.icon +
            '"></i></div>' +
            '<div class="lh-dash-label">' +
            s.module +
            "</div>" +
            "</a>";
        });

        html += "</div>";
        container.innerHTML = html;

        var workspace = document.querySelector(".page-head");
        if (workspace && workspace.parentNode) {
          workspace.parentNode.insertBefore(container, workspace.nextSibling);
        }
      },
    });
  }

  function waitForPage() {
    if (typeof frappe !== "undefined" && typeof frappe.ready === "function") {
      frappe.ready(function () {
        setInterval(function () {
          if (
            window.location.pathname.startsWith("/app/home") &&
            !document.getElementById("lh-dashboard")
          ) {
            renderDashboard();
          }
        }, 1000);
      });
    } else {
      document.addEventListener("DOMContentLoaded", function () {
        setInterval(function () {
          if (
            window.location.pathname.startsWith("/app/home") &&
            !document.getElementById("lh-dashboard")
          ) {
            renderDashboard();
          }
        }, 1000);
      });
    }
  }

  waitForPage();
})();
