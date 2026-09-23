package dev.mini.candlelight

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color as AColor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.JsResult
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/**
 * หลังล็อกอิน แอพเป็นแค่กรอบของหน้าเว็บ /app — หน้าเดียวกับที่คอมกับ .exe เปิด ทุกหน้าจอจึงเขียนที่เดียว
 *
 * สัญญากับหน้าเว็บ (SPEC ข้อ 6):
 *  - token ส่งไปทาง #t=… หน้าเว็บเก็บเป็น cl.token แล้วลบออกจาก URL ด้วย history.replaceState ก่อนทำอย่างอื่น
 *  - window.CLHost มีแค่ signedOut() กับ deviceKind() ไม่มีอะไรที่อ่านข้อมูลในเครื่องได้
 *  - ปุ่มย้อนกลับของเครื่องถาม window.clBack() ก่อน ได้ false (อยู่หน้าบนสุดแล้ว) ค่อยปิดแอพ
 */
private val SERVER_HOST = SERVER.substringAfter("://").substringBefore('/')

/** #t= หายจาก URL แล้ว = หน้าเว็บรับ token ไปแล้ว (ข้อแรกของสัญญา) — หน้าเว็บรุ่นเก่าที่ไม่รู้จักแอพไม่แตะมันเลย */
private const val TOOK_TOKEN = "!/[#&]t=/.test(location.hash)"

/**
 * สะพานจากหน้าเว็บ (window.CLHost) — ห้ามชื่อ "Android" เพราะ board.html อ่าน window.Android ของมันเอง
 * addJavascriptInterface ฉีดเข้าทุกเฟรม (รวม iframe กระดานกับโต๊ะรบ) จึงเปิดให้แค่สองอย่างที่ไม่มีพิษภัย
 * เมธอดถูกเรียกบนเธรดของ WebView → กระโดดกลับ main ก่อนแตะ state ของ Compose
 */
class CLHost(private val onSignedOut: () -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    /** หน้าเว็บออกจากระบบแล้ว (ล้าง cl.token ของมันเองแล้ว) → ล้าง token ในเครื่อง กลับหน้าล็อกอินของแอพ */
    @JavascriptInterface fun signedOut() { main.post { onSignedOut() } }
    /** ไอคอนเครื่องข้างชื่อผู้เล่นที่กองไฟ */
    @JavascriptInterface fun deviceKind(): String = "phone"
}

/**
 * confirm()/alert() ของหน้าเว็บ (ออกจากระบบ, ออกจากโต๊ะ) — กล่องของ WebView เองขึ้นหัวว่า
 * 'The page at "https://…workers.dev" says:' ดูเหมือนคำเตือนของเบราว์เซอร์ จึงทำกล่องเองแค่ข้อความกับปุ่ม
 * ส่วนปุ่ม "เต็มจอ" ของโต๊ะรบ WebView ส่งวิวมาให้ ต้องแปะทับทั้งหน้าต่างเองแล้วซ่อนแถบระบบ
 */
private class AppChrome(private val activity: Activity?) : WebChromeClient() {
    private var shown: View? = null
    private var callback: WebChromeClient.CustomViewCallback? = null
    private var dialog: AlertDialog? = null
    val isFullscreen: Boolean get() = shown != null

    override fun onJsAlert(view: WebView?, url: String?, message: String?, result: JsResult?): Boolean = ask(message, result, false)
    override fun onJsConfirm(view: WebView?, url: String?, message: String?, result: JsResult?): Boolean = ask(message, result, true)

    /** ตกลง → confirm(), ยกเลิก / กดนอกกล่อง / ปุ่มย้อนกลับ → cancel() — JsResult ต้องได้คำตอบครั้งเดียวเสมอ ไม่งั้นหน้าเว็บค้าง */
    private fun ask(message: String?, result: JsResult?, withCancel: Boolean): Boolean {
        val act = activity
        if (act == null || result == null || act.isFinishing) return false   // ให้ WebView ใช้กล่องของมันเอง
        dialog = AlertDialog.Builder(act)
            .setMessage(message)
            .setPositiveButton("ตกลง") { _, _ -> result.confirm() }
            .apply { if (withCancel) setNegativeButton("ยกเลิก") { _, _ -> result.cancel() } }
            .setOnCancelListener { result.cancel() }
            .show()
        return true
    }

