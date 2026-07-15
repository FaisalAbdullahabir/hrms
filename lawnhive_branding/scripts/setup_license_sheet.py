"""
Google Sheet Setup Script for License Tracking
Run: python setup_license_sheet.py

Prerequisites:
  1. credentials.json in the same directory
  2. pip install gspread google-auth
"""

import gspread
from google.oauth2.service_account import Credentials
from gspread.utils import ValidationConditionType
from datetime import datetime, timedelta

SHEET_ID = "1efx89SqowNn6C2QVdV1whcACg5vZHO9kqMiG6cAUaUM"
CREDENTIALS_FILE = "credentials.json"

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]


def main():
    creds = Credentials.from_service_account_file(CREDENTIALS_FILE, scopes=SCOPES)
    gc = gspread.authorize(creds)
    sheet = gc.open_by_key(SHEET_ID).sheet1

    # ── Headers ──
    headers = [
        "client_id",
        "client_name",
        "client_type",
        "status",
        "plan",
        "activated_date",
        "expiry_date",
        "last_check_in",
    ]
    sheet.clear()
    sheet.append_row(headers, value_input_option="RAW")

    # ── Test row ──
    today = datetime.now()
    expiry = today + timedelta(days=90)
    test_row = [
        "NGO001",
        "Surovi",
        "ngo",
        "free_trial",
        "free_trial",
        today.strftime("%Y-%m-%d"),
        expiry.strftime("%Y-%m-%d"),
        "",
    ]
    sheet.append_row(test_row, value_input_option="RAW")

    # ── Data validation: client_type column (C) ──
    sheet.add_validation(
        "C2:C1000",
        ValidationConditionType.one_of_list,
        ["ngo", "business"],
        "Pick ngo or business",
    )

    # ── Data validation: status column (D) ──
    sheet.add_validation(
        "D2:D1000",
        ValidationConditionType.one_of_list,
        ["active", "inactive", "free_trial", "expired"],
        "Pick a valid status",
    )

    # ── Format header row: bold + orange background ──
    sheet.format("A1:H1", {
        "textFormat": {"bold": True},
        "backgroundColor": {"red": 0.99, "green": 0.85, "blue": 0.66},
    })

    print("Sheet setup complete!")
    print(f"  Headers: {headers}")
    print(f"  Test row: {test_row}")
    print(f"  Validations: client_type (C), status (D)")
    print(f"  Header styling: bold + orange background")


if __name__ == "__main__":
    main()
