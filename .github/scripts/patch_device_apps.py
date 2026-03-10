from pathlib import Path
import re

matches = sorted(
    Path.home().glob('.pub-cache/hosted/pub.dev/device_apps-*/android/build.gradle')
)
if not matches:
    raise SystemExit('device_apps build.gradle not found in pub cache')

gradle_file = matches[-1]
content = gradle_file.read_text(encoding='utf-8')

if 'namespace ' not in content:
    content = content.replace(
        'android {',
        "android {\n    namespace 'fr.g123k.deviceapps'",
        1,
    )

content = re.sub(r'compileSdkVersion\s+\d+', 'compileSdkVersion 34', content)
content = re.sub(r'targetSdkVersion\s+\d+', 'targetSdkVersion 34', content)

gradle_file.write_text(content, encoding='utf-8')
print(f'Patched {gradle_file}')
