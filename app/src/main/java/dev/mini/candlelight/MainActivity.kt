package dev.mini.candlelight

import android.annotation.SuppressLint
import android.content.Context
import android.os.Bundle
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.io.IOException

// ---------------------------------------------------------------- palette
// ค่าเดียวกับ :root ของหน้าเว็บ /app — ล็อกอินเสร็จ หน้าเว็บขึ้นต่อในกรอบเดียวกันทันที สีจึงต้องไม่กระโดด
val Ground = Color(0xFF0B0B0E)    // --bg
val Surface = Color(0xFF121217)   // --panel
val Raised = Color(0xFF16161C)    // --panel-2
val Well = Color(0xFF0F0F14)      // --well
val Line = Color(0xFF26262E)      // --line
val Ink = Color(0xFFE8E2D4)       // --ink-hi
val Muted = Color(0xFF8A8579)     // --dim
val Amber = Color(0xFFE0B26A)     // --amber
val Teal = Color(0xFF6FB3A8)      // --teal
val Blood = Color(0xFFC46A5A)     // --bad

/** พื้นหลังแถบภาพบนการ์ด เข้มกว่าพื้นการ์ดหนึ่งขั้น — .pic .art ของเว็บ */
val ArtBand = Color(0xFF0D0D11)

// ---------------------------------------------------------------- session
/** ของที่แอพจำเอง: token กับชื่อที่ใช้ตอนเข้าแบบผู้เล่นรับเชิญ ส่วนโต๊ะ ตัวละคร หน้าตา หน้าเว็บเก็บใน localStorage ของมัน */
class Session(ctx: Context) {
    private val p = ctx.getSharedPreferences("session", Context.MODE_PRIVATE)
    var name: String get() = p.getString("name", "") ?: ""; set(v) { p.edit().putString("name", v).apply() }
    var token: String? get() = p.getString("token", null); set(v) { p.edit().putString("token", v).apply() }
    // userName/userSub/guest/code/pid เป็นของแอพรุ่นก่อน (ตอนหน้าจอ D&D ยังเป็น native) ไม่มีใครอ่านแล้ว ลบทิ้งไปด้วยตอนออก
    // look (หน้าตาตัวละครจากตัวแก้ไขเดิมของแอพ) จงใจเก็บไว้ เผื่อรุ่นหน้าส่งต่อให้หน้าเว็บได้ — ตอนนี้หน้าเว็บยังไม่มีช่องรับ
    fun signOut() { p.edit().remove("token").remove("userName").remove("userSub").remove("guest").remove("code").remove("pid").apply() }
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // แถบระบบสีเดียวกับพื้นหน้าเว็บ ไม่งั้นเห็นรอยต่อตรงขอบบน/ล่าง
        window.statusBarColor = Ground.toArgb()
        window.navigationBarColor = Ground.toArgb()
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Amber, onPrimary = Color(0xFF1A1408), background = Ground, surface = Surface,
                    onBackground = Ink, onSurface = Ink, secondary = Teal, error = Blood, outline = Line,
                    surfaceVariant = Raised, onSurfaceVariant = Muted,
                )
            ) { App(Session(this)) }
        }
    }
}

/**
 * หน้าจอของตัวแอพเหลือแค่นี้ ที่เหลือทั้งหมดอยู่ในหน้าเว็บ /app:
 *   ไม่มี token → login ; มี token ตอนเปิดแอพ → splash (ตรวจ token) → web
 *   web โหลดไม่ขึ้น / เน็ตหลุดตอน splash → offline → tabletop (โต๊ะรบในแอพ เล่นกับบอทได้ไม่ต้องต่อเน็ต)
 */
