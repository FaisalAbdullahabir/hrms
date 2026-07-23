import json

path = "/home/frappe/frappe-bench/apps/education/education/education/doctype/student/student.json"
d = json.load(open(path))

# Find the section/tab where email and mobile are, and check adjacent fields
for i, f in enumerate(d.get("fields", [])):
    if f["fieldname"] in ("student_email_id", "student_mobile_number"):
        # Show surrounding fields for context
        start = max(0, i-1)
        end = min(len(d["fields"]), i+2)
        for j in range(start, end):
            ff = d["fields"][j]
            marker = " <-- CHANGED" if ff["fieldname"] in ("student_email_id", "student_mobile_number") else ""
            print(f"  [{j}] {ff.get('fieldname',''):30s} type={ff.get('fieldtype',''):15s} label={ff.get('label',''):30s} reqd={ff.get('reqd',0)}{marker}")
        print()
