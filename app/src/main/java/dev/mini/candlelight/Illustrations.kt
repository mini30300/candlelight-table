package dev.mini.candlelight

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke

/**
 * ภาพประกอบลายเส้น — ชุดเดียวกับที่หน้าเว็บ /app ใช้ เอาพิกัดจาก SVG มาตรง ๆ
 *
 * ทำไมไม่ใช้ vector drawable: ต้นฉบับเป็น circle/ellipse/rect ซึ่ง <vector> ของ Android ไม่มี
 * ต้องแปลงเป็น pathData ทุกอัน วาดด้วย Canvas เองตรงกว่า แก้ตามเว็บได้ทีละเส้น
 * และเส้นหนาเท่ากันทุกขนาดภาพ เหมือน non-scaling-stroke ของ SVG
 */
class Pen(
    private val ds: DrawScope,
    /** ตัวคูณจากพิกัด viewBox เป็นพิกเซลจริง */
    val k: Float,
    private val ox: Float,
    private val oy: Float,
    private val color: Color,
    /** ความหนาเส้นฐานเป็นพิกเซล ไม่ขึ้นกับ k */
    private val sw: Float,
) {
    private fun px(x: Float) = ox + x * k
    private fun py(y: Float) = oy + y * k
    private fun dashOf(dash: FloatArray?) =
        dash?.let { PathEffect.dashPathEffect(floatArrayOf(it[0] * k, it[1] * k), 0f) }

    private fun pen(w: Float, dash: FloatArray?) =
        Stroke(width = sw * w, cap = StrokeCap.Round, join = StrokeJoin.Round, pathEffect = dashOf(dash))

    fun line(x1: Float, y1: Float, x2: Float, y2: Float, a: Float = 1f, w: Float = 1f, dash: FloatArray? = null) {
        ds.drawLine(color, Offset(px(x1), py(y1)), Offset(px(x2), py(y2)),
            strokeWidth = sw * w, cap = StrokeCap.Round, pathEffect = dashOf(dash), alpha = a)
    }

    fun circle(cx: Float, cy: Float, r: Float, a: Float = 1f, fill: Boolean = false, w: Float = 1f) {
        ds.drawCircle(color, r * k, Offset(px(cx), py(cy)), alpha = a, style = if (fill) Fill else pen(w, null))
    }

    fun oval(cx: Float, cy: Float, rx: Float, ry: Float, a: Float = 1f, fill: Boolean = false, w: Float = 1f) {
        ds.drawOval(color, Offset(px(cx - rx), py(cy - ry)), Size(2f * rx * k, 2f * ry * k),
            alpha = a, style = if (fill) Fill else pen(w, null))
    }

    fun rect(x: Float, y: Float, wd: Float, ht: Float, r: Float = 0f, a: Float = 1f, w: Float = 1f) {
        ds.drawRoundRect(color, Offset(px(x), py(y)), Size(wd * k, ht * k),
            CornerRadius(r * k, r * k), alpha = a, style = pen(w, null))
    }

    /** เส้นชุดหนึ่งในพิกัด viewBox — m/l/q/c/z เหมือน path ของ SVG */
    inner class Pb {
        val path = Path()
        private var cx = 0f
        private var cy = 0f
        fun m(x: Float, y: Float) { path.moveTo(px(x), py(y)); cx = x; cy = y }
        fun l(x: Float, y: Float) { path.lineTo(px(x), py(y)); cx = x; cy = y }
        fun c(x1: Float, y1: Float, x2: Float, y2: Float, x: Float, y: Float) {
            path.cubicTo(px(x1), py(y1), px(x2), py(y2), px(x), py(y)); cx = x; cy = y
        }
        /** quadratic ของ SVG — ยกเป็น cubic เอง จะได้ไม่ต้องพึ่ง API ที่เปลี่ยนชื่อระหว่างเวอร์ชัน */
        fun q(qx: Float, qy: Float, x: Float, y: Float) {
            c(cx + 2f / 3f * (qx - cx), cy + 2f / 3f * (qy - cy),
              x + 2f / 3f * (qx - x), y + 2f / 3f * (qy - y), x, y)
        }
        fun z() { path.close() }
    }

    fun path(a: Float = 1f, w: Float = 1f, dash: FloatArray? = null, build: Pb.() -> Unit) {
        val b = Pb()
        b.build()
        ds.drawPath(b.path, color, alpha = a, style = pen(w, dash))
    }

    /** เปลวเทียนหนึ่งดวง ใช้ซ้ำหลายที่ */
    fun flame(x: Float, y: Float) {
        path {
            m(x, y)
            c(x + 2.6f, y + 3.4f, x + 3.4f, y + 6f, x, y + 9.8f)
            c(x - 3.4f, y + 6f, x - 2.6f, y + 3.4f, x, y)
            z()
        }
    }
}