@Composable
fun App(session: Session) {
    val scope = rememberCoroutineScope()
    var token by remember { mutableStateOf(session.token) }
    var screen by rememberSaveable { mutableStateOf("splash") }
    // ข้อความที่พกไปหน้าถัดไป: ทำไมต้องล็อกอินใหม่ หรือทำไมถึงออฟไลน์
    var note by rememberSaveable { mutableStateOf<String?>(null) }
    Api.authToken = token
    fun signOut(why: String?) { session.signOut(); Api.authToken = null; token = null; note = why; screen = "splash" }
    Box(Modifier.fillMaxSize().background(Ground)) {
        val t = token
        when {
            // โต๊ะรบอยู่ในแอพ ไม่ต้องล็อกอิน ไม่ต้องต่อเน็ต — เปิดได้จากหน้าออฟไลน์ หรือจากหน้าล็อกอินตอนเน็ตหลุด
            screen == "tabletop" -> TabletopScreen(onBack = { screen = "offline" })
            t == null -> LoginScreen(session, note,
                onLoggedIn = { token = it; note = null; screen = "web" },
                onTabletop = { screen = "tabletop" })
            screen == "splash" -> SplashScreen(
                onValid = { screen = "web" },
                onSignedOut = {
                    // token ตายก่อนหน้าเว็บได้เห็น หน้าเว็บจึงไม่ได้ล้างของตัวเอง: cl.code/cl.pid ยังชี้ที่นั่งของบัญชีเก่า
                    // บัญชีถัดไปที่ล็อกอินจะเด้งเข้าที่นั่งนั้นแล้วโดน 403 ทุกคำสั่ง → ล้างที่เก็บของ WebView ทิ้งทั้งหมด
                    // (มีแค่ของหน้าเว็บ /app — battle-table.html ในแอพไม่ได้เก็บอะไร) หน้าตาตัวละครใน cl.sheet หายไปด้วย
                    WebStorage.getInstance().deleteAllData()
                    signOut(it)
                },
                onOffline = { note = null; screen = "offline" })
            screen == "offline" -> OfflineScreen(note,
                onTabletop = { screen = "tabletop" },
                onRetry = { note = null; screen = "splash" })
            else -> WebAppScreen(t,
                onSignedOut = {
                    // หน้าเว็บยิง /api/logout แบบไม่รอผลแล้วเรียกเราทันที WebView ถูกทิ้งในเฟรมถัดไป คำขอนั้นอาจโดนตัดกลางทาง
                    // → ปิด session ซ้ำจากฝั่งแอพ (ปิดไปแล้วก็ไม่เป็นไร)
                    scope.launch { try { Api.logout(t) } catch (e: Exception) { } }
                    signOut(null)
                },
                onOffline = { note = it; screen = "offline" })
        }
    }
}

// ---------------------------------------------------------------- ชิ้นส่วนที่ใช้ร่วมกัน (ชุดเดียวกับหน้าเว็บ /app)

/**
 * คอลัมน์กลางจอแบบหน้าล็อกอินของเว็บ: กว้างไม่เกิน 360dp มีแสงเทียนจาง ๆ ลงมาจากขอบบน (body::before ของเว็บ)
 * สั้นกว่าจอก็อยู่กลางจอ ยาวกว่าจอ (คีย์บอร์ดขึ้น, เปิดช่องรหัสจับคู่) ก็เลื่อนได้
 */
@Composable
private fun CenterColumn(content: @Composable ColumnScope.() -> Unit) {
    BoxWithConstraints(
        Modifier.fillMaxSize().background(Ground).drawBehind {
            drawRect(
                Brush.radialGradient(
                    listOf(Amber.copy(alpha = 0.075f), Color.Transparent),
                    center = Offset(size.width / 2f, -size.height * 0.12f),
                    radius = size.maxDimension * 0.62f,
                )
            )
        }.statusBarsPadding().navigationBarsPadding()
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight)
                .padding(horizontal = 16.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Column(Modifier.widthIn(max = 360.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, content = content)
        }
    }
}

