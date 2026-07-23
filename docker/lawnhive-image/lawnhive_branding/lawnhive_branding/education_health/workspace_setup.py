"""
Education Sub-Workspace Setup
Creates 7 sub-workspaces under "Education" (LawnHive Learning):
  Student Management, Academics, Admissions, Assessment,
  Fee Management, Attendance, Health Records
Also cleans up the main Education workspace.
Idempotent — safe to run multiple times.
"""
import frappe
import json
import random
import string


def _id():
    return ''.join(random.choices(string.ascii_letters + string.digits, k=10))


def setup_education_workspaces():
    results = {}
    try:
        results = _create_sub_workspaces()
    except Exception as e:
        results["error"] = str(e)[:500]
        frappe.db.rollback()

    try:
        _clean_main_workspace()
    except Exception as e:
        results["clean_error"] = str(e)[:500]
        frappe.db.rollback()

    print(json.dumps(results, indent=2))
    return results


# ── Sub-workspace definitions ──────────────────────────────────────

SUB_WORKSPACES = {
    "Student Management": {
        "shortcuts": ["Student", "Student Group"],
        "cards": [
            {
                "name": "Student Masters",
                "links": [
                    ("DocType", "Student"),
                    ("DocType", "Student Group"),
                    ("DocType", "Student Category"),
                    ("DocType", "Student Batch Name"),
                ],
            },
            {
                "name": "Enrollment",
                "links": [
                    ("DocType", "Program Enrollment"),
                    ("DocType", "Course Enrollment"),
                ],
            },
            {
                "name": "Other",
                "links": [
                    ("DocType", "Student Log"),
                    ("DocType", "Guardian"),
                ],
            },
        ],
    },
    "Academics": {
        "shortcuts": ["Program", "Course"],
        "cards": [
            {
                "name": "Academic Period",
                "links": [
                    ("DocType", "Academic Year"),
                    ("DocType", "Academic Term"),
                ],
            },
            {
                "name": "Course Structure",
                "links": [
                    ("DocType", "Program"),
                    ("DocType", "Course"),
                    ("DocType", "Topic"),
                ],
            },
            {
                "name": "Scheduling",
                "links": [
                    ("DocType", "Course Schedule"),
                    ("DocType", "Course Activity"),
                ],
            },
        ],
    },
    "Admissions": {
        "shortcuts": ["Student Applicant"],
        "cards": [
            {
                "name": "Admissions",
                "links": [
                    ("DocType", "Student Applicant"),
                    ("DocType", "Student Admission"),
                ],
            },
        ],
    },
    "Assessment": {
        "shortcuts": ["Assessment Plan"],
        "cards": [
            {
                "name": "Assessment",
                "links": [
                    ("DocType", "Assessment Plan"),
                    ("DocType", "Assessment Criteria"),
                    ("DocType", "Assessment Group"),
                    ("DocType", "Assessment Result"),
                    ("DocType", "Grading Scale"),
                ],
            },
            {
                "name": "Assessment Reports",
                "links": [
                    ("Report", "Course wise Assessment Report"),
                    ("Report", "Final Assessment Grades"),
                    ("Report", "Assessment Plan Status"),
                    ("DocType", "Student Report Generation Tool"),
                ],
            },
        ],
    },
    "Fee Management": {
        "shortcuts": ["Fees", "Sales Invoice"],
        "cards": [
            {
                "name": "Fee Masters",
                "links": [
                    ("DocType", "Fees"),
                    ("DocType", "Fee Structure"),
                    ("DocType", "Fee Category"),
                ],
            },
            {
                "name": "Billing",
                "links": [
                    ("DocType", "Sales Invoice"),
                    ("DocType", "Sales Order"),
                ],
            },
            {
                "name": "Fee Reports",
                "links": [
                    ("Report", "Student Fee Collection"),
                    ("Report", "Program wise Fee Collection"),
                ],
            },
        ],
    },
    "Attendance": {
        "shortcuts": ["Student Attendance", "Student Monthly Attendance Sheet"],
        "cards": [
            {
                "name": "Attendance",
                "links": [
                    ("DocType", "Student Attendance"),
                    ("DocType", "Student Leave Application"),
                ],
            },
            {
                "name": "Attendance Reports",
                "links": [
                    ("Report", "Absent Student Report"),
                    ("Report", "Student Monthly Attendance Sheet"),
                    ("Report", "Student Batch-Wise Attendance"),
                ],
            },
        ],
    },
    "Health Records": {
        "shortcuts": ["Student Health Record"],
        "cards": [
            {
                "name": "Health Records",
                "links": [
                    ("DocType", "Student Health Record"),
                ],
            },
            {
                "name": "Health Reports",
                "links": [
                    ("Report", "BMI Growth Report"),
                ],
            },
        ],
    },
}

# Sequence IDs: sub-workspaces get sequence between Education's children
# HR sub-workspaces use seq 3-12; Education starts at 9
# We'll assign: 10, 11, 12, 13, 14, 15, 16
SUB_WS_ORDER = [
    "Student Management",
    "Academics",
    "Admissions",
    "Assessment",
    "Fee Management",
    "Attendance",
    "Health Records",
]


def _create_sub_workspaces():
    results = {}
    for idx, ws_name in enumerate(SUB_WS_ORDER):
        defn = SUB_WORKSPACES[ws_name]
        result = _create_one_workspace(ws_name, defn, 10 + idx)
        results[ws_name] = result
    return results