/** ภาพหนึ่งใบ: ขนาด viewBox + วิธีวาด */
class Art(val vw: Float, val vh: Float, val draw: Pen.() -> Unit)

@Composable
fun Illustration(art: Art, modifier: Modifier = Modifier, color: Color = Amber, alpha: Float = 0.85f) {
    Canvas(modifier) {
        if (size.width < 1f || size.height < 1f) return@Canvas
        val k = minOf(size.width / art.vw, size.height / art.vh)
        val pen = Pen(this, k, (size.width - art.vw * k) / 2f, (size.height - art.vh * k) / 2f,
            color.copy(alpha = color.alpha * alpha), 1.5f * density)
        art.draw(pen)
    }
}

/** ลูกเต๋า d20 หนึ่งลูก — จุดกลางกับรัศมี */
private fun Pen.d20(cx: Float, cy: Float, r: Float) {
    val h = r * 0.866f                                  // ครึ่งความกว้างของหกเหลี่ยม
    path {
        m(cx, cy - r); l(cx + h, cy - r / 2f); l(cx + h, cy + r / 2f)
        l(cx, cy + r); l(cx - h, cy + r / 2f); l(cx - h, cy - r / 2f); z()
    }
    val ax = cx - h * 0.69f
    val bx = cx + h * 0.69f
    val ay = cy - r * 0.32f
    val dy = cy + r * 0.62f
    path { m(ax, ay); l(bx, ay); l(cx, dy); z() }        // หน้าที่หงายขึ้น
    line(cx, cy - r, ax, ay); line(cx, cy - r, bx, ay)   // ซี่ไปมุม
    line(cx - h, cy - r / 2f, ax, ay); line(cx + h, cy - r / 2f, bx, ay)
    line(cx - h, cy + r / 2f, ax, ay); line(cx + h, cy + r / 2f, bx, ay)
    line(cx - h, cy + r / 2f, cx, dy); line(cx + h, cy + r / 2f, cx, dy)
    line(cx, cy + r, cx, dy)
}

// ────────────────────────────────────────────────────────────── ภาพทั้งชุด
object Arts {

    /** เทียนหนึ่งเล่ม — สัญลักษณ์บนหัวจอ */
    val candle = Art(24f, 40f) {
        circle(12f, 10f, 8f, a = .08f, fill = true)
        flame(12f, 4.5f)
        line(12f, 17.2f, 12f, 14.2f)
        path { m(8f, 18.5f); l(8f, 38f); l(16f, 38f); l(16f, 18.5f) }
        oval(12f, 18.5f, 4f, 1.6f)
        line(9.5f, 24.5f, 9.5f, 28.5f, a = .55f)
    }