/** เทียนใหญ่มีรัศมีแสง + ชื่อแอพ — หัวของหน้าล็อกอิน หน้ารอเข้าระบบ และหน้าออฟไลน์ */
@Composable
private fun CandleMark() {
    Box(
        Modifier.size(132.dp, 150.dp).drawBehind {
            drawCircle(
                Brush.radialGradient(listOf(Amber.copy(alpha = 0.14f), Color.Transparent), center = Offset(size.width / 2f, size.height * 0.34f), radius = size.width / 2f),
                radius = size.width / 2f, center = Offset(size.width / 2f, size.height * 0.34f),
            )
        },
        contentAlignment = Alignment.Center,
    ) { Illustration(Arts.candle, Modifier.size(56.dp, 94.dp), alpha = 1f) }
    Spacer(Modifier.height(6.dp))
    Text("CANDLELIGHT TABLE", color = Amber, fontSize = 13.sp, letterSpacing = 3.sp, fontFamily = FontFamily.Monospace, maxLines = 1)
}

/** เทียน + วงหมุน + "กำลังเข้าสู่ระบบ…" — หน้าเว็บมีหน้าเดียวกันนี้ ต่อกันแล้วไม่สะดุด */
@Composable
fun SplashBody() {
    CenterColumn {
        CandleMark()
        Spacer(Modifier.height(36.dp))
        CircularProgressIndicator(color = Amber, strokeWidth = 2.dp, trackColor = Color.Transparent, modifier = Modifier.size(28.dp))
        Spacer(Modifier.height(14.dp))
        Text("กำลังเข้าสู่ระบบ…", color = Muted, fontSize = 14.sp)
    }
}

@Composable fun fieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = Amber, unfocusedBorderColor = Line, focusedTextColor = Ink, unfocusedTextColor = Ink,
    focusedLabelColor = Amber, unfocusedLabelColor = Muted, cursorColor = Amber, focusedContainerColor = Well, unfocusedContainerColor = Well,
)

// ---------------------------------------------------------------- splash: มี token อยู่แล้ว ตรวจก่อนค่อยเปิดหน้าเว็บ

@Composable
fun SplashScreen(onValid: () -> Unit, onSignedOut: (String?) -> Unit, onOffline: () -> Unit) {
    LaunchedEffect(Unit) {
        try {
            Api.me()
            onValid()
        } catch (e: CancellationException) {
            throw e
        } catch (e: ApiException) {
            // token ตายจริง → ล็อกอินใหม่; เซิร์ฟเวอร์แค่สะดุด (5xx, ถี่ไป) → เข้าหน้าเว็บไปเลย ให้หน้าเว็บบอกเอง
            if (e.fatalAuth) onSignedOut(e.message) else onValid()
        } catch (e: IOException) {
            onOffline()                                  // ไม่มีเน็ต / ต่อเซิร์ฟเวอร์ไม่ได้ — token ยังเก็บไว้
        } catch (e: Exception) {
            onValid()
        }
    }
    SplashBody()
}

