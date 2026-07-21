"""
Add missing is_billing_contact column to Contact table.

This column was missing from the Contact DocType schema, causing
Sales Invoice creation to fail with:
  Unknown column 'tabContact.is_billing_contact' in 'WHERE'

Fixed in: v1.0.1
"""

import frappe


def execute():
    # Check if column already exists
    columns = frappe.db.sql(
        "SHOW COLUMNS FROM tabContact LIKE 'is_billing_contact'",
        as_dict=True,
    )

    if not columns:
        frappe.db.sql(
            "ALTER TABLE tabContact ADD COLUMN is_billing_contact int(1) default 0"
        )
        frappe.db.commit()
        frappe.logger().info("Added is_billing_contact column to tabContact")
    else:
        frappe.logger().info("is_billing_contact column already exists in tabContact")