    /** D&D — คนสามคนนั่งรอบโต๊ะ มีเทียน หนังสือ แก้ว และลูกเต๋าที่เพิ่งทอย */
    val party = Art(320f, 180f) {
        // ชั้นวางขวดหลังร้าน
        line(6f, 32f, 116f, 32f, a = .45f)
        for ((bx, bh) in listOf(22f to 15f, 42f to 12f, 64f to 17f, 88f to 13f)) {
            path(a = .45f) {
                m(bx, 32f); l(bx, 32f - bh)
                q(bx, 32f - bh - 3f, bx + 2f, 32f - bh - 4f)
                l(bx + 2f, 32f - bh - 7f); l(bx + 6f, 32f - bh - 7f); l(bx + 6f, 32f - bh - 4f)
                q(bx + 8f, 32f - bh - 3f, bx + 8f, 32f - bh)
                l(bx + 8f, 32f); z()
            }
        }
        // พื้นไม้
        line(8f, 176f, 112f, 150f, a = .35f)
        line(312f, 176f, 208f, 150f, a = .35f)
        // โต๊ะแปดเหลี่ยม
        oval(160f, 104f, 46f, 14f, a = .08f, fill = true)
        path {
            m(260f, 108f); l(240.9f, 126.8f); l(190.9f, 138.4f); l(129.1f, 138.4f); l(79.1f, 126.8f)
            l(60f, 108f); l(79.1f, 89.2f); l(129.1f, 77.6f); l(190.9f, 77.6f); l(240.9f, 89.2f); z()
        }
        path { m(60f, 116f); l(79.1f, 134.8f); l(129.1f, 146.4f); l(190.9f, 146.4f); l(240.9f, 134.8f); l(260f, 116f) }
        line(60f, 108f, 60f, 116f); line(79.1f, 126.8f, 79.1f, 134.8f); line(129.1f, 138.4f, 129.1f, 146.4f)
        line(190.9f, 138.4f, 190.9f, 146.4f); line(240.9f, 126.8f, 240.9f, 134.8f); line(260f, 108f, 260f, 116f)
        line(102f, 143f, 102f, 172f); line(218f, 143f, 218f, 172f)
        line(160f, 154f, 160f, 174f, a = .5f)
        // เทียนกลางโต๊ะ
        line(156f, 86f, 156f, 104f); line(164f, 86f, 164f, 104f)
        oval(160f, 86f, 4f, 1.6f)
        path { m(156f, 104f); q(160f, 106f, 164f, 104f) }
        line(160f, 84.5f, 160f, 81.5f)
        flame(160f, 70f)
        // หนังสือที่เปิดอยู่
        path { m(98f, 110f); l(128f, 105f); l(133f, 113f); l(103f, 118f); z() }
        path { m(98f, 110f); l(98f, 113f); l(103f, 121f); l(133f, 116f); l(133f, 113f) }
        path { m(103f, 121f); l(98f, 113f) }
        line(110f, 108f, 124f, 106f, a = .55f)
        // แก้ว
        oval(226f, 104f, 6f, 2.4f)
        path { m(220f, 104f); l(220f, 116f); q(226f, 119f, 232f, 116f); l(232f, 104f) }
        path { m(232f, 107f); q(238f, 107f, 238f, 111f); q(238f, 115f, 232f, 115f) }
        // คนฝั่งไกล — คนเล่าเรื่อง
        circle(186f, 36f, 10f)
        line(181f, 36f, 184f, 36f); line(188f, 36f, 191f, 36f)
        path(a = .55f) { m(186f, 47f); q(194f, 47f, 198f, 51f) }
        path { m(172f, 52f); q(186f, 44f, 200f, 52f) }
        path { m(174f, 52f); l(170f, 79f) }
        path { m(198f, 52f); l(202f, 79f) }
        line(182f, 46.5f, 181f, 51.5f, a = .55f); line(190f, 46.5f, 191f, 51.5f, a = .55f)
        // เสียงเล่าเรื่อง
        path(a = .8f) { m(204f, 20f); q(209f, 14f, 214f, 20f); q(219f, 26f, 224f, 20f); q(229f, 14f, 234f, 20f) }
        path(a = .8f) { m(204f, 20f); l(199f, 25f) }
        // คนซ้าย กับลูกเต๋าที่เพิ่งทอยออกไป
        circle(38f, 66f, 9f)
        line(42f, 66f, 45f, 66f); line(33f, 66f, 36f, 66f)
        path { m(23f, 82f); q(38f, 72f, 53f, 82f) }
        path { m(25f, 82f); l(21f, 118f); l(55f, 118f); l(51f, 82f) }
        line(35f, 75.5f, 34f, 80.5f, a = .55f); line(41f, 75.5f, 42f, 80.5f, a = .55f)
        path { m(52f, 86f); l(60f, 90f); l(66f, 84f) }
        d20(72f, 80f, 8.5f)
        oval(38f, 120f, 14f, 5f)
        line(26f, 121f, 24f, 149f); line(50f, 121f, 52f, 149f)
        // คนขวา
        circle(284f, 70f, 9f)
        line(276f, 70f, 279f, 70f); line(285f, 70f, 288f, 70f)
        path { m(269f, 86f); q(284f, 76f, 299f, 86f) }
        path { m(271f, 86f); l(267f, 122f); l(301f, 122f); l(297f, 86f) }
        line(281f, 79.5f, 280f, 84.5f, a = .55f); line(287f, 79.5f, 288f, 84.5f, a = .55f)
        line(270f, 90f, 258f, 102f)
        oval(284f, 124f, 14f, 5f)
        line(272f, 125f, 270f, 153f); line(296f, 125f, 298f, 153f)
    }