// ---------------------------------------------------------------- login
/** ปุ่ม Google ในแบบ filled_black ของ GIS (ปุ่มของหน้าเว็บใช้ใน WebView ไม่ได้ Google บล็อก) + ลิงก์ผู้เล่นรับเชิญ */
@Composable
fun LoginScreen(session: Session, note: String?, onLoggedIn: (String) -> Unit, onTabletop: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(note) }
    // เข้าไม่สำเร็จ (เน็ตหลุด, Google ในเครื่องใช้ไม่ได้ ฯลฯ): ยังเล่นโต๊ะรบกับบอทได้ เพราะหน้านั้นอยู่ในแอพ
    // Google ตอนไม่มีเน็ตโยน GetCredentialException ไม่ใช่ IOException จึงดูแค่ว่าไม่สำเร็จ ไม่แยกว่าเพราะเน็ต
    var failed by remember { mutableStateOf(false) }
    var pairOpen by remember { mutableStateOf(false) }

    fun finish(tok: String, user: User) {
        session.token = tok
        if (session.name.isBlank()) session.name = user.name
        Api.authToken = tok
        onLoggedIn(tok)
    }

    CenterColumn {
        CandleMark()
        Spacer(Modifier.height(10.dp))
        Text("โต๊ะผจญภัยที่ Claude เป็นผู้เล่าเรื่อง", color = Muted, fontSize = 14.sp, textAlign = TextAlign.Center)
        Spacer(Modifier.height(36.dp))
        Button(
            onClick = {
                busy = true; error = null; failed = false
                scope.launch {
                    try {
                        val cm = CredentialManager.create(context)
                        val option = GetSignInWithGoogleOption.Builder(WEB_CLIENT_ID).build()
                        val req = GetCredentialRequest.Builder().addCredentialOption(option).build()
                        val result = cm.getCredential(context, req)
                        val cred = result.credential
                        if (cred is CustomCredential && cred.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                            val idToken = GoogleIdTokenCredential.createFrom(cred.data).idToken
                            val (tok, user) = Api.loginGoogle(idToken)
                            finish(tok, user)
                        } else { error = "ไม่ได้รับข้อมูลจาก Google"; failed = true }
                    } catch (e: GetCredentialCancellationException) {
                        error = null
                    } catch (e: ApiException) {
                        error = e.message; failed = true
                    } catch (e: IOException) {
                        error = "ต่อเซิร์ฟเวอร์ไม่ได้ — ตรวจอินเทอร์เน็ตแล้วลองใหม่"; failed = true
                    } catch (e: Exception) {
                        error = "เข้าสู่ระบบด้วย Google ไม่สำเร็จ: " + (e.message ?: e.javaClass.simpleName); failed = true
                    } finally { busy = false }
                }
            },
            enabled = !busy, modifier = Modifier.fillMaxWidth().height(48.dp), shape = RoundedCornerShape(4.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF202124), contentColor = Color.White),
            contentPadding = PaddingValues(start = 8.dp, end = 16.dp),
        ) {
            Box(Modifier.size(32.dp).clip(CircleShape).background(Color.White), contentAlignment = Alignment.Center) {
                GoogleMark(Modifier.size(18.dp))
            }
            Text(
                if (busy) "กำลังเข้าสู่ระบบ…" else "ลงชื่อเข้าใช้ด้วย Google",
                fontSize = 15.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center, maxLines = 1,
                modifier = Modifier.weight(1f),
            )
        }
        Spacer(Modifier.height(10.dp))
        TextButton(
            onClick = {
                busy = true; error = null; failed = false
                scope.launch {
                    try {
                        val (tok, user) = Api.loginGuest(session.name)
                        finish(tok, user)
                    } catch (e: ApiException) {
                        error = e.message; failed = true
                    } catch (e: IOException) {
                        error = "ต่อเซิร์ฟเวอร์ไม่ได้ — ตรวจอินเทอร์เน็ตแล้วลองใหม่"; failed = true
                    } catch (e: Exception) {
                        error = "เล่นแบบผู้เล่นรับเชิญไม่สำเร็จ: " + (e.message ?: e.javaClass.simpleName); failed = true
                    } finally { busy = false }
                }
            },
            enabled = !busy, modifier = Modifier.heightIn(min = 44.dp),
        ) { Text("เข้าเล่นแบบผู้เล่นรับเชิญ", color = Ink, fontSize = 14.sp, textDecoration = TextDecoration.Underline) }
        Text(
            "ผู้เล่นรับเชิญผูกกับเครื่องนี้เท่านั้น ลบแอพแล้วจะหายถาวร",
            color = Muted, fontSize = 12.sp, lineHeight = 18.sp, textAlign = TextAlign.Center,
        )
        error?.let {
            Spacer(Modifier.height(12.dp))
            Text(it, color = Blood, fontSize = 13.sp, lineHeight = 19.sp, textAlign = TextAlign.Center)
        }
        if (failed) TextButton(onClick = onTabletop, modifier = Modifier.heightIn(min = 44.dp)) {
            Text("เล่นโต๊ะรบกับบอทแบบออฟไลน์ ›", color = Amber, fontSize = 14.sp)
        }
        Spacer(Modifier.height(20.dp))
        TextButton(onClick = { pairOpen = !pairOpen }, modifier = Modifier.heightIn(min = 44.dp)) {
            Text((if (pairOpen) "▾ " else "▸ ") + "มีรหัสจับคู่เครื่อง?", color = Muted, fontSize = 13.sp)
        }
        if (pairOpen) PairClaim(enabled = !busy) { tok, user -> finish(tok, user) }
    }
}

