extends Node2D
# PORCA DE TAMANCO - Noites Cabulosas no Ceará
# Batatinha frita 1,2,3 na Pedra da Caveira (Itapajé, CE)

enum State { COVER, STORY, PLAY, WIN, LOSE }
enum Phase { VERDE, AVISO, VERMELHO }

const W := 960.0
const H := 640.0
const LINHA_Y := 190.0
const PORCA_POS := Vector2(480, 120)
const ALCANCE_VISAO := 900.0
const VEL := 170.0

const HISTORIA := [
	"ITAPAJÉ, CEARÁ.\nNoite alta. Lá do topo da Pedra da Caveira, o vento assobia nas fendas da rocha, e a cidade lá embaixo parece muito longe.",
	"Os mais velhos avisam: quando um toc-toc-toc de tamancos ecoa no lajedo, é a Porca de Tamanco fazendo a ronda. Ela não corre atrás de ninguém. Ela só espera... e olha.",
	"Três vaqueiros subiram a pedra esta semana. Nenhum desceu. Só ficaram os rastros de tamanco na terra e, no meio do caminho, a lamparina de cada um, ainda acesa.",
	"Agora é a sua vez. Você sobe a pedra com a lamparina quase sem óleo e uma decisão na cabeça: acabar com a assombração ou virar mais uma história de assombração.",
	"Há armas espalhadas pelo lajedo. Cada uma tem um preço: umas ficam perto e seguras, outras te deixam à vista. Escolha com cuidado, e se esconda atrás das pedras e dos mandacarus.",
    "Quando o toc-toc parar, ela se vira. Se te vir se mexendo, acabou. E lembre: quanto mais a noite passa, mais furiosa ela fica.\n\nRespire fundo. A noite começa agora."
]
const WIN_TXT := "A Porca de Tamanco tombou. O toc-toc-toc parou para sempre e o vento da Pedra da Caveira finalmente silenciou.\n\nVocê durou %d segundos."
const LOSE_TXT := "A Porca de Tamanco te viu. Toc... toc... toc... Ninguém desceu da pedra para contar.\n\nVocê resistiu %d segundos."