def _create_one_workspace(ws_name, defn, sequence_id):
    if frappe.db.exists("Workspace", ws_name):
        # Delete existing broken records and recreate
        frappe.db.sql("DELETE FROM `tabWorkspace Shortcut` WHERE parent = %s", (ws_name,))
        frappe.db.sql("DELETE FROM `tabWorkspace Link` WHERE parent = %s", (ws_name,))
        frappe.db.sql("DELETE FROM `tabWorkspace` WHERE name = %s", (ws_name,))
        frappe.db.commit()

    # Build content JSON
    content = []

    # Shortcuts header
    content.append({"id": _id(), "type": "header", "data": {
        "text": '<span class="h4"><b>Your Shortcuts</b></span>', "col": 12
    }})
    for sc in defn["shortcuts"]:
        content.append({"id": _id(), "type": "shortcut", "data": {
            "shortcut_name": sc, "col": 3
        }})

    content.append({"id": _id(), "type": "spacer", "data": {"col": 12}})

    # Masters & Reports header
    content.append({"id": _id(), "type": "header", "data": {
        "text": '<span class="h4"><b>Masters &amp; Reports</b></span>', "col": 12
    }})
    for card in defn["cards"]:
        content.append({"id": _id(), "type": "card", "data": {
            "card_name": card["name"], "col": 4
        }})

    # Create workspace via direct DB insert (avoids permission/controller issues)
    frappe.db.sql("""
        INSERT INTO tabWorkspace
            (name, label, title, module, parent_page, public, is_hidden,
             sequence_id, content, owner, creation, modified_by, modified,
             docstatus, idx, hide_custom)
        VALUES
            (%s, %s, %s, 'Education', 'Education', 1, 0,
             %s, %s, 'Administrator', NOW(), 'Administrator', NOW(),
             0, 0, 0)
    """, (ws_name, ws_name, ws_name, sequence_id, json.dumps(content)))

    # Create shortcuts
    for i, sc_name in enumerate(defn["shortcuts"]):
        sc_id = _id()
        frappe.db.sql("""
            INSERT INTO `tabWorkspace Shortcut`
                (name, type, link_to, label, parent, parentfield, parenttype,
                 owner, creation, modified_by, modified, docstatus, idx)
            VALUES
                (%s, 'DocType', %s, %s, %s, 'shortcuts', 'Workspace',
                 'Administrator', NOW(), 'Administrator', NOW(), 0, %s)
        """, (sc_id, sc_name, sc_name, ws_name, i + 1))

    # Create links (card headers + items)
    link_idx = 0
    for card in defn["cards"]:
        # Card header (section divider — link_type=NULL, link_to=NULL)
        header_id = _id()
        frappe.db.sql("""
            INSERT INTO `tabWorkspace Link`
                (name, type, label, link_type, link_to, hidden, onboard,
                 is_query_report, link_count, parent, parentfield, parenttype,
                 owner, creation, modified_by, modified, docstatus, idx)
            VALUES
                 (%s, 'Card Break', %s, NULL, NULL, 0, 0,
                 0, 0, %s, 'links', 'Workspace',
                 'Administrator', NOW(), 'Administrator', NOW(), 0, %s)
        """, (header_id, card["name"], ws_name, link_idx))
        link_idx += 1

        # Card items
        for link_type, link_to in card["links"]:
            item_id = _id()
            is_report = 1 if link_type == "Report" else 0
            frappe.db.sql("""
                INSERT INTO `tabWorkspace Link`
                    (name, type, label, link_type, link_to, hidden, onboard,
                     is_query_report, link_count, parent, parentfield, parenttype,
                     owner, creation, modified_by, modified, docstatus, idx)
                VALUES
                     (%s, 'Link', %s, %s, %s, 0, 0,
                     %s, 0, %s, 'links', 'Workspace',
                     'Administrator', NOW(), 'Administrator', NOW(), 0, %s)
            """, (item_id, link_to, link_type, link_to,
                  is_report, ws_name, link_idx))
            link_idx += 1

    frappe.db.commit()
    frappe.clear_cache()
    return "created"


def _clean_main_workspace():
    """Remove card groups from main Education workspace that now live in sub-workspaces.
    Keep: Tools, Setup, Settings, Content Masters, Other Reports.
    Also remove duplicate links that moved to sub-workspaces."""
    cards_to_remove = {
        "Student Management", "Academics", "Admissions",
        "Assessment", "Fee Management", "Attendance",
        "Assessment Reports", "Fee Reports", "Attendance Reports",
    }

    ws = frappe.get_doc("Workspace", "Education")
    content = json.loads(ws.content) if ws.content else []

    new_content = []
    for block in content:
        if block.get("type") == "card":
            card_name = block.get("data", {}).get("card_name", "")
            if card_name in cards_to_remove:
                continue
        new_content.append(block)

    if len(new_content) != len(content):
        ws.content = json.dumps(new_content)
        ws.save(ignore_permissions=True)

        # Remove links that belong to removed card groups
        labels_to_remove = set()
        for card_name in cards_to_remove:
            for ws_def in SUB_WORKSPACES.values():
                for card in ws_def["cards"]:
                    if card["name"] == card_name:
                        for _, link_to in card["links"]:
                            labels_to_remove.add(link_to)

        frappe.db.sql("""
            DELETE FROM `tabWorkspace Link`
            WHERE parent = 'Education'
              AND link_to IN %s
              AND link_to IS NOT NULL
        """, (tuple(labels_to_remove),))

        frappe.db.commit()
