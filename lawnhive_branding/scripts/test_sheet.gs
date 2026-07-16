function testPlanFeatures() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheets = ss.getSheets();
  
  // List all sheet names
  Logger.log("=== All Sheets ===");
  for (var i = 0; i < sheets.length; i++) {
    Logger.log("Sheet " + i + ": '" + sheets[i].getName() + "'");
  }
  
  // Check Plan_Features tab
  var pfSheet = ss.getSheetByName("Plan_Features");
  if (!pfSheet) {
    Logger.log("ERROR: 'Plan_Features' tab NOT found!");
    return;
  }
  
  Logger.log("Found 'Plan_Features' tab!");
  var data = pfSheet.getDataRange().getValues();
  Logger.log("Rows: " + data.length);
  
  for (var j = 0; j < data.length; j++) {
    Logger.log("Row " + j + ": " + JSON.stringify(data[j]));
  }
}
