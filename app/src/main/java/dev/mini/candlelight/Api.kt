package dev.mini.candlelight

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL

const val SERVER = "https://candlelight-table.mini3030023450.workers.dev"
const val WEB_CLIENT_ID = "59633844460-7o8qv78qos5amd8abcipnoqptnb2fr04.apps.googleusercontent.com"

data class User(val sub: String, val email: String, val name: String, val picture: String)
data class MyRoom(val code: String, val scene: String, val players: Int, val playerId: String?, val owner: Boolean, val updated: Long)

data class Player(
    val id: String, val name: String, val race: String, val cls: String, val bg: String,
    val stats: Map<String, Int>, val hp: Int, val maxHp: Int, val joinedAt: Long,
)

data class Entry(
    val seq: Int, val ts: Long, val t: String, val who: String, val text: String, val choices: List<String>,
)

data class Look(
    var race: String = "human", var hair: String = "short", var face: String = "plain", var cloak: String = "cloak",
    var weapon: String = "sword", var hat: String = "none", var hairColor: String = "#2A2420", var skin: String = "#B9A48E",
    var tunic: String = "#6B6258", var cloakColor: String = "#3E3A47", var accent: String = "#8A6420",
) {
    fun toJson(): JSONObject = JSONObject().put("race", race).put("hair", hair).put("face", face).put("cloak", cloak)
        .put("weapon", weapon).put("hat", hat).put("hairColor", hairColor).put("skin", skin).put("tunic", tunic)
        .put("cloakColor", cloakColor).put("accent", accent)
    companion object {
        fun from(o: JSONObject?): Look { val l = Look(); if (o == null) return l
            l.race = o.optString("race", l.race); l.hair = o.optString("hair", l.hair); l.face = o.optString("face", l.face); l.cloak = o.optString("cloak", l.cloak)
            l.weapon = o.optString("weapon", l.weapon); l.hat = o.optString("hat", l.hat)
            if (!o.isNull("hairColor")) l.hairColor = o.optString("hairColor", l.hairColor); if (!o.isNull("skin")) l.skin = o.optString("skin", l.skin)
            if (!o.isNull("tunic")) l.tunic = o.optString("tunic", l.tunic); if (!o.isNull("cloakColor")) l.cloakColor = o.optString("cloakColor", l.cloakColor)
            if (!o.isNull("accent")) l.accent = o.optString("accent", l.accent); return l }
        fun fromString(s: String?): Look = try { from(JSONObject(s ?: "{}")) } catch (e: Exception) { Look() }
    }
}

data class Board(val json: String, val seq: Int, val scene: String, val time: String, val mode: String, val round: Int, val currentId: String?, val currentName: String?)

data class Room(
    val code: String, val scene: String, val ownerSub: String?, val players: List<Player>, val seq: Int,
    val pending: Int, val log: List<Entry>, val board: Board?,
)

class ApiException(msg: String) : Exception(msg)

object Api {
    /** session token from Google login; set by the app at startup and after login */
    @Volatile var authToken: String? = null

    private fun parseUser(o: JSONObject) = User(o.optString("sub"), o.optString("email"), o.optString("name"), o.optString("picture"))
    private fun parsePlayer(id: String, o: JSONObject): Player {
        val st = o.optJSONObject("stats") ?: JSONObject()
        val stats = listOf("STR", "DEX", "CON", "INT", "WIS", "CHA").associateWith { st.optInt(it, 10) }
        return Player(
            id = id, name = o.optString("name"), race = o.optString("race"), cls = o.optString("cls"),
            bg = o.optString("bg"), stats = stats, hp = o.optInt("hp"), maxHp = o.optInt("maxHp", 1),
            joinedAt = o.optLong("joinedAt"),
        )
    }

    fun parseRoom(o: JSONObject): Room {
        val ps = o.optJSONObject("players") ?: JSONObject()
        val players = ps.keys().asSequence().map { parsePlayer(it, ps.getJSONObject(it)) }.sortedBy { it.joinedAt }.toList()
        val logArr = o.optJSONArray("log") ?: JSONArray()
        val log = (0 until logArr.length()).map { i ->
            val e = logArr.getJSONObject(i)
            val ch = e.optJSONArray("choices") ?: JSONArray()
            Entry(e.optInt("seq"), e.optLong("ts"), e.optString("t"), e.optString("who"), e.optString("text"),
                (0 until ch.length()).map { ch.getString(it) })
        }
        val owner = if (o.isNull("ownerSub")) null else o.optString("ownerSub")
        return Room(o.optString("code"), o.optString("scene"), owner, players, o.optInt("seq"), o.optInt("pending"), log, parseBoard(o.optJSONObject("board")))
    }