    override fun onShowCustomView(view: View?, callback: WebChromeClient.CustomViewCallback?) {
        val win = activity?.window
        val decor = win?.decorView as? FrameLayout
        if (view == null || win == null || decor == null || shown != null) { callback?.onCustomViewHidden(); return }
        decor.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        shown = view; this.callback = callback
        WindowInsetsControllerCompat(win, decor).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    override fun onHideCustomView() { dismiss() }

    /** ปุ่มย้อนกลับตอนเต็มจอ = ออกจากเต็มจอ ให้หน้าเว็บรู้ตัวด้วย (fullscreenchange) */
    fun exitFullscreen() { val cb = callback; if (cb != null) cb.onCustomViewHidden() else dismiss() }

    /** เอาวิวเต็มจอกับกล่องข้อความที่ค้างอยู่ออกเฉย ๆ — ใช้ตอน WebView กำลังจะถูกทิ้งด้วย */
    fun dismiss() {
        dialog?.let { if (it.isShowing) it.cancel() }; dialog = null     // กดปุ่มไปแล้วห้าม cancel ซ้ำ ได้คำตอบสองครั้ง
        val v = shown ?: return
        shown = null; callback = null
        val win = activity?.window ?: return
        val decor = win.decorView as? FrameLayout ?: return
        decor.removeView(v)
        WindowInsetsControllerCompat(win, decor).show(WindowInsetsCompat.Type.systemBars())
    }
}

/**
 * ดูการโหลดหน้าเว็บ: เปิดลิงก์นอกเว็บเกมในเบราว์เซอร์, โหลดไม่ขึ้น → [offline], ตัวเรนเดอร์ตาย → [gone] (true = พังเอง)
 * [ready] = หน้าเว็บขึ้นแล้วและรับ token ไปแล้ว — ถึงตอนนั้นค่อยเอาหน้ารอเข้าระบบของแอพที่ทับไว้ออก
 * ไม่รอ onPageFinished เพราะมันรอทุกสคริปต์ async ในหน้า (GIS ของ Google ที่ในแอพไม่ได้ใช้ เน็ตช้าทีค้างเป็นนาที)
 */
private class AppClient(private val offline: (String?) -> Unit, private val gone: (Boolean) -> Unit) : WebViewClient() {
    var ready by mutableStateOf(false)
    /** WebView ตัวนี้จบแล้ว (ไปหน้าออฟไลน์ / ตัวเรนเดอร์ตาย / ถูกทิ้ง) callback ที่มาทีหลังไม่ต้องทำอะไรอีก */
    private var over = false
    private val main = Handler(Looper.getMainLooper())

    fun release() { over = true; main.removeCallbacksAndMessages(null) }

    private fun leave(why: String?) { if (!over) { release(); offline(why) } }

    /**
     * ถามหน้าเว็บว่ารับ token ไปหรือยัง ยังไม่รับก็ถามใหม่เรื่อย ๆ จนหน้าโหลดเสร็จ ([last])
     * โหลดเสร็จแล้ว #t= ยังอยู่ = เซิร์ฟเวอร์ยังเสิร์ฟหน้าเว็บรุ่นก่อนแอพนี้ (ปล่อยแอพก่อนอัปเดตเซิร์ฟเวอร์)
     * หน้านั้นมีแต่ปุ่ม Google ที่ WebView ใช้ไม่ได้ กับปุ่มผู้เล่นรับเชิญที่สร้างบัญชีใหม่แยกจากของเรา → ไปหน้าออฟไลน์แทน
     */
    private fun check(w: WebView, last: Boolean) {
        if (over || ready) return
        w.evaluateJavascript(TOOK_TOKEN) { r ->
            when {
                over || ready -> {}
                r == "false" && last -> leave("เซิร์ฟเวอร์ยังไม่รองรับแอพรุ่นนี้")
                r == "false" -> main.postDelayed({ check(w, false) }, 150)
                else -> ready = true      // "true" หรืออ่านค่าไม่ได้ — ไม่ขังผู้เล่นไว้หลังหน้ารอ
            }
        }
    }

    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
        if (request == null || !request.isForMainFrame) return false   // iframe กระดาน/โต๊ะรบ (srcdoc) ปล่อยตามปกติ
        val url = request.url
        if (url.scheme == "https" && url.host == SERVER_HOST) return false
        // ลิงก์ออกนอกเว็บเกม → เบราว์เซอร์ของเครื่อง ไม่ให้เว็บอื่นมาเปิดในกรอบที่มี CLHost
        when (url.scheme) {
            "http", "https", "mailto" ->
                try { view?.context?.startActivity(Intent(Intent.ACTION_VIEW, url)) } catch (e: ActivityNotFoundException) { }
        }
        return true
    }
    /** หน้าใหม่เริ่มวาดแล้ว — เริ่มถามได้ */
    override fun onPageCommitVisible(view: WebView?, url: String?) { if (view != null) check(view, false) }
    override fun onPageFinished(view: WebView?, url: String?) { if (view != null) check(view, true) }
    override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
        if (request?.isForMainFrame == true) leave(null)
    }
    override fun onReceivedHttpError(view: WebView?, request: WebResourceRequest?, errorResponse: WebResourceResponse?) {
        val code = errorResponse?.statusCode ?: 0
        if (request?.isForMainFrame == true && code >= 400) leave("เซิร์ฟเวอร์ตอบ HTTP $code")
    }
    // ตัวเรนเดอร์ของ WebView ตาย — ต้องตอบ true (ไม่งั้นแอพปิดตัวตาม) แล้วห้ามแตะ WebView ตัวนี้อีก
    override fun onRenderProcessGone(view: WebView?, detail: RenderProcessGoneDetail?): Boolean {
        if (!over) { release(); gone(detail?.didCrash() ?: true) }
        return true
    }
}

