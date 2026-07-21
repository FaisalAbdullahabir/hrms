"""
Rebrand container apps after container rebuild.
Run from host: docker cp rebrand_container_apps.py <container>:/tmp/ && docker exec <container> python3 /tmp/rebrand_container_apps.py
"""
import subprocess
import sys

CONTAINER = "docker-frappe-1"
LOCAL_FILES = {
    "erpnext": "/home/frappe/frappe-bench/apps/erpnext/erpnext/hooks.py",
    "hrms": "/home/frappe/frappe-bench/apps/hrms/hrms/hooks.py",
}
LOCAL_PATHS = {
    "erpnext": "D:/Github/hrms/erpnext/erpnext/hooks.py",
    "hrms": "D:/Github/hrms/hrms/hooks.py",
}
CONTAINER_EDITS = {
    "education": {
        "path": "/home/frappe/frappe-bench/apps/education/education/hooks.py",
        "replacements": [
            ('app_title = "Education"', 'app_title = "LawnHive Learning"'),
            ('"title": "Education"', '"title": "LawnHive Learning"'),
        ],
    },
    "drive": {
        "path": "/home/frappe/frappe-bench/apps/drive/drive/hooks.py",
        "replacements": [
            ('app_title = "Frappe Drive"', 'app_title = "LawnHive Files"'),
            ('"title": "Drive"', '"title": "LawnHive Files"'),
        ],
    },
}


def docker_cp(local, container, remote):
    subprocess.run(["docker", "cp", local, f"{container}:{remote}"], check=True)


def container_sed(container, remote_path, replacements):
    for old, new in replacements:
        cmd = f"sed -i 's|{old}|{new}|g' {remote_path}"
        subprocess.run(["docker", "exec", container, "bash", "-c", cmd], check=True)


print("=== Rebranding container apps ===")

# 1. Copy local files to container
for app, remote_path in LOCAL_FILES.items():
    local_path = LOCAL_PATHS[app]
    print(f"Copying {app} hooks.py...")
    docker_cp(local_path, CONTAINER, remote_path)

# 2. Edit container-only apps
for app, info in CONTAINER_EDITS.items():
    print(f"Editing {app} hooks.py in container...")
    container_sed(CONTAINER, info["path"], info["replacements"])

# 3. Verify
print("\n=== Verification ===")
result = subprocess.run(
    ["docker", "exec", CONTAINER, "grep", "app_title",
     "/home/frappe/frappe-bench/apps/erpnext/erpnext/hooks.py",
     "/home/frappe/frappe-bench/apps/hrms/hrms/hooks.py",
     "/home/frappe/frappe-bench/apps/education/education/hooks.py",
     "/home/frappe/frappe-bench/apps/drive/drive/hooks.py"],
    capture_output=True, text=True
)
print(result.stdout)

print("=== Done. Now run: ===")
print("  docker exec {c} bench build".format(c=CONTAINER))
print("  docker exec {c} bench --site site1.local clear-cache".format(c=CONTAINER))
