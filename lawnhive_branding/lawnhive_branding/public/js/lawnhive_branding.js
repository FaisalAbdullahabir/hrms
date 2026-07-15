/*
 * LawnHive Branding — Client-side Overrides
 * Targeted: only replaces known selectors, does NOT walk the entire DOM.
 * Does NOT modify any core files.
 */

frappe.ready(function () {
    _override_boot_data();
    _replace_document_title();
    _override_about_dialog();
    _fix_help_links();
    _fix_powered_by();
    _replace_erpnext_text();
    _hide_notification_empty();

    frappe.router.on('change', function () {
        setTimeout(function () {
            _replace_document_title();
            _fix_powered_by();
            _replace_erpnext_text();
        }, 500);
    });

    var observer = new MutationObserver(function (mutations) {
        for (var i = 0; i < mutations.length; i++) {
            var t = mutations[i].target;
            if (!t.classList) continue;
            if (t.classList.contains('modal-body') ||
                t.classList.contains('dropdown-menu') ||
                t.classList.contains('page-head') ||
                t.classList.contains('page-title') ||
                t.classList.contains('desk-sidebar') ||
                t.classList.contains('standard-sidebar-section') ||
                t.classList.contains('nested-container')) {
                _fix_help_links();
                _fix_powered_by();
                _replace_erpnext_text();
                break;
            }
        }
    });
    observer.observe(document.body, { childList: true, subtree: true });
});

/**
 * Override frappe.boot.apps_data — replace ERPNext/Frappe HR with LawnHive
 */
function _override_boot_data() {
    if (!frappe.boot || !frappe.boot.apps_data || !frappe.boot.apps_data.apps) return;
    frappe.boot.apps_data.apps.forEach(function (app) {
        if (app.title === 'ERPNext' || app.name === 'erpnext') {
            app.title = 'LawnHive HR';
            app.logo = '/assets/lawnhive_branding/images/logo.png';
        }
        if (app.title === 'Frappe HR' || app.name === 'hrms') {
            app.title = 'LawnHive HR';
            app.logo = '/assets/lawnhive_branding/images/logo.png';
        }
    });
}

/**
 * Replace "ERPNext" / "Frappe" in document title only
 */
function _replace_document_title() {
    var title = document.title || '';
    if (title.indexOf('ERPNext') !== -1 || title.indexOf('Frappe') !== -1) {
        document.title = title
            .replace(/ERPNext/g, 'LawnHive HR')
            .replace(/Frappe Framework/g, 'LawnHive HR')
            .replace(/Frappe/g, 'LawnHive HR');
    }
}

/**
 * Replace "Powered by ERPNext" in footer
 */
function _fix_powered_by() {
    var selectors = ['.footer-logo-extension', '.footer-powered', '.app-footer .text-muted', '.app-footer span'];
    selectors.forEach(function (sel) {
        document.querySelectorAll(sel).forEach(function (el) {
            var text = el.textContent || '';
            if (text.indexOf('ERPNext') !== -1 || text.indexOf('Frappe') !== -1) {
                el.innerHTML = '<span style="color:#f59f36;font-weight:600;">Powered by LawnHive</span>';
            }
        });
    });
}

/**
 * Override Help dropdown links
 */
function _fix_help_links() {
    var helpMenu = document.querySelector('.navbar .dropdown:last-child .dropdown-menu');
    if (!helpMenu) return;
    helpMenu.querySelectorAll('a').forEach(function (a) {
        var href = a.getAttribute('href') || '';
        var text = (a.textContent || '').trim().toLowerCase();
        if (href.indexOf('discuss.frappe.io') !== -1 || href.indexOf('discuss.erpnext') !== -1 ||
            text.indexOf('frappe support') !== -1 || text.indexOf('erpnext support') !== -1 || text === 'discuss') {
            a.setAttribute('href', 'https://lawnhive.com/support');
            a.setAttribute('target', '_blank');
            a.textContent = 'LawnHive Support';
        }
        if (href.indexOf('github.com/frappe') !== -1) {
            a.setAttribute('href', 'https://lawnhive.com');
            a.setAttribute('target', '_blank');
            a.textContent = 'LawnHive';
        }
        if (href.indexOf('docs.erpnext.com') !== -1 || href.indexOf('frappe.io') !== -1) {
            a.setAttribute('href', 'https://lawnhive.com/docs');
            a.setAttribute('target', '_blank');
            a.textContent = 'LawnHive Docs';
        }
    });
}

