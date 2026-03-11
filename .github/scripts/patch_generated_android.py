from pathlib import Path

APP_PACKAGE = 'com.orbittap.app'
APP_PACKAGE_PATH = APP_PACKAGE.replace('.', '/')

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

manifest_open = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
permission_lines = [
    '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />',
    '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />',
    '    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />',
    '    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />',
]
if manifest_open in content:
    insertion = '\n'.join(
        permission for permission in permission_lines if permission not in content
    )
    if insertion:
        content = content.replace(
            manifest_open,
            f'{manifest_open}\n{insertion}',
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

main_activity = Path(f'android/app/src/main/kotlin/{APP_PACKAGE_PATH}/MainActivity.kt')
main_activity.parent.mkdir(parents=True, exist_ok=True)
main_activity.write_text(
    f'''package {APP_PACKAGE}

import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orbit_tap/media_source")
            .setMethodCallHandler {{ call, result ->
                when (call.method) {{
                    "deleteSourceUris" -> {{
                        val uris = call.argument<List<String>>("uris").orEmpty()
                        result.success(deleteSourceUris(uris))
                    }}
                    else -> result.notImplemented()
                }}
            }}
    }}

    private fun deleteSourceUris(uriStrings: List<String>): List<String> {{
        val failed = mutableListOf<String>()
        for (uriString in uriStrings) {{
            if (!deleteSourceUri(uriString)) {{
                failed.add(uriString)
            }}
        }}
        return failed
    }}

    private fun deleteSourceUri(uriString: String): Boolean {{
        return try {{
            val uri = Uri.parse(uriString)
            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            try {{
                contentResolver.takePersistableUriPermission(uri, takeFlags)
            }} catch (_: SecurityException) {{
                // Best effort only.
            }} catch (_: IllegalArgumentException) {{
                // Some providers do not support persisted permissions.
            }}

            val document = DocumentFile.fromSingleUri(this, uri)
            if (document != null && document.exists() && document.canWrite()) {{
                if (document.delete()) {{
                    return true
                }}
            }}

            contentResolver.delete(uri, null, null) > 0
        }} catch (_: Exception) {{
            false
        }}
    }}
}}
''',
    encoding='utf-8',
)

print('Patched generated Android project.')
