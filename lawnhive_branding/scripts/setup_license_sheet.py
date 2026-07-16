"""
Google Sheet Setup Script for License Tracking
Run: python setup_license_sheet.py

Prerequisites:
  1. credentials.json in the same directory
  2. pip install gspread google-auth google-api-python-client
"""

import sys
import gspread
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build
from datetime import datetime, timedelta

SHEET_ID = "1efx89SqowNn6C2QVdV1whcACg5vZHO9kqMiG6cAUaUM"
CREDENTIALS_FILE = "credentials.json"

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]


def _get_or_create_sheet(spreadsheet, name, rows, cols):
    """Get existing sheet or create new one. Returns (sheet, is_new)."""
    existing = [s.title for s in spreadsheet.worksheets()]
    if name in existing:
        return spreadsheet.worksheet(name), False
    else:
        return spreadsheet.add_worksheet(title=name, rows=rows, cols=cols), True


def _format_header(sheet, col_count):
    """Bold + light gray background on row 1."""
    last_col = chr(ord("A") + col_count - 1)
    sheet.format(f"A1:{last_col}1", {
        "textFormat": {"bold": True},
        "backgroundColor": {"red": 0.93, "green": 0.93, "blue": 0.93},
    })


def setup_clients_sheet(gc, sheets_api):
    """Setup the Clients tab (idempotent)."""
    spreadsheet = gc.open_by_key(SHEET_ID)
    sheet, is_new = _get_or_create_sheet(spreadsheet, "Clients", 1000, 11)

    headers = [
        "client_id", "client_name", "client_type", "status",
        "plan", "activated_date", "expiry_date", "last_check_in",
        "contact_email", "login_password", "contact_phone",
    ]

    if is_new:
        sheet.append_row(headers, value_input_option="RAW")
        print(f"  [Clients] Created with headers")
    else:
        existing_values = sheet.get_all_values()
        if not existing_values or existing_values[0] != headers:
            sheet.clear()
            sheet.append_row(headers, value_input_option="RAW")
            print(f"  [Clients] Headers rewritten")
        else:
            print(f"  [Clients] Headers match — keeping data")

    # Add test row only if empty (header only)
    existing_values = sheet.get_all_values()
    if len(existing_values) <= 1:
        today = datetime.now()
        expiry = today + timedelta(days=90)
        test_row = [
            "NGO001", "Surovi", "ngo", "free_trial", "free_trial",
            today.strftime("%Y-%m-%d"), expiry.strftime("%Y-%m-%d"), "",
            "admin@surovi.com", "", "01712345678",
        ]
        sheet.append_row(test_row, value_input_option="RAW")
        print(f"  [Clients] Test row added")

    # ── Step 1: Clear ALL existing data validations on the sheet ──
    sheet_id = sheet.id
    sheets_api.batchUpdate(
        spreadsheetId=SHEET_ID,
        body={"requests": [{
            "updateCells": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": 1000,
                    "startColumnIndex": 0,
                    "endColumnIndex": 11,
                },
                "fields": "dataValidation"
            }
        }]}
    ).execute()
    print(f"  [Clients] Cleared all old validations")

    # ── Step 2: Apply NEW validations on correct ranges only ──
    validations = [
        {
            "startCol": 2,  # C (0-indexed=2)
            "endCol": 3,
            "values": ["ngo", "business", "retail"],
        },
        {
            "startCol": 3,  # D (0-indexed=3)
            "endCol": 4,
            "values": ["active", "inactive", "free_trial"],
        },
        {
            "startCol": 4,  # E (0-indexed=4)
            "endCol": 5,
            "values": ["free_trial", "basic", "premium"],
        },
    ]

    batch = []
    for v in validations:
        batch.append({
            "setDataValidation": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 1,      # row 2 (0-indexed)
                    "endRowIndex": 1000,
                    "startColumnIndex": v["startCol"],
                    "endColumnIndex": v["endCol"],
                },
                "rule": {
                    "condition": {
                        "type": "ONE_OF_LIST",
                        "values": [{"userEnteredValue": val} for val in v["values"]],
                    },
                    "showCustomUi": True,
                    "strict": True,
                },
            }
        })

    sheets_api.batchUpdate(
        spreadsheetId=SHEET_ID,
        body={"requests": batch},
    ).execute()
    print(f"  [Clients] New validations applied (C, D, E only)")

    _format_header(sheet, 11)
    print(f"  [Clients] Header formatted")


