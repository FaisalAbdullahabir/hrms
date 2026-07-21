(function () {
  var MAP = {
    erpnext: { title: "LawnHive Accounting", logo: "/assets/lawnhive_branding/images/logo.png" },
    hrms: { title: "LawnHive Workspace", logo: "/assets/lawnhive_branding/images/logo.png" },
    education: { title: "LawnHive Learning", logo: "/assets/lawnhive_branding/images/logo.png" },
    drive: { title: "LawnHive Files", logo: "/assets/lawnhive_branding/images/logo.png" },
  };

  function rebrand() {
    var items = document.querySelectorAll(".app-name-cls");
    items.forEach(function (el) {
      var name = el.getAttribute("app-name");
      if (MAP[name]) {
        var titleEl = el.querySelector(".app-title");
        if (titleEl) titleEl.textContent = MAP[name].title;
        var img = el.querySelector("img");
        if (img) img.src = MAP[name].logo;
      }
    });
  }

  if (typeof frappe !== "undefined" && typeof frappe.ready === "function") {
    frappe.ready(rebrand);
  } else {
    document.addEventListener("DOMContentLoaded", rebrand);
  }
})();