/** chrome://inspect เปิดได้เฉพาะ build ที่ debug ได้ — ใน release ใครต่อสาย USB ก็อ่าน cl.token ได้ */
fun allowWebDebugging(ctx: Context) {
    WebView.setWebContentsDebuggingEnabled((ctx.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0)
}

private fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) { if (c is Activity) return c; c = c.baseContext }
    return null
}

/**
 * [onOffline] ได้ null = เน็ตหลุด / โหลดหน้าไม่ขึ้น, ได้ข้อความ = เหตุอื่น (เซิร์ฟเวอร์ตอบผิด, หน้าเว็บตาย)
 */
@Composable
fun WebAppScreen(token: String, onSignedOut: () -> Unit, onOffline: (String?) -> Unit) {
    val offline by rememberUpdatedState(onOffline)
    // เปลี่ยนเลขนี้ = ทิ้ง WebView ตัวเดิม สร้างตัวใหม่ โหลด #t= ใหม่
    var generation by remember { mutableStateOf(0) }
    val lastRebuild = remember { longArrayOf(0L) }
    key(generation) {
        WebAppPage(token, onSignedOut, onOffline, onGone = { crashed ->
            // ระบบเก็บตัวเรนเดอร์คืนตอนแอพอยู่เบื้องหลัง (ไม่ได้พัง) → เปิดหน้าใหม่เงียบ ๆ ผู้เล่นกลับมาก็เล่นต่อได้
            // พังเอง หรือโดนเก็บซ้ำติด ๆ กัน (หน่วยความจำไม่พอจริง วนโหลดไปก็ตายอีก) → หน้าออฟไลน์
            val now = SystemClock.elapsedRealtime()
            if (!crashed && (lastRebuild[0] == 0L || now - lastRebuild[0] > 30_000)) { lastRebuild[0] = now; generation++ }
            else offline("หน้าเกมหยุดทำงานกะทันหัน")
        })
    }
}

@SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
@Composable
private fun WebAppPage(token: String, onSignedOut: () -> Unit, onOffline: (String?) -> Unit, onGone: (Boolean) -> Unit) {
    val activity = LocalContext.current.findActivity()
    val signedOut by rememberUpdatedState(onSignedOut)
    val offline by rememberUpdatedState(onOffline)
    val gone by rememberUpdatedState(onGone)
    val chrome = remember { AppChrome(activity) }
    val webRef = remember { arrayOfNulls<WebView>(1) }
    val client = remember { AppClient(offline = { offline(it) }, gone = { webRef[0] = null; gone(it) }) }

    BackHandler {
        val w = webRef[0]
        when {
            chrome.isFullscreen -> chrome.exitFullscreen()
            w == null -> activity?.finish()
            // !! ให้ได้ true/false เสมอ; ได้ "null" แปลว่าหน้าเว็บยังไม่มีหรือพัง → ถือว่าอยู่หน้าบนสุด
            else -> w.evaluateJavascript("window.clBack?!!clBack():false") { r -> if (r != "true") activity?.finish() }
        }
    }

    Box(Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                WebView(ctx).apply {
                    setBackgroundColor(AColor.parseColor("#0B0B0E"))
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    // หน้าเว็บมาจากเน็ตล้วน ๆ ไม่ต้องแตะไฟล์หรือ content provider ในเครื่อง (API ≤29 ค่าเริ่มต้นเปิดอยู่)
                    settings.allowFileAccess = false
                    settings.allowContentAccess = false
                    allowWebDebugging(ctx)
                    webViewClient = client
                    webChromeClient = chrome
                    addJavascriptInterface(CLHost { signedOut() }, "CLHost")
                    webRef[0] = this
                    loadUrl(WEB_APP + "#t=" + Uri.encode(token))
                }
            },
            onRelease = { client.release(); chrome.dismiss(); webRef[0] = null; it.destroy() },
        )
        // หน้ารอเข้าระบบของแอพทับไว้จนหน้าเว็บรับ token แล้ว (หน้าเว็บมีหน้ารอแบบเดียวกันต่อทันที) จะได้ไม่เห็นจอดำเปล่าคั่นกลาง
        if (!client.ready) SplashBody()
    }
}
