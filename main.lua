--nbody particles in love

local lg = love.graphics

lg.setDefaultFilter("nearest", "nearest")

--dimension of the particles textures
local dim = 64
--time passes faster or slower
local timescale = 1.0
--break update step into multiple updates
local steps_per_render = 1
--percentage of particles that exert force per-update
local sampling_percent = 1.0
--visual zoom
local zoom = 1
--cam position
local cx, cy = 0, 0

--format for simulation configurations
local sim_template = {
	--which worldgen to use
	gen = "dense",
	--stronger or weaker forces
	force_scale = 1.0,
	--distance scale forces act over
	force_distance = 10.0,
	--the term included in the shader inline; determines the "style" of force
	force_term = "vec3 f = dir;",
	--scale of masses present
	--1 = all particles are same mass
	--500 = particles mass between 1 and 500
	mass_scale = 1.0,
	--the term included in the shader that
	--determines the distribution of particle masses
	mass_distribution = "u * u",
}
local sim_configs = {
	gravity = {
		gen = "dense",
		force_scale = 1.0,
		force_distance = 10.0,
		force_term = "vec3 f = dir * (m1 * m2) / max(1.0, r * r);",
		mass_scale = 1.0,
		mass_distribution = "u * u",
	},
	strings = {
		gen = "sparse",
		force_scale = 0.00005,
		force_distance = 20.0,
		force_term = "vec3 f = dir * m2 * max(1.0, r * r);",
		mass_scale = 5.0,
		mass_distribution = "u",
	},
	cloud = {
		gen = "dense",
		force_scale = 0.01,
		force_distance = 10.0,
		force_term = "vec3 f = dir * (r * m1 * 0.3 - 5.0);",
		mass_scale = 2.0,
		mass_distribution = "u",
	},
	boids = {
		gen = "dense",
		force_scale = 0.3,
		force_distance = 10.0,
		force_term = "vec3 f = dir / max(1.0, r);",
		mass_scale = 2.0,
		mass_distribution = "u",
	},
	shy = {
		gen = "dense",
		force_scale = 0.05,
		force_distance = 5.0,
		force_term = "vec3 f = dir * float(r > 2.0);",
		mass_scale = 2.0,
		mass_distribution = "u",
	},
	atoms = {
		gen = "dense",
		force_scale = 0.5,
		force_distance = 15.0,
		force_term = "vec3 f = dir * float(r < 2.0);",
		mass_scale = 10.0,
		mass_distribution = "u",
	},
	sines = {
		gen = "dense",
		force_scale = 0.1,
		force_distance = 40.0,
		force_term = "vec3 f = dir * sin(r);",
		mass_scale = 10.0,
		mass_distribution = "u",
	},
	cosines = {
		gen = "sparse",
		force_scale = 0.05,
		force_distance = 25.0,
		force_term = "vec3 f = dir * m2 * -cos(r);",
		mass_scale = 10.0,
		mass_distribution = "u",
	},
	spiral = {
		gen = "sparse",
		force_scale = 0.01,
		force_distance = 5.0,
		force_term = "vec3 f = dir * m2 + vec3(rotate(dir.xy, 0.025 * m1 * 3.14159), dir.z) * 0.5;",
		mass_scale = 5.0,
		mass_distribution = "u",
	},
	center_avoid = {
		gen = "sparse",
		force_scale = 1.0,
		force_distance = 1.0,
		constant_term = "vec3 acc = -pos; acc = acc / (length(acc) * 0.1);",
		force_term = "vec3 f = -(dir * m1 * m2 / (r * r)) * 10.0;",
		mass_scale = 1.0,
		mass_distribution = "u",
	},
	nebula = {
		gen = "dense",
		force_scale = 1.0,
		force_distance = 2.0,
		force_term = [[
			float factor = min(mix(-m2, 1.0, r), 1.0) / max(0.1, r * r) * m1;
			vec3 f = dir * factor;
		]],
		mass_scale = 30.0,
		mass_distribution = "u",
	},
}

--parameters of worldgen
local gen_configs = {
	dense = {
		walk_scale = 3,
		bigjump_scale = 30,
		bigjump_chance = 0.01,
		scatter_scale = 0.1,
	},
	sparse = {
		walk_scale = 1,
		bigjump_scale = 35,
		bigjump_chance = 0.02,
		scatter_scale = 3,
	},
}

local init_vel_scale = 1.0

--proportion to fade towards black between frames
--basically smaller = longer trails
local basic_fade_amount = 0.1

--amount to downres the render buffer
local downres = 2

--format of the buffer textures
local fmt_t = {format="rgba32f"}
--set up separate buffers
local particles = {
	pos = lg.newCanvas(dim, dim, fmt_t),
	vel = lg.newCanvas(dim, dim, fmt_t),
	acc = lg.newCanvas(dim, dim, fmt_t),
}

