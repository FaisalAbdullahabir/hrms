var MODULE_OPTIONS = [
  "HR", "Payroll", "Accounting", "Manufacturing", "Stock", "Selling",
  "Buying", "Quality", "CRM", "Assets", "Projects", "Support",
  "Website", "Tools", "Education", "Drive"
];

var DEFAULT_MODULES = {
  ngo: ["HR", "Payroll", "Accounting"],
  business: ["HR", "Payroll", "Accounting"],
  retail: ["Stock", "Selling", "Buying", "Accounting"]
};

function addInterestedPlanColumn() {
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) {
      Logger.log("ERROR: Cannot access active spreadsheet");
      return;
    }
    Logger.log("Spreadsheet: " + ss.getName());

    var clientsSheet = ss.getSheetByName("Clients");
    if (!clientsSheet) {
      Logger.log("ERROR: 'Clients' tab not found. Available sheets: " + ss.getSheets().map(function(s) { return s.getName(); }).join(", "));
      return;
    }

    var headerRange = clientsSheet.getRange(1, 12);
    var currentHeader = headerRange.getValue();
    if (currentHeader === "interested_plan") {
      Logger.log("Column L already has interested_plan header, skipping");
      return;
    }
    headerRange.setValue("interested_plan");
    Logger.log("Added interested_plan header to column L");
  } catch (err) {
    Logger.log("ERROR in addInterestedPlanColumn: " + err.message);
  }
}

function addEnabledModulesColumn() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName("Clients");

  sheet.getRange("M1:M1000").clear();

  var headerRange = sheet.getRange(1, 13, 1, 16);
  headerRange.setValues([MODULE_OPTIONS]);
  headerRange.setFontWeight("bold");

  sheet.getRange(2, 13, 999, 16).insertCheckboxes();

  var lastRow = sheet.getLastRow();
  if (lastRow > 1) {
    var data = sheet.getRange(2, 1, lastRow - 1, 3).getValues();
    for (var i = 0; i < data.length; i++) {
      var row = i + 2;
      var clientType = String(data[i][2] || "").trim().toLowerCase();
      var enabledModules = DEFAULT_MODULES[clientType] || [];
      for (var j = 0; j < MODULE_OPTIONS.length; j++) {
        sheet.getRange(row, 13 + j).setValue(enabledModules.indexOf(MODULE_OPTIONS[j]) >= 0);
      }
    }
  }

  Logger.log("Module checkbox columns created: M through AB (16 modules)");
}

