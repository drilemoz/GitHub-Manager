package br.com.githubmanager.app

import android.Manifest
import android.app.ActivityManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var pendingStoragePermissionResult: MethodChannel.Result? = null
    private var reattachingCachedEngineOnCreate = false
    private var restoredActivityStateOnCreate = false
    private var flutterUiDisplayed = false
    private var pendingNotificationRoute: String? = null
    private var notificationChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        reattachingCachedEngineOnCreate = cachedRunningEngine() != null
        restoredActivityStateOnCreate = savedInstanceState != null
        flutterUiDisplayed = false
        pendingNotificationRoute = intent?.getStringExtra("notificationRoute")
        if (reattachingCachedEngineOnCreate) {
            // O engine já desenhou o primeiro frame em uma Activity anterior.
            // Troca o LaunchTheme antes do attach para não manter a splash nativa
            // aguardando um "primeiro frame" que já aconteceu nesse isolate.
            setTheme(R.style.NormalTheme)
        }

        super.onCreate(savedInstanceState)
        attachNotificationChannel()

        if (reattachingCachedEngineOnCreate) {
            window.setBackgroundDrawableResource(android.R.color.transparent)
            GitHubManagerApplication.recordCachedEngineReattach(
                context = applicationContext,
                taskId = taskId,
                restoredActivityState = restoredActivityStateOnCreate,
            )
        }
        cleanupDuplicateRecentTasks()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingNotificationRoute = intent.getStringExtra("notificationRoute")
        pendingNotificationRoute?.let { route ->
            notificationChannel?.invokeMethod("notificationTapped", route)
        }
        cleanupDuplicateRecentTasks()
    }

    private fun attachNotificationChannel() {
        val engine = flutterEngine ?: cachedRunningEngine() ?: return
        // Canal separado: não substitui os métodos Android de arquivo/instalação
        // nem depende do handler deixado por uma Activity anterior no engine em cache.
        notificationChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "br.com.githubmanager.app/notifications",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeNotificationRoute" -> {
                        result.success(pendingNotificationRoute)
                        pendingNotificationRoute = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        flutterUiDisplayed = true
        // Garante que nenhum background do LaunchTheme sobreviva ao momento em
        // que a FlutterView já está efetivamente renderizando pixels.
        setTheme(R.style.NormalTheme)
        window.setBackgroundDrawableResource(android.R.color.transparent)
    }

    private fun cleanupDuplicateRecentTasks() {
        runCatching {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            activityManager.appTasks
                .filter { appTask -> appTask.taskInfo.id != taskId }
                .forEach { appTask -> appTask.finishAndRemoveTask() }
        }
    }

    private fun cachedRunningEngine(): FlutterEngine? =
        FlutterEngineCache.getInstance()
            .get(MAIN_ENGINE_ID)
            ?.takeIf { it.dartExecutor.isExecutingDart }

    override fun getCachedEngineId(): String? =
        if (cachedRunningEngine() != null) MAIN_ENGINE_ID else null

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put(MAIN_ENGINE_ID, flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "br.com.githubmanager.app/platform",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUri" -> openUri(
                    rawUri = call.argument<String>("uri"),
                    mimeType = call.argument<String>("mimeType"),
                    result = result,
                )
                "openFile" -> openFile(
                    location = call.argument<String>("path"),
                    mimeType = call.argument<String>("mimeType"),
                    result = result,
                )
                "installApk" -> installApk(
                    location = call.argument<String>("path"),
                    result = result,
                )
                "shareFile" -> shareFile(
                    location = call.argument<String>("path"),
                    mimeType = call.argument<String>("mimeType"),
                    result = result,
                )
                "publishToDownloads" -> publishToDownloads(
                    sourcePath = call.argument<String>("sourcePath"),
                    fileName = call.argument<String>("fileName"),
                    mimeType = call.argument<String>("mimeType"),
                    relativeFolder = call.argument<String>("relativeFolder"),
                    result = result,
                )
                "requestLegacyDownloadsPermission" -> requestLegacyDownloadsPermission(result)
                "deletePublishedDownload" -> deletePublishedDownload(
                    location = call.argument<String>("location"),
                    result = result,
                )
                "cleanupManagedProjectDownloads" -> cleanupManagedProjectDownloads(
                    relativeFolder = call.argument<String>("relativeFolder"),
                    keepLocation = call.argument<String>("keepLocation"),
                    result = result,
                )
                "showUploadForegroundService" -> {
                    try {
                        val arguments = UploadForegroundService.Arguments(
                            uploadId = call.argument<String>("uploadId").orEmpty(),
                            projectName = call.argument<String>("projectName").orEmpty(),
                            repositoryFullName = call.argument<String>("repositoryFullName").orEmpty(),
                            phase = call.argument<String>("phase").orEmpty(),
                            current = call.argument<Int>("current") ?: 0,
                            total = call.argument<Int>("total") ?: 0,
                            indeterminate = call.argument<Boolean>("indeterminate") ?: true,
                            activeCount = call.argument<Int>("activeCount") ?: 1,
                        )
                        if (call.argument<Boolean>("startService") != false) {
                            UploadForegroundService.show(applicationContext, arguments)
                        } else {
                            UploadForegroundService.update(applicationContext, arguments)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("UPLOAD_FOREGROUND_FAILED", error.message, null)
                    }
                }
                "stopUploadForegroundService" -> {
                    try {
                        UploadForegroundService.stop(applicationContext)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("UPLOAD_FOREGROUND_STOP_FAILED", error.message, null)
                    }
                }
                "showDownloadForegroundService" -> {
                    try {
                        val arguments = DownloadForegroundService.Arguments(
                            downloadId = call.argument<String>("downloadId").orEmpty(),
                            fileName = call.argument<String>("fileName").orEmpty(),
                            repositoryFullName = call.argument<String>("repositoryFullName").orEmpty(),
                            current = call.argument<Int>("current") ?: 0,
                            total = call.argument<Int>("total") ?: 0,
                            indeterminate = call.argument<Boolean>("indeterminate") ?: true,
                            activeCount = call.argument<Int>("activeCount") ?: 1,
                        )
                        if (call.argument<Boolean>("startService") != false) {
                            DownloadForegroundService.show(applicationContext, arguments)
                        } else {
                            DownloadForegroundService.update(applicationContext, arguments)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("DOWNLOAD_FOREGROUND_FAILED", error.message, null)
                    }
                }
                "stopDownloadForegroundService" -> {
                    try {
                        DownloadForegroundService.stop(applicationContext)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("DOWNLOAD_FOREGROUND_STOP_FAILED", error.message, null)
                    }
                }
                "consumeNativeCrashReport" -> {
                    result.success(
                        GitHubManagerApplication.consumePendingNativeCrash(applicationContext),
                    )
                }
                "consumeNativeEngineLifecycleReport" -> {
                    result.success(
                        GitHubManagerApplication.consumePendingEngineLifecycle(applicationContext),
                    )
                }
                "getInstalledAppInfo" -> {
                    val packageName = call.argument<String>("packageName").orEmpty()
                    queryInstalledApp(packageName, result)
                }
                "getDeviceInfo" -> {
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER.orEmpty(),
                            "model" to Build.MODEL.orEmpty(),
                            "androidRelease" to Build.VERSION.RELEASE.orEmpty(),
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
                            "supported64BitAbis" to Build.SUPPORTED_64_BIT_ABIS.toList(),
                        ),
                    )
                }
                "getActivityLaunchState" -> {
                    result.success(
                        mapOf(
                            "cachedEngineReattach" to reattachingCachedEngineOnCreate,
                            "flutterUiDisplayed" to flutterUiDisplayed,
                            "taskId" to taskId,
                            "restoredActivityState" to restoredActivityStateOnCreate,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun queryInstalledApp(packageName: String, result: MethodChannel.Result) {
        // Nunca enumera apps: consulta apenas o applicationId informado pelo projeto.
        val valid = Regex("^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)+$")
        if (packageName.length !in 3..255 || !valid.matches(packageName)) {
            result.success(mapOf("status" to "unknown", "reason" to "invalid_package_id"))
            return
        }
        try {
            val info = if (Build.VERSION.SDK_INT >= 33) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            result.success(
                mapOf(
                    "status" to "installed",
                    "packageName" to info.packageName,
                    "versionName" to (info.versionName ?: ""),
                    "versionCode" to code,
                ),
            )
        } catch (_: PackageManager.NameNotFoundException) {
            // Android 11+ pode ocultar um pacote existente. Nem getPackageInfo
            // nem getLaunchIntentForPackage permitem concluir que foi removido
            // quando o pacote não está visível. Não mostrar falso "Não instalado".
            result.success(
                mapOf(
                    "status" to if (Build.VERSION.SDK_INT >= 30) "unknown" else "notInstalled",
                    "reason" to if (Build.VERSION.SDK_INT >= 30) "package_visibility" else "absent",
                ),
            )
        } catch (_: SecurityException) {
            result.success(mapOf("status" to "unknown", "reason" to "security"))
        } catch (_: Exception) {
            result.success(mapOf("status" to "unknown", "reason" to "query_failed"))
        }
    }

    private fun openUri(rawUri: String?, mimeType: String?, result: MethodChannel.Result) {
        if (rawUri.isNullOrBlank()) {
            result.error("URI_REQUIRED", "URI inválida", null)
            return
        }
        try {
            val uri = Uri.parse(rawUri)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                if (mimeType.isNullOrBlank()) {
                    data = uri
                } else {
                    setDataAndType(uri, mimeType)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("OPEN_URI_FAILED", error.message, null)
        }
    }

    private fun openFile(location: String?, mimeType: String?, result: MethodChannel.Result) {
        if (location.isNullOrBlank()) {
            result.error("FILE_REQUIRED", "Arquivo inválido", null)
            return
        }
        try {
            val uri = resolveShareUri(location)
            val resolvedMime = mimeType ?: contentResolver.getType(uri) ?: "application/octet-stream"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, resolvedMime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("OPEN_FILE_FAILED", error.message, null)
        }
    }

    private fun shareFile(location: String?, mimeType: String?, result: MethodChannel.Result) {
        if (location.isNullOrBlank()) {
            result.error("FILE_REQUIRED", "Arquivo inválido", null)
            return
        }
        try {
            val uri = resolveShareUri(location)
            val resolvedMime = mimeType ?: contentResolver.getType(uri) ?: "application/octet-stream"
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = resolvedMime
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Compartilhar arquivo"))
            result.success(null)
        } catch (error: Exception) {
            result.error("SHARE_FILE_FAILED", error.message, null)
        }
    }

    private fun installApk(location: String?, result: MethodChannel.Result) {
        if (location.isNullOrBlank()) {
            result.error("APK_REQUIRED", "APK inválido", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                val settingsIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
                startActivity(settingsIntent)
                result.success("permission_required")
                return
            }
            val uri = resolveShareUri(location)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success("launched")
        } catch (error: Exception) {
            result.error("INSTALL_APK_FAILED", error.message, null)
        }
    }

    private fun publishToDownloads(
        sourcePath: String?,
        fileName: String?,
        mimeType: String?,
        relativeFolder: String?,
        result: MethodChannel.Result,
    ) {
        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("DOWNLOAD_ARGUMENTS_REQUIRED", "Arquivo de download inválido", null)
            return
        }
        val source = File(sourcePath)
        if (!source.exists()) {
            result.error("DOWNLOAD_SOURCE_NOT_FOUND", "Arquivo temporário não encontrado", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType ?: "application/octet-stream")
                    val relativePath = buildString {
                        append(Environment.DIRECTORY_DOWNLOADS)
                        append("/GitHub")
                        if (!relativeFolder.isNullOrBlank()) {
                            append("/")
                            append(safeFolderName(relativeFolder))
                        }
                    }
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("Não foi possível criar o arquivo em Downloads")
                try {
                    contentResolver.openOutputStream(uri, "w").use { output ->
                        requireNotNull(output) { "Não foi possível abrir Downloads para escrita" }
                        FileInputStream(source).use { input -> input.copyTo(output) }
                    }
                    val completed = ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }
                    contentResolver.update(uri, completed, null, null)
                    result.success(uri.toString())
                } catch (error: Exception) {
                    contentResolver.delete(uri, null, null)
                    throw error
                }
                return
            }

            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                result.error(
                    "STORAGE_PERMISSION_REQUIRED",
                    "Permissão para salvar na pasta Downloads é necessária neste Android.",
                    null,
                )
                return
            }

            @Suppress("DEPRECATION")
            val downloadsRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val githubDirectory = File(downloadsRoot, "GitHub")
            val downloads = if (relativeFolder.isNullOrBlank()) {
                githubDirectory
            } else {
                File(githubDirectory, safeFolderName(relativeFolder))
            }
            if (!downloads.exists()) {
                downloads.mkdirs()
            }
            val target = uniqueLegacyFile(downloads, fileName)
            FileInputStream(source).use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
            result.success(target.absolutePath)
        } catch (error: Exception) {
            val message = error.message.orEmpty()
            val storageFull = message.contains("ENOSPC", ignoreCase = true) ||
                message.contains("No space left", ignoreCase = true)
            result.error(
                if (storageFull) "STORAGE_FULL" else "DOWNLOAD_PUBLISH_FAILED",
                error.message,
                null,
            )
        }
    }

    private fun requestLegacyDownloadsPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingStoragePermissionResult != null) {
            result.error("PERMISSION_REQUEST_ACTIVE", "Já existe um pedido de permissão em andamento", null)
            return
        }
        pendingStoragePermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            STORAGE_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingStoragePermissionResult?.success(granted)
            pendingStoragePermissionResult = null
        }
    }

    private fun deletePublishedDownload(location: String?, result: MethodChannel.Result) {
        if (location.isNullOrBlank()) {
            result.success(true)
            return
        }
        try {
            if (location.startsWith("content://")) {
                val uri = Uri.parse(location)
                val deletedRows = contentResolver.delete(uri, null, null)
                if (deletedRows > 0) {
                    result.success(true)
                    return
                }

                // Quando o MediaStore devolve 0, confirmamos se o arquivo já
                // não existe. Se ele ainda puder ser aberto, não removemos o
                // registro do histórico silenciosamente.
                val stillExists = try {
                    contentResolver.openFileDescriptor(uri, "r")?.use { true } ?: false
                } catch (_: java.io.FileNotFoundException) {
                    false
                }
                if (stillExists) {
                    result.error(
                        "DELETE_DOWNLOAD_NOT_CONFIRMED",
                        "O Android não confirmou a exclusão do arquivo em Downloads.",
                        null,
                    )
                } else {
                    result.success(true)
                }
                return
            }

            val file = File(location)
            if (!file.exists()) {
                result.success(true)
                return
            }
            if (!file.delete()) {
                result.error(
                    "DELETE_DOWNLOAD_NOT_CONFIRMED",
                    "Não foi possível apagar o arquivo da pasta Downloads.",
                    null,
                )
                return
            }
            result.success(true)
        } catch (error: Exception) {
            result.error("DELETE_DOWNLOAD_FAILED", error.message, null)
        }
    }

    /**
     * Limpeza conservadora: somente arquivos publicados por ESTE aplicativo
     * no nível exato de Downloads/GitHub/<projeto>. Nunca percorre subpastas,
     * nem remove arquivos de outros aplicativos, parciais ou IS_PENDING.
     * Em Android 9 ou anterior, o Dart exclui somente caminhos que constam
     * de seu histórico de downloads, evitando varrer dados de terceiros.
     */
    private fun cleanupManagedProjectDownloads(
        relativeFolder: String?,
        keepLocation: String?,
        result: MethodChannel.Result,
    ) {
        if (relativeFolder.isNullOrBlank()) {
            result.error("DOWNLOAD_FOLDER_REQUIRED", "Pasta do projeto ausente.", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(mapOf("removed" to emptyList<String>(), "failed" to 0))
            return
        }
        val folder = safeFolderName(relativeFolder)
        val expectedPath = "${Environment.DIRECTORY_DOWNLOADS}/GitHub/$folder/"
        val removed = mutableListOf<String>()
        var failed = 0
        try {
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.RELATIVE_PATH,
                MediaStore.MediaColumns.OWNER_PACKAGE_NAME,
            )
            // A comparação também é conferida em Kotlin; não confiar somente
            // na cláusula SQL se algum provedor normalizar barras/case.
            val where = "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.IS_PENDING}=0"
            val toDelete = mutableListOf<Uri>()
            val cursor = contentResolver.query(
                collection, projection, where, arrayOf(expectedPath), null,
            ) ?: throw IllegalStateException("O MediaStore não retornou a lista de downloads.")
            cursor.use {
                val idIndex = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val folderIndex = it.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
                val ownerIndex = it.getColumnIndexOrThrow(MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
                while (it.moveToNext()) {
                    val actualFolder = it.getString(folderIndex).orEmpty()
                    val owner = it.getString(ownerIndex).orEmpty()
                    if (!actualFolder.equals(expectedPath, ignoreCase = true) || owner != packageName) {
                        continue
                    }
                    val uri = android.content.ContentUris.withAppendedId(collection, it.getLong(idIndex))
                    val location = uri.toString()
                    if (location == keepLocation) continue
                    toDelete.add(uri)
                }
            }
            // Evitar exclusão enquanto o cursor MediaStore ainda percorre
            // a consulta: alguns provedores invalidam a posição da consulta.
            for (uri in toDelete) {
                try {
                    if (contentResolver.delete(uri, null, null) > 0) {
                        removed.add(uri.toString())
                    } else {
                        failed++
                    }
                } catch (_: Exception) {
                    failed++
                }
            }
            result.success(mapOf("removed" to removed, "failed" to failed))
        } catch (error: Exception) {
            result.error("DOWNLOAD_CLEANUP_FAILED", error.message, null)
        }
    }

    private fun resolveShareUri(location: String): Uri {
        if (location.startsWith("content://")) {
            return Uri.parse(location)
        }
        val file = File(location)
        if (!file.exists()) {
            throw IllegalArgumentException("Arquivo não encontrado")
        }
        return FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
    }

    private fun safeFolderName(value: String): String {
        val cleaned = value
            .replace(Regex("[\\/:*?\"<>|]"), "-")
            .replace(Regex("\\s+"), " ")
            .trim()
        return cleaned.ifBlank { "Projeto" }
    }

    private fun uniqueLegacyFile(directory: File, requestedName: String): File {
        var target = File(directory, requestedName)
        if (!target.exists()) {
            return target
        }
        val dot = requestedName.lastIndexOf('.')
        val stem = if (dot > 0) requestedName.substring(0, dot) else requestedName
        val extension = if (dot > 0) requestedName.substring(dot) else ""
        var index = 2
        while (target.exists()) {
            target = File(directory, "$stem-$index$extension")
            index++
        }
        return target
    }

    companion object {
        private const val STORAGE_PERMISSION_REQUEST = 7012
        private const val MAIN_ENGINE_ID = "github_manager_main_engine"
    }
}