--larger points = more chunky look
--smaller = "higher fidelity"
lg.setPointSize(1)

--hide mouse since it's not used
love.mouse.setVisible(false)


local rotate_frag = [[
vec2 rotate(vec2 v, float t) {
	float s = sin(t);
	float c = cos(t);
	return vec2(
		c * v.x - s * v.y,
		s * v.x + c * v.y
	);
}
]]

local sim_types = {}
local selected_sim = nil
--pick random sim type
function pick_sim()
	selected_sim = sim_types[love.math.random(1, #sim_types)]
end
for k,v in pairs(sim_configs) do
	local accel_shader = lg.newShader([[
	uniform Image MainTex;
	const float timescale = ]]..timescale..[[;
	const float force_scale = ]]..v.force_scale..[[;
	const float force_distance = ]]..v.force_distance..[[;
	uniform float dt;

	uniform float sampling_percent;
	uniform float sampling_percent_offset;
	const int dim = ]]..dim..[[;
	#ifdef PIXEL
	const float mass_scale = ]]..v.mass_scale..[[;
	float mass(float u) {
		return mix(1.0, mass_scale, ]]..v.mass_distribution..[[);
	}

	]]..rotate_frag..[[

	void effect() {
		//get our position
		vec3 pos = Texel(MainTex, VaryingTexCoord.xy).xyz;
		float my_mass = mass(VaryingTexCoord.x);

		float sample_accum = sampling_percent_offset;

		float current_force_scale = force_scale / sampling_percent;
		]]..(v.constant_term or "vec3 acc = vec3(0.0);")..[[

		//iterate all particles
		for (int y = 0; y < dim; y++) {
			for (int x = 0; x < dim; x++) {
				sample_accum = sample_accum + sampling_percent;
				if (sample_accum >= 1.0) {
					sample_accum -= 1.0;

					vec2 ouv = (vec2(x, y) + vec2(0.5, 0.5)) / float(dim);
					vec3 other_pos = Texel(MainTex, ouv).xyz;
					//define mass quantities
					float m1 = my_mass;
					float m2 = mass(ouv.x);
					//get normalised direction and distance
					vec3 dir = other_pos - pos;
					float r = length(dir) / force_distance;
					if (r > 0.0) {
						dir = normalize(dir);
						]]..(v.force_term or "vec3 f = dir;")..[[
						acc += (f / m1) * current_force_scale;
					}
				}
			}
		}
		love_PixelColor = vec4(acc, 1.0);
	}
	#endif
	]])
	table.insert(sim_types, {
		name = k,
		accel_shader = accel_shader,
		gen = v.gen,
	})
end

local render_shader = lg.newShader([[
uniform Image MainTex;
uniform Image VelocityTex;
uniform float CamRotation;
const int dim = ]]..dim..[[;

]]..rotate_frag..[[

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
	vec2 uv = vertex_position.xy;
	vec3 pos = Texel(MainTex, uv).xyz;
	vec3 vel = Texel(VelocityTex, uv).xyz;

	//rotate with camera
	pos.xz = rotate(pos.xz, CamRotation);

	//perspective
	float near = -500.0;
	float far = 500.0;
	float depth = (pos.z - near) / (far - near);
	if (depth < 0.0) {
		//clip
		return vec4(0.0 / 0.0);
	} else {
		vertex_position.xy = pos.xy / mix(0.25, 2.0, depth);
	}

	//derive colour
	float it = length(vel) * 0.1;
	float clamped_it = clamp(it, 0.0, 1.0);

	float i = (uv.x + uv.y * float(dim)) / float(dim);
	i += length(pos) * 0.001;
	i *= 3.14159 * 2.0;

	VaryingColor.rgb = mix(
		vec3(
			(cos(i + 0.0) + 1.0) / 2.0,
			(cos(i + 2.0) + 1.0) / 2.0,
			(cos(i + 4.0) + 1.0) / 2.0
		) * clamped_it,
		vec3(1.0),
		sqrt(it) * 0.01
	);
	VaryingColor.a = (it * 0.1) * (1.0 - depth);

	//debug
	//VaryingColor = vec4(1.0);

	return transform_projection * vertex_position;
}
#endif
#ifdef PIXEL
void effect() {
	love_PixelColor = VaryingColor;
}
#endif
]])

--sharpen convolution to add faint outlines to particles
local sharpen_shader = lg.newShader([[
extern vec2 texture_size;
extern float sharpen_amount;
#ifdef PIXEL
float conv[9] = float[9](
	-1, -2, -1,
	-2, 13, -2,
	-1, -2, -1
);
vec4 effect( vec4 color, Image tex, vec2 uv, vec2 screen_coords ) {
	vec4 pre = Texel(tex, uv);
	vec4 c = vec4(0.0);
	int i = 0;
	float conv_sum = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float conv_amount = conv[i++];
			conv_sum += conv_amount;
			vec2 o = vec2(x, y) / texture_size;
			vec4 px = Texel(tex, uv + o);
			c.rgb += px.rgb * conv_amount;
			if (x == 0 && y == 0) {
				c.a = px.a;
			}
		}
	}
	c.rgb /= conv_sum;
	return mix(pre, c, sharpen_amount);
}
#endif
]])

