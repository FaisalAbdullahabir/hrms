var MODULE_OPTIONS = [
  "HR", "Payroll", "Accounting", "Manufacturing", "Stock", "Selling",
  "Buying", "Quality", "CRM", "Assets", "Projects", "Support",
  "Website", "Tools", "Education", "Drive"
];

function _getApiKey() {
  return PropertiesService.getScriptProperties().getProperty("api_key") || "";
}

function _validateApiKey(e) {
  var stored = _getApiKey();
  if (!stored) return false;
  var key = "";
  if (e.parameter && e.parameter.api_key) key = e.parameter.api_key;
  if (e.postData && e.postData.headers) {
    key = key || e.postData.headers["X-API-Key"] || "";
  }
  return key === stored;
}

function doGet(e) {
  if (!_validateApiKey(e)) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "Unauthorized" }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var clientsSheet = ss.getSheetByName("Clients");
  if (!clientsSheet) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "Clients tab not found" }))
      .setMimeType(ContentService.MimeType.JSON);
  }
  var data = clientsSheet.getDataRange().getValues();
  var clientId = (e.parameter.client_id || "").trim();
  if (!clientId) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "client_id required" }))
      .setMimeType(ContentService.MimeType.JSON);
  }
  var found = null;
  for (var i = 1; i < data.length; i++) {
    if (String(data[i][0]).trim() === clientId) {
      clientsSheet.getRange(i + 1, 8).setValue(new Date());

      var enabledModules = [];
      for (var m = 0; m < MODULE_OPTIONS.length; m++) {
        var cellVal = data[i][12 + m];
        if (cellVal === true || String(cellVal).trim() === "TRUE") {
          enabledModules.push(MODULE_OPTIONS[m]);
        }
      }

      found = {
        client_id:       String(data[i][0]),
        client_name:     String(data[i][1]),
        client_type:     String(data[i][2]),
        status:          String(data[i][3]),
        plan:            String(data[i][4]),
        activated_date:  String(data[i][5]),
        expiry_date:     String(data[i][6]),
        last_check_in:   new Date().toISOString(),
        contact_email:   String(data[i][8] || "").trim(),
        enabled_modules: enabledModules.join(", ")
      };
      break;
    }
  }
  if (!found) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "not_found" }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  var features = {};
  var tabName = (found.client_type === "retail") ? "Plan_Features_Retail" : "Plan_Features_HR";
  var pfSheet = ss.getSheetByName(tabName);
  if (pfSheet) {
    var pfData = pfSheet.getDataRange().getValues();
    for (var j = 1; j < pfData.length; j++) {
      if (String(pfData[j][0]).trim() === found.plan) {
        if (tabName === "Plan_Features_HR") {
          features = {
            max_employees: parseInt(pfData[j][1]) || 0,
            payroll:       String(pfData[j][2]).trim().toLowerCase() === "true",
            recruitment:   String(pfData[j][3]).trim().toLowerCase() === "true",
            performance:   String(pfData[j][4]).trim().toLowerCase() === "true",
            reports:       String(pfData[j][5]).trim().toLowerCase() === "true"
          };
        } else {
          features = {
            max_warehouses:         parseInt(pfData[j][1]) || 0,
            max_pos_terminals:      parseInt(pfData[j][2]) || 0,
            max_products:           parseInt(pfData[j][3]) || 0,
            barcode_scanning:       String(pfData[j][4]).trim().toLowerCase() === "true",
            stock_reports:          String(pfData[j][5]).trim().toLowerCase() === "true",
            batch_serial_tracking:  String(pfData[j][6]).trim().toLowerCase() === "true",
            item_variants:          String(pfData[j][7]).trim().toLowerCase() === "true",
            pricing_rules:          String(pfData[j][8]).trim().toLowerCase() === "true",
            multi_currency:         String(pfData[j][9]).trim().toLowerCase() === "true",
            delivery_tracking:      String(pfData[j][10]).trim().toLowerCase() === "true"
          };
        }
        break;
      }
    }
  }
  found.features = features;
  return ContentService
    .createTextOutput(JSON.stringify(found))
    .setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  if (!_validateApiKey(e)) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "Unauthorized" }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var body = JSON.parse(e.postData.contents);

  if (body.action === "update_module_list") {
    return handleUpdateModuleList(ss, body);
  }

  var clientsSheet = ss.getSheetByName("Clients");
  if (!clientsSheet) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "Clients tab not found" }))
      .setMimeType(ContentService.MimeType.JSON);
  }
  var clientId = (body.client_id || "").trim();
  var newStatus = (body.status || "").trim();
  if (!clientId || !newStatus) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "client_id and status required" }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  var VALID_STATUSES = ["active", "inactive", "free_trial", "pending_setup"];
  if (VALID_STATUSES.indexOf(newStatus) === -1) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "Invalid status value" }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  var data = clientsSheet.getDataRange().getValues();
  for (var i = 1; i < data.length; i++) {
    if (String(data[i][0]).trim() === clientId) {
      clientsSheet.getRange(i + 1, 4).setValue(newStatus);
      if (body.activated_date) {
        clientsSheet.getRange(i + 1, 6).setValue(body.activated_date);
      }
      if (body.expiry_date) {
        clientsSheet.getRange(i + 1, 7).setValue(body.expiry_date);
      }
      return ContentService
        .createTextOutput(JSON.stringify({ status: "updated", client_id: clientId, new_status: newStatus }))
        .setMimeType(ContentService.MimeType.JSON);
    }
  }
  return ContentService
    .createTextOutput(JSON.stringify({ status: "not_found" }))
    .setMimeType(ContentService.MimeType.JSON);
}

function handleUpdateModuleList(ss, body) {
  var modules = body.modules || MODULE_OPTIONS;
  if (modules.length === 0) {
    modules = MODULE_OPTIONS;
  }

  var refSheet = ss.getSheetByName("Available_Modules");
  if (refSheet) {
    refSheet.clear();
  } else {
    refSheet = ss.insertSheet("Available_Modules");
  }
  refSheet.getRange(1, 1).setValue("Module Name");
  refSheet.getRange(1, 1).setFontWeight("bold");
  for (var i = 0; i < modules.length; i++) {
    refSheet.getRange(i + 2, 1).setValue(modules[i]);
  }
  refSheet.setColumnWidth(1, 200);

  return ContentService
    .createTextOutput(JSON.stringify({
      status: "updated",
      modules_count: modules.length,
      modules: modules,
      reference_tab: "Available_Modules"
    }))
    .setMimeType(ContentService.MimeType.JSON);
}
