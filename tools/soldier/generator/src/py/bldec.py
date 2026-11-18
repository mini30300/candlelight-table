# ลดสามเหลี่ยมด้วย Blender (Decimate แบบ collapse + กลุ่มจุดยอด): บริเวณที่น้ำหนักต่ำ (หน้า ตา ปาก มือ) ลดน้อยกว่า
#   ต้นทุนการยุบขอบใน Blender = ข้อผิดพลาดกำลังสอง + ความยาวขอบ × (2 - w1 - w2) × factor  -> factor เล็ก = ไล่ระดับได้
#   ผลคงที่ทุกครั้งเมื่อข้อมูลเข้าเหมือนเดิม (ไม่มีการสุ่ม)
import numpy as np

_bpy = None


def _get():
    global _bpy
    if _bpy is None:
        import bpy
        _bpy = bpy
    return _bpy


def decimate(V, F, target, w=None, factor=0.0):
    """V (n,3), F (m,3) ; target = จำนวนสามเหลี่ยม ; w = น้ำหนักการลด 0..1 ต่อจุด (1 = ลดปกติ) ; คืน (V2, F2)"""
    bpy = _get()
    me = bpy.data.meshes.new("dec")
    me.from_pydata(np.asarray(V, float).tolist(), [], np.asarray(F, int).tolist())
    me.update()
    ob = bpy.data.objects.new("dec", me)
    bpy.context.scene.collection.objects.link(ob)
    md = ob.modifiers.new("d", "DECIMATE")
    md.decimate_type = "COLLAPSE"
    md.ratio = float(target) / len(F)
    md.use_collapse_triangulate = True
    if w is not None and factor > 0:
        vg = ob.vertex_groups.new(name="w")
        q = np.round(np.clip(w, 0, 1) * 100).astype(int)
        for lv in np.unique(q):
            vg.add(np.nonzero(q == lv)[0].tolist(), lv / 100.0, "REPLACE")
        md.vertex_group = "w"
        md.vertex_group_factor = float(factor)
    dg = bpy.context.evaluated_depsgraph_get()
    oe = ob.evaluated_get(dg)
    m2 = oe.to_mesh()
    n = len(m2.vertices)
    V2 = np.empty(n * 3)
    m2.vertices.foreach_get("co", V2)
    F2 = np.array([p.vertices[:] for p in m2.polygons], np.int64)
    oe.to_mesh_clear()
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    return V2.reshape(-1, 3).astype(np.float64), F2