/** ตัว G สี่สีบนปุ่ม Google — วาดเองด้วยวงโค้งสี่ท่อนกับขีดขวาง */
@Composable
private fun GoogleMark(modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val w = size.minDimension * 0.22f                 // ความหนาเส้น
        val r = size.minDimension / 2f - w / 2f
        val tl = Offset(size.width / 2f - r, size.height / 2f - r)
        val box = Size(2f * r, 2f * r)
        fun arc(c: Color, start: Float, sweep: Float) = drawArc(c, start, sweep, false, tl, box, style = Stroke(w))
        arc(Color(0xFFEA4335), 200f, 125f)                  // แดง ด้านบน
        arc(Color(0xFFFBBC05), 145f, 60f)                   // เหลือง ด้านซ้าย
        arc(Color(0xFF34A853), 35f, 115f)                   // เขียว ด้านล่าง
        arc(Color(0xFF4285F4), -5f, 45f)                    // น้ำเงิน ด้านขวา
        drawRect(Color(0xFF4285F4), Offset(size.width / 2f, size.height / 2f - w / 2f), Size(r + w / 2f, w))
    }
}

/** ยังไม่มีบัญชีในเครื่องนี้ แต่มีในอีกเครื่อง เอารหัสจับคู่มาแลกเป็นบัญชีเดียวกัน — พับไว้ใต้ปุ่ม เหมือนหน้าเว็บ */
@Composable
private fun PairClaim(enabled: Boolean, onDone: (String, User) -> Unit) {
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    val clean = code.filter { it.isLetterOrDigit() }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "ในเครื่องที่ล็อกอินอยู่ กด “เชื่อมบัญชีกับอีกเครื่อง” แล้วเอารหัส 8 ตัวมาใส่ตรงนี้ · รหัสอายุ 5 นาที ใช้ได้ครั้งเดียว",
            color = Muted, fontSize = 12.sp, lineHeight = 18.sp,
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = code,
                onValueChange = { v -> code = v.uppercase().filter { it.isLetterOrDigit() || it == '-' }.take(9) },
                modifier = Modifier.weight(1f),
                singleLine = true,
                enabled = enabled && !busy,
                placeholder = { Text("รหัสจับคู่ 8 ตัว", color = Muted, fontSize = 13.sp) },
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace, letterSpacing = 2.sp),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                shape = RoundedCornerShape(8.dp),
                colors = fieldColors(),
            )
            Button(
                onClick = {
                    busy = true; err = null
                    scope.launch {
                        try {
                            val (tok, user) = Api.pairClaim(clean)
                            onDone(tok, user)
                        } catch (e: ApiException) {
                            err = e.message
                        } catch (e: Exception) {
                            err = "เชื่อมไม่สำเร็จ: " + (e.message ?: e.javaClass.simpleName)
                        } finally { busy = false }
                    }
                },
                enabled = enabled && !busy && clean.length == 8,
                modifier = Modifier.height(56.dp), shape = RoundedCornerShape(8.dp),
            ) { Text(if (busy) "…" else "เชื่อม", fontWeight = FontWeight.Bold, fontSize = 15.sp) }
        }
        err?.let { Text(it, color = Blood, fontSize = 12.sp, lineHeight = 17.sp) }
    }
}