    /** เทเบิลท็อป — หุ่นถือดาบยืนบนฐาน มีลัง ไม้บรรทัด และลูกเต๋า */
    val mini = Art(320f, 180f) {
        line(20f, 178f, 120f, 96f, a = .35f); line(160f, 178f, 160f, 96f, a = .35f)
        line(300f, 178f, 200f, 96f, a = .35f); line(56f, 148f, 264f, 148f, a = .35f)
        line(40f, 162f, 280f, 162f, a = .35f); line(70f, 132f, 250f, 132f, a = .35f)
        // ฐานกลม
        oval(130f, 150f, 34f, 12f, a = .08f, fill = true)
        oval(130f, 150f, 34f, 12f)
        oval(130f, 150f, 26f, 9f, a = .45f)
        // ผ้าคลุม
        path(a = .6f) { m(112f, 63f); q(86f, 89f, 80f, 129f) }
        path(a = .6f) { m(146f, 63f); q(140f, 93f, 130f, 115f) }
        path(a = .6f) { m(80f, 129f); q(92f, 121f, 104f, 125f); q(116f, 129f, 130f, 117f) }
        // ตัวหุ่น
        circle(130f, 42f, 10f)
        line(125f, 42f, 128f, 42f); line(132f, 42f, 135f, 42f)
        line(130f, 52f, 130f, 100f)
        path { m(108f, 62f); q(130f, 54f, 152f, 62f) }
        line(116f, 100f, 144f, 100f)
        line(114f, 64f, 117f, 100f, a = .5f); line(146f, 64f, 143f, 100f, a = .5f)
        line(124f, 100f, 112f, 146f); line(136f, 100f, 150f, 144f)
        line(110f, 62f, 102f, 96f)
        path { m(150f, 62f); l(164f, 48f); l(170f, 40f) }
        // ดาบ — เส้นหนากว่าเพื่อนนิดหนึ่ง
        path(w = 1.15f) { m(164f, 46f); l(200f, 10f) }
        path(w = 1.15f) { m(164f, 46f); l(160f, 50f) }
        path(w = 1.15f) { m(164f, 38f); l(172f, 46f) }
        // ลัง
        path { m(232f, 118f); l(262f, 104f); l(294f, 118f); l(264f, 132f); z() }
        path { m(232f, 118f); l(232f, 136f); l(264f, 150f); l(294f, 136f); l(294f, 118f) }
        line(264f, 132f, 264f, 150f)
        path(a = .45f) { m(248f, 111f); l(264f, 118f); l(280f, 111f) }
        // ไม้บรรทัด
        circle(34f, 170f, 6f); circle(34f, 170f, 2f)
        line(40f, 170f, 298f, 170f)
        for ((tx, th) in listOf(48f to 8f, 74f to 5f, 100f to 5f, 126f to 5f, 152f to 5f,
                                178f to 8f, 204f to 5f, 230f to 5f, 256f to 5f, 282f to 5f))
            line(tx, 170f, tx, 170f - th)
        d20(292f, 146f, 12f)
    }

    /** เชื่อมเครื่อง — มือถือกับคอม มีรหัสลอยอยู่ตรงกลาง */
    val link = Art(160f, 80f) {
        oval(70f, 27f, 24f, 7f, a = .08f, fill = true)
        rect(14f, 16f, 26f, 48f, r = 4f)
        line(23f, 21f, 31f, 21f); line(24f, 59f, 30f, 59f)
        rect(17f, 25f, 20f, 30f, r = 1f, a = .45f)
        rect(100f, 18f, 46f, 30f, r = 2f)
        rect(104f, 22f, 38f, 22f, a = .45f)
        path { m(92f, 50f); l(154f, 50f); l(158f, 56f); l(88f, 56f); z() }
        line(44f, 44f, 62f, 44f, dash = floatArrayOf(4f, 5f))
        line(78f, 44f, 96f, 44f, dash = floatArrayOf(4f, 5f))
        path {
            m(70f, 36f); l(72.2f, 41.8f); l(78f, 44f); l(72.2f, 46.2f)
            l(70f, 52f); l(67.8f, 46.2f); l(62f, 44f); l(67.8f, 41.8f); z()
        }
        rect(52f, 8f, 36f, 18f, r = 3f)
        line(60f, 13f, 60f, 21f); line(67f, 13f, 67f, 21f); line(74f, 13f, 74f, 21f); line(81f, 13f, 81f, 21f)
    }

