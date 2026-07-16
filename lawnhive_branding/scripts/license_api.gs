/**
 * License Check API — Google Apps Script
 * Deploy as Web App: "Anyone" access
 *
 * GET  ?client_id=NGO001        → returns license data + features
 * POST { client_id, status }    → updates status in Clients tab
 *
 * Sheet tabs:
 *   "Clients"              — A=client_id, B=client_name, C=client_type, D=status, E=plan, F=activated_date, G=expiry_date, H=last_check_in, I=contact_email, J=login_password, K=contact_phone, L=interested_plan, M=enabled_modules
 *   "Plan_Features_HR"     — A=plan, B=max_employees, C=payroll, D=recruitment, E=performance, F=reports
 *   "Plan_Features_Retail" — A=plan, B=max_warehouses, C=max_pos_terminals, D=max_products, E=barcode_scanning, F=stock_reports, G=batch_serial_tracking, H=item_variants, I=pricing_rules, J=multi_currency, K=delivery_tracking
 */

function doGet(e) {
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
      found = {
        client_id:       String(data[i][0]),
        client_name:     String(data[i][1]),
        client_type:     String(data[i][2]),
        status:          String(data[i][3]),
        plan:            String(data[i][4]),
        activated_date:  String(data[i][5]),
        expiry_date:     String(data[i][6]),
        last_check_in:   new Date().toISOString(),
        enabled_modules: String(data[i][12] || "").trim()
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
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var clientsSheet = ss.getSheetByName("Clients");
  if (!clientsSheet) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "Clients tab not found" }))
      .setMimeType(ContentService.MimeType.JSON);
  }
  var body = JSON.parse(e.postData.contents);
  var clientId = (body.client_id || "").trim();
  var newStatus = (body.status || "").trim();
  if (!clientId || !newStatus) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "client_id and status required" }))
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