--generate the mesh used to render the particles
local points = {}
for y = 1, dim do
	for x = 1, dim do
		table.insert(points, {
			--position = uv
			(x - 0.5) / dim,
			(y -0.5) / dim
		})
	end
end
local render_mesh = lg.newMesh(points, "points", "static")

--generate the render buffer
local sw, sh = lg.getDimensions()
local rs = 1 / downres
local rw, rh = sw * rs, sh * rs
local render_cv = lg.newCanvas(rw, rh, {format="rgba16f"})

--some debug timing stuff
local update_time = 0
local draw_time = 0
local function update_timer(current_timer, lerp_amount, f)
	local time_start = love.timer.getTime()
	f()
	local time_end = love.timer.getTime()
	return current_timer * (1 - lerp_amount) + (time_end - time_start) * lerp_amount

end

--setup initial buffer state
function init_particles()
	local gen = gen_configs[selected_sim.gen]
	local walk_scale = gen.walk_scale
	local bigjump_scale = gen.bigjump_scale
	local bigjump_chance = gen.bigjump_chance
	local scatter_scale = gen.scatter_scale

	local function copy_img_to_canvas(img, canvas)
		lg.setCanvas(canvas)
		lg.setBlendMode("replace", "premultiplied")
		lg.draw(img)
		lg.setBlendMode("alpha", "alphamultiply")
		lg.setCanvas()
	end

	--spawn particles with random walk
	local pos_img = love.image.newImageData(dim, dim, fmt_t.format)
	local _pos = {0, 0, 0}
	local _total = {0, 0, 0}
	pos_img:mapPixel(function(x, y, r, g, b, a)
		--random walk
		for i, v in ipairs(_pos) do
			_pos[i] = v + love.math.randomNormal(walk_scale, 0)
		end

		if love.math.random() < bigjump_chance then
			for i, v in ipairs(_pos) do
				_pos[i] = v + love.math.randomNormal(bigjump_scale, 0)
			end
		end

		r = _pos[1] + love.math.randomNormal(scatter_scale, 0)
		g = _pos[2] + love.math.randomNormal(scatter_scale, 0)
		b = _pos[3] + love.math.randomNormal(scatter_scale, 0)
		a = 1

		--note down for later
		_total[1] = _total[1] + r
		_total[2] = _total[2] + g
		_total[3] = _total[3] + b

		return r, g, b, a
	end)

	--apply mean offset
	for i,v in ipairs(_total) do
		_total[i] = v / (dim * dim)
	end
	pos_img:mapPixel(function(x, y, r, g, b, a)
		r = r - _total[1]
		g = g - _total[2]
		b = b - _total[3]
		return r, g, b, a
	end)

	copy_img_to_canvas(lg.newImage(pos_img), particles.pos)

	--zero out acc, vel
	lg.setCanvas(particles.vel)
	lg.clear(0,0,0,1)
	lg.setCanvas(particles.acc)
	lg.clear(0,0,0,1)

	--reset canvas
	lg.setCanvas()

end

--timing for the visual hints
local hint_time = 5.0
local hint_timer = 0.0

function love.load()
	pick_sim()
	init_particles()
end

--update
function love.update(dt)
	--measure the update time we care about
	update_time = update_timer(update_time, 0.99, function()
		local actual_dt = dt / steps_per_render
		local accel_shader = selected_sim.accel_shader
		accel_shader:send("sampling_percent", sampling_percent)

		for i = 1, steps_per_render do
			--render next state
			lg.setShader(accel_shader)
			accel_shader:send("sampling_percent_offset", love.math.random())

			lg.setBlendMode("replace", "premultiplied")
			lg.setColor(1,1,1,1)
			lg.setCanvas(particles.acc)
			lg.draw(particles.pos)

			--
			lg.setShader()
			lg.setBlendMode("add", "alphamultiply")
			lg.setColor(1,1,1,actual_dt)
			--integrate vel
			lg.setCanvas(particles.vel)
			lg.draw(particles.acc)
			--integrate pos
			lg.setCanvas(particles.pos)
			lg.draw(particles.vel)
		end
		lg.setColor(1,1,1,1)
	end)
	lg.setCanvas()
	lg.setBlendMode("alpha", "alphamultiply")
	lg.setShader()


	--pan
	local pan_amount = (50 / zoom) * dt
	if love.keyboard.isDown("up") then
		cy = cy - pan_amount
	end
	if love.keyboard.isDown("down") then
		cy = cy + pan_amount
	end
	--rotate
	local rotate_amount = math.pi * 0.5 * dt
	if love.keyboard.isDown("left") then
		cx = cx - rotate_amount
	end
	if love.keyboard.isDown("right") then
		cx = cx + rotate_amount
	end

	--zoom
	if love.keyboard.isDown("i") then
		zoom = zoom * 1.01
	end
	if love.keyboard.isDown("o") then
		zoom = zoom / 1.01
	end

	--update hint timer
	hint_timer = hint_timer + dt
