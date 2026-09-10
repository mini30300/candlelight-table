package dev.mini.candlelight

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL

const val SERVER = "https://candlelight-table.mini3030023450.workers.dev"

data class Player(
    val id: String, val name: String, val race: String, val cls: String, val bg: String,
    val stats: Map<String, Int>, val hp: Int, val maxHp: Int, val joinedAt: Long,
)

data class Entry(
    val seq: Int, val ts: Long, val t: String, val who: String, val text: String, val choices: List<String>,
)

data class Room(
    val code: String, val scene: String, val players: List<Player>, val seq: Int,
    val pending: Int, val log: List<Entry>,
)

class ApiException(msg: String) : Exception(msg)

object Api {
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
        return Room(o.optString("code"), o.optString("scene"), players, o.optInt("seq"), o.optInt("pending"), log)
    }

    private suspend fun request(method: String, path: String, body: JSONObject? = null): JSONObject = withContext(Dispatchers.IO) {
        val conn = (URL(SERVER + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15000; readTimeout = 20000
            setRequestProperty("Accept", "application/json")
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

    private fun playerJson(name: String, race: String, cls: String, bg: String, stats: Map<String, Int>, maxHp: Int) =
        JSONObject().put("name", name).put("race", race).put("cls", cls).put("bg", bg)
            .put("stats", JSONObject(stats as Map<*, *>)).put("maxHp", maxHp).put("hp", maxHp)

    /** returns (code, playerId, room) */
    suspend fun createRoom(name: String, race: String, cls: String, bg: String, stats: Map<String, Int>, maxHp: Int): Triple<String, String, Room> {
        val r = request("POST", "/api/rooms", JSONObject().put("player", playerJson(name, race, cls, bg, stats, maxHp)))
        return Triple(r.getString("code"), r.getString("playerId"), parseRoom(r.getJSONObject("room")))
    }

    suspend fun joinRoom(code: String, name: String, race: String, cls: String, bg: String, stats: Map<String, Int>, maxHp: Int): Triple<String, String, Room> {
        val r = request("POST", "/api/rooms/$code/join", JSONObject().put("player", playerJson(name, race, cls, bg, stats, maxHp)))
        return Triple(r.getString("code"), r.getString("playerId"), parseRoom(r.getJSONObject("room")))
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

    suspend fun leave(code: String, playerId: String) {
        runCatching { request("POST", "/api/rooms/$code/leave", JSONObject().put("playerId", playerId)) }
    }
}
