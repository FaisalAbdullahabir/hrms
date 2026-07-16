/**
 * One-time setup: adds "interested_plan" header to Clients tab column L.
 * Run once from Apps Script Editor.
 */
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

/**
 * One-time setup: adds "enabled_modules" header to Clients tab column M.
 * Run once from Apps Script Editor.
 */
function addEnabledModulesColumn() {
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) {
      Logger.log("ERROR: Cannot access active spreadsheet");
      return;
    }

    var clientsSheet = ss.getSheetByName("Clients");
    if (!clientsSheet) {
      Logger.log("ERROR: 'Clients' tab not found");
      return;
    }

    var headerRange = clientsSheet.getRange(1, 13);
    var currentHeader = headerRange.getValue();
    if (currentHeader === "enabled_modules") {
      Logger.log("Column M already has enabled_modules header, skipping");
      return;
    }
    headerRange.setValue("enabled_modules");
    Logger.log("Added enabled_modules header to column M");
  } catch (err) {
    Logger.log("ERROR in addEnabledModulesColumn: " + err.message);
  }
}

/**
 * Registration Handler — Google Apps Script
 * Triggered when a Google Form response is submitted.
 *
 * Sheet tabs:
 *   "Form Responses" — raw form responses (auto-created by Google Forms)
 *   "Clients"        — license tracking client registry
 *
 * Column mapping (Form Responses):
 *   A = Timestamp (auto)
 *   B = Organization Name
 *   C = Contact Person Name
 *   D = Email
 *   E = Phone Number
 *   F = Organization Type (NGO / Business / Retail)
 *   G = Expected Number of Users
 *   H = Interested Plan
 */

function onFormSubmit(e) {
  try {
    Logger.log("=== onFormSubmit TRIGGERED ===");

    // ════════════════════════════════════════════════════════════════
    // STEP 1: Read submitted row from trigger event
    // ════════════════════════════════════════════════════════════════
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

    // Debug: show first 15 column values
    for (var d = 0; d < Math.min(15, data.length); d++) {
      Logger.log("  data[" + d + "] = '" + String(data[d]).substring(0, 50) + "'");
    }

    var orgName       = String(data[1] || "").trim(); // B: Organization Name
    var contactPerson = String(data[2] || "").trim(); // C: Contact Person
    var contactEmail  = String(data[3] || "").trim(); // D: Email
    var contactPhone  = String(data[4] || "").trim(); // E: Phone
    var orgType       = String(data[5] || "").trim(); // F: Organization Type
    var expectedUsers = String(data[6] || "").trim(); // G: Expected Users
    var interestedPlan = String(data[7] || "").trim(); // H: Interested Plan

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

    // Convert org type to lowercase
    var clientType = orgType.toLowerCase();
    if (clientType.indexOf("ngo") >= 0 || clientType.indexOf("non") >= 0) {
      clientType = "ngo";
    } else if (clientType.indexOf("retail") >= 0 || clientType.indexOf("market") >= 0) {
      clientType = "retail";
    } else {
      clientType = "business";
    }
    Logger.log("clientType: '" + clientType + "'");

    // ════════════════════════════════════════════════════════════════
    // STEP 2: Generate unique client_id (no duplicates)
    // ════════════════════════════════════════════════════════════════
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

    // Calculate activated_date (today) and expiry_date (today + 14 days)
    var today = new Date();
    var expiry = new Date(today.getTime() + 14 * 24 * 60 * 60 * 1000);
    var dateOptions = { year: 'numeric', month: '2-digit', day: '2-digit' };
    var activatedDate = Utilities.formatDate(today, Session.getScriptTimeZone(), "yyyy-MM-dd");
    var expiryDate = Utilities.formatDate(expiry, Session.getScriptTimeZone(), "yyyy-MM-dd");
    Logger.log("activated_date: " + activatedDate + ", expiry_date: " + expiryDate);

    // ════════════════════════════════════════════════════════════════
    // STEP 3: Add new row to "Clients" tab
    // ════════════════════════════════════════════════════════════════
    var newRow = [
      clientId,        // A: client_id
      orgName,         // B: client_name
      clientType,      // C: client_type
      "pending_setup", // D: status
      "free_trial",    // E: plan
      activatedDate,   // F: activated_date
      expiryDate,      // G: expiry_date
      "",              // H: last_check_in
      contactEmail,    // I: contact_email
      "",              // J: login_password
      contactPhone,    // K: contact_phone
      interestedPlan,  // L: interested_plan
      ""               // M: enabled_modules (admin sets manually)
    ];

    Logger.log("Appending row to Clients tab...");
    clientsSheet.appendRow(newRow);
    Logger.log("Row appended successfully");

    // ════════════════════════════════════════════════════════════════
    // STEP 4: Send confirmation email in Bengali (NO password)
    // ════════════════════════════════════════════════════════════════
    var subject = "LawnHive HRM Software — রেজিস্ট্রেশন সফল হয়েছে";
    var planLabel = interestedPlan || "Free Trial";
    var body =
      "প্রিয় " + contactPerson + ",\n\n" +
      "LawnHive HRM Software-তে আপনার রেজিস্ট্রেশন সফলভাবে গ্রহণ করা হয়েছে।\n\n" +
      "আপনার তথ্য:\n" +
      "  ক্লায়েন্ট আইডি: " + clientId + "\n" +
      "  প্রতিষ্ঠান: " + orgName + "\n" +
      "  প্ল্যান: ফ্রি ট্রায়াল (১৪ দিন)\n" +
      "  প্রত্যাশিত ব্যবহারকারী: " + (expectedUsers || "N/A") + "\n" +
      "  আগ্রহী প্ল্যান: " + planLabel + "\n\n" +
      "আপনি " + planLabel + " প্ল্যানে আগ্রহ দেখিয়েছেন। এখন ১৪ দিনের ফ্রি ট্রায়াল দিয়ে শুরু হবে, ট্রায়াল শেষে পেমেন্ট করলে আপনার পছন্দের প্ল্যানে আপগ্রেড হয়ে যাবে।\n\n" +
      "LawnHive টিম শীঘ্রই আপনার সাথে যোগাযোগ করবে এবং সিস্টেম সেটআপ সম্পন্ন করবে।\n\n" +
      "ধন্যবাদ,\n" +
      "LawnHive HRM Software টিম\n" +
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
