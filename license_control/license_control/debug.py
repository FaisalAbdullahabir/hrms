import frappe
import json
import importlib


def run():
    """FINAL VERIFICATION — all fixes applied."""
    print("=" * 80)
    print("FINAL SYSTEMIC VERIFICATION — ALL FIXES APPLIED")
    print("=" * 80)

    frappe.clear_cache()

    tasks = importlib.import_module("license_control.tasks")
    MODULE_WORKSPACE_MAP = tasks.MODULE_WORKSPACE_MAP
    ALWAYS_VISIBLE_WORKSPACES = tasks.ALWAYS_VISIBLE_WORKSPACES
    NON_GATED_MODULES = tasks.NON_GATED_MODULES
    FEATURE_GATED_MODULES = tasks.FEATURE_GATED_MODULES
    ALWAYS_ENABLED_MODULES = tasks.ALWAYS_ENABLED_MODULES

    raw = frappe.db.get_single_value("License Status", "enabled_modules")
    enabled = set()
    if raw:
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                enabled = set(parsed)
        except (json.JSONDecodeError, TypeError):
            enabled = set(m.strip() for m in raw.split(",") if m.strip())

    features_raw = frappe.db.get_single_value("License Status", "features")
    features = {}
    if features_raw:
        try:
            features = json.loads(features_raw)
        except (json.JSONDecodeError, TypeError):
            pass

    final_allowed = set()
    for mod in NON_GATED_MODULES:
        if mod in enabled:
            final_allowed.add(mod)
    for mod, feature_key in FEATURE_GATED_MODULES.items():
        if mod in enabled and features.get(feature_key, False):
            final_allowed.add(mod)
    final_allowed.update(ALWAYS_ENABLED_MODULES)

    # Sidebar simulation
    print("\n[SIDEBAR SIMULATION (admin@surovi.com)]:")
    from frappe.desk.desktop import Workspace as WsClass
    frappe.set_user("admin@surovi.com")

    fields = ["name", "title", "for_user", "parent_page", "content",
              "public", "module", "icon", "indicator_color", "is_hidden"]
    filters = {
        "restrict_to_domain": ["in", [None] + list(frappe.get_active_domains())],
        "module": ["not in", ["Dummy Module"]],
    }
    all_pages = frappe.get_all("Workspace", fields=fields, filters=filters,
                               order_by="sequence_id asc", ignore_permissions=True)
    has_access = "Workspace Manager" in frappe.get_roles()
    visible = []
    perm_errors = []

    for page in all_pages:
        try:
            ws = WsClass(page, True)
            permitted = ws.is_permitted()
            v = page.public and (has_access or not page.is_hidden) and page.title != "Welcome Workspace"
            if v and permitted:
                visible.append(page.name)
        except frappe.PermissionError:
            perm_errors.append(page.name)

    print("  Visible ({}): {}".format(len(visible), visible))
    print("  PermissionErrors: {}".format(len(perm_errors)))
    frappe.set_user("Administrator")

    all_ok = len(perm_errors) == 0 and "Education" in visible
    print("\n  FINAL: {}".format("ALL CHECKS PASSED" if all_ok else "ISSUES REMAIN"))


def toggle_test():
    """Test toggling each module on/off."""
    print("=" * 80)
    print("MODULE TOGGLE TEST")
    print("=" * 80)

    tasks = importlib.import_module("license_control.tasks")
    MODULE_WORKSPACE_MAP = tasks.MODULE_WORKSPACE_MAP

    raw = frappe.db.get_single_value("License Status", "enabled_modules")
    original = set()
    if raw:
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                original = set(parsed)
        except (json.JSONDecodeError, TypeError):
            original = set(m.strip() for m in raw.split(",") if m.strip())

    print("Original:", sorted(original))

    # Test 1: Enable ALL
    print("\n[TEST 1] Enable ALL modules...")
    all_mods = sorted(MODULE_WORKSPACE_MAP.keys())
    frappe.db.set_single_value("License Status", "enabled_modules", json.dumps(all_mods))
    frappe.db.commit()
    tasks.apply_feature_restrictions()

    fails = []
    for mod, ws_list in MODULE_WORKSPACE_MAP.items():
        for ws_name in ws_list:
            ws_pub = frappe.db.get_value("Workspace", ws_name, "public")
            if ws_pub != 1:
                fails.append((ws_name, ws_pub))
    if fails:
        for name, pub in fails:
            print("  FAIL: {} pub={}".format(name, pub))
    else:
        print("  ALL VISIBLE — PASS")

    # Test 2: Disable ALL
    print("\n[TEST 2] Disable ALL modules...")
    frappe.db.set_single_value("License Status", "enabled_modules", json.dumps([]))
    frappe.db.commit()
    tasks.apply_feature_restrictions()

    fails2 = []
    for mod, ws_list in MODULE_WORKSPACE_MAP.items():
        for ws_name in ws_list:
            ws_pub = frappe.db.get_value("Workspace", ws_name, "public")
            if ws_pub != 0:
                fails2.append((ws_name, ws_pub))
    if fails2:
        for name, pub in fails2:
            print("  FAIL: {} pub={}".format(name, pub))
    else:
        print("  ALL HIDDEN — PASS")

    # Test 3: Enable HR + Education only
    print("\n[TEST 3] Enable HR + Education only...")
    frappe.db.set_single_value("License Status", "enabled_modules", json.dumps(["HR", "Education"]))
    frappe.db.commit()
    tasks.apply_feature_restrictions()

    fails3 = []
    for mod, ws_list in MODULE_WORKSPACE_MAP.items():
        for ws_name in ws_list:
            ws_pub = frappe.db.get_value("Workspace", ws_name, "public")
            expected = 1 if mod in ("HR", "Education") else 0
            if ws_pub != expected:
                fails3.append((ws_name, ws_pub, expected))
    if fails3:
        for name, pub, exp in fails3:
            print("  FAIL: {} pub={} expected={}".format(name, pub, exp))
    else:
        print("  CORRECT TOGGLE — PASS")

    # Restore
    print("\n[RESTORE] Restoring:", sorted(original))
    frappe.db.set_single_value("License Status", "enabled_modules", json.dumps(sorted(original)))
    frappe.db.commit()
    tasks.apply_feature_restrictions()
    print("  Done.")


def check_scheduler():
    """Check scheduler and error logs."""
    print("\n" + "=" * 80)
    print("SCHEDULER & ERROR LOGS")
    print("=" * 80)

    print("\nRecent license_control error logs:")
    errors = frappe.get_all("Error Log",
        fields=["name", "method", "creation", "error"],
        filters={"method": ["like", "%license_control%"]},
        order_by="creation desc",
        limit_page_length=10,
        ignore_permissions=True
    )
    if errors:
        for e in errors:
            print("  {} | {} | {}".format(
                e.creation, e.method, (e.error or "")[:200]
            ))
    else:
        print("  No error logs")
