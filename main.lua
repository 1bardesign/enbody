--nbody particles in love

local lg = love.graphics

lg.setDefaultFilter("nearest", "nearest")

--dimension of the particles textures
local dim = 64
--time passes faster or slower
local timescale = 0.5
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
	force_term = "vec2 f = dir;",
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
		force_term = "vec2 f = dir * (m1 * m2) / max(1.0, r * r);",
		mass_scale = 1.0,
		mass_distribution = "u * u",
	},
	strings = {
		gen = "sparse",
		force_scale = 0.0001,
		force_distance = 20.0,
		force_term = "vec2 f = dir * m2 * max(1.0, r * r);",
		mass_scale = 5.0,
		mass_distribution = "u",
	},
	cloud = {
		gen = "dense",
		force_scale = 0.01,
		force_distance = 10.0,
		force_term = "vec2 f = dir * (r * m1 * 0.3 - 5.0);",
		mass_scale = 2.0,
		mass_distribution = "u",
	},
	boids = {
		gen = "dense",
		force_scale = 0.3,
		force_distance = 10.0,
		force_term = "vec2 f = dir / max(1.0, r);",
		mass_scale = 2.0,
		mass_distribution = "u",
	},
	shy = {
		gen = "dense",
		force_scale = 0.05,
		force_distance = 5.0,
		force_term = "vec2 f = dir * float(r > 2.0);",
		mass_scale = 2.0,
		mass_distribution = "u",
	},
	atoms = {
		gen = "dense",
		force_scale = 0.5,
		force_distance = 15.0,
		force_term = "vec2 f = dir * float(r < 2.0);",
		mass_scale = 10.0,
		mass_distribution = "u",
	},
	sines = {
		gen = "dense",
		force_scale = 0.1,
		force_distance = 40.0,
		force_term = "vec2 f = dir * sin(r);",
		mass_scale = 10.0,
		mass_distribution = "u",
	},
	cosines = {
		gen = "sparse",
		force_scale = 0.05,
		force_distance = 25.0,
		force_term = "vec2 f = dir * m2 * -cos(r);",
		mass_scale = 10.0,
		mass_distribution = "u",
	},
	spiral = {
		gen = "sparse",
		force_scale = 0.01,
		force_distance = 5.0,
		force_term = "vec2 f = dir * m2 + rotate(dir, 0.025 * m1 * 3.14159) * 0.5;",
		mass_scale = 5.0,
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
--set up double buffer
local current_particles = lg.newCanvas(dim, dim, fmt_t)
local old_particles = lg.newCanvas(dim, dim, fmt_t)

--larger points = more chunky look
--smaller = "higher fidelity"
lg.setPointSize(1)


local sim_types = {}
local selected_sim = nil
--pick random sim type
function pick_sim()
	selected_sim = sim_types[love.math.random(1, #sim_types)]
end
for k,v in pairs(sim_configs) do
	local shader = lg.newShader([[
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

	vec2 rotate(vec2 v, float t) {
		float s = sin(t);
		float c = cos(t);
		return vec2(
			c * v.x - s * v.y,
			s * v.x + c * v.y
		);
	}

	void effect() {
		vec4 me = Texel(MainTex, VaryingTexCoord.xy);
		float my_mass = mass(VaryingTexCoord.x);
		//get our position
		vec2 pos = me.xy;
		vec2 vel = me.zw;

		float dt_proper = dt * timescale;

		float sample_accum = sampling_percent_offset;

		float current_force_scale = (dt_proper * force_scale) / sampling_percent;
		
		//integrate
		pos += vel * dt_proper;

		//iterate all particles
		for (int y = 0; y < dim; y++) {
			for (int x = 0; x < dim; x++) {
				sample_accum = sample_accum + sampling_percent;
				if (sample_accum >= 1.0) {
					sample_accum -= 1.0;

					vec2 ouv = (vec2(x, y) + vec2(0.5, 0.5)) / float(dim);
					vec4 other = Texel(MainTex, ouv);
					//define mass quantities
					float m1 = my_mass;
					float m2 = mass(ouv.x);
					//get normalised direction and distance
					vec2 dir = other.xy - pos;
					float r = length(dir) / force_distance;
					if (r > 0.0) {
						dir = normalize(dir);
						]]..v.force_term..[[
						vel += (f / m1) * current_force_scale;
					}
				}
			}
		}
		//store
		me.xy = pos;
		me.zw = vel;
		//apply force
		love_PixelColor = me;
	}
	#endif
	]])
	table.insert(sim_types, {
		name = k,
		integrate = shader,
		gen = v.gen,
	})
end

local render_shader = lg.newShader([[
uniform Image MainTex;
const int dim = ]]..dim..[[;
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
	vec2 uv = vertex_position.xy;
	vec4 sample = Texel(MainTex, uv);
	vertex_position.xy = sample.rg;
	//derive colour
	float it = length(sample.zw) * 0.1;
	float clamped_it = clamp(it, 0.0, 1.0);

	float i = (uv.x + uv.y * float(dim)) / float(dim);
	i *= 3.14159 * 2.0;

	VaryingColor.rgb = mix(
		vec3(
			(cos(i + 0.0) + 1.0) / 2.0,
			(cos(i + 2.0) + 1.0) / 2.0,
			(cos(i + 4.0) + 1.0) / 2.0
		) * clamped_it,
		vec3(1.0),
		sqrt(it) * 0.05
	);
	VaryingColor.a = it * 0.1;

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

	local rd = love.image.newImageData(dim, dim, fmt_t.format)
	--spawn with random walk
	local _x, _y = 0, 0
	local tx, ty = 0, 0
	rd:mapPixel(function(x, y, r, g, b, a)
		--random walk
		_x = _x + love.math.randomNormal(walk_scale, 0)
		_y = _y + love.math.randomNormal(walk_scale, 0)

		if love.math.random() < bigjump_chance then
			_x = _x + love.math.randomNormal(bigjump_scale, 0)
			_y = _y + love.math.randomNormal(bigjump_scale, 0)
		end

		r = _x + love.math.randomNormal(scatter_scale, 0)
		g = _y + love.math.randomNormal(scatter_scale, 0)
		b = 0
		a = 1

		--note down for later
		tx = tx + r
		ty = ty + g

		return r, g, b, a
	end)

	--apply mean offset
	tx = tx / (dim * dim)
	ty = ty / (dim * dim)
	rd:mapPixel(function(x, y, r, g, b, a)
		r = r - tx
		g = g - ty
		return r, g, b, a
	end)

	--reset the velocities - we'd do this at generation time but love uses premultiplied colours for imagedata...
	local reset_vel_shader = lg.newShader([[
	uniform Image MainTex;
	const float init_vel_scale = ]]..init_vel_scale..[[;
	#ifdef PIXEL
	vec2 hash2(vec2 i) {
		i = vec2(
			dot(i, vec2(157.8, 251.9)),
			dot(i, vec2(-31.6, 97.13))
		);
		return fract(sin(i) * 43758.5453) * 2.0 - 1.0;
	}
	void effect() {
		vec2 n = hash2(
			VaryingTexCoord.xy
		) * init_vel_scale;
		love_PixelColor = vec4(
			Texel(MainTex, VaryingTexCoord.xy).xy,
			n
		);
	}
	#endif
	]])

	rd = lg.newImage(rd)
	for i,v in ipairs({
		current_particles,
		old_particles,
	}) do
		lg.setCanvas(v)
		lg.setShader(reset_vel_shader)
		lg.setBlendMode("replace", "premultiplied")
		lg.draw(rd)
		lg.setBlendMode("alpha", "alphamultiply")
		lg.setShader()
		lg.setCanvas()
	end
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
		for i = 1, steps_per_render do
			--swap double buffer
			current_particles, old_particles = old_particles, current_particles
			--render next state
			lg.setBlendMode("replace", "premultiplied")
			local integrate_shader = selected_sim.integrate
			lg.setShader(integrate_shader)
			integrate_shader:send("dt", dt / steps_per_render)
			integrate_shader:send("sampling_percent", sampling_percent)
			integrate_shader:send("sampling_percent_offset", love.math.random())

			lg.setCanvas(current_particles)
			lg.draw(old_particles)
		end
	end)
	lg.setCanvas()
	lg.setBlendMode("alpha", "alphamultiply")
	lg.setShader()

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
		lg.translate(-cx, -cy)
		lg.setShader(render_shader)
		
		lg.setBlendMode("add", "alphamultiply")
		render_mesh:setTexture(current_particles)
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
	--pan
	elseif k == "up" then
		cy = cy - (8 / zoom)
	elseif k == "down" then
		cy = cy + (8 / zoom)
	elseif k == "left" then
		cx = cx - (8 / zoom)
	elseif k == "right" then
		cx = cx + (8 / zoom)
	--zoom
	elseif k == "i" then
		zoom = zoom * 1.1
	elseif k == "o" then
		zoom = zoom / 1.1
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
	else
		hint_timer = 0
	end
end
