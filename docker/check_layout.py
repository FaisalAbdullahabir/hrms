import frappe
import os
os.chdir("/home/frappe/frappe-bench/sites")
frappe.connect("site1.local")

# Check what the actual desk layout structure looks like
# Look for sidebar-related CSS in core Frappe
import subprocess

# Find the sidebar layout CSS in the frappe assets
result = subprocess.run(
    ["find", "/home/frappe/frappe-bench/apps/frappe/frappe/public", "-name", "*.css", "-exec", "grep", "-l", "desk-sidebar\\|layout-side-section", "{}", ";"],
    capture_output=True, text=True, timeout=10
)
print("=== Frappe CSS files with sidebar layout ===")
print(result.stdout[:2000])

# Also check for the parent wrapper
result2 = subprocess.run(
    ["grep", "-rn", "layout-side-section\\|side-section\\|sidebar-wrapper", "/home/frappe/frappe-bench/apps/frappe/frappe/public/scss/"],
    capture_output=True, text=True, timeout=10
)
print("\n=== SCSS sidebar references ===")
print(result2.stdout[:3000])

frappe.destroy()