/**
 * Override About dialog
 */
function _override_about_dialog() {
    if (typeof frappe.ui === 'undefined' || !frappe.ui.toolbar || !frappe.ui.toolbar.about) return;
    frappe.ui.toolbar.about = function () {
        frappe.call({
            method: 'lawnhive_branding.utils.get_about_info',
            callback: function (r) {
                if (r && r.message) {
                    new frappe.ui.Dialog({
                        title: __('About LawnHive HR'),
                        indicator: 'orange',
                        size: 'small',
                        static: true,
                        body:
                            '<div style="text-align:center;padding:20px;">' +
                            '<h3 style="color:#f59f36;margin-bottom:5px;">LawnHive HR</h3>' +
                            '<p style="color:#666;margin-bottom:15px;">Version: ' + (r.message.version || '1.0.0') + '</p>' +
                            '<p style="margin-bottom:5px;"><strong>Publisher:</strong> LawnHive</p>' +
                            '<p style="margin-bottom:5px;"><strong>Website:</strong> <a href="https://lawnhive.com/" target="_blank" style="color:#f59f36;">lawnhive.com</a></p>' +
                            '<hr>' +
                            '<p style="color:#999;font-size:12px;">HR & Payroll Management System</p>' +
                            '</div>',
                    }).show();
                }
            },
        });
    };
}

/**
 * Step 5: Targeted ERPNext text replacement in known selectors only.
 * Does NOT walk every DOM node.
 */
function _replace_erpnext_text() {
    var selectors = [
        '.page-title',
        '.page-head .title-area',
        '.modal-title',
        '.sidebar-item-label',
        '.dropdown-item',
        '.list-subject',
        '.form-title',
        '.panel-heading',
        '.frappe-control .label-area',
        '.app-logo',
        '.app-switcher-label',
        '.desk-sidebar .standard-sidebar-label',
        '.desk-sidebar .sidebar-item-label',
        '.desk-sidebar .section-title',
        '.desk-sidebar [data-title]',
        '.standard-sidebar-item .ellipsis',
        '.sidebar-item-container .ellipsis',
    ];
    selectors.forEach(function (sel) {
        document.querySelectorAll(sel).forEach(function (el) {
            var text = el.textContent || '';
            if (text.indexOf('ERPNext') === -1 && text.indexOf('Frappe') === -1) return;
            el.textContent = text
                .replace(/ERPNext Settings/g, 'Settings')
                .replace(/ERPNext Integrations/g, 'Integrations')
                .replace(/ERPNext/g, 'LawnHive HR')
                .replace(/Frappe HR/g, 'LawnHive HR')
                .replace(/Frappe Framework/g, 'LawnHive HR')
                .replace(/Frappe/g, 'LawnHive HR');
        });
    });

    /* Dynamic year in footer copyright */
    document.querySelectorAll('.app-footer, .footer-copyright, .footer-powered').forEach(function (el) {
        var text = el.textContent || '';
        if (text.indexOf('LawnHive') !== -1 && text.indexOf('20') === -1) {
            var year = new Date().getFullYear();
            el.innerHTML = el.innerHTML.replace(
                /LawnHive/,
                '<span style="color:#f59f36;">' + year + ' LawnHive</span>'
            );
        }
    });
}

/**
 * Step 9: Hide notification bell empty state if it shows broken UI
 */
function _hide_notification_empty() {
    var observer = new MutationObserver(function () {
        document.querySelectorAll('.notification-actions, .notification-panel').forEach(function (panel) {
            if (panel.textContent.trim() === '' && panel.children.length === 0) {
                panel.style.display = 'none';
            }
        });
    });
    observer.observe(document.body, { childList: true, subtree: true });
}
