package dev.mini.candlelight

import android.annotation.SuppressLint
import android.graphics.Color as AColor
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

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
    private val queue = ArrayList<String>()
    fun call(js: String) {
        val w = web
        if (w == null || !ready) { queue.add(js); return }
        w.post { w.evaluateJavascript(js, null) }
    }
    fun flush() { ready = true; val w = web ?: return; val q = ArrayList(queue); queue.clear(); w.post { q.forEach { w.evaluateJavascript(it, null) } } }
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
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            WebView(ctx).apply {
                setBackgroundColor(AColor.parseColor("#0B0B0E"))
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.allowFileAccess = true
                settings.mediaPlaybackRequiresUserGesture = false
                webViewClient = WebViewClient()
                addJavascriptInterface(bridge, "Android")
                controller.web = this
                loadUrl("file:///android_asset/board.html")
            }
        },
        onRelease = { controller.web = null; controller.ready = false },
    )
}

/** Convenience wrappers */
fun BoardController.setBoard(json: String) = call("window.setBoard && window.setBoard(${jsStr(json)})")
fun BoardController.setMe(id: String) = call("window.setMe && window.setMe(${jsStr(id)})")
fun BoardController.setControl(mode: String) = call("window.setControl && window.setControl(${jsStr(mode)})")
fun BoardController.setPreview(lookJson: String) = call("window.setPreview && window.setPreview(${jsStr(lookJson)})")
fun BoardController.focusMe() = call("window.focusMe && window.focusMe()")

/** Re-push state whenever the board changes. */
@Composable
fun BoardSync(controller: BoardController, me: String?, board: Board?, control: String) {
    LaunchedEffect(me) { if (me != null) controller.setMe(me) }
    LaunchedEffect(control) { controller.setControl(control) }
    LaunchedEffect(board?.seq, board?.json?.length) { if (board != null) controller.setBoard(board.json) }
}