    fun parseBoard(b: JSONObject?): Board? {
        if (b == null) return null
        val combat = b.optJSONObject("combat")
        var curId: String? = null; var curName: String? = null; var round = 0
        if (combat != null) {
            round = combat.optInt("round", 1)
            val order = combat.optJSONArray("order"); val turn = combat.optInt("turn", 0)
            if (order != null && turn in 0 until order.length()) {
                curId = order.getJSONObject(turn).optString("id")
                curName = b.optJSONObject("tokens")?.optJSONObject(curId)?.optString("name")
            }
        }
        return Board(b.toString(), b.optInt("seq"), b.optString("scene", "tavern"), b.optString("time", "night"), b.optString("mode", "explore"), round, curId, curName)
    }

    private suspend fun request(method: String, path: String, body: JSONObject? = null): JSONObject = withContext(Dispatchers.IO) {
        val conn = (URL(SERVER + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15000; readTimeout = 20000
            setRequestProperty("Accept", "application/json")
            authToken?.let { setRequestProperty("Authorization", "Bearer $it") }
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
            if (code !in 200..299) throw ApiException(json.optString("error", "HTTP $code"))
            json
        } finally { conn.disconnect() }
    }

    private fun playerJson(name: String, race: String, cls: String, bg: String, stats: Map<String, Int>, maxHp: Int, look: Look) =
        JSONObject().put("name", name).put("race", race).put("cls", cls).put("bg", bg)
            .put("stats", JSONObject(stats as Map<*, *>)).put("maxHp", maxHp).put("hp", maxHp).put("look", look.toJson())

    /** returns (code, playerId, room) */
    suspend fun createRoom(name: String, race: String, cls: String, bg: String, stats: Map<String, Int>, maxHp: Int, look: Look): Triple<String, String, Room> {
        val r = request("POST", "/api/rooms", JSONObject().put("player", playerJson(name, race, cls, bg, stats, maxHp, look)))
        return Triple(r.getString("code"), r.getString("playerId"), parseRoom(r.getJSONObject("room")))
    }

    suspend fun joinRoom(code: String, name: String, race: String, cls: String, bg: String, stats: Map<String, Int>, maxHp: Int, look: Look): Triple<String, String, Room> {
        val r = request("POST", "/api/rooms/$code/join", JSONObject().put("player", playerJson(name, race, cls, bg, stats, maxHp, look)))
        return Triple(r.getString("code"), r.getString("playerId"), parseRoom(r.getJSONObject("room")))
    }

    suspend fun move(code: String, playerId: String, x: Double, z: Double): Board? {
        val r = request("POST", "/api/rooms/$code/move", JSONObject().put("playerId", playerId).put("x", x).put("z", z))
        return parseBoard(r.optJSONObject("board"))
    }

    suspend fun setLook(code: String, playerId: String, look: Look): Room {
        val r = request("POST", "/api/rooms/$code/look", JSONObject().put("playerId", playerId).put("look", look.toJson()))
        return parseRoom(r.getJSONObject("room"))
    }

    suspend fun getRoom(code: String, since: Int = 0): Room = parseRoom(request("GET", "/api/rooms/$code?since=$since"))

    suspend fun act(code: String, playerId: String, text: String, rolls: List<String>): Room {
        val r = request("POST", "/api/rooms/$code/act",
            JSONObject().put("playerId", playerId).put("text", text).put("rolls", JSONArray(rolls)))
        return parseRoom(r.getJSONObject("room"))
    }

    suspend fun roll(code: String, playerId: String, die: Int): Pair<Int, Room> {
        val r = request("POST", "/api/rooms/$code/roll", JSONObject().put("playerId", playerId).put("die", die))
        return r.getInt("value") to parseRoom(r.getJSONObject("room"))
    }

    suspend fun setHp(code: String, playerId: String, hp: Int): Room {
        val r = request("POST", "/api/rooms/$code/hp", JSONObject().put("playerId", playerId).put("hp", hp))
        return parseRoom(r.getJSONObject("room"))
    }

    /** exchange a Google ID token for our session token */
    suspend fun loginGoogle(idToken: String): Pair<String, User> {
        val r = request("POST", "/api/auth/google", JSONObject().put("idToken", idToken))
        return r.getString("token") to parseUser(r.getJSONObject("user"))
    }

    suspend fun me(): Pair<User, List<MyRoom>> {
        val r = request("GET", "/api/me")
        val arr = r.optJSONArray("rooms") ?: JSONArray()
        val rooms = (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            MyRoom(o.optString("code"), o.optString("scene"), o.optInt("players"), if (o.isNull("playerId")) null else o.optString("playerId"), o.optBoolean("owner"), o.optLong("updated"))
        }
        return parseUser(r.getJSONObject("user")) to rooms
    }

    suspend fun logout() { runCatching { request("POST", "/api/logout", JSONObject()) } }

    suspend fun closeRoom(code: String) { request("POST", "/api/rooms/$code/close", JSONObject()) }

    suspend fun leave(code: String, playerId: String) {
        runCatching { request("POST", "/api/rooms/$code/leave", JSONObject().put("playerId", playerId)) }
    }
}
