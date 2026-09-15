extends Node2D
## 粒子特效：全部由 Godot 官方节点与资源实现。
##
## 层次（见 particle_fx.tscn）：
##   Burst     GPUParticles2D  —— 球撞到圆环实心处（未从缺口穿过）的碰撞反馈
##   RingBreak GPUParticles2D  —— 球从缺口逃出、圆环碎裂
##   Trail     GPUParticles2D  —— 小球运动轨迹（`trail_enabled` 官方拖尾）
##
## 三个节点都是 GPU 粒子（`GPUParticles2D` + `ParticleProcessMaterial`），
## 发射/生命周期/阻尼/重力/缩放曲线/颜色渐变全部交给引擎，本脚本只负责：
##   1. 把 res://particles.cfg 的参数套到节点上；
##   2. 在正确的世界位置触发一次性爆发；
##   3. 每帧把拖尾发射器挪到球的位置。
##
## ⚠️ 渲染器必须是 forward_plus。Compatibility 渲染器不支持官方粒子拖尾
##    （运行时会打印 "The Compatibility renderer does not support particle trails."），
##    `trail_enabled` 会完全失效。
##
## 坐标：本节点直接挂在 `Main` 下，与 `World` 共用同一套**世界坐标**
## （`Camera2D` 负责换算到屏幕），所以传给 `impact()` / `emit_trail()` 的
## 位置就是世界坐标，不需要任何换算。
## ⚠️ 早期版本曾用一个 `position/scale` 对齐 `world_to_screen()` 的容器节点，
##    接入 `Camera2D` 后那种做法会**二次偏移**，已废弃。

const CFG_PATH := "res://particles.cfg"


class Ref:
	var node: GPUParticles2D
	var mat: ParticleProcessMaterial

	func _init(p_node: GPUParticles2D) -> void:
		node = p_node
		mat = p_node.process_material as ParticleProcessMaterial


var burst: Ref
var ring_break: Ref
var trail: Ref

var _cfg := ConfigFile.new()
var _cfg_loaded := false
var _trail_frame := 0


func _ready() -> void:
	burst = Ref.new($Burst)
	ring_break = Ref.new($RingBreak)
	trail = Ref.new($Trail)
	_cfg_loaded = _cfg.load(CFG_PATH) == OK
	if not _cfg_loaded:
		push_warning("particles.cfg 未加载，沿用 particle_fx.tscn 里保存的参数。")
		return
	for s in ["burst", "ring_break", "trail"]:
		if _cfg.has_section(s):
			_apply(_ref_for(s), s)


func _ref_for(section: String) -> Ref:
	match section:
		"burst": return burst
		"ring_break": return ring_break
		_: return trail


# ------------------------------------------------------------------ 配置套用

## 只覆盖配置文件里**显式写出**的键；没写的沿用场景里保存的值，
## 所以在编辑器里调好的观感不会被配置文件里的遗漏项清掉。
func _apply(r: Ref, s: String) -> void:
	var one_shot: bool = _val(s, "one_shot", r.node.one_shot)
	r.node.one_shot = one_shot
	r.node.amount = _val(s, "amount", r.node.amount)
	r.node.lifetime = _val(s, "lifetime", r.node.lifetime)
	r.node.explosiveness = _val(s, "explosiveness", r.node.explosiveness)
	r.mat.spread = _val(s, "spread", r.mat.spread)
	r.mat.initial_velocity_min = _val(s, "velocity_min", r.mat.initial_velocity_min)
	r.mat.initial_velocity_max = _val(s, "velocity_max", r.mat.initial_velocity_max)
	r.mat.damping_min = _val(s, "damping_min", r.mat.damping_min)
	r.mat.damping_max = _val(s, "damping_max", r.mat.damping_max)
	r.mat.gravity = Vector3(0.0, _val(s, "gravity", r.mat.gravity.y), 0.0)
	r.mat.scale_min = _val(s, "scale_min", r.mat.scale_min)
	r.mat.scale_max = _val(s, "scale_max", r.mat.scale_max)
	if _cfg.has_section_key(s, "emission_radius"):
		r.mat.emission_sphere_radius = _val(s, "emission_radius", r.mat.emission_sphere_radius)
	# 一次性发射器初始化时保持静默，等 impact()/ring_break_at() 触发
	if one_shot:
		r.node.emitting = false
	else:
		r.node.emitting = _val(s, "enabled", r.node.emitting)


func _val(s: String, key: String, fallback: Variant) -> Variant:
	if not _cfg.has_section_key(s, key):
		return fallback
	var v: Variant = _cfg.get_value(s, key)
	# 用 fallback 的静态类型决定转换方向，避免把 float 塞进 int 属性。
	match typeof(fallback):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return float(v)
		TYPE_BOOL:
			return bool(v)
	return v


# ------------------------------------------------------------------ 游戏调用

## 球撞到圆环实心处的碰撞反馈。dir_world 为环心指向撞击点的方向（世界坐标）。
func impact(world_pos: Vector2, dir_world: Vector2, color: Color) -> void:
	_fire(burst, world_pos, dir_world, color)


## 圆环被撞碎（球从缺口逃出）。
func ring_break_at(world_pos: Vector2, dir_world: Vector2, color: Color) -> void:
	_fire(ring_break, world_pos, dir_world, color)


func _fire(r: Ref, world_pos: Vector2, dir_world: Vector2, color: Color) -> void:
	if r == null:
		return
	r.node.position = world_pos
	# 让爆发扇面朝撞击点法线方向铺开。
	var d := dir_world.normalized()
	if d != Vector2.ZERO:
		r.node.rotation = d.angle() + PI * 0.5
	r.mat.color = color
	# 官方文档：one_shot 发射器在 GPU 上计算，用 restart() 而不是 emitting=true，
	# 否则收到信号后可能有一小段时间不重新开始发射周期。
	r.node.restart()


## 把小球的运动轨迹交给官方拖尾发射器。
func emit_trail(ball_world: Vector2, radius_world: float, color: Color) -> void:
	if trail == null:
		return
	trail.node.position = ball_world
	trail.mat.color = color
	var interval := maxi(1, int(_val("trail", "sample_interval", 1)))
	_trail_frame += 1
	# 官方没有发射频率参数，用抽帧开关 emitting 来降采样发射密度。
	if interval > 1:
		trail.node.emitting = (_trail_frame % interval) == 0
	if _cfg.has_section_key("trail", "emission_radius_scale"):
		var k := float(_val("trail", "emission_radius_scale", 0.5))
		trail.mat.emission_sphere_radius = maxf(0.5, radius_world * k)


func stop_trail() -> void:
	if trail != null:
		trail.node.emitting = false


func restart_trail() -> void:
	if trail == null:
		return
	_trail_frame = 0
	trail.node.emitting = true
	trail.node.restart()
