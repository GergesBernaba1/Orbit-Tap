from pathlib import Path

strings_file = Path('android/app/src/main/res/values/strings.xml')
strings_file.parent.mkdir(parents=True, exist_ok=True)
strings_file.write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources>\n'
    '    <string name="app_name">Orbit Tap</string>\n'
    '</resources>\n',
    encoding='utf-8',
)

manifest_file = Path('android/app/src/main/AndroidManifest.xml')
content = manifest_file.read_text(encoding='utf-8')

permission_line = (
    '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" '
    'android:maxSdkVersion="29" />'
)
manifest_open = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
if permission_line not in content and manifest_open in content:
    content = content.replace(
        manifest_open,
        f'{manifest_open}\n{permission_line}',
        1,
    )

for original in ('orbit_tap', 'hidenfiles', 'Hidden Files'):
    content = content.replace(
        f'android:label="{original}"',
        'android:label="@string/app_name"',
    )

content = content.replace(
    'android:icon="@mipmap/ic_launcher"',
    'android:icon="@drawable/orbit_tap_icon"',
)
content = content.replace(
    'android:roundIcon="@mipmap/ic_launcher_round"',
    'android:roundIcon="@drawable/orbit_tap_icon"',
)

manifest_file.write_text(content, encoding='utf-8')

source_icon = Path('.github/android/orbit_tap_icon.xml')
dest_dir = Path('android/app/src/main/res/drawable')
dest_dir.mkdir(parents=True, exist_ok=True)
(dest_dir / 'orbit_tap_icon.xml').write_text(source_icon.read_text(encoding='utf-8'), encoding='utf-8')

print('Patched generated Android project.')