end

--render
function love.draw()
	--measure the render time we care about
	draw_time = update_timer(draw_time, 0.99, function()
		--fade render canvas one step
		lg.setBlendMode("alpha", "alphamultiply")
		lg.setCanvas(render_cv)
		local lum = 0.075
		lg.setColor(lum, lum, lum, basic_fade_amount)
		lg.rectangle("fill", 0, 0, rw, rh)
		lg.setColor(1,1,1,1)

		--draw current state into render canvas
		lg.push()

		lg.translate(rw * 0.5, rh * 0.5)
		lg.scale(zoom, zoom)
		lg.translate(0, -cy)
		lg.setShader(render_shader)
		if render_shader:hasUniform("CamRotation") then render_shader:send("CamRotation", cx) end
		if render_shader:hasUniform("VelocityTex") then render_shader:send("VelocityTex", particles.vel) end
		
		lg.setBlendMode("add", "alphamultiply")
		render_mesh:setTexture(particles.pos)
		lg.draw(render_mesh)
		lg.pop()

		--draw render canvas as-is
		lg.setCanvas()
		lg.setShader(sharpen_shader)
		sharpen_shader:send("texture_size", {render_cv:getDimensions()})
		sharpen_shader:send("sharpen_amount", 0.025)
		lg.setBlendMode("alpha", "premultiplied")
		lg.setColor(1,1,1,1)
		lg.draw(
			render_cv,
			0, 0,
			0,
			downres, downres
		)
		lg.setShader()
		lg.setBlendMode("alpha", "alphamultiply")
	end)

	--debug
	if love.keyboard.isDown("`") then
		lg.print(string.format("%s\nfps: %4d\nupdate: %02.2fms\ndraw:  %02.2fms", selected_sim.name, love.timer.getFPS(), update_time * 1e3, draw_time * 1e3), 10, 10)

		lg.push()
		lg.translate(200, 10)
		for i,v in ipairs({
			particles.pos,
			particles.vel,
			particles.acc,
		}) do
			lg.translate(0, v:getHeight())
			lg.draw(v)
		end
		lg.pop()
	end

	--draw hints if recently pressed or on boot
	if hint_timer < hint_time then
		lg.setColor(1,1,1, 1.0 - (hint_timer / hint_time))
		lg.printf("enbody", 0, 10, sw, "center")
		for i,v in ipairs {
			{"Q / ESC", "quit"},
			{"ARROWS", "pan camera"},
			{"I / O", "zoom in/out"},
			{"S", "screenshot"},
			{"E", "rebuild system"},
			{"R", "new rules"},
		} do
			local y = sh - (16 * i + 10)
			lg.printf(v[1], 0, y, sw * 0.5 - 10, "right")
			lg.printf(v[2], sw * 0.5 + 10, y, sw * 0.5 - 10, "left")
			lg.printf("-", sw * 0.5 - 10, y, 20, "center")
		end
		lg.setColor(1,1,1,1)
	end
end

--respond to input
function love.keypressed(k)
	--save a screenshot to png
	if k == "s" then
		love.graphics.captureScreenshot(function(id)
			local f = io.open(string.format("%d.png", os.time()), "w")
			if f then
				f:write(id:encode("png"):getString())

				f:close()
			end
		end)
	--new setup
	elseif k == "e" then
		init_particles()
	--new world
	elseif k == "r" then
		--restart, soft or hard
		if love.keyboard.isDown("lctrl") then
			love.event.quit("restart")
		else
			love.load()
		end
	--quit
	elseif k == "q" or k == "escape" then
		--quit out
		love.event.quit()
	--some other key? re-hint
	elseif
		--not arrow key
		k ~= "up"
		and k ~= "down"
		and k ~= "left"
		and k ~= "right"
		--not i/o
		and k ~= "i"
		and k ~= "o"
	then
		hint_timer = 0
	end
end
