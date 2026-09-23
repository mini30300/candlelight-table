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
}
