package dev.mini.candlelight

import android.annotation.SuppressLint
import android.graphics.Color as AColor
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

/**
 * The board page ships inside the APK, so it opens with no network round-trip and works offline.
 * It used to be fetched from the Worker's /board; the Worker copy is now only a fallback, and updating
 * the board means shipping a build rather than deploying the Worker.
 */
const val BOARD_ASSET = "file:///android_asset/board.html"

/** Bridge the board page calls (window.Android.*). Callbacks run on a WebView thread → hop to main. */
class BoardBridge(
    private val onMove: (Double, Double) -> Unit,
    private val onTapToken: (String) -> Unit,
    private val onReady: () -> Unit,
) {
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    @JavascriptInterface fun move(x: Double, z: Double) { main.post { onMove(x, z) } }
    @JavascriptInterface fun tapToken(id: String) { main.post { onTapToken(id) } }
    @JavascriptInterface fun ready() { main.post { onReady() } }
    @JavascriptInterface fun log(s: String) { android.util.Log.d("Board", s) }
}

/** Holder so callers can push JS into the page once it is ready. */
class BoardController {
    var web: WebView? = null
    var ready: Boolean = false
    @Volatile var lastError: String? = null
    /** human-readable loading status shown on top of the board until the page reports ready */
    var status = mutableStateOf<String?>("เริ่มโหลดกระดาน…")
    private val queue = ArrayList<String>()
    fun call(js: String) {
        val w = web
        if (w == null || !ready) { queue.add(js); return }
        w.post { w.evaluateJavascript(js, null) }
    }
    fun flush() { ready = true; status.value = null; val w = web ?: return; val q = ArrayList(queue); queue.clear(); w.post { q.forEach { w.evaluateJavascript(it, null) } } }
    /** set once the Worker copy has been tried, so a second failure cannot bounce between the two forever */
    var usedServer: Boolean = false
    fun reload() { ready = false; usedServer = false; status.value = "โหลดใหม่…"; web?.post { web?.loadUrl(BOARD_ASSET) } }
    private var inset = -1
    /** dp (= CSS px) of app UI covering the bottom of the board; the page parks the joystick just above it */
    fun setInset(dp: Int) { if (dp != inset) { inset = dp; call("window.setInset && window.setInset($dp)") } }
}

private fun jsStr(s: String): String = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun BoardView(
    modifier: Modifier = Modifier,
    controller: BoardController,
    onMove: (Double, Double) -> Unit = { _, _ -> },
    onTapToken: (String) -> Unit = {},
) {
    val bridge = remember { BoardBridge(onMove, onTapToken) { controller.flush() } }
    val status by controller.status
    Box(modifier) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                WebView(ctx).apply {
                    setBackgroundColor(AColor.parseColor("#0B0B0E"))
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.allowFileAccess = true
                    settings.mediaPlaybackRequiresUserGesture = false
                    settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                    settings.cacheMode = android.webkit.WebSettings.LOAD_NO_CACHE
                    settings.useWideViewPort = true
                    settings.loadWithOverviewMode = true
                    WebView.setWebContentsDebuggingEnabled(true)
                    webViewClient = object : WebViewClient() {
                        override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) { if (!controller.ready) controller.status.value = "กำลังเปิดกระดาน…" }
                        override fun onPageFinished(view: WebView?, url: String?) { if (!controller.ready) controller.status.value = "โหลดหน้าเสร็จ รอสคริปต์วาด…" }
                        override fun onReceivedError(view: WebView?, request: android.webkit.WebResourceRequest?, error: android.webkit.WebResourceError?) {
                            if (request?.isForMainFrame != true) return
                            // the page is bundled, so this should not happen — but rather than sit on a dead board, try the Worker copy once
                            if (!controller.usedServer) {
                                controller.usedServer = true
                                controller.status.value = "ใช้สำเนาบนเซิร์ฟเวอร์…"
                                view?.loadUrl(SERVER + "/board")
                                return
                            }
                            controller.lastError = "โหลดกระดานไม่ได้: ${error?.description}"; controller.status.value = controller.lastError
                        }
                        override fun onReceivedHttpError(view: WebView?, request: android.webkit.WebResourceRequest?, errorResponse: android.webkit.WebResourceResponse?) {
                            if (request?.isForMainFrame == true) { controller.lastError = "เซิร์ฟเวอร์ตอบ HTTP ${errorResponse?.statusCode}"; controller.status.value = controller.lastError }
                        }
                    }
                    webChromeClient = object : android.webkit.WebChromeClient() {
                        override fun onProgressChanged(view: WebView?, newProgress: Int) { if (!controller.ready && newProgress < 100) controller.status.value = "กำลังโหลด $newProgress%" }
                        override fun onConsoleMessage(m: android.webkit.ConsoleMessage?): Boolean {
                            m?.let { android.util.Log.d("BoardJS", "${it.messageLevel()} ${it.message()} @${it.lineNumber()}"); if (it.messageLevel() == android.webkit.ConsoleMessage.MessageLevel.ERROR) { controller.lastError = it.message(); controller.status.value = "JS: " + it.message() } }
                            return true
                        }
                    }
                    addJavascriptInterface(bridge, "Android")
                    controller.web = this
                    loadUrl(BOARD_ASSET)
                }
            },
            onRelease = { controller.web = null; controller.ready = false },
        )
        if (status != null) {
            Text(status!!, color = Color(0xFF6F6C78), fontSize = 11.sp, fontFamily = FontFamily.Monospace,
                modifier = Modifier.align(Alignment.TopStart).padding(8.dp).background(Color(0xCC141419)).padding(6.dp, 3.dp))
        }
    }
}

/** Convenience wrappers */
fun BoardController.setBoard(json: String) = call("window.setBoard && window.setBoard(${jsStr(json)})")
fun BoardController.setMe(id: String) = call("window.setMe && window.setMe(${jsStr(id)})")
fun BoardController.setControl(mode: String) = call("window.setControl && window.setControl(${jsStr(mode)})")
fun BoardController.setPreview(lookJson: String) = call("window.setPreview && window.setPreview(${jsStr(lookJson)})")
fun BoardController.focusMe() = call("window.focusMe && window.focusMe()")
/** Throw a die on the board. The page seeds the tumble from [seq], so the same roll looks the same on every phone. */
fun BoardController.showRoll(seq: Int, who: String, die: Int, value: Int, mine: Boolean) =
    call("window.showRoll && window.showRoll($seq, ${jsStr(who)}, $die, $value, $mine)")

/** Re-push state whenever the board changes. */
@Composable
fun BoardSync(controller: BoardController, me: String?, board: Board?, control: String) {
    LaunchedEffect(me) { if (me != null) controller.setMe(me) }
    LaunchedEffect(control) { controller.setControl(control) }
    LaunchedEffect(board?.seq, board?.json?.length) { if (board != null) controller.setBoard(board.json) }
}
