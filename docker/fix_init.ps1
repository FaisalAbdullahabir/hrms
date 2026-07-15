$content = @"
#!/bin/bash
set -e

export PATH="`${NVM_DIR}/versions/node/v`${NODE_VERSION_DEVELOP}/bin/:`${PATH}"

if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
    echo "Bench already exists, skipping init"
    cd /home/frappe/frappe-bench
    bench start
    exit 0
fi

echo "Creating new bench..."
cd /home/frappe

bench init --skip-redis-config-generation frappe-bench

cd /home/frappe/frappe-bench

bench set-mariadb-host mariadb
bench set-redis-cache-host redis://redis:6379
bench set-redis-queue-host redis://redis:6379
bench set-redis-socketio-host redis://redis:6379

sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile

bench get-app erpnext
bench get-app hrms

bench new-site hrms.localhost --force --mariadb-root-password 123 --admin-password admin --no-mariadb-socket

bench --site hrms.localhost install-app erpnext
bench --site hrms.localhost install-app hrms
bench --site hrms.localhost set-config developer_mode 1
bench --site hrms.localhost enable-scheduler
bench --site hrms.localhost clear-cache
bench use hrms.localhost

bench start
"@

[System.IO.File]::WriteAllText("d:\Github\hrms\docker\init.sh", $content, [System.Text.UTF8Encoding]::new($false))

$bytes = [System.IO.File]::ReadAllBytes("d:\Github\hrms\docker\init.sh")
"First 3 bytes: $($bytes[0]) $($bytes[1]) $($bytes[2])"
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
if ($text -match "`r") { "CRLF: PROBLEM!" } else { "CRLF: Clean OK" }
Write-Host "Done!"