function onFormSubmit(e) {
  try {
    Logger.log("=== onFormSubmit TRIGGERED ===");

    var sheet = e.range.getSheet();
    var sheetName = sheet.getName();
    Logger.log("Source sheet name: '" + sheetName + "'");

    if (sheetName !== "Form Responses") {
      Logger.log("SKIP: Sheet name does not match 'Form Responses'");
      return;
    }

    var row = e.range.getRow();
    Logger.log("Submitted row number: " + row);

    var data = sheet.getRange(row, 1, 1, sheet.getLastColumn()).getValues()[0];
    Logger.log("Raw data length: " + data.length + " columns");

    for (var d = 0; d < Math.min(15, data.length); d++) {
      Logger.log("  data[" + d + "] = '" + String(data[d]).substring(0, 50) + "'");
    }

    var orgName       = String(data[1] || "").trim();
    var contactPerson = String(data[2] || "").trim();
    var contactEmail  = String(data[3] || "").trim();
    var contactPhone  = String(data[4] || "").trim();
    var orgType       = String(data[5] || "").trim();
    var expectedUsers = String(data[6] || "").trim();
    var interestedPlan = String(data[7] || "").trim();

    Logger.log("orgName: '" + orgName + "'");
    Logger.log("contactPerson: '" + contactPerson + "'");
    Logger.log("contactEmail: '" + contactEmail + "'");
    Logger.log("contactPhone: '" + contactPhone + "'");
    Logger.log("orgType: '" + orgType + "'");
    Logger.log("expectedUsers: '" + expectedUsers + "'");
    Logger.log("interestedPlan: '" + interestedPlan + "'");

    if (!orgName || !contactEmail) {
      Logger.log("ERROR: Organization Name or Email is empty — skipping");
      return;
    }

    var clientType = orgType.toLowerCase();
    if (clientType.indexOf("ngo") >= 0 || clientType.indexOf("non") >= 0) {
      clientType = "ngo";
    } else if (clientType.indexOf("retail") >= 0 || clientType.indexOf("market") >= 0) {
      clientType = "retail";
    } else {
      clientType = "business";
    }
    Logger.log("clientType: '" + clientType + "'");

    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var clientsSheet = ss.getSheetByName("Clients");
    if (!clientsSheet) {
      Logger.log("ERROR: 'Clients' tab not found");
      return;
    }
    Logger.log("Clients tab found");

    var prefix = (clientType === "ngo") ? "ngo_" :
                 (clientType === "retail") ? "retail_" : "biz_";

    var lastRow = clientsSheet.getLastRow();
    Logger.log("Clients tab last row: " + lastRow);

    var existingIds = [];
    if (lastRow > 1) {
      existingIds = clientsSheet.getRange(2, 1, lastRow - 1, 1)
        .getValues()
        .flat()
        .map(function(id) { return String(id).trim(); });
    }
    Logger.log("Existing IDs found: " + existingIds.length);

    var nextNum = 1;
    for (var i = 0; i < existingIds.length; i++) {
      if (existingIds[i].indexOf(prefix) === 0) {
        var num = parseInt(existingIds[i].replace(prefix, ""), 10);
        if (!isNaN(num) && num >= nextNum) {
          nextNum = num + 1;
        }
      }
    }

    var clientId = prefix + String(nextNum).padStart(3, "0");
    Logger.log("Generated client_id: '" + clientId + "'");

    var today = new Date();
    var expiry = new Date(today.getTime() + 14 * 24 * 60 * 60 * 1000);
    var activatedDate = Utilities.formatDate(today, Session.getScriptTimeZone(), "yyyy-MM-dd");
    var expiryDate = Utilities.formatDate(expiry, Session.getScriptTimeZone(), "yyyy-MM-dd");
    Logger.log("activated_date: " + activatedDate + ", expiry_date: " + expiryDate);

    var newRow = [
      clientId,
      orgName,
      clientType,
      "pending_setup",
      "free_trial",
      activatedDate,
      expiryDate,
      "",
      contactEmail,
      "",
      contactPhone,
      interestedPlan
    ];

    Logger.log("Appending row to Clients tab...");
    clientsSheet.appendRow(newRow);

    var newRowNum = clientsSheet.getLastRow();
    var enabledModules = DEFAULT_MODULES[clientType] || [];
    for (var j = 0; j < MODULE_OPTIONS.length; j++) {
      clientsSheet.getRange(newRowNum, 13 + j).setValue(enabledModules.indexOf(MODULE_OPTIONS[j]) >= 0);
    }
    Logger.log("Checkboxes set for new row " + newRowNum);

    var subject = "LawnHive Workspace — রেজিস্ট্রেশন সফল হয়েছে";
    var planLabel = interestedPlan || "Free Trial";
    var body =
      "প্রিয় " + contactPerson + ",\n\n" +
      "LawnHive Workspace-তে আপনার রেজিস্ট্রেশন সফলভাবে গ্রহণ করা হয়েছে।\n\n" +
      "আপনার তথ্য:\n" +
      "  ক্লায়েন্ট আইডি: " + clientId + "\n" +
      "  প্রতিষ্ঠান: " + orgName + "\n" +
      "  প্ল্যান: ফ্রি ট্রায়াল (১৪ দিন)\n" +
      "  প্রত্যাশিত ব্যবহারকারী: " + (expectedUsers || "N/A") + "\n" +
      "  আগ্রহী প্ল্যান: " + planLabel + "\n\n" +
      "আপনি " + planLabel + " প্ল্যানে আগ্রহ দেখিয়েছেন। এখন ১৪ দিনের ফ্রি ট্রায়াল দিয়ে শুরু হবে, ট্রায়াল শেষে পেমেন্ট করলে আপনার পছন্দের প্ল্যানে আপগ্রেড হয়ে যাবে।\n\n" +
      "LawnHive টিম শীঘ্রই আপনার সাথে যোগাযোগ করবে এবং সিস্টেম সেটআপ সম্পন্ন করবে।\n\n" +
      "ধন্যবাদ,\n" +
      "LawnHive Workspace টিম\n" +
      "https://lawnhive.com";

    Logger.log("Sending confirmation email to: " + contactEmail);
    MailApp.sendEmail(contactEmail, subject, body);
    Logger.log("Email sent successfully");

    Logger.log("=== SUCCESS: " + clientId + " | " + orgName + " | " + clientType + " | users=" + expectedUsers + " ===");

  } catch (err) {
    Logger.log("=== FATAL ERROR: " + err.message + " ===");
    Logger.log("Stack: " + err.stack);
  }
}