    /** ยังไม่มีโต๊ะ — โต๊ะเปล่ากับเก้าอี้สองตัว */
    val empty = Art(200f, 80f) {
        val g = .75f
        path(a = g) {
            m(150f, 36f); l(140.5f, 44.2f); l(115.5f, 49.3f); l(84.5f, 49.3f); l(59.5f, 44.2f)
            l(50f, 36f); l(59.5f, 27.8f); l(84.5f, 22.7f); l(115.5f, 22.7f); l(140.5f, 27.8f); z()
        }
        path(a = g) { m(50f, 41f); l(59.5f, 49.2f); l(84.5f, 54.3f); l(115.5f, 54.3f); l(140.5f, 49.2f); l(150f, 41f) }
        line(50f, 36f, 50f, 41f, a = g); line(59.5f, 44.2f, 59.5f, 49.2f, a = g)
        line(84.5f, 49.3f, 84.5f, 54.3f, a = g); line(115.5f, 49.3f, 115.5f, 54.3f, a = g)
        line(140.5f, 44.2f, 140.5f, 49.2f, a = g); line(150f, 36f, 150f, 41f, a = g)
        line(68f, 52f, 68f, 70f, a = g); line(132f, 52f, 132f, 70f, a = g)
        line(100f, 55f, 100f, 69f, a = .38f)
        line(97f, 24f, 97f, 36f, a = g); line(103f, 24f, 103f, 36f, a = g)
        path(a = g) { m(97f, 36f); q(100f, 37.5f, 103f, 36f) }
        oval(100f, 24f, 3f, 1.2f, a = g)
        line(100f, 23f, 100f, 20.5f, a = g)
        oval(70f, 64f, 9f, 3f, a = g)
        path(a = g) { m(61f, 64f); l(61f, 73f); q(70f, 77f, 79f, 73f); l(79f, 64f) }
        oval(130f, 64f, 9f, 3f, a = g)
        path(a = g) { m(121f, 64f); l(121f, 73f); q(130f, 77f, 139f, 73f); l(139f, 64f) }
    }

    /** โต๊ะรบ — หน่วยบนตาราง มีเส้นยิงกับไม้บรรทัด */
    val toolBattle = Art(96f, 64f) {
        line(44.7f, 14f, 28.7f, 52f, a = .35f); line(16.7f, 26.7f, 84.7f, 26.7f, a = .35f)
        line(67.3f, 14f, 51.3f, 52f, a = .35f); line(11.3f, 39.3f, 79.3f, 39.3f, a = .35f)
        path { m(22f, 14f); l(90f, 14f); l(74f, 52f); l(6f, 52f); z() }
        oval(34f, 40f, 8f, 3f); oval(62f, 28f, 8f, 3f)
        circle(34f, 20f, 3.5f)
        path { m(28.5f, 26.5f); q(34f, 23.5f, 39.5f, 26.5f) }
        path { m(30f, 27f); l(28f, 39f); l(40f, 39f); l(38f, 27f) }
        line(42f, 38f, 54f, 30f, dash = floatArrayOf(2f, 3f))
        path(dash = floatArrayOf(2f, 3f)) { m(66f, 26f); q(80f, 18f, 80f, 40f) }
        path { m(77f, 36f); l(80f, 40f); l(83f, 36f) }
        line(14f, 58f, 54f, 58f)
        for (x in listOf(14f, 24f, 34f, 44f, 54f)) line(x, 58f, x, 55f)
        for (x in listOf(19f, 29f, 39f, 49f)) line(x, 58f, x, 56f)
    }

