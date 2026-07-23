import json

path = "/home/frappe/frappe-bench/apps/education/education/education/doctype/student/student.json"
d = json.load(open(path))

changes = []
for f in d.get("fields", []):
    if f["fieldname"] == "student_email_id":
        old_reqd = f.get("reqd", 0)
        f["reqd"] = 0
        changes.append(f"student_email_id: {old_reqd} -> 0 (optional)")
    elif f["fieldname"] == "student_mobile_number":
        old_reqd = f.get("reqd", 0)
        f["reqd"] = 1
        changes.append(f"student_mobile_number: {old_reqd} -> 1 (mandatory)")

if changes:
    with open(path, "w") as fp:
        json.dump(d, fp, indent=2)
    for c in changes:
        print(f"  Changed: {c}")
else:
    print("No changes needed")

# Verify
d2 = json.load(open(path))
for f in d2.get("fields", []):
    if f["fieldname"] in ("student_email_id", "student_mobile_number"):
        print(f"  VERIFY: {f['fieldname']} reqd={f.get('reqd', 0)}")
