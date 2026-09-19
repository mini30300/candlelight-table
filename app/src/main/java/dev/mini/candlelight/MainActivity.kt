package dev.mini.candlelight

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import android.annotation.SuppressLint
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.key
import androidx.compose.ui.viewinterop.AndroidView
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Casino
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

// ---------------------------------------------------------------- palette
val Ground = Color(0xFF16141C)
val Surface = Color(0xFF211E29)
val Raised = Color(0xFF2B2735)
val Line = Color(0xFF3A3446)
val Ink = Color(0xFFECE5D4)
val Muted = Color(0xFF9C94A8)
val Amber = Color(0xFFE3A83C)
val AmberDim = Color(0xFF8A6420)
val Teal = Color(0xFF55B7AD)
val Blood = Color(0xFFC74A3D)

val ABIL = listOf("STR", "DEX", "CON", "INT", "WIS", "CHA")
val RACES = listOf("Human", "Elf", "Dwarf", "Halfling", "Tiefling", "Dragonborn")
val CLASSES = listOf("Fighter", "Wizard", "Rogue", "Cleric", "Ranger", "Bard", "Paladin")
val CLASS_HP = mapOf("Fighter" to 10, "Paladin" to 10, "Ranger" to 10, "Cleric" to 8, "Rogue" to 8, "Bard" to 8, "Wizard" to 6)

fun roll4d6(): Int = List(4) { (1..6).random() }.sorted().drop(1).sum()
fun mod(v: Int): String { val m = Math.floorDiv(v - 10, 2); return if (m >= 0) "+$m" else "$m" }

// ---------------------------------------------------------------- session
class Session(ctx: Context) {
    private val p = ctx.getSharedPreferences("session", Context.MODE_PRIVATE)
    var code: String? get() = p.getString("code", null); set(v) { p.edit().putString("code", v).apply() }
    var playerId: String? get() = p.getString("pid", null); set(v) { p.edit().putString("pid", v).apply() }
    var name: String get() = p.getString("name", "") ?: ""; set(v) { p.edit().putString("name", v).apply() }
    var token: String? get() = p.getString("token", null); set(v) { p.edit().putString("token", v).apply() }
    var userName: String get() = p.getString("userName", "") ?: ""; set(v) { p.edit().putString("userName", v).apply() }
    var userSub: String? get() = p.getString("userSub", null); set(v) { p.edit().putString("userSub", v).apply() }
    var look: String? get() = p.getString("look", null); set(v) { p.edit().putString("look", v).apply() }
    var control: String get() = p.getString("control", "tap") ?: "tap"; set(v) { p.edit().putString("control", v).apply() }
    fun clear() { p.edit().remove("code").remove("pid").apply() }
    fun signOut() { p.edit().remove("token").remove("userName").remove("userSub").remove("code").remove("pid").apply() }
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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

@Composable
fun App(session: Session) {
    var token by remember { mutableStateOf(session.token) }
    var code by remember { mutableStateOf(session.code) }
    var playerId by remember { mutableStateOf(session.playerId) }
    // what the player picked after logging in; null means the pick has not been made this launch
    var play by remember { mutableStateOf<String?>(null) }
    Api.authToken = token
    Box(Modifier.fillMaxSize().background(Ground)) {
        when {
            token == null -> LoginScreen(session) { token = it }
            // already sitting at a table: go straight back to it rather than asking again
            code != null && playerId != null ->
                GameScreen(code!!, playerId!!, mySub = session.userSub, session = session, onLeave = { session.clear(); code = null; playerId = null })
            play == null -> PickPlayScreen(session, onPick = { play = it },
                onSignOut = { session.signOut(); Api.authToken = null; token = null; play = null })
            play == "tabletop" -> TabletopScreen(onBack = { play = null })
            else -> LobbyScreen(session,
                onEnter = { c, p -> session.code = c; session.playerId = p; code = c; playerId = p },
                onSignOut = { session.signOut(); Api.authToken = null; token = null; play = null },
                onBack = { play = null })
        }
    }
}

// ---------------------------------------------------------------- pick what to play
@Composable
fun PickPlayScreen(session: Session, onPick: (String) -> Unit, onSignOut: () -> Unit) {
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("CANDLELIGHT TABLE", color = Amber, fontSize = 13.sp, letterSpacing = 3.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.weight(1f))
            Text(session.userName, color = Muted, fontSize = 12.sp)
            TextButton(onClick = { scope.launch { Api.logout(); onSignOut() } }, contentPadding = PaddingValues(6.dp, 0.dp)) { Text("ออกจากระบบ", color = Muted, fontSize = 12.sp) }
        }
        Text("จะเล่นอะไรดี", color = Ink, fontSize = 26.sp, fontWeight = FontWeight.Bold, lineHeight = 32.sp)
        PickCard("D&D", "เล่นกับเพื่อน มี Claude เป็นผู้เล่าเรื่อง สร้างตัวละคร นั่งลงที่โต๊ะ ทอยเต๋า",
            "ต้องต่ออินเทอร์เน็ต") { onPick("dnd") }
        PickCard("เทเบิลท็อป", "โต๊ะรบสามมิติ แผนที่โลก ถาดลูกเต๋า วางหน่วยแล้วสั่งให้เดิน วัดระยะเป็นนิ้ว",
            "เล่นคนเดียว ไม่ต้องต่อเน็ต") { onPick("tabletop") }
        Spacer(Modifier.height(4.dp))
    }
}

