/**
 * Setup Form Questions — Google Apps Script
 * Programmatically adds all questions to the LawnHive HR Registration Form.
 *
 * Usage:
 *   1. Apps Script Editor → function dropdown → setupFormQuestions → Run
 *   2. clasp push (from scripts/ folder)
 *
 * Idempotent: clears ALL existing items before adding new ones.
 */

var FORM_ID = "1A0e2MwWKJRY0CuRNSI5GTZfpc5nZ1UHVnElGsc1R-uE";

function setupFormQuestions() {
  var form = FormApp.openById(FORM_ID);

  // ════════════════════════════════════════════════════════════════
  // STEP 1: Delete ALL existing items one by one from index 0
  // ════════════════════════════════════════════════════════════════
  var deletedCount = 0;
  while (form.getItems().length > 0) {
    form.deleteItem(0);
    deletedCount++;
  }

  // ════════════════════════════════════════════════════════════════
  // STEP 2: Set form title
  // ════════════════════════════════════════════════════════════════
  form.setTitle("LawnHive HR - Client Registration");

  // ════════════════════════════════════════════════════════════════
  // STEP 3: Add 6 new questions
  // ════════════════════════════════════════════════════════════════

  // Q1: Organization Name
  var q1 = form.addTextItem();
  q1.setTitle("Organization Name");
  q1.setHelpText("আপনার প্রতিষ্ঠানের পূর্ণ নাম লিখুন");
  q1.setRequired(true);

  // Q2: Contact Person Name
  var q2 = form.addTextItem();
  q2.setTitle("Contact Person Name");
  q2.setHelpText("যিনি যোগাযোগের জন্য দায়িত্বশীল");
  q2.setRequired(true);

  // Q3: Email
  var q3 = form.addTextItem();
  q3.setTitle("Email");
  q3.setHelpText("যোগাযোগের ইমেইল ঠিকানা");
  q3.setRequired(true);
  var emailValidation = FormApp.createTextValidation()
    .requireTextIsEmail()
    .build();
  q3.setValidation(emailValidation);

  // Q4: Phone Number
  var q4 = form.addTextItem();
  q4.setTitle("Phone Number");
  q4.setHelpText("01XXXXXXXXX ফরম্যাটে লিখুন");
  q4.setRequired(true);

  // Q5: Organization Type
  var q5 = form.addMultipleChoiceItem();
  q5.setTitle("Organization Type");
  q5.setHelpText("আপনার প্রতিষ্ঠানের ধরন সিলেক্ট করুন");
  q5.setChoiceValues(["NGO", "Business", "Retail/Market"]);
  q5.setRequired(true);

  // Q6: Expected Number of Users
  var q6 = form.addTextItem();
  q6.setTitle("Expected Number of Users");
  q6.setHelpText("কতজন ব্যবহারকারী সিস্টেম ব্যবহার করবে (শুধু সংখ্যা)");
  q6.setRequired(true);
  var numberValidation = FormApp.createTextValidation()
    .requireNumberBetween(1, 999999)
    .setHelpText("শুধু পূর্ণ সংখ্যা লিখুন (1 - 999999)")
    .build();
  q6.setValidation(numberValidation);

  // ════════════════════════════════════════════════════════════════
  // Q7: Interested Plan — Multiple choice, Required
  // ════════════════════════════════════════════════════════════════
  var q7 = form.addMultipleChoiceItem();
  q7.setTitle("Interested Plan");
  q7.setHelpText("আপনি কোন প্ল্যানে আগ্রহী? (বর্তমানে সবার জন্য ১৪ দিনের ফ্রি ট্রায়াল আছে)");
  q7.setChoiceValues(["Free Trial (14 days)", "Basic", "Premium"]);
  q7.setRequired(true);

  Logger.log("Deleted " + deletedCount + " old items, added 7 new questions");
}
