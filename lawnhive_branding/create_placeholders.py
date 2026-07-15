import base64, os

# Minimal valid 1x1 transparent PNG
PNG_1x1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)

out_dir = os.path.join(os.path.dirname(__file__), "lawnhive_branding", "public", "images")
os.makedirs(out_dir, exist_ok=True)

for fname in ("logo.png", "favicon.png"):
    path = os.path.join(out_dir, fname)
    with open(path, "wb") as f:
        f.write(PNG_1x1)
    print(f"Created: {path}")