@Composable
private fun PickCard(title: String, body: String, foot: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Surface).border(1.dp, Line, RoundedCornerShape(12.dp))
        .clickable { onClick() }.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, color = Amber, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Text(body, color = Ink, fontSize = 14.sp, lineHeight = 21.sp)
        Text(foot, color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
    }
}

// ---------------------------------------------------------------- tabletop: the bundled 3D pages
/** asset file, name, one line about it */
private val TOOLS = listOf(
    Triple("battle-table.html", "โต๊ะรบ", "วางหน่วย ลากให้เดินจริง วัดระยะเป็นนิ้ว หมุนกล้องรอบโต๊ะ"),
    Triple("worldmap.html", "แผนที่โลก", "แผนที่ยุทธศาสตร์สุ่ม ไม่มีขอบ ซูมได้ไม่จำกัด"),
    Triple("dice-tray.html", "ถาดลูกเต๋า", "d4–d20 ฟิสิกส์จริง นับผลแบบ 40k"),
    Triple("skeleton-rig-v4.html", "โครงกระดูก", "หน้าจูนท่าเดิน–วิ่ง–ตี และชุดเกราะ 3 แบบ"),
)

@Composable
fun TabletopScreen(onBack: () -> Unit) {
    var open by remember { mutableStateOf<String?>(null) }
    BackHandler(enabled = true) { if (open != null) open = null else onBack() }
    if (open != null) {
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            Row(Modifier.fillMaxWidth().background(Ground).padding(8.dp, 4.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { open = null }) { Text("‹ กลับ", color = Amber, fontSize = 14.sp) }
                Text(TOOLS.first { it.first == open }.second, color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
            }
            // keyed so switching pages builds a fresh WebView instead of leaving the old one loaded
            key(open) { AssetPage(open!!, Modifier.weight(1f).fillMaxWidth()) }
        }
        return
    }
    Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack, contentPadding = PaddingValues(0.dp, 0.dp)) { Text("‹ กลับ", color = Muted, fontSize = 13.sp) }
            Spacer(Modifier.weight(1f))
        }
        Text("เทเบิลท็อป", color = Ink, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text("ทุกหน้าอยู่ในแอพแล้ว เปิดได้โดยไม่ต้องต่อเน็ต", color = Muted, fontSize = 13.sp)
        TOOLS.forEach { (asset, title, body) -> PickCard(title, body, asset) { open = asset } }
        Spacer(Modifier.height(4.dp))
    }
}

/** A bundled page on its own, with no bridge: none of the 3D pages calls back into the app. */
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
            WebView.setWebContentsDebuggingEnabled(true)
            loadUrl("file:///android_asset/$asset")
        }
    }, onRelease = { it.destroy() })
}

// ---------------------------------------------------------------- login
@Composable
fun LoginScreen(session: Session, onLoggedIn: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Column(Modifier.fillMaxSize().statusBarsPadding().padding(28.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(14.dp, 22.dp).background(Amber, RoundedCornerShape(50)))
        Spacer(Modifier.height(18.dp))
        Text("CANDLELIGHT TABLE", color = Amber, fontSize = 14.sp, letterSpacing = 4.sp, fontFamily = FontFamily.Monospace)
        Spacer(Modifier.height(8.dp))
        Text("โต๊ะผจญภัยที่ Claude เป็นผู้เล่าเรื่อง", color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, lineHeight = 30.sp)
        Spacer(Modifier.height(6.dp))
        Text("เข้าสู่ระบบเพื่อให้ตัวละครและโต๊ะของคุณติดตามไปทุกเครื่อง", color = Muted, fontSize = 14.sp, textAlign = TextAlign.Center, lineHeight = 20.sp)
        Spacer(Modifier.height(36.dp))
        Button(
            onClick = {
                busy = true; error = null
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
                            session.token = tok; session.userName = user.name; session.userSub = user.sub
                            if (session.name.isBlank()) session.name = user.name
                            Api.authToken = tok
                            onLoggedIn(tok)
                        } else error = "ไม่ได้รับข้อมูลจาก Google"
                    } catch (e: GetCredentialCancellationException) {
                        error = null
                    } catch (e: ApiException) {
                        error = e.message
                    } catch (e: Exception) {
                        error = "เข้าสู่ระบบด้วย Google ไม่สำเร็จ: " + (e.message ?: e.javaClass.simpleName)
                    } finally { busy = false }
                }
            },
            enabled = !busy, modifier = Modifier.fillMaxWidth().height(52.dp), shape = RoundedCornerShape(8.dp),
        ) { Text(if (busy) "กำลังเข้าสู่ระบบ…" else "เข้าสู่ระบบด้วย Google", fontWeight = FontWeight.Bold, fontSize = 16.sp) }
        error?.let { Spacer(Modifier.height(12.dp)); Text(it, color = Blood, fontSize = 13.sp, textAlign = TextAlign.Center) }
    }
}

