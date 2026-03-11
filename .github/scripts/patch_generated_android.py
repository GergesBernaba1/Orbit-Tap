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
    '    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />',
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

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {{
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteFailures: List<String> = emptyList()
    private var pendingDeleteConfirmUris: List<String> = emptyList()

    private val deleteRequestLauncher = registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) {{ activityResult ->
        val result = pendingDeleteResult ?: return@registerForActivityResult
        val failed = if (activityResult.resultCode == Activity.RESULT_OK) {{
            pendingDeleteFailures
        }} else {{
            (pendingDeleteFailures + pendingDeleteConfirmUris).distinct()
        }}

        pendingDeleteResult = null
        pendingDeleteFailures = emptyList()
        pendingDeleteConfirmUris = emptyList()
        result.success(failed)
    }}

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "orbit_tap/media_source")
            .setMethodCallHandler {{ call, result ->
                when (call.method) {{
                    "deleteSourceUris" -> {{
                        if (pendingDeleteResult != null) {{
                            result.error("delete_in_progress", "Another media delete request is already in progress.", null)
                            return@setMethodCallHandler
                        }}

                        val uris = call.argument<List<String>>("uris").orEmpty()
                        handleDeleteSourceUris(uris, result)
                    }}
                    "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                    "openAllFilesAccessSettings" -> result.success(openAllFilesAccessSettings())
                    else -> result.notImplemented()
                }}
            }}
    }}

    private fun hasAllFilesAccess(): Boolean {{
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()
    }}

    private fun openAllFilesAccessSettings(): Boolean {{
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {{
            return false
        }}

        val directIntent = Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:$APP_PACKAGE")
        ).apply {{
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }}

        val fallbackIntent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).apply {{
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }}

        return try {{
            startActivity(directIntent)
            true
        }} catch (_: Exception) {{
            try {{
                startActivity(fallbackIntent)
                true
            }} catch (_: Exception) {{
                false
            }}
        }}
    }}

    private fun handleDeleteSourceUris(
        uriStrings: List<String>,
        result: MethodChannel.Result,
    ) {{
        val failed = mutableListOf<String>()
        val confirmUris = mutableListOf<Uri>()
        val confirmUriStrings = mutableListOf<String>()

        for (uriString in uriStrings) {{
            when (attemptDeleteSourceUri(uriString)) {{
                DeleteOutcome.DELETED -> Unit
                DeleteOutcome.NEEDS_USER_CONFIRMATION -> {{
                    val confirmUri = resolveDeleteUri(Uri.parse(uriString))
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && isMediaStoreUri(confirmUri)) {{
                        confirmUris.add(confirmUri)
                        confirmUriStrings.add(uriString)
                    }} else {{
                        failed.add(uriString)
                    }}
                }}
                DeleteOutcome.FAILED -> failed.add(uriString)
            }}
        }}

        if (confirmUris.isEmpty()) {{
            result.success(failed.distinct())
            return
        }}

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {{
            result.success((failed + confirmUriStrings).distinct())
            return
        }}

        try {{
            val pendingIntent = MediaStore.createDeleteRequest(contentResolver, confirmUris.distinct())
            pendingDeleteResult = result
            pendingDeleteFailures = failed.distinct()
            pendingDeleteConfirmUris = confirmUriStrings.distinct()
            val request = IntentSenderRequest.Builder(pendingIntent.intentSender).build()
            deleteRequestLauncher.launch(request)
        }} catch (_: Exception) {{
            result.success((failed + confirmUriStrings).distinct())
        }}
    }}

    private fun attemptDeleteSourceUri(uriString: String): DeleteOutcome {{
        return try {{
            val originalUri = Uri.parse(uriString)
            val deleteUri = resolveDeleteUri(originalUri)
            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            try {{
                contentResolver.takePersistableUriPermission(originalUri, takeFlags)
            }} catch (_: SecurityException) {{
                // Best effort only.
            }} catch (_: IllegalArgumentException) {{
                // Some providers do not support persisted permissions.
            }}

            val document = DocumentFile.fromSingleUri(this, originalUri)
            if (document != null && document.exists() && document.canWrite() && document.delete()) {{
                return DeleteOutcome.DELETED
            }}

            val deletedRows = contentResolver.delete(deleteUri, null, null)
            if (deletedRows > 0) {{
                DeleteOutcome.DELETED
            }} else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && isMediaStoreUri(deleteUri)) {{
                DeleteOutcome.NEEDS_USER_CONFIRMATION
            }} else {{
                DeleteOutcome.FAILED
            }}
        }} catch (_: RecoverableSecurityException) {{
            val deleteUri = resolveDeleteUri(Uri.parse(uriString))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && isMediaStoreUri(deleteUri)) {{
                DeleteOutcome.NEEDS_USER_CONFIRMATION
            }} else {{
                DeleteOutcome.FAILED
            }}
        }} catch (_: SecurityException) {{
            val deleteUri = resolveDeleteUri(Uri.parse(uriString))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && isMediaStoreUri(deleteUri)) {{
                DeleteOutcome.NEEDS_USER_CONFIRMATION
            }} else {{
                DeleteOutcome.FAILED
            }}
        }} catch (_: Exception) {{
            DeleteOutcome.FAILED
        }}
    }}

    private fun resolveDeleteUri(uri: Uri): Uri {{
        if (!DocumentsContract.isDocumentUri(this, uri)) {{
            return uri
        }}

        if (uri.authority != "com.android.providers.media.documents") {{
            return uri
        }}

        val documentId = runCatching {{ DocumentsContract.getDocumentId(uri) }}.getOrNull() ?: return uri
        val parts = documentId.split(":", limit = 2)
        if (parts.size != 2) {{
            return uri
        }}

        val mediaId = parts[1].toLongOrNull() ?: return uri
        val baseUri = when (parts[0]) {{
            "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            else -> null
        }} ?: return uri

        return ContentUris.withAppendedId(baseUri, mediaId)
    }}

    private fun isMediaStoreUri(uri: Uri): Boolean {{
        val authority = uri.authority ?: return false
        return authority == MediaStore.AUTHORITY || authority.startsWith("${{MediaStore.AUTHORITY}}.")
    }}

    private enum class DeleteOutcome {{
        DELETED,
        NEEDS_USER_CONFIRMATION,
        FAILED,
    }}
}}
''',
    encoding='utf-8',
)

print('Patched generated Android project.')