const VIG_SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(0.5, 0.9);
uniform float radius = 0.7;
uniform float red = 0.0;
void fragment() {
    vec2 d = UV - center;
    d.x *= 1.5;
    float dist = length(d);
    float dark = smoothstep(radius * 0.4, radius, dist);
    vec3 col = mix(vec3(0.0), vec3(0.45, 0.0, 0.02), red * 0.5);
    COLOR = vec4(col, clamp(dark * 0.8 + red * 0.1, 0.0, 0.9));
}
"""

var state := State.COVER
var phase := Phase.VERDE
var phase_t := 3.0
var elapsed := 0.0
var dif := 0.0
var tension := 0.0
var time_s := 0.0
var player := Vector2(480, 590)
var moving := false
var step_t := 0.0
var heart_t := 0.0
var arma = null
var toast := ""
var toast_t := 0.0
var story_i := 0
var type_acc := 0.0
var end_t := 0.0
var end_shown := false

var blocks: Array[Rect2] = [
	Rect2(170, 430, 110, 80), Rect2(620, 350, 130, 90), Rect2(400, 500, 100, 70),
	Rect2(800, 500, 110, 80),
	Rect2(340, 320, 90, 80),
	Rect2(262, 300, 24, 80)
]
var armas: Array = [
	{"nome": "Peixeira", "pos": Vector2(120, 570), "alcance": 80.0, "vel": 1.0, "desc": "curta e leve. Chegue bem perto dela", "ativa": true},
	{"nome": "Facão", "pos": Vector2(700, 470), "alcance": 125.0, "vel": 0.8, "desc": "alcance médio, mas pesado: você anda mais devagar", "ativa": true},
	{"nome": "Baladeira", "pos": Vector2(470, 350), "alcance": 330.0, "vel": 1.0, "desc": "um tiro de longe, mas pode errar e irritá-la", "ativa": true}
]
var rock_polys: Array = []
var stars := PackedVector2Array()
var grass: Array = []
var lajes: Array = []
var cracks: Array = []
var nuvens: Array = []

var rng := RandomNumberGenerator.new()
var font: Font
var font_t: Font
var ui: CanvasLayer
var fx: CanvasLayer
var vig: ColorRect
var mat: ShaderMaterial
var music: AudioStreamPlayer
var wind: AudioStreamPlayer
var sfx := {}
var cover_nodes: Array = []
var story_nodes: Array = []
var end_nodes: Array = []
var lbl_story: Label
var lbl_end: Label
var btn_next: Button


func _ready() -> void:
	rng.randomize()
	font = ThemeDB.fallback_font
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Chiller", "Creepster", "Impact", "Arial Black"])
	font_t = sf
	_gerar_cenario()
	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	fx = CanvasLayer.new()
	fx.layer = 1
	add_child(fx)
	# vinheta de lamparina (escuridão + tensão)
	vig = ColorRect.new()
	vig.size = Vector2(W, H)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIG_SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	vig.material = mat
	fx.add_child(vig)
	# áudio
	music = _make_player("music.wav", true, -9.0)
	wind = _make_player("wind.wav", true, -14.0)
	for n in ["step", "clack", "alert", "pickup", "shot", "hit", "scream", "win", "lose", "heart"]:
		sfx[n] = _make_player(n + ".wav", false, 0.0)
	# capa
	var t2 := _label("Noites Cabulosas no Ceará", 44, Vector2(0, 215), Vector2(W, 56), Color(0.8, 0.7, 0.5), HORIZONTAL_ALIGNMENT_CENTER, true)
	var t3 := _label("Pedra da Caveira  •  Itapajé", 18, Vector2(0, 285), Vector2(W, 30), Color(0.6, 0.6, 0.65))
	var b1 := _button("COMEÇAR", Vector2(330, 430), Vector2(300, 64), 28, _on_start)
	var t4 := _label("Setas / WASD: andar     ESPAÇO: atacar", 16, Vector2(0, 520), Vector2(W, 26), Color(0.7, 0.7, 0.75))
	cover_nodes = [t2, t3, b1, t4]
	# história
	lbl_story = _label("", 22, Vector2(90, 432), Vector2(780, 120), Color(0.95, 0.93, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	btn_next = _button("CONTINUAR", Vector2(570, 556), Vector2(320, 44), 18, _next_page)
	var b_skip := _button("PULAR", Vector2(90, 556), Vector2(120, 44), 18, _start_game)
	story_nodes = [lbl_story, btn_next, b_skip]
	# fim de jogo
	lbl_end = _label("", 22, Vector2(100, 320), Vector2(760, 110), Color(0.85, 0.8, 0.72))
	var b_again := _button("TENTAR DE NOVO", Vector2(170, 450), Vector2(300, 56), 22, _start_game)
	var b_cover := _button("VOLTAR À CAPA", Vector2(490, 450), Vector2(300, 56), 22, _to_cover)
	end_nodes = [lbl_end, b_again, b_cover]
	_set_state(State.COVER)


func _gerar_cenario() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for b in blocks:
		var pts := PackedVector2Array()
		if b.size.x >= 40.0:
			var c := b.get_center()
			for i in 14:
				var ang := TAU * i / 14.0
				var k := r.randf_range(0.86, 1.08)
				pts.append(c + Vector2(cos(ang) * b.size.x * 0.56 * k, sin(ang) * b.size.y * 0.6 * k))
		rock_polys.append(pts)
	for i in 70:
		stars.append(Vector2(r.randf_range(0, W), r.randf_range(0, 150)))
	for i in 70:
		var x := r.randf_range(0, W)
		if r.randf() < 0.6:
			x = r.randf_range(0, 150) if r.randf() < 0.5 else r.randf_range(810, W)
		grass.append(Vector3(x, r.randf_range(215, H - 10), r.randf_range(10, 30)))
	for i in 24:
		lajes.append(Vector3(r.randf_range(0, W), r.randf_range(215, H), r.randf_range(25, 70)))
	for i in 16:
		var a := Vector2(r.randf_range(0, W), r.randf_range(215, H))
		cracks.append([a, a + Vector2(r.randf_range(-60, 60), r.randf_range(-25, 25))])
	for i in 14:
		nuvens.append(Vector3(r.randf_range(0, W), r.randf_range(20, 130), r.randf_range(22, 50)))


func _make_player(file: String, loop: bool, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var st = load("res://audio/" + file)
	if loop and st is AudioStreamWAV:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = st.data.size() / 2
	p.stream = st
	p.volume_db = vol
	add_child(p)
	return p


func _label(txt: String, sz: int, pos: Vector2, size_: Vector2, col: Color, al := HORIZONTAL_ALIGNMENT_CENTER, horror := false) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.size = size_
	l.horizontal_alignment = al
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", sz)
	if horror:
		l.add_theme_font_override("font", font_t)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	ui.add_child(l)
	return l


func _button(txt: String, pos: Vector2, sz: Vector2, fsize: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = pos
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(fsize * 1.4))
	b.add_theme_font_override("font", font_t)
	b.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	b.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.25))
	b.add_theme_color_override("font_pressed_color", Color(1, 0.3, 0.25))
	for n in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.3, 0.03, 0.03) if n == "hover" else Color(0.04, 0.02, 0.02)
		sb.set_border_width_all(3)
		sb.border_color = Color(0.6, 0.04, 0.04)
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override(n, sb)
	b.pressed.connect(cb)
	ui.add_child(b)
	return b


func _set_state(s: State) -> void:
	state = s
	for n in cover_nodes:
		n.visible = (s == State.COVER)
	for n in story_nodes:
		n.visible = (s == State.STORY)
	for n in end_nodes:
		n.visible = false
	vig.visible = (s == State.PLAY)
	position = Vector2.ZERO


func _on_start() -> void:
	music.play()
	story_i = 0
	_set_state(State.STORY)
	_show_page()


func _show_page() -> void:
	lbl_story.text = HISTORIA[story_i]
	lbl_story.visible_characters = 0
	type_acc = 0.0
	btn_next.text = "COMEÇAR A NOITE" if story_i == HISTORIA.size() - 1 else "CONTINUAR"


func _next_page() -> void:
	var vc := lbl_story.visible_characters
	if vc != -1 and vc < lbl_story.text.length():
		type_acc = 9999.0
		lbl_story.visible_characters = -1
		return
	story_i += 1
	if story_i >= HISTORIA.size():
		_start_game()
	else:
		_show_page()


func _to_cover() -> void:
	music.stop()
	wind.stop()
	_set_state(State.COVER)


func _start_game() -> void:
	elapsed = 0.0
	dif = 0.0
	tension = 0.0
	phase = Phase.VERDE
	phase_t = 2.5
	player = Vector2(480, 590)
	arma = null
	for a in armas:
		a["ativa"] = true
	heart_t = 1.0
	end_shown = false
	end_t = 0.0
	_set_state(State.PLAY)
	if not music.playing:
		music.play()
	wind.play()
	_say("Ela está de costas. Ande... e escolha uma arma.")


func _say(t: String) -> void:
	toast = t
	toast_t = 3.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ok: bool = event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
		match state:
			State.COVER:
				if ok:
					_on_start()
			State.STORY:
				if ok:
					_next_page()
			State.PLAY:
				if event.keycode == KEY_SPACE:
					_atacar()
			State.WIN, State.LOSE:
				if ok and end_shown:
					_start_game()


func _process(delta: float) -> void:
	time_s += delta
	match state:
		State.STORY:
			type_acc += delta * 45.0
			if lbl_story.visible_characters != -1:
				lbl_story.visible_characters = int(type_acc)
		State.PLAY:
			_play(delta)
		State.WIN, State.LOSE:
			end_t += delta
			var lim := 0.9 if state == State.WIN else 1.6
			if not end_shown and end_t > lim:
				end_shown = true
				var txt := WIN_TXT if state == State.WIN else LOSE_TXT
				lbl_end.text = txt % int(elapsed)
				for n in end_nodes:
					n.visible = true
				sfx["win" if state == State.WIN else "lose"].play()
	queue_redraw()


func _play(delta: float) -> void:
	elapsed += delta
	dif = clampf(elapsed / 75.0, 0.0, 1.0)
	toast_t -= delta
	_update_phase(delta)
	_update_player(delta)
	var target := 0.0
	if phase == Phase.VERMELHO:
		target = 1.0
	elif phase == Phase.AVISO:
		target = 0.4
	tension = move_toward(tension, target, delta * 3.0)
	heart_t -= delta
	if heart_t <= 0.0:
		sfx["heart"].play()
		heart_t = lerpf(1.1, 0.45, maxf(dif, tension))
	var shake := 3.0 * tension if phase == Phase.VERMELHO else 0.0
	position = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake
	mat.set_shader_parameter("center", player / Vector2(W, H))
	mat.set_shader_parameter("radius", lerpf(0.72, 0.46, dif) + sin(time_s * 9.0) * 0.012 + rng.randf_range(-0.01, 0.01))
	mat.set_shader_parameter("red", tension)
	if phase == Phase.VERMELHO and moving and _visible_to_porca(player):
		_end(false)


func _update_phase(delta: float) -> void:
	phase_t -= delta
	if phase_t > 0.0:
		return
	match phase:
		Phase.VERDE:
			phase = Phase.AVISO
			phase_t = lerpf(0.9, 0.35, dif)
			sfx["clack"].play()
		Phase.AVISO:
			phase = Phase.VERMELHO
			phase_t = rng.randf_range(2.4, 3.8) + 1.2 * dif
			sfx["alert"].play()
		Phase.VERMELHO:
			phase = Phase.VERDE
			phase_t = maxf(0.7, rng.randf_range(1.6, 3.4) * (1.0 - 0.6 * dif))


func _update_player(delta: float) -> void:
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A): d.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): d.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W): d.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S): d.y += 1
	moving = d != Vector2.ZERO
	if not moving:
		return
	var mult: float = 1.0
	if arma != null:
		mult = arma["vel"]
	var mv := d.normalized() * VEL * mult * delta
	var nx := Vector2(clampf(player.x + mv.x, 15.0, W - 15.0), player.y)
	if not _hits_block(nx):
		player = nx
	var ny := Vector2(player.x, clampf(player.y + mv.y, 60.0, H - 40.0))
	if not _hits_block(ny):
		player = ny
	step_t -= delta
	if step_t <= 0.0:
		sfx["step"].play()
		step_t = 0.28
	for a in armas:
		if a["ativa"] and arma != a and player.distance_to(a["pos"]) < 24.0:
			arma = a
			sfx["pickup"].play()
			_say("Pegou: " + a["nome"] + " - " + a["desc"])


func _atacar() -> void:
	if arma == null:
		_say("Você precisa de uma arma!")
		return
	if phase == Phase.VERMELHO and _visible_to_porca(player):
		_end(false)
		return
	if player.distance_to(PORCA_POS) > arma["alcance"]:
		_say("Longe demais! Chegue mais perto da Porca.")
		return
	if arma["nome"] == "Baladeira":
		sfx["shot"].play()
		if not _line_clear(player) or rng.randf() > 0.6:
			arma["ativa"] = false
			arma = null
			_say("ERROU! Ela ouviu o tiro!")
			phase = Phase.AVISO
			phase_t = 0.35
			sfx["clack"].play()
			return
	_end(true)


func _end(win: bool) -> void:
	_set_state(State.WIN if win else State.LOSE)
	end_t = 0.0
	end_shown = false
	music.stop()
	wind.stop()
	if win:
		sfx["hit"].play()
	else:
		sfx["scream"].play()


func _hits_block(p: Vector2) -> bool:
	for r in blocks:
		if r.grow(12.0).has_point(p):
			return true
	return false


func _line_clear(p: Vector2) -> bool:
	for r in blocks:
		if _seg_hits_rect(PORCA_POS, p, r):
			return false
	return true


func _visible_to_porca(p: Vector2) -> bool:
	var to := p - PORCA_POS
	if to.length() > ALCANCE_VISAO:
		return false
	if absf(to.angle_to(Vector2.DOWN)) > lerpf(0.55, 0.85, dif):
		return false
	return _line_clear(p)


func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(b):
		return true
	var c := [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false


# ---------------------------------------------------------------- desenho

func _txt(p: Vector2, t: String, sz: int, col: Color, w: float = -1.0, al := HORIZONTAL_ALIGNMENT_LEFT, f: Font = null) -> void:
	var ft: Font = f if f != null else font
	draw_string(ft, p + Vector2(1, 1), t, al, w, sz, Color(0, 0, 0, 0.85))
	draw_string(ft, p, t, al, w, sz, col)


# título "sangrando": texto vermelho com gotas escorrendo e leve piscar
func _titulo(t: String, base: Vector2, sz: int, col: Color, ndrips: int) -> void:
	var w: float = font_t.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x0 := base.x - w / 2.0
	var fl := 1.0 if rng.randf() > 0.04 else 0.55
	var c := Color(col.r * fl, col.g * fl, col.b * fl)
	draw_string(font_t, Vector2(x0 + 4, base.y + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.9))
	draw_string(font_t, Vector2(x0, base.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)
	for i in ndrips:
		var dx := x0 + w * (float(i) + 0.5) / ndrips + sin(i * 12.9) * 12.0
		var ln := sz * (0.2 + 0.4 * absf(sin(i * 7.3 + time_s * 0.4)))
		var y0 := base.y - sz * 0.08
		draw_line(Vector2(dx, y0), Vector2(dx, y0 + ln), c.darkened(0.15), 3.0)
		draw_circle(Vector2(dx, y0 + ln), 4.0, c.darkened(0.15))


func _draw() -> void:
	_draw_cenario()
	if state == State.COVER or state == State.STORY:
		if state == State.COVER:
			_draw_face(Vector2(480, 330), 2.4)
			draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.84))
			_titulo("PORCA DE TAMANCO", Vector2(480, 160), 84, Color(0.72, 0.03, 0.03), 12)
		else:
			_draw_porca(PORCA_POS, 1)
			draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(60, 390, 840, 220), Color(0, 0, 0, 0.88))
			draw_rect(Rect2(60, 390, 840, 220), Color(0.5, 0.03, 0.03), false, 3.0)
			_txt(Vector2(90, 422), "NARRADOR", 26, Color(0.75, 0.05, 0.05), -1.0, HORIZONTAL_ALIGNMENT_LEFT, font_t)
		return
	if state == State.PLAY and phase == Phase.VERMELHO:
		var cone := lerpf(0.55, 0.85, dif)
		draw_colored_polygon(PackedVector2Array([PORCA_POS,
			PORCA_POS + Vector2.DOWN.rotated(-cone) * ALCANCE_VISAO,
			PORCA_POS + Vector2.DOWN.rotated(cone) * ALCANCE_VISAO]), Color(1, 0, 0, 0.17))
	if state == State.PLAY and arma != null:
		draw_arc(PORCA_POS, arma["alcance"], 0, TAU, 72, Color(1, 0.8, 0.3, 0.35), 2.0)
	for a in armas:
		if a["ativa"] and arma != a:
			var p: Vector2 = a["pos"]
			draw_circle(p, 18 + 3 * sin(time_s * 4.0), Color(1, 0.85, 0.3, 0.2))
			_draw_arma(p, a["nome"])
			_txt(p + Vector2(-40, -22), a["nome"], 13, Color(1, 0.9, 0.5), 80.0, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_pedras()
	var mode := 0
	if state == State.WIN:
		mode = 2
	elif phase == Phase.VERMELHO:
		mode = 1
	_draw_porca(PORCA_POS, mode)
	if mode == 0:
		_txt(PORCA_POS + Vector2(-60, -48), "Porca de Tamanco", 14, Color(1, 0.8, 0.85), 120.0, HORIZONTAL_ALIGNMENT_CENTER)
	draw_circle(player, 11, Color(0.95, 0.85, 0.6))
	draw_rect(Rect2(player.x - 7, player.y + 8, 14, 16), Color(0.2, 0.4, 0.7))
	if state == State.PLAY:
		_draw_hud()
	elif state == State.LOSE and not end_shown:
		draw_rect(Rect2(0, 0, W, H), Color(0.4, 0, 0, 0.55))
		_draw_face(Vector2(480 + rng.randf_range(-8, 8), 300 + rng.randf_range(-8, 8)), 2.0 + end_t * 1.2)
	if (state == State.WIN or state == State.LOSE) and end_shown:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.9))
		if state == State.LOSE:
			_titulo("VOCÊ MORREU", Vector2(480, 170), 100, Color(0.72, 0.03, 0.03), 12)
			_titulo("FIM DE JOGO", Vector2(480, 255), 56, Color(0.6, 0.03, 0.03), 8)
		else:
			_titulo("VOCÊ GANHOU!", Vector2(480, 170), 100, Color(0.92, 0.85, 0.65), 0)
			_titulo("A NOITE ACABOU", Vector2(480, 255), 52, Color(0.7, 0.65, 0.5), 0)


func _draw_cenario() -> void:
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, 240), Vector2(0, 240)]),
		PackedColorArray([Color(0.02, 0.03, 0.09), Color(0.02, 0.03, 0.09), Color(0.16, 0.2, 0.3), Color(0.16, 0.2, 0.3)]))
	for s in stars:
		draw_circle(s, 1.2, Color(1, 1, 1, 0.7))
	draw_circle(Vector2(800, 80), 54, Color(0.88, 0.9, 0.8, 0.08))
	draw_circle(Vector2(800, 80), 36, Color(0.88, 0.9, 0.8))
	for c in nuvens:
		var x: float = fposmod(c.x + time_s * 5.0, W + 300.0) - 150.0
		draw_circle(Vector2(x, c.y), c.z, Color(0.1, 0.12, 0.18, 0.55))
		draw_circle(Vector2(x + c.z * 0.9, c.y + 6), c.z * 0.8, Color(0.1, 0.12, 0.18, 0.55))
	# montanhas ao longe (vista da pedra)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 210), Vector2(0, 150), Vector2(120, 118), Vector2(260, 160),
		Vector2(400, 108), Vector2(560, 150), Vector2(720, 104), Vector2(860, 145), Vector2(W, 118), Vector2(W, 210)]), Color(0.07, 0.11, 0.16))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 210), Vector2(0, 178), Vector2(160, 150), Vector2(320, 186),
		Vector2(520, 152), Vector2(700, 190), Vector2(W, 160), Vector2(W, 210)]), Color(0.04, 0.07, 0.08))
	# chão de granito
	draw_rect(Rect2(0, LINHA_Y, W, H - LINHA_Y), Color(0.22, 0.23, 0.26))
	draw_colored_polygon(PackedVector2Array([Vector2(330, 195), Vector2(385, 150), Vector2(575, 150), Vector2(630, 195)]), Color(0.3, 0.31, 0.35))
	for l in lajes:
		draw_set_transform(Vector2(l.x, l.y), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, l.z, Color(0.3, 0.31, 0.35, 0.45))
	for g in grass:
		draw_set_transform(Vector2(g.x, g.y), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, g.z, Color(0.1, 0.3, 0.13, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for c in cracks:
		draw_line(c[0], c[1], Color(0.1, 0.1, 0.12), 2.0)
	draw_line(Vector2(0, LINHA_Y), Vector2(W, LINHA_Y), Color(0.85, 0.12, 0.12, 0.8), 3.0)


func _draw_pedras() -> void:
	for i in blocks.size():
		var r := blocks[i]
		if r.size.x < 40.0:
			var verde := Color(0.1, 0.4, 0.17)
			draw_rect(r, verde)
			draw_rect(Rect2(r.position.x - 10, r.position.y + 15, 10, 8), verde)
			draw_rect(Rect2(r.end.x, r.position.y + 30, 10, 8), verde)
		else:
			var pts: PackedVector2Array = rock_polys[i]
			draw_colored_polygon(pts, Color(0.36, 0.37, 0.41))
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, Color(0.58, 0.6, 0.66), 2.0)


func _draw_arma(p: Vector2, nome: String) -> void:
	var aco := Color(0.85, 0.87, 0.9)
	var madeira := Color(0.5, 0.3, 0.12)
	if nome == "Peixeira":
		draw_line(p + Vector2(-6, 6), p + Vector2(9, -9), aco, 3.0)
		draw_line(p + Vector2(-6, 6), p + Vector2(-11, 11), madeira, 5.0)
	elif nome == "Facão":
		draw_line(p + Vector2(-8, 8), p + Vector2(11, -11), aco, 7.0)
		draw_line(p + Vector2(-8, 8), p + Vector2(-13, 13), madeira, 6.0)
	else:
		draw_line(p + Vector2(0, 11), p + Vector2(0, -1), madeira, 4.0)
		draw_line(p + Vector2(0, -1), p + Vector2(-8, -12), madeira, 3.0)
		draw_line(p + Vector2(0, -1), p + Vector2(8, -12), madeira, 3.0)
		draw_line(p + Vector2(-8, -12), p + Vector2(8, -12), Color(0.8, 0.2, 0.2), 2.0)


func _draw_porca(c: Vector2, mode: int) -> void:
	var rosa := Color(0.93, 0.55, 0.65)
	var marrom := Color(0.45, 0.25, 0.1)
	if mode == 2:
		draw_set_transform(c + Vector2(0, 30), 1.4, Vector2.ONE)
		draw_circle(Vector2.ZERO, 30, rosa.darkened(0.3))
		draw_line(Vector2(-14, -8), Vector2(-4, 2), Color.BLACK, 3.0)
		draw_line(Vector2(-14, 2), Vector2(-4, -8), Color.BLACK, 3.0)
		draw_line(Vector2(4, -8), Vector2(14, 2), Color.BLACK, 3.0)
		draw_line(Vector2(4, 2), Vector2(14, -8), Color.BLACK, 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if mode == 1:
		_draw_face(c, 0.3)
	else:
		draw_circle(c, 30, rosa.darkened(0.15))
		draw_circle(c + Vector2(-20, -22), 9, rosa.darkened(0.15))
		draw_circle(c + Vector2(20, -22), 9, rosa.darkened(0.15))
		draw_circle(c + Vector2(0, -34), 6, rosa)
		if phase == Phase.AVISO and state == State.PLAY:
			draw_circle(c + Vector2(-27, 2), 3, Color(1, 0.2, 0.1))
			draw_circle(c + Vector2(27, 2), 3, Color(1, 0.2, 0.1))
	draw_rect(Rect2(c.x - 18, c.y + 28, 12, 12), marrom)
	draw_rect(Rect2(c.x + 6, c.y + 28, 12, 12), marrom)


func _draw_face(c: Vector2, s: float) -> void:
	var rosa := Color(0.93, 0.55, 0.65)
	draw_set_transform(c, 0.0, Vector2(s, s))
	draw_circle(Vector2(-80, -85), 32, rosa)
	draw_circle(Vector2(80, -85), 32, rosa)
	draw_circle(Vector2.ZERO, 100, rosa)
	draw_circle(Vector2(0, 35), 42, Color(0.75, 0.35, 0.45))
	draw_circle(Vector2(-15, 35), 8, Color.BLACK)
	draw_circle(Vector2(15, 35), 8, Color.BLACK)
	draw_circle(Vector2(-38, -15), 16, Color(0.9, 0.05, 0.05))
	draw_circle(Vector2(38, -15), 16, Color(0.9, 0.05, 0.05))
	draw_circle(Vector2(-38, -15), 5, Color.BLACK)
	draw_circle(Vector2(38, -15), 5, Color.BLACK)
	draw_rect(Rect2(-60, 70, 120, 28), Color.BLACK)
	for i in 6:
		var x := -56.0 + i * 20.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, 70), Vector2(x + 14, 70), Vector2(x + 7, 88)]), Color(0.95, 0.95, 0.85))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_hud() -> void:
	draw_rect(Rect2(0, 0, W, 54), Color(0, 0, 0, 0.65))
	draw_line(Vector2(0, 54), Vector2(W, 54), Color(0.55, 0.1, 0.1), 2.0)
	_txt(Vector2(16, 22), "TEMPO", 12, Color(0.7, 0.7, 0.75))
	_txt(Vector2(16, 46), "%d s" % int(elapsed), 22, Color.WHITE)
	var st := "ELA ESTÁ DE COSTAS"
	var col := Color(0.4, 1, 0.4)
	if phase == Phase.AVISO:
		st = "TOC-TOC... ELA VAI SE VIRAR!"
		col = Color(1, 0.8, 0.2)
	elif phase == Phase.VERMELHO:
		st = "PARE! ELA ESTÁ OLHANDO"
		col = Color(1, 0.3, 0.3)
	draw_rect(Rect2(290, 8, 380, 38), Color(col.r, col.g, col.b, 0.22))
	draw_rect(Rect2(290, 8, 380, 38), col, false, 2.0)
	_txt(Vector2(290, 36), st, 30, col, 380.0, HORIZONTAL_ALIGNMENT_CENTER, font_t)
	_txt(Vector2(760, 22), "FÚRIA DA PORCA", 12, Color(0.9, 0.6, 0.6))
	draw_rect(Rect2(760, 30, 180, 12), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(760, 30, 180 * dif, 12), Color(0.85, 0.1, 0.1))
	draw_rect(Rect2(0, H - 34, W, 34), Color(0, 0, 0, 0.65))
	var at := "ARMA: nenhuma"
	if arma != null:
		at = "ARMA: " + arma["nome"]
	_txt(Vector2(16, H - 11), at, 18, Color(1, 0.9, 0.5))
	_txt(Vector2(500, H - 11), "Setas/WASD: andar    ESPAÇO: atacar", 16, Color(0.75, 0.75, 0.8), 450.0, HORIZONTAL_ALIGNMENT_RIGHT)
	if toast_t > 0.0:
		_txt(Vector2(80, H - 70), toast, 20, Color(1, 1, 1, minf(1.0, toast_t)), 800.0, HORIZONTAL_ALIGNMENT_CENTER)