// ---------------------------------------------------------------- lobby + character wizard
val HAIRS = listOf("short" to "สั้น", "long" to "ยาว", "tied" to "มัด", "shaved" to "โกน", "hood" to "ฮู้ด")
val FACES = listOf("plain" to "เรียบ", "scar" to "แผลเป็น", "beard" to "เครา", "mustache" to "หนวด", "tattoo" to "รอยสัก")
val CLOAKS = listOf("none" to "ไม่ใส่", "cloak" to "เสื้อคลุม", "cape" to "ผ้าคลุมไหล่")
val HATS = listOf("none" to "ไม่ใส่", "helm" to "หมวกเกราะ", "hood" to "ฮู้ด", "crown" to "มงกุฎ", "bandana" to "ผ้าโพก")
val WEAPONS = listOf("none" to "ไม่มี", "sword" to "ดาบ", "staff" to "ไม้เท้า", "bow" to "ธนู", "dagger" to "มีดสั้น", "axe" to "ขวาน", "shield" to "โล่")
val HAIR_COLORS = listOf("#2A2420", "#4A3A2E", "#6B6258", "#8C7A5E", "#7A2E2A", "#3A3A44")
val SKIN_COLORS = listOf("#B9A48E", "#9E8468", "#7A5F48", "#5A4536", "#8A8C90", "#7C6F86")
val TUNIC_COLORS = listOf("#6B6258", "#4B5A55", "#5A3F48", "#4F4A2F", "#3A3A44", "#5A4A3A", "#B8862F", "#5E8F8A")
val CLOAK_COLORS = listOf("#3E3A47", "#2E3A36", "#4A2E2E", "#3A3128", "#26262E", "#2E3542")
val CLASS_DEFAULT_WEAPON = mapOf("Fighter" to "sword", "Wizard" to "staff", "Rogue" to "dagger", "Cleric" to "shield", "Ranger" to "bow", "Bard" to "none", "Paladin" to "sword")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LobbyScreen(session: Session, onEnter: (String, String) -> Unit, onSignOut: () -> Unit, onBack: (() -> Unit)? = null) {
    var name by remember { mutableStateOf(session.name) }
    var myRooms by remember { mutableStateOf<List<MyRoom>>(emptyList()) }
    LaunchedEffect(Unit) {
        try { val (u, rooms) = Api.me(); session.userName = u.name; session.userSub = u.sub; myRooms = rooms }
        catch (e: ApiException) { if (e.message?.contains("เข้าสู่ระบบ") == true) onSignOut() }
        catch (e: Exception) { }
    }
    var step by remember { mutableStateOf(1) }
    var race by remember { mutableStateOf(RACES[0]) }
    var cls by remember { mutableStateOf(CLASSES[0]) }
    var bg by remember { mutableStateOf("") }
    var stats by remember { mutableStateOf(ABIL.associateWith { roll4d6() }) }
    var look by remember { mutableStateOf(Look.fromString(session.look)) }
    var lookVersion by remember { mutableStateOf(0) }
    var mode by remember { mutableStateOf("host") }
    var joinCode by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val preview = remember { BoardController() }
    fun updateLook(f: (Look) -> Unit) { val l = look.copy(); f(l); look = l; lookVersion++; session.look = l.toJson().toString() }
    LaunchedEffect(lookVersion, race) { look.race = race.lowercase(); preview.setPreview(look.toJson().toString()) }

    Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (onBack != null) TextButton(onClick = onBack, contentPadding = PaddingValues(0.dp, 0.dp)) { Text("‹ ", color = Muted, fontSize = 13.sp) }
            Text("CANDLELIGHT TABLE", color = Amber, fontSize = 13.sp, letterSpacing = 3.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.weight(1f))
            Text(session.userName, color = Muted, fontSize = 12.sp)
            TextButton(onClick = { scope.launch { Api.logout(); onSignOut() } }, contentPadding = PaddingValues(6.dp, 0.dp)) { Text("ออกจากระบบ", color = Muted, fontSize = 12.sp) }
        }
        Text("สร้างตัวละคร แล้วนั่งลงที่โต๊ะ", color = Ink, fontSize = 26.sp, fontWeight = FontWeight.Bold, lineHeight = 32.sp)

        val resumable = myRooms.filter { it.playerId != null }
        if (resumable.isNotEmpty()) Panel {
            Label("โต๊ะของฉัน · กลับเข้าเล่นต่อ")
            resumable.forEach { r ->
                OutlinedButton(onClick = { onEnter(r.code, r.playerId!!) }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.outlinedButtonColors(containerColor = Ground, contentColor = Ink), border = androidx.compose.foundation.BorderStroke(1.dp, if (r.owner) AmberDim else Line)) {
                    Column(Modifier.weight(1f)) {
                        Text(r.scene, fontSize = 14.sp, maxLines = 1)
                        Text("ห้อง ${r.code} · ${r.players} ผู้เล่น" + if (r.owner) " · เจ้าของ" else "", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    }
                    Text("เข้า", color = Amber, fontSize = 13.sp)
                }
            }
        }

        // step indicator
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("เผ่า·อาชีพ", "ค่าสเตตัส", "รูปลักษณ์").forEachIndexed { i, l ->
                val n = i + 1; val on = n == step
                Row(Modifier.weight(1f).clip(RoundedCornerShape(6.dp)).background(if (on) Amber.copy(alpha = .14f) else Surface).border(1.dp, if (on) Amber else Line, RoundedCornerShape(6.dp))
                    .clickable { step = n }.padding(8.dp, 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                    Text("$n", color = if (on) Amber else Muted, fontFamily = FontFamily.Monospace, fontSize = 12.sp); Spacer(Modifier.width(6.dp))
                    Text(l, color = if (on) Amber else Muted, fontSize = 12.sp, maxLines = 1)
                }
            }
        }

        // live pawn preview (shared across steps)
        Box(Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(10.dp)).border(1.dp, Line, RoundedCornerShape(10.dp))) {
            BoardView(Modifier.fillMaxSize(), preview)
            Text("หมุนดูได้", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.align(Alignment.BottomEnd).padding(8.dp))
        }

        when (step) {
            1 -> Panel {
                Label("เผ่าพันธุ์")
                ChipRow(RACES.map { it to it }, race) { race = it }
                Label("อาชีพ")
                ChipRow(CLASSES.map { it to it }, cls) { cls = it; updateLook { l -> l.weapon = CLASS_DEFAULT_WEAPON[it] ?: l.weapon } }
                Text("HP เริ่มต้น ${CLASS_HP[cls]} + CON · ความเร็ว 30 ft", color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                Button(onClick = { step = 2 }, modifier = Modifier.fillMaxWidth().height(48.dp), shape = RoundedCornerShape(8.dp)) { Text("ถัดไป", fontWeight = FontWeight.Bold) }
            }
            2 -> Panel {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Label("Ability scores · 4d6 drop lowest", Modifier.weight(1f))
                    TextButton(onClick = { stats = ABIL.associateWith { roll4d6() } }) {
                        Icon(Icons.Default.Refresh, null, tint = Amber, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("ทอยใหม่", color = Amber)
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { ABIL.forEach { a -> StatBox(a, stats[a] ?: 10, Modifier.weight(1f)) } }
                val hp = (CLASS_HP[cls] ?: 8) + Math.floorDiv((stats["CON"] ?: 10) - 10, 2)
                Text("HP เริ่มต้น $hp  ·  $cls ${CLASS_HP[cls]} + CON ${mod(stats["CON"] ?: 10)}", color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { step = 1 }, modifier = Modifier.weight(1f).height(48.dp), shape = RoundedCornerShape(8.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = Muted), border = androidx.compose.foundation.BorderStroke(1.dp, Line)) { Text("ย้อนกลับ") }
                    Button(onClick = { step = 3 }, modifier = Modifier.weight(2f).height(48.dp), shape = RoundedCornerShape(8.dp)) { Text("ถัดไป", fontWeight = FontWeight.Bold) }
                }
            }
            else -> Panel {
                Label("ทรงผม"); ChipRow(HAIRS, look.hair) { v -> updateLook { it.hair = v; if (v == "hood") it.cloak = "cloak" } }
                Label("สีผม"); Swatches(HAIR_COLORS, look.hairColor) { v -> updateLook { it.hairColor = v } }
                Label("ใบหน้า"); ChipRow(FACES, look.face) { v -> updateLook { it.face = v } }
                Label("สีผิว"); Swatches(SKIN_COLORS, look.skin) { v -> updateLook { it.skin = v } }
                Label("เสื้อ"); Swatches(TUNIC_COLORS, look.tunic) { v -> updateLook { it.tunic = v } }
                Label("เสื้อคลุม"); ChipRow(CLOAKS, look.cloak) { v -> updateLook { it.cloak = v } }
                if (look.cloak != "none") Swatches(CLOAK_COLORS, look.cloakColor) { v -> updateLook { it.cloakColor = v } }
                Label("หมวก"); ChipRow(HATS, look.hat) { v -> updateLook { it.hat = v } }
                Label("อาวุธ"); ChipRow(WEAPONS, look.weapon) { v -> updateLook { it.weapon = v } }
                OutlinedTextField(name, { name = it.take(40) }, label = { Text("ชื่อตัวละคร") }, singleLine = true, modifier = Modifier.fillMaxWidth(), colors = fieldColors())
                OutlinedTextField(bg, { bg = it.take(120) }, label = { Text("ปูมหลังสั้น ๆ (ไม่บังคับ)") }, singleLine = true, modifier = Modifier.fillMaxWidth(), colors = fieldColors())

                HorizontalDivider(color = Line)
                Label("โต๊ะ")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ModeButton("เปิดห้องใหม่", mode == "host", Modifier.weight(1f)) { mode = "host" }
                    ModeButton("เข้าห้องเพื่อน", mode == "join", Modifier.weight(1f)) { mode = "join" }
                }
                if (mode == "join") {
                    OutlinedTextField(joinCode, { joinCode = it.uppercase().filter { c -> c.isLetter() }.take(5) }, label = { Text("รหัสห้อง 5 ตัว") },
                        singleLine = true, modifier = Modifier.fillMaxWidth(), colors = fieldColors(),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters))
                }
                error?.let { Text(it, color = Blood, fontSize = 13.sp) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { step = 2 }, modifier = Modifier.weight(1f).height(50.dp), shape = RoundedCornerShape(8.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = Muted), border = androidx.compose.foundation.BorderStroke(1.dp, Line)) { Text("ย้อนกลับ") }
                    Button(
                        onClick = {
                            if (name.isBlank()) { error = "ตั้งชื่อตัวละครก่อน"; return@Button }
                            if (mode == "join" && joinCode.length < 5) { error = "ใส่รหัสห้องให้ครบ"; return@Button }
                            error = null; busy = true
                            scope.launch {
                                try {
                                    session.name = name
                                    val hp = (CLASS_HP[cls] ?: 8) + Math.floorDiv((stats["CON"] ?: 10) - 10, 2)
                                    look.race = race.lowercase()
                                    val (c, p, _) = if (mode == "join") Api.joinRoom(joinCode, name, race, cls, bg, stats, hp, look)
                                                    else Api.createRoom(name, race, cls, bg, stats, hp, look)
                                    onEnter(c, p)
                                } catch (e: Exception) { error = e.message ?: "เชื่อมต่อไม่ได้" } finally { busy = false }
                            }
                        },
                        enabled = !busy, modifier = Modifier.weight(2f).height(50.dp), shape = RoundedCornerShape(8.dp),
                    ) { Text(if (busy) "กำลังเชื่อมต่อ…" else "นั่งลงที่โต๊ะ", fontWeight = FontWeight.Bold, fontSize = 16.sp) }
                }
            }
        }
        Spacer(Modifier.height(20.dp))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable fun ChipRow(options: List<Pair<String, String>>, value: String, onPick: (String) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        options.forEach { (v, l) ->
            val on = v == value
            Box(Modifier.clip(RoundedCornerShape(6.dp)).background(if (on) Amber.copy(alpha = .14f) else Raised).border(1.dp, if (on) Amber else Line, RoundedCornerShape(6.dp))
                .clickable { onPick(v) }.defaultMinSize(minHeight = 40.dp).padding(12.dp, 8.dp), contentAlignment = Alignment.Center) {
                Text(l, color = if (on) Amber else Ink, fontSize = 13.sp)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable fun Swatches(colors: List<String>, value: String, onPick: (String) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        colors.forEach { c ->
            val on = c.equals(value, ignoreCase = true)
            Box(Modifier.size(36.dp).clip(CircleShape).background(Color(android.graphics.Color.parseColor(c))).border(if (on) 2.dp else 1.dp, if (on) Ink else Line, CircleShape).clickable { onPick(c) })
        }
    }
}

// ---------------------------------------------------------------- game
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GameScreen(code: String, playerId: String, mySub: String?, session: Session, onLeave: () -> Unit) {
    var confirmClose by remember { mutableStateOf(false) }
    var room by remember { mutableStateOf<Room?>(null) }
    var log by remember { mutableStateOf(listOf<Entry>()) }
    var seq by remember { mutableStateOf(0) }
    var input by remember { mutableStateOf("") }
    var pendingRolls by remember { mutableStateOf(listOf<String>()) }
    var lastRoll by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var sending by remember { mutableStateOf(false) }
    var tab by remember { mutableStateOf("board") }
    var control by remember { mutableStateOf(session.control) }
    var showSettings by remember { mutableStateOf(false) }
    var tappedToken by remember { mutableStateOf<String?>(null) }
    // highest roll already thrown on the board; -1 until the first load, so old rolls are not replayed on entry
    var rollSeen by remember { mutableStateOf(-1) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val board = remember { BoardController() }
    // joystick parks just above whatever covers the bottom of the board (story panel, tabs, keyboard)
    val density = LocalDensity.current
    val insetRefs = remember { arrayOfNulls<LayoutCoordinates>(2) } // [board, spacer above the bottom panel]
    fun syncInset() {
        val bc = insetRefs[0] ?: return
        val sc = insetRefs[1] ?: return
        if (!bc.isAttached || !sc.isAttached) return
        val covered = bc.size.height - bc.localPositionOf(sc, Offset(0f, sc.size.height.toFloat())).y
        board.setInset(with(density) { covered.toDp().value }.roundToInt().coerceAtLeast(0))
    }

    fun apply(r: Room) {
        room = r
        if (r.log.isNotEmpty()) {
            val known = log.map { it.seq }.toSet()
            log = (log + r.log.filter { it.seq !in known }).sortedBy { it.seq }
            seq = maxOf(seq, r.log.maxOf { it.seq })
            // Throw a die on the board for every roll that lands while we are sitting here. The server decided the
            // number and every player's poll brings it down, so all we do is show it; the page seeds the tumble from
            // the entry's seq, which makes it the same throw on everyone's screen. The roller sees it at once, since
            // their own Api.roll response comes back through here; everyone else sees it on their next poll.
            if (rollSeen < 0) rollSeen = r.log.maxOf { it.seq }      // first load: the backlog is history, not news
            else {
                val mine = r.players.find { it.id == playerId }?.name
                r.log.filter { it.t == "roll" && it.die > 0 && it.seq > rollSeen }.sortedBy { it.seq }
                    .forEach { e -> board.showRoll(e.seq, e.who, e.die, e.value, e.who == mine); rollSeen = e.seq }
            }
        }
        seq = maxOf(seq, r.seq)
    }

    LaunchedEffect(code) {
        while (true) {
            try { apply(Api.getRoom(code, seq)); error = null }
            catch (e: ApiException) { error = e.message; if (e.message?.contains("ไม่พบห้อง") == true) { delay(4000); onLeave(); return@LaunchedEffect } }
            catch (e: Exception) { error = "ออฟไลน์ — กำลังลองใหม่" }
            delay(if (tab == "board") 2000 else 3000)
        }
    }
    LaunchedEffect(log.size) { if (log.isNotEmpty() && tab == "story") listState.animateScrollToItem(log.size - 1) }
    BoardSync(board, playerId, room?.board, control)
    var boardHint by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { delay(10000); if (!board.ready) boardHint = board.lastError ?: "กระดาน 3D ยังไม่ตอบสนอง (ต้องต่ออินเทอร์เน็ต) — เล่นต่อได้ที่แท็บเรื่องราว" }

    val isOwner = mySub != null && room?.ownerSub == mySub
    val waiting = (room?.pending ?: 0) > 0
    val b = room?.board
    val inCombat = b?.mode == "combat"
    val myTurn = inCombat && b?.currentId == playerId

    fun send() {
        val t = input.trim(); if (t.isEmpty() || sending) return
        sending = true
        scope.launch {
            try { apply(Api.act(code, playerId, t, pendingRolls)); input = ""; pendingRolls = emptyList(); lastRoll = null }
            catch (e: Exception) { error = e.message } finally { sending = false }
        }
    }
    fun roll(d: Int) {
        scope.launch {
            try {
                val (v, r) = Api.roll(code, playerId, d)
                lastRoll = "d$d → $v" + if (d == 20 && v == 20) " ✦" else if (d == 20 && v == 1) " ✗" else ""
                pendingRolls = pendingRolls + "d$d=$v"; apply(r)
            } catch (e: Exception) { error = e.message }
        }
    }

    Box(Modifier.fillMaxSize()) {
        // 3D board always alive underneath
        BoardView(Modifier.fillMaxSize().onGloballyPositioned { insetRefs[0] = it; syncInset() }, board,
            onMove = { x, z -> scope.launch { try { Api.move(code, playerId, x, z) } catch (e: ApiException) { error = e.message } catch (e: Exception) { } } },
            onTapToken = { id -> tappedToken = id })

        Column(Modifier.fillMaxSize().statusBarsPadding().imePadding()) {
            // header (transparent over board)
            Row(Modifier.fillMaxWidth().background(if (tab == "board") Color.Transparent else Ground).padding(16.dp, 12.dp, 8.dp, 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("SCENE · ห้อง $code" + if (inCombat) " · ต่อสู้ รอบ ${b?.round}" else "", color = if (inCombat) Blood else Muted, fontSize = 11.sp, letterSpacing = 2.sp, fontFamily = FontFamily.Monospace)
                    Text(room?.scene ?: "…", color = Amber, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                }
                IconButton(onClick = { showSettings = true }) { Icon(Icons.Default.Settings, "ตั้งค่า", tint = Muted) }
                IconButton(onClick = { scope.launch { Api.leave(code, playerId); onLeave() } }) { Icon(Icons.Default.Logout, "ออก", tint = Muted) }
            }
            error?.let { Text(it, color = Blood, fontSize = 12.sp, modifier = Modifier.background(Ground.copy(alpha = .8f)).padding(16.dp, 6.dp)) }

            when (tab) {
                "board" -> {
                    if (!board.ready && boardHint != null) Text(boardHint!!, color = Muted, fontSize = 12.sp, modifier = Modifier.padding(16.dp, 4.dp))
                    Spacer(Modifier.weight(1f).onGloballyPositioned { insetRefs[1] = it; syncInset() })
                    if (inCombat) Row(Modifier.padding(16.dp, 4.dp)) {
                        Text(if (myTurn) "▶ เทิร์นของคุณ · เดินได้ 30 ft" else "เทิร์นของ ${b?.currentName ?: "…"}", color = if (myTurn) Amber else Ink, fontSize = 13.sp,
                            modifier = Modifier.background(Surface.copy(alpha = .92f), RoundedCornerShape(8.dp)).border(1.dp, if (myTurn) Amber else Line, RoundedCornerShape(8.dp)).padding(10.dp, 6.dp))
                    }
                    if (waiting) Text("ส่งถึง DM แล้ว รอผู้เล่าเรื่อง…", color = Muted, fontSize = 12.sp, modifier = Modifier.padding(16.dp, 2.dp).background(Surface.copy(alpha = .85f), RoundedCornerShape(6.dp)).padding(8.dp, 4.dp))
                    Column(Modifier.fillMaxWidth().background(Surface.copy(alpha = .94f)).padding(12.dp, 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        log.lastOrNull { it.t == "dm" }?.let { e ->
                            Text(e.text, color = Ink, fontSize = 13.sp, lineHeight = 19.sp, maxLines = 3, modifier = Modifier.clickable { tab = "story" })
                        }
                        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(input, { input = it.take(600) }, placeholder = { Text("ทำอะไร…", color = Muted) }, modifier = Modifier.weight(1f), maxLines = 2, colors = fieldColors())
                            DieButton("d20") { roll(20) }
                            FilledIconButton(onClick = { send() }, enabled = !sending, modifier = Modifier.size(48.dp), shape = RoundedCornerShape(8.dp)) { Icon(Icons.Default.Send, "ส่งให้ DM") }
                        }
                        lastRoll?.let { Text(it, color = Teal, fontFamily = FontFamily.Monospace, fontSize = 12.sp) }
                    }
                }
                "story" -> Column(Modifier.weight(1f).fillMaxWidth().background(Ground)) {
                    LazyColumn(state = listState, modifier = Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(16.dp, 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        items(log, key = { it.seq }) { e -> LogEntry(e, isLast = e.seq == log.lastOrNull()?.seq) { choice -> input = choice } }
                        if (waiting) item {
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                                Box(Modifier.size(8.dp, 12.dp).background(Amber, RoundedCornerShape(50))); Spacer(Modifier.width(10.dp))
                                Text("ส่งถึง DM แล้ว รอผู้เล่าเรื่อง…", color = Muted, fontSize = 13.sp)
                            }
                        }
                    }
                    Column(Modifier.fillMaxWidth().background(Surface).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                            Icon(Icons.Default.Casino, null, tint = Muted, modifier = Modifier.size(18.dp))
                            listOf(4, 6, 8, 10, 12, 20).forEach { d -> DieButton("d$d") { roll(d) } }
                            Spacer(Modifier.weight(1f))
                            lastRoll?.let { Text(it, color = Teal, fontFamily = FontFamily.Monospace, fontSize = 13.sp) }
                        }
                        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(input, { input = it.take(600) }, placeholder = { Text("ตัวละครของคุณทำอะไร…", color = Muted) }, modifier = Modifier.weight(1f), maxLines = 4, colors = fieldColors())
                            FilledIconButton(onClick = { send() }, enabled = !sending, modifier = Modifier.size(52.dp), shape = RoundedCornerShape(8.dp)) { Icon(Icons.Default.Send, "ส่งให้ DM") }
                        }
                    }
                }
                else -> Column(Modifier.weight(1f).fillMaxWidth().background(Ground).verticalScroll(rememberScrollState()).padding(16.dp, 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Label("Party · ${room?.players?.size ?: 0}")
                    room?.players?.forEach { p ->
                        PartyCard(p, mine = p.id == playerId) { newHp -> scope.launch { try { apply(Api.setHp(code, playerId, newHp)) } catch (e: Exception) { error = e.message } } }
                    }
                    if (isOwner) OutlinedButton(onClick = { confirmClose = true }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Blood), border = androidx.compose.foundation.BorderStroke(1.dp, Blood)) {
                        Icon(Icons.Default.DeleteForever, null, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("ปิดโต๊ะ (ลบห้องนี้ถาวร)")
                    }
                    Spacer(Modifier.height(12.dp))
                }
            }

            // bottom tabs
            Row(Modifier.fillMaxWidth().background(Surface).border(1.dp, Line).padding(vertical = 6.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                listOf("board" to "กระดาน", "story" to "เรื่องราว", "party" to "ปาร์ตี้").forEach { (k, l) ->
                    TextButton(onClick = { tab = k }) { Text(l, color = if (tab == k) Amber else Muted, fontFamily = FontFamily.Monospace, fontSize = 12.sp) }
                }
            }
        }
    }

    tappedToken?.let { id ->
        val name = room?.board?.json?.let { try { org.json.JSONObject(it).optJSONObject("tokens")?.optJSONObject(id)?.optString("name") } catch (e: Exception) { null } } ?: id
        AlertDialog(onDismissRequest = { tappedToken = null }, containerColor = Surface, titleContentColor = Ink, textContentColor = Muted,
            title = { Text(name) }, text = { Text("อยากทำอะไรกับ $name ?") },
            confirmButton = { TextButton(onClick = { input = "พูดคุยกับ$name: "; tappedToken = null; tab = "story" }) { Text("พูดคุย", color = Amber) } },
            dismissButton = { TextButton(onClick = { input = "โจมตี$name"; tappedToken = null; send() }) { Text("โจมตี", color = Blood) } })
    }
    if (showSettings) {
        AlertDialog(onDismissRequest = { showSettings = false }, containerColor = Surface, titleContentColor = Ink, textContentColor = Muted,
            title = { Text("ตั้งค่า") },
            text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Label("วิธีเดินบนกระดาน")
                ChipRow(listOf("tap" to "แตะพื้นเพื่อเดิน", "joystick" to "จอยสติ๊กวงกลม"), control) { control = it; session.control = it }
                Text("จอยสติ๊กจะโผล่มุมล่างซ้ายของกระดาน ลากเพื่อเดินตามทิศกล้อง", color = Muted, fontSize = 12.sp)
            } },
            confirmButton = { TextButton(onClick = { showSettings = false }) { Text("ปิด", color = Amber) } })
    }
    if (confirmClose) {
        AlertDialog(
            onDismissRequest = { confirmClose = false },
            containerColor = Surface, titleContentColor = Ink, textContentColor = Muted,
            title = { Text("ปิดโต๊ะ $code ?") },
            text = { Text("เรื่องราวและตัวละครในห้องนี้จะถูกลบทั้งหมด ผู้เล่นคนอื่นจะถูกส่งกลับหน้าแรก") },
            confirmButton = { TextButton(onClick = { confirmClose = false; scope.launch { try { Api.closeRoom(code); onLeave() } catch (e: Exception) { error = e.message } } }) { Text("ปิดโต๊ะ", color = Blood) } },
            dismissButton = { TextButton(onClick = { confirmClose = false }) { Text("ยกเลิก", color = Ink) } },
        )
    }
}

// ---------------------------------------------------------------- pieces
@Composable fun Panel(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().background(Surface, RoundedCornerShape(10.dp)).border(1.dp, Line, RoundedCornerShape(10.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
}
@Composable fun Label(t: String, m: Modifier = Modifier) = Text(t.uppercase(), color = Muted, fontSize = 11.sp, letterSpacing = 2.sp, fontFamily = FontFamily.Monospace, modifier = m)

@Composable fun fieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = Amber, unfocusedBorderColor = Line, focusedTextColor = Ink, unfocusedTextColor = Ink,
    focusedLabelColor = Amber, unfocusedLabelColor = Muted, cursorColor = Amber, focusedContainerColor = Ground, unfocusedContainerColor = Ground,
)

@Composable fun StatBox(a: String, v: Int, m: Modifier) {
    Column(m.background(Ground, RoundedCornerShape(6.dp)).border(1.dp, Line, RoundedCornerShape(6.dp)).padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(a, color = Muted, fontSize = 9.sp, fontFamily = FontFamily.Monospace, letterSpacing = 1.sp)
        Text("$v", color = Ink, fontSize = 18.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
        Text(mod(v), color = Teal, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
    }
}

@Composable fun ModeButton(t: String, on: Boolean, m: Modifier, onClick: () -> Unit) {
    OutlinedButton(onClick, m, shape = RoundedCornerShape(8.dp),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = if (on) Amber.copy(alpha = .12f) else Color.Transparent, contentColor = if (on) Amber else Ink),
        border = androidx.compose.foundation.BorderStroke(1.dp, if (on) Amber else Line)) { Text(t) }
}

@Composable fun DieButton(t: String, onClick: () -> Unit) {
    OutlinedButton(onClick, shape = RoundedCornerShape(6.dp), contentPadding = PaddingValues(8.dp, 4.dp), modifier = Modifier.height(32.dp),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = Raised, contentColor = Ink), border = androidx.compose.foundation.BorderStroke(1.dp, Line)) {
        Text(t, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun Dropdown(label: String, value: String, options: List<String>, m: Modifier, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(open, { open = it }, m) {
        OutlinedTextField(value, {}, readOnly = true, label = { Text(label) }, singleLine = true, colors = fieldColors(),
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(open) }, modifier = Modifier.menuAnchor().fillMaxWidth())
        ExposedDropdownMenu(open, { open = false }, modifier = Modifier.background(Raised)) {
            options.forEach { o -> DropdownMenuItem(text = { Text(o, color = Ink) }, onClick = { onPick(o); open = false }) }
        }
    }
}

@Composable fun LogEntry(e: Entry, isLast: Boolean, onChoice: (String) -> Unit) {
    val whoColor = when (e.t) { "dm" -> Amber; "roll" -> Teal; else -> Muted }
    Column(Modifier.fillMaxWidth()) {
        Text(e.who.uppercase(), color = whoColor, fontSize = 10.sp, letterSpacing = 1.5.sp, fontFamily = FontFamily.Monospace)
        Spacer(Modifier.height(3.dp))
        when (e.t) {
            "dm" -> Column(Modifier.fillMaxWidth().drawLeftRule().padding(start = 12.dp)) {
                Text(e.text, color = Ink, fontSize = 15.sp, lineHeight = 23.sp)
                if (isLast && e.choices.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        e.choices.forEach { c ->
                            OutlinedButton({ onChoice(c) }, shape = RoundedCornerShape(6.dp), contentPadding = PaddingValues(12.dp, 6.dp),
                                colors = ButtonDefaults.outlinedButtonColors(containerColor = Raised, contentColor = Ink), border = androidx.compose.foundation.BorderStroke(1.dp, Line)) {
                                Text(c, fontSize = 13.sp, textAlign = TextAlign.Start, modifier = Modifier.fillMaxWidth())
                            }
                        }
                    }
                }
            }
            "roll" -> Text(e.text, color = Teal, fontFamily = FontFamily.Monospace, fontSize = 14.sp)
            "sys" -> Text(e.text, color = Muted, fontSize = 13.sp)
            else -> Text(e.text, color = Color(0xFFD9D1C0), fontSize = 15.sp, lineHeight = 22.sp)
        }
    }
}

fun Modifier.drawLeftRule(): Modifier = this.then(
    Modifier.drawBehind {
        drawRect(color = AmberDim, size = androidx.compose.ui.geometry.Size(2.dp.toPx(), size.height))
    }
)

@Composable fun PartyCard(p: Player, mine: Boolean, onHp: (Int) -> Unit) {
    val pct = (p.hp.toFloat() / p.maxHp).coerceIn(0f, 1f)
    val barColor = when { pct <= .25f -> Blood; pct <= .5f -> Amber; else -> Teal }
    Column(Modifier.fillMaxWidth().background(Ground, RoundedCornerShape(10.dp)).border(1.dp, if (mine) AmberDim else Line, RoundedCornerShape(10.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(p.name, color = Ink, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.weight(1f))
            Text("${p.race} ${p.cls}${if (mine) " · คุณ" else ""}", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            LinearProgressIndicator(progress = { pct }, color = barColor, trackColor = Surface, modifier = Modifier.fillMaxWidth().height(8.dp))
            Row { Text("HP", color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.weight(1f)); Text("${p.hp} / ${p.maxHp}", color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            ABIL.forEach { a ->
                Column(Modifier.weight(1f).background(Surface, RoundedCornerShape(4.dp)).padding(vertical = 3.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(a, color = Muted, fontSize = 9.sp, fontFamily = FontFamily.Monospace)
                    Text("${p.stats[a] ?: 10}", color = Ink, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                }
            }
        }
        if (mine) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf(-5, -1, 1, 5).forEach { d ->
                OutlinedButton({ onHp((p.hp + d).coerceIn(0, p.maxHp)) }, Modifier.weight(1f).height(32.dp), shape = RoundedCornerShape(6.dp), contentPadding = PaddingValues(0.dp),
                    colors = ButtonDefaults.outlinedButtonColors(containerColor = Raised, contentColor = Ink), border = androidx.compose.foundation.BorderStroke(1.dp, Line)) {
                    Text(if (d > 0) "+$d" else "$d", fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                }
            }
        }
        if (p.bg.isNotBlank()) Text(p.bg, color = Muted, fontSize = 12.sp)
    }
}
