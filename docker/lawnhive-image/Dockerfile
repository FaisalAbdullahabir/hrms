###############################################################################
# LawnHive Workspace - Custom Frappe Image
# Base: Frappe/ERPNext v15 (Debian Bookworm)
# Apps: Frappe 15, ERPNext 15, HRMS 15, Education, Drive
#       + LawnHive Branding + License Control
###############################################################################

FROM frappe/erpnext:version-15 AS base

# ── System dependencies ───────────────────────────────────────────────
USER root
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends cron \
    && rm -rf /var/lib/apt/lists/*

# ── Install Python packages for custom apps ──────────────────────────
USER frappe
WORKDIR /home/frappe/frappe-bench

# ── Ensure common_site_config.json exists (Drive frontend needs socketio_port) ──
RUN echo '{"socketio_port": 9000}' > /home/frappe/frappe-bench/sites/common_site_config.json

# ── Step 1: Get apps from GitHub ─────────────────────────────────────
RUN bench get-app hrms --branch version-15
RUN bench get-app education
RUN bench get-app drive

# ── Step 2: COPY custom local apps ──────────────────────────────────
USER root
COPY --chown=frappe:frappe lawnhive_branding /home/frappe/frappe-bench/apps/lawnhive_branding
COPY --chown=frappe:frappe license_control  /home/frappe/frappe-bench/apps/license_control

# ── Step 3: pip install all custom apps in editable mode ─────────────
USER frappe
RUN /home/frappe/frappe-bench/env/bin/pip install \
    -e /home/frappe/frappe-bench/apps/hrms \
    -e /home/frappe/frappe-bench/apps/education \
    -e /home/frappe/frappe-bench/apps/drive \
    -e /home/frappe/frappe-bench/apps/lawnhive_branding \
    -e /home/frappe/frappe-bench/apps/license_control \
    --no-deps 2>/dev/null || true

# ── Step 4: Rebrand erpnext & hrms hooks.py ─────────────────────────
USER root
RUN sed -i 's/^app_title = "ERPNext"/app_title = "LawnHive Next"/' \
        /home/frappe/frappe-bench/apps/erpnext/erpnext/hooks.py \
    && sed -i 's/^app_title = "Frappe HR"/app_title = "LawnHive Workspace"/' \
        /home/frappe/frappe-bench/apps/hrms/hrms/hooks.py \
    && sed -i 's/^app_title = "Education"/app_title = "LawnHive Learning"/' \
        /home/frappe/frappe-bench/apps/education/education/hooks.py \
    && sed -i 's/^app_title = "Drive"/app_title = "LawnHive Files"/' \
        /home/frappe/frappe-bench/apps/drive/drive/hooks.py

# ── Step 4b: Patch Student DocType mandatory flags ───────────────────
RUN python3 -c "import json; p='/home/frappe/frappe-bench/apps/education/education/education/doctype/student/student.json'; d=json.load(open(p)); [f.update({'reqd':0}) if f.get('fieldname')=='student_email_id' else f.update({'reqd':1}) if f.get('fieldname')=='student_mobile_number' else None for f in d.get('fields',[])]; json.dump(d,open(p,'w'),indent=2)"

# ── Step 5: Write apps.txt ──────────────────────────────────────────
RUN echo "frappe"      >  /home/frappe/frappe-bench/sites/apps.txt \
    && echo "erpnext"      >> /home/frappe/frappe-bench/sites/apps.txt \
    && echo "hrms"         >> /home/frappe/frappe-bench/sites/apps.txt \
    && echo "lawnhive_branding" >> /home/frappe/frappe-bench/sites/apps.txt \
    && echo "license_control"  >> /home/frappe/frappe-bench/sites/apps.txt \
    && echo "education"    >> /home/frappe/frappe-bench/sites/apps.txt \
    && echo "drive"        >> /home/frappe/frappe-bench/sites/apps.txt

# ── Step 6: Build assets (so first boot is fast) ────────────────────
USER frappe
RUN cd /home/frappe/frappe-bench && bench build 2>&1 || true

# ── Step 7: Install cron + backup scripts ────────────────────────
USER root
COPY --chown=root:root cron-backup /etc/cron.d/lawnhive-backup
RUN chmod 0644 /etc/cron.d/lawnhive-backup
COPY --chown=frappe:frappe backup.sh /home/frappe/backup.sh
RUN chmod +x /home/frappe/backup.sh

# ── Step 8: Copy startup script (no hardcoded secrets!) ─────────────
COPY --chown=frappe:frappe start.sh /home/frappe/start.sh
RUN chmod +x /home/frappe/start.sh

# ── Step 9: Fix ownership (only apps.txt — apps already frappe-owned) ──
USER root
RUN chown frappe:frappe /home/frappe/frappe-bench/sites/apps.txt

# ── Expose ports ─────────────────────────────────────────────────────
EXPOSE 8000 9000

# ── Health check ─────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/login')" || exit 1

# ── Start (as root — start.sh drops to frappe for bench serve) ────
USER root
CMD ["/home/frappe/start.sh"]
