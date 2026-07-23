"""
Patch: Change Student DocType mandatory flags.
- student_email_id: mandatory -> optional
- student_mobile_number: optional -> mandatory
"""
import json
import os


def execute():
    # 1. Update the JSON file (for Docker image)
    json_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..", "..", "..", "..", "..", "..",
        "apps", "education", "education", "education",
        "doctype", "student", "student.json"
    )
    # Normalize path
    json_path = os.path.normpath(json_path)

    if os.path.exists(json_path):
        with open(json_path) as f:
            data = json.load(f)

        changed = False
        for field in data.get("fields", []):
            if field["fieldname"] == "student_email_id" and field.get("reqd"):
                field["reqd"] = 0
                changed = True
            elif field["fieldname"] == "student_mobile_number" and not field.get("reqd"):
                field["reqd"] = 1
                changed = True

        if changed:
            with open(json_path, "w") as f:
                json.dump(data, f, indent=2)

    # 2. Update tabDocField (the actual runtime source for field meta)
    import frappe
    frappe.db.sql("""
        UPDATE tabDocField
        SET reqd = 0
        WHERE parent = 'Student' AND fieldname = 'student_email_id'
    """)
    frappe.db.sql("""
        UPDATE tabDocField
        SET reqd = 1
        WHERE parent = 'Student' AND fieldname = 'student_mobile_number'
    """)
    frappe.db.commit()
