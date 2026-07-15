function _injectLawnhiveBadge() {
    if (document.querySelector('.lawnhive-floating-badge')) return;
    var badge = document.createElement('a');
    badge.className = 'lawnhive-floating-badge';
    badge.href = 'https://lawnhive.com/';
    badge.target = '_blank';
    badge.innerHTML = '<span class="dot"></span>Developed by LawnHive';
    document.body.appendChild(badge);
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', _injectLawnhiveBadge);
} else {
    _injectLawnhiveBadge();
}

if (typeof frappe !== 'undefined' && frappe.after_ajax) {
    frappe.after_ajax(_injectLawnhiveBadge);
}
