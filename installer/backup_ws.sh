mysqldump -u root -pfrappe _b533f5fdd65aaf8c "tabWorkspace" > /tmp/ws_workspace.sql 2>/dev/null
mysqldump -u root -pfrappe _b533f5fdd65aaf8c "tabWorkspace Shortcut" > /tmp/ws_shortcuts.sql 2>/dev/null
mysqldump -u root -pfrappe _b533f5fdd65aaf8c "tabWorkspace Link" > /tmp/ws_links.sql 2>/dev/null
echo "Done. Line counts:"
wc -l /tmp/ws_workspace.sql /tmp/ws_shortcuts.sql /tmp/ws_links.sql
