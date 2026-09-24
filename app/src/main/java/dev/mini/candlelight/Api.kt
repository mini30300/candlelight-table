package dev.mini.candlelight

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL

const val SERVER = "https://candlelight-table.mini3030023450.workers.dev"
const val WEB_CLIENT_ID = "59633844460-7o8qv78qos5amd8abcipnoqptnb2fr04.apps.googleusercontent.com"
/** หน้าเล่นบนเบราว์เซอร์/คอม เสิร์ฟจาก Worker ตัวเดียวกัน — แอพก็เปิดหน้านี้ใน WebView หลังล็อกอิน */
const val WEB_APP = "$SERVER/app"

data class User(val sub: String, val email: String, val name: String, val picture: String, val guest: Boolean = false)

/** code คือรหัสข้อผิดพลาดจากเซิร์ฟเวอร์ (AUTH_REQUIRED, RATE_LIMITED, PAIR_INVALID, …) เอาไว้แยกกรณีโดยไม่ต้องจับคำไทย */
class ApiException(msg: String, val code: String = "", val status: Int = 0) : Exception(msg) {
    /** token นี้ใช้ต่อไม่ได้แล้ว ต้องล็อกอินใหม่ — เงื่อนไขเดียวกับ fatalAuth() ของหน้าเว็บ */
    val fatalAuth: Boolean get() = status == 401 || code == "GUEST_EXPIRED" || code == "GUEST_LINKED"
}

/**
 * ตัวแอพคุยกับเซิร์ฟเวอร์แค่ตอนล็อกอินกับตอนตรวจ token ที่เก็บไว้ ที่เหลือ (โต๊ะ D&D ห้อง กองไฟ) หน้าเว็บ /app
 * ทำเองทั้งหมด ด้วย token ที่แอพส่งให้ทาง #t=
 */
object Api {
    /** session token from Google login; set by the app at startup and after login */
    @Volatile var authToken: String? = null

    private fun parseUser(o: JSONObject) = User(o.optString("sub"), o.optString("email"), o.optString("name"), o.optString("picture"), o.optBoolean("guest"))

    private suspend fun request(method: String, path: String, body: JSONObject? = null, bearer: String? = authToken): JSONObject = withContext(Dispatchers.IO) {
        val conn = (URL(SERVER + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15000; readTimeout = 20000
            setRequestProperty("Accept", "application/json")
            bearer?.let { setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
            }
        }
        try {
            if (body != null) conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use(BufferedReader::readText) ?: "{}"
            val json = try { JSONObject(text) } catch (e: Exception) { JSONObject().put("error", "ตอบกลับไม่ถูกต้อง ($code)") }
            if (code !in 200..299) throw ApiException(json.optString("error", "HTTP $code"), json.optString("code"), code)
            json
        } finally { conn.disconnect() }
    }

    /** exchange a Google ID token for our session token */
    suspend fun loginGoogle(idToken: String): Pair<String, User> {
        val r = request("POST", "/api/auth/google", JSONObject().put("idToken", idToken))
        return r.getString("token") to parseUser(r.getJSONObject("user"))
    }

    /** บัญชีผู้เล่นรับเชิญ เซิร์ฟเวอร์สร้างให้ทันที ตัวตนอยู่ที่ token ในเครื่องนี้เท่านั้น */
    suspend fun loginGuest(name: String = ""): Pair<String, User> {
        val r = request("POST", "/api/auth/guest", JSONObject().put("name", name))
        return r.getString("token") to parseUser(r.getJSONObject("user"))
    }

    /** เอารหัสจากอีกเครื่องมาแลกเป็น token ของบัญชีเดียวกัน — เครื่องนี้ยังไม่มีบัญชีก็เรียกได้ รหัสคือกุญแจ */
    suspend fun pairClaim(code: String): Pair<String, User> {
        val clean = code.uppercase().filter { it.isLetterOrDigit() }
        val r = request("POST", "/api/auth/pair/claim", JSONObject().put("code", clean))
        return r.getString("token") to parseUser(r.getJSONObject("user"))
    }

    /** ตรวจว่า token ที่เก็บไว้ยังใช้ได้ (หน้ารอเข้าระบบตอนเปิดแอพ) */
    suspend fun me(): User = parseUser(request("GET", "/api/me").getJSONObject("user"))

    /** ปิด session ที่เซิร์ฟเวอร์ — รับ token มาเอง เพราะตอนเรียก แอพล้าง authToken ไปแล้ว */
    suspend fun logout(token: String) { request("POST", "/api/logout", JSONObject(), token) }
}
