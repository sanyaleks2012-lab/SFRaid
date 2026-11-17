package com.sf2de.raid.raid_forge

// android/app/src/main/kotlin/<ваш/пакет>/MainActivity.kt
// Оставьте свою строку `package ...` первой строкой файла!

import android.content.pm.PackageManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val executor = Executors.newSingleThreadExecutor()
    private var pendingPerm: MethodChannel.Result? = null
    private val reqCode = 4242

    private val permListener =
        Shizuku.OnRequestPermissionResultListener { code, result ->
            if (code == reqCode) {
                pendingPerm?.success(result == PackageManager.PERMISSION_GRANTED)
                pendingPerm = null
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Shizuku.addRequestPermissionResultListener(permListener)
    }

    override fun onDestroy() {
        Shizuku.removeRequestPermissionResultListener(permListener)
        executor.shutdown()
        super.onDestroy()
    }

    // ---------- helpers ----------

    private fun q(s: String) = "'" + s.replace("'", "'\\''") + "'"

    private fun state(): String {
        val installed = try {
            packageManager.getPackageInfo("moe.shizuku.privileged.api", 0)
            true
        } catch (e: Exception) {
            false
        }
        if (!Shizuku.pingBinder()) return if (installed) "notRunning" else "notInstalled"
        if (Shizuku.isPreV11()) return "notRunning"
        return if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED)
            "ready" else "noPermission"
    }

    // В Shizuku API 13+ newProcess приватный — вызываем через reflection.
    private fun newProcess(cmd: Array<String>): Process {
        val m = Shizuku::class.java.getDeclaredMethod(
            "newProcess",
            Array<String>::class.java,
            Array<String>::class.java,
            String::class.java
        )
        m.isAccessible = true
        return m.invoke(null, cmd, null, null) as Process
    }

    private data class Res(val code: Int, val out: ByteArray, val err: String)

    private fun exec(cmd: String, stdin: ByteArray? = null): Res {
        val p = newProcess(arrayOf("sh", "-c", cmd))
        var err = ""
        val t = Thread { err = p.errorStream.readBytes().toString(Charsets.UTF_8) }
        t.start()
        if (stdin != null) p.outputStream.use { it.write(stdin) } else p.outputStream.close()
        val out = p.inputStream.readBytes()
        val code = p.waitFor()
        t.join()
        return Res(code, out, err)
    }

    private fun MethodChannel.Result.run(block: () -> Any?) {
        executor.execute {
            try {
                val r = block()
                runOnUiThread { success(r) }
            } catch (e: Exception) {
                runOnUiThread { error("SHIZUKU", e.message, null) }
            }
        }
    }

    private fun ok(r: Res): Res {
        if (r.code != 0) throw RuntimeException(r.err.ifBlank { "exit ${r.code}" })
        return r
    }

    // ---------- channel ----------

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "raidforge/shizuku")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "state" -> result.success(state())

                    "requestPermission" -> {
                        if (state() == "ready") {
                            result.success(true)
                        } else if (!Shizuku.pingBinder()) {
                            result.success(false)
                        } else {
                            pendingPerm = result
                            Shizuku.requestPermission(reqCode)
                        }
                    }

                    "exists" -> result.run {
                        val p = call.argument<String>("path")!!
                        exec("test -f ${q(p)}").code == 0
                    }

                    "read" -> result.run {
                        val p = call.argument<String>("path")!!
                        ok(exec("cat ${q(p)}")).out
                    }

                    "write" -> result.run {
                        val p = call.argument<String>("path")!!
                        val d = call.argument<ByteArray>("data")!!
                        ok(exec("cat > ${q(p)}", d))
                        null
                    }

                    "copy" -> result.run {
                        val s = call.argument<String>("src")!!
                        val d = call.argument<String>("dst")!!
                        ok(exec("cp ${q(s)} ${q(d)}"))
                        null
                    }

                    "list" -> result.run {
                        val d = call.argument<String>("dir")!!
                        val r = exec("ls -1 ${q(d)}")
                        if (r.code != 0) "" else r.out.toString(Charsets.UTF_8)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}