def setup_plan_features_hr(gc, sheets_api):
    """Setup Plan_Features_HR tab for NGO/Business clients."""
    spreadsheet = gc.open_by_key(SHEET_ID)
    sheet, is_new = _get_or_create_sheet(spreadsheet, "Plan_Features_HR", 100, 6)

    headers = ["plan", "max_employees", "payroll", "recruitment", "performance", "reports"]
    plan_data = [
        ["free_trial", 10, "FALSE", "FALSE", "FALSE", "FALSE"],
        ["basic",      50, "TRUE",  "FALSE", "FALSE", "FALSE"],
        ["premium",    999999, "TRUE", "TRUE",  "TRUE",  "TRUE"],
    ]

    sheet.clear()
    sheet.append_row(headers, value_input_option="RAW")
    for row in plan_data:
        sheet.append_row(row, value_input_option="RAW")

    _format_header(sheet, len(headers))
    print(f"  [Plan_Features_HR] {len(plan_data)} plans written")


def setup_plan_features_retail(gc, sheets_api):
    """Setup Plan_Features_Retail tab for Retail/Market clients."""
    spreadsheet = gc.open_by_key(SHEET_ID)
    sheet, is_new = _get_or_create_sheet(spreadsheet, "Plan_Features_Retail", 100, 11)

    headers = [
        "plan", "max_warehouses", "max_pos_terminals", "max_products",
        "barcode_scanning", "stock_reports", "batch_serial_tracking",
        "item_variants", "pricing_rules", "multi_currency", "delivery_tracking",
    ]
    plan_data = [
        ["free_trial", 1,   1,   100,   "TRUE",  "FALSE", "FALSE", "FALSE", "FALSE", "FALSE", "FALSE"],
        ["basic",      2,   2,   5000,  "TRUE",  "TRUE",  "FALSE", "FALSE", "FALSE", "FALSE", "FALSE"],
        ["premium",    999, 999, 999999,"TRUE",  "TRUE",  "TRUE",  "TRUE",  "TRUE",  "TRUE",  "TRUE"],
    ]

    sheet.clear()
    sheet.append_row(headers, value_input_option="RAW")
    for row in plan_data:
        sheet.append_row(row, value_input_option="RAW")

    _format_header(sheet, len(headers))
    print(f"  [Plan_Features_Retail] {len(plan_data)} plans written")


def delete_old_plan_features(spreadsheet):
    """Delete old mixed Plan_Features tab if it exists."""
    existing = [s.title for s in spreadsheet.worksheets()]
    if "Plan_Features" in existing:
        old_sheet = spreadsheet.worksheet("Plan_Features")
        spreadsheet.del_worksheet(old_sheet)
        print(f"  [Plan_Features] Old tab deleted")


def main():
    creds = Credentials.from_service_account_file(CREDENTIALS_FILE, scopes=SCOPES)
    gc = gspread.authorize(creds)
    service = build("sheets", "v4", credentials=creds)
    sheets_api = service.spreadsheets()
    spreadsheet = gc.open_by_key(SHEET_ID)

    args = sys.argv[1:]
    run_all = not args

    if run_all or "--clients" in args:
        print("\n=== Setting up Clients tab ===")
        setup_clients_sheet(gc, sheets_api)

    if run_all or "--plan-features-hr" in args:
        print("\n=== Setting up Plan_Features_HR tab ===")
        setup_plan_features_hr(gc, sheets_api)

    if run_all or "--plan-features-retail" in args:
        print("\n=== Setting up Plan_Features_Retail tab ===")
        setup_plan_features_retail(gc, sheets_api)

    if run_all or "--cleanup" in args:
        print("\n=== Cleaning up old tabs ===")
        delete_old_plan_features(spreadsheet)

    print("\nDone!")


if __name__ == "__main__":
    main()