// ---------------------------------------------------------------- offline: หน้าเว็บโหลดไม่ขึ้น แต่โต๊ะรบอยู่ในแอพ

@Composable
fun OfflineScreen(why: String?, onTabletop: () -> Unit, onRetry: () -> Unit) {
    CenterColumn {
        CandleMark()
        Spacer(Modifier.height(24.dp))
        Text(
            (why ?: "ไม่มีอินเทอร์เน็ต") + " — เล่นโต๊ะรบกับบอทได้",
            color = Ink, fontSize = 17.sp, fontWeight = FontWeight.Bold, lineHeight = 25.sp, textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(20.dp))
        // การ์ดเดียวกับ TABLETOP ในหน้าเลือกเกมของเว็บ ย่อลงเหลือที่ใช้ได้ตอนไม่มีเน็ต
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Surface).border(1.dp, Line, RoundedCornerShape(14.dp))
        ) {
            Box(
                Modifier.fillMaxWidth().height(120.dp).drawBehind {
                    drawRect(ArtBand)
                    drawRect(
                        Brush.radialGradient(
                            listOf(Amber.copy(alpha = 0.10f), Color.Transparent),
                            center = Offset(size.width / 2f, size.height),
                            radius = size.width * 0.62f,
                        )
                    )
                },
                contentAlignment = Alignment.Center,
            ) { Illustration(Arts.mini, Modifier.fillMaxSize().padding(12.dp)) }
            HorizontalDivider(color = Line)
            Column(Modifier.padding(start = 18.dp, top = 16.dp, end = 18.dp, bottom = 18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("TABLETOP", color = Amber, fontSize = 20.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                Text("จำลองการรบบนโต๊ะสามมิติ — จัดทัพ เลือกจุดลงสนาม แล้วผลัดกันเดินกับยิง เล่นกับบอทได้แม้ไม่มีเน็ต",
                    color = Ink, fontSize = 14.sp, lineHeight = 21.sp)
                Spacer(Modifier.height(4.dp))
                Button(onClick = onTabletop, modifier = Modifier.fillMaxWidth().height(48.dp), shape = RoundedCornerShape(8.dp)) {
                    Text("เล่นโต๊ะรบกับบอท ›", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        OutlinedButton(
            onClick = onRetry, modifier = Modifier.fillMaxWidth().height(48.dp), shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink), border = androidx.compose.foundation.BorderStroke(1.dp, Line),
        ) { Text("ลองใหม่", fontSize = 15.sp) }
    }
}

// ---------------------------------------------------------------- tabletop: the bundled 3D page

@Composable
fun TabletopScreen(onBack: () -> Unit) {
    // ไม่มีหน้าเลือกเครื่องมือแล้ว — กดเทเบิลท็อปแล้วเข้าโต๊ะรบเลย
    BackHandler(enabled = true) { onBack() }
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().background(Ground).padding(8.dp, 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ กลับ", color = Amber, fontSize = 14.sp) }
            Text("TABLETOP", color = Muted, fontSize = 12.sp, letterSpacing = 2.sp, fontFamily = FontFamily.Monospace)
        }
        AssetPage("battle-table.html", Modifier.weight(1f).fillMaxWidth())
    }
}

/** A bundled page on its own, with no bridge: battle-table.html never calls back into the app. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun AssetPage(asset: String, modifier: Modifier = Modifier) {
    AndroidView(modifier = modifier, factory = { ctx ->
        WebView(ctx).apply {
            setBackgroundColor(android.graphics.Color.parseColor("#0B0B0E"))
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = true
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            webViewClient = WebViewClient()
            allowWebDebugging(ctx)
            loadUrl("file:///android_asset/$asset")
        }
    }, onRelease = { it.destroy() })
}
