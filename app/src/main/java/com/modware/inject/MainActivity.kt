package com.modware.inject

import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import kotlin.concurrent.thread
import rikka.shizuku.Shizuku

class MainActivity : Activity() {

    private val password = "12345678"
    private val MP = ViewGroup.LayoutParams.MATCH_PARENT
    private val WC = ViewGroup.LayoutParams.WRAP_CONTENT

    private lateinit var root: FrameLayout
    private lateinit var status: TextView
    private lateinit var btnShizuku: Button
    private lateinit var input: EditText

    private val permListener =
        Shizuku.OnRequestPermissionResultListener { _, _ -> runOnUiThread { refresh() } }
    private val binderListener =
        Shizuku.OnBinderReceivedListener { runOnUiThread { refresh() } }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
    private fun shizukuOn() = Shizuku.pingBinder()
    private fun shizukuOk() =
        Shizuku.pingBinder() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        root = FrameLayout(this)
        root.setBackgroundResource(R.drawable.bg_gradient)
        setContentView(root)
        showGate()
        Shizuku.addBinderReceivedListenerSticky(binderListener)
        Shizuku.addRequestPermissionResultListener(permListener)
    }

    override fun onResume() {
        super.onResume()
        if (::status.isInitialized) refresh()
    }

    override fun onDestroy() {
        Shizuku.removeBinderReceivedListener(binderListener)
        Shizuku.removeRequestPermissionResultListener(permListener)
        super.onDestroy()
    }

    // ---------- Layar gerbang ----------
    private fun showGate() {
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(28), dp(28), dp(28))
        }
        val img = ImageView(this).apply { setImageResource(R.drawable.black_hole) }
        status = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, dp(16))
        }
        btnShizuku = Button(this).apply { setOnClickListener { onShizukuClick() } }
        input = EditText(this).apply {
            hint = "Password"
            setHintTextColor(Color.parseColor("#88FFFFFF"))
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
        }
        val enter = Button(this).apply {
            text = "Masuk"
            setOnClickListener { onEnter() }
        }
        col.addView(img, LinearLayout.LayoutParams(dp(220), dp(220)))
        col.addView(status, LinearLayout.LayoutParams(MP, WC))
        col.addView(btnShizuku, LinearLayout.LayoutParams(MP, WC))
        col.addView(input, LinearLayout.LayoutParams(MP, WC))
        col.addView(enter, LinearLayout.LayoutParams(MP, WC))
        root.removeAllViews()
        root.addView(col, FrameLayout.LayoutParams(MP, MP))
        refresh()
    }

    private fun refresh() {
        val on = shizukuOn()
        val ok = shizukuOk()
        status.text = "Shizuku: " + (if (on) "menyala ✓" else "belum menyala ✗") +
            "\nAkses: " + (if (ok) "diizinkan ✓" else "belum diizinkan ✗")
        btnShizuku.text = when {
            !on -> "Buka Shizuku"
            !ok -> "Berikan akses Shizuku"
            else -> "Shizuku siap ✓"
        }
        btnShizuku.isEnabled = !ok
    }

    private fun onShizukuClick() {
        if (!shizukuOn()) {
            val i = packageManager.getLaunchIntentForPackage("moe.shizuku.privileged.api")
            if (i != null) startActivity(i) else toast("Aplikasi Shizuku belum terpasang")
        } else if (!shizukuOk()) {
            if (Shizuku.shouldShowRequestPermissionRationale()) {
                toast("Izin ditolak permanen. Beri izin manual lewat aplikasi Shizuku.")
            } else {
                Shizuku.requestPermission(100)
            }
        }
    }

    private fun onEnter() {
        when {
            !shizukuOk() -> toast("Nyalakan Shizuku dan beri aksesnya dulu")
            input.text.toString() != password -> toast("Password salah")
            else -> showMain()
        }
    }

    // ---------- Layar utama ----------
    private fun showMain() {
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(48), dp(20), dp(20))
        }
        val title = TextView(this).apply {
            text = "Modware Inject"
            setTextColor(Color.WHITE)
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(16))
        }
        val btn = Button(this).apply { text = "INJECT" }
        val out = TextView(this).apply {
            setTextColor(Color.parseColor("#C8FFC8"))
            typeface = Typeface.MONOSPACE
            textSize = 12f
            setTextIsSelectable(true)
        }
        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#66000000"))
            setPadding(dp(10), dp(10), dp(10), dp(10))
            addView(out)
        }
        btn.setOnClickListener {
            btn.isEnabled = false
            out.text = "Menjalankan script...\n"
            runScript(out, scroll, btn)
        }
        col.addView(title, LinearLayout.LayoutParams(MP, WC))
        col.addView(btn, LinearLayout.LayoutParams(MP, WC))
        col.addView(scroll, LinearLayout.LayoutParams(MP, 0, 1f))
        root.removeAllViews()
        root.addView(col, FrameLayout.LayoutParams(MP, MP))
    }

    private fun addLine(out: TextView, scroll: ScrollView, s: String) {
        runOnUiThread {
            out.append(s + "\n")
            scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
        }
    }

    private fun runScript(out: TextView, scroll: ScrollView, btn: Button) {
        val script = assets.open("optimasi_hyperos.sh").bufferedReader().use { it.readText() }
        thread {
            try {
                val m = Shizuku::class.java.getDeclaredMethod(
                    "newProcess",
                    Array<String>::class.java,
                    Array<String>::class.java,
                    String::class.java
                )
                m.isAccessible = true
                val cmd = arrayOf("sh", "-c", "exec 2>&1\n" + script)
                val p = m.invoke(null, cmd, null, null) as Process
                p.inputStream.bufferedReader().forEachLine { addLine(out, scroll, it) }
                addLine(out, scroll, "[selesai, kode ${p.waitFor()}]")
            } catch (e: Exception) {
                addLine(out, scroll, "ERROR: " + (e.cause ?: e))
            }
            runOnUiThread { btn.isEnabled = true }
        }
    }
}
