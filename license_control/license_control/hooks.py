app_name = "license_control"
app_title = "License Control"
app_description = "License tracking and module visibility control for LawnHive HR"
app_publisher = "LawnHive"
app_email = "info@lawnhive.com"
app_license = "MIT"

# ── Scheduler: hourly license check ──
scheduler_events = {
    "hourly": [
        "license_control.tasks.check_license",
    ],
}

# ── Install hooks ──
after_install = "license_control.setup.after_install"