    /** แผนที่โลก — รังผึ้งหกเหลี่ยมกับเส้นชั้นความสูง */
    val toolWorld = Art(96f, 64f) {
        for ((hx, hy) in listOf(44f to 32f, 63.1f to 32f, 24.9f to 32f, 53.5f to 48.5f,
                                34.5f to 48.5f, 34.5f to 15.5f, 53.5f to 15.5f))
            path {
                m(hx, hy - 11f); l(hx + 9.5f, hy - 5.5f); l(hx + 9.5f, hy + 5.5f)
                l(hx, hy + 11f); l(hx - 9.5f, hy + 5.5f); l(hx - 9.5f, hy - 5.5f); z()
            }
        path(a = .45f) {
            m(20f, 34f); c(24f, 22f, 38f, 16f, 50f, 20f); c(62f, 24f, 70f, 24f, 72f, 34f)
            c(74f, 44f, 66f, 52f, 54f, 54f); c(42f, 56f, 30f, 52f, 24f, 46f)
        }
        path(a = .45f) {
            m(30f, 34f); c(34f, 26f, 44f, 22f, 52f, 25f); c(60f, 28f, 66f, 30f, 66f, 37f)
            c(66f, 44f, 60f, 47f, 52f, 48f)
        }
        path(a = .45f) { m(40f, 34f); c(42f, 30f, 48f, 28f, 52f, 29f); c(56f, 30f, 60f, 32f, 60f, 36f) }
        circle(34f, 40f, 1.6f, fill = true); circle(52f, 30f, 1.6f, fill = true); circle(60f, 44f, 1.6f, fill = true)
        path(dash = floatArrayOf(2f, 3f)) { m(34f, 40f); q(42f, 26f, 52f, 30f); q(58f, 32f, 64f, 38f) }
        path { m(66f, 38f); l(66f, 28f); l(73f, 30.5f); z() }
        circle(82f, 16f, 6f, a = .7f)
        line(82f, 8f, 82f, 24f, a = .7f); line(74f, 16f, 90f, 16f, a = .7f)
    }

    /** ถาดลูกเต๋า — d20 d4 d6 ในถาด */
    val toolDice = Art(96f, 64f) {
        rect(12f, 12f, 72f, 40f, r = 6f)
        rect(16f, 16f, 64f, 32f, r = 4f, a = .45f)
        path(a = .6f) { m(21f, 24f); q(17f, 32f, 21f, 40f) }
        path(a = .6f) { m(25f, 27f); q(22.5f, 32f, 25f, 37f) }
        d20(38f, 32f, 11f)
        path { m(56f, 26f); l(63f, 40f); l(49f, 40f); z() }
        line(56f, 26f, 56f, 35f); line(56f, 35f, 49f, 40f); line(56f, 35f, 63f, 40f)
        path { m(74f, 20f); l(82f, 25f); l(74f, 30f); l(66f, 25f); z() }
        path { m(66f, 25f); l(66f, 35f); l(74f, 40f); l(82f, 35f); l(82f, 25f) }
        line(74f, 30f, 74f, 40f)
        circle(70f, 25f, 1.2f, fill = true); circle(74f, 25f, 1.2f, fill = true); circle(78f, 25f, 1.2f, fill = true)
    }

    /** โครงกระดูก — หุ่นข้อต่อกำลังเหวี่ยงดาบ */
    val toolRig = Art(96f, 64f) {
        line(8f, 58f, 88f, 58f, a = .4f)
        path(a = .3f) { m(39f, 38f); l(36f, 47f); l(30f, 56f) }
        path(a = .3f) { m(45f, 38f); l(49f, 47f); l(52f, 56f) }
        circle(42f, 13f, 6f)
        line(42f, 19f, 42f, 38f); line(35f, 22f, 49f, 22f); line(38f, 38f, 46f, 38f)
        path { m(35f, 22f); l(29f, 30f); l(32f, 38f) }
        path { m(49f, 22f); l(58f, 16f); l(63f, 9f) }
        line(63f, 9f, 83f, 5f)
        line(66f, 5.5f, 67.2f, 11.5f)
        path { m(39f, 38f); l(31f, 47f); l(34f, 56f) }
        path { m(45f, 38f); l(54f, 46f); l(58f, 56f) }
        path(a = .7f) { m(50.3f, 42.7f); c(48.5f, 45.6f, 50.6f, 49.4f, 55.9f, 50.6f) }
        for ((jx, jy) in listOf(35f to 22f, 49f to 22f, 29f to 30f, 58f to 16f, 39f to 38f,
                                45f to 38f, 31f to 47f, 54f to 46f, 34f to 56f, 58f to 56f))
            circle(jx, jy, 2f)
    }
}
