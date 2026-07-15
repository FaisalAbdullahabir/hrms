/**
 * License Check API — Google Apps Script
 * Deploy as Web App: "Anyone" access
 *
 * Usage: ?client_id=NGO001
 * Returns: { client_id, client_name, client_type, status, plan, activated_date, expiry_date, last_check_in }
 *
 * Sheet columns:
 *   A = client_id
 *   B = client_name
 *   C = client_type (ngo / business)
 *   D = status (active / inactive / free_trial / expired)
 *   E = plan
 *   F = activated_date
 *   G = expiry_date
 *   H = last_check_in
 */

function doGet(e) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  var data = sheet.getDataRange().getValues();

  var clientId = (e.parameter.client_id || "").trim();
  if (!clientId) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: "error", message: "client_id required" }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  // Search column A (index 0) for matching client_id
  for (var i = 1; i < data.length; i++) {
    if (String(data[i][0]).trim() === clientId) {
      // Update last_check_in (column H, index 7)
      sheet.getRange(i + 1, 8).setValue(new Date());

      var result = {
        client_id:       String(data[i][0]),
        client_name:     String(data[i][1]),
        client_type:     String(data[i][2]),
        status:          String(data[i][3]),
        plan:            String(data[i][4]),
        activated_date:  String(data[i][5]),
        expiry_date:     String(data[i][6]),
        last_check_in:   new Date().toISOString()
      };

      return ContentService
        .createTextOutput(JSON.stringify(result))
        .setMimeType(ContentService.MimeType.JSON);
    }
  }

  // Not found
  return ContentService
    .createTextOutput(JSON.stringify({ status: "not_found" }))
    .setMimeType(ContentService.MimeType.JSON);
}
