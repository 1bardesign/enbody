--nbody particles in love

love.window.setTitle("EnBody")

local lg = love.graphics

lg.setDefaultFilter("nearest", "nearest")

--dimension of the particles textures
local dim = 64

local zoom = 1 / 6
local timescale = 2.0
local world_scale = 10
local bigjump_scale = 250
local bigjump_chance = 0.01
local scatter_scale = 1
local init_vel_scale = 1.0
local force_scale = 1

local basic_fade_amount = 0.1

local downres = 2

local mass_scale = 1.0
local sampling_percent = 1.0

local fmt_t = {format="rgba32f"}
--set up double buffer
local current_particles = lg.newCanvas(dim, dim, fmt_t)
local old_particles = lg.newCanvas(dim, dim, fmt_t)

lg.setPointSize(1)

--setup initial buffer state
function love.load()
	local rd = love.image.newImageData(dim, dim, fmt_t.format)
	--spawn with random walk
	local _x, _y = 0, 0
	local tx, ty = 0, 0
	rd:mapPixel(function(x, y, r, g, b, a)
		_x = _x + love.math.randomNormal(world_scale, 0)
		_y = _y + love.math.randomNormal(world_scale, 0)

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

	--get the centre
	tx = tx / (dim * dim)
	ty = ty / (dim * dim)

	--mean offset
	rd:mapPixel(function(x, y, r, g, b, a)
		r = r - tx
		g = g - ty
		return r, g, b, a
	end)

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

local integrate_shader = lg.newShader([[
uniform Image MainTex;
const float timescale = ]]..timescale..[[;
const float force_scale = ]]..force_scale..[[;
uniform float dt;

uniform float sampling_percent;
uniform float sampling_percent_offset;
const int dim = ]]..dim..[[;
#ifdef PIXEL
const float mass_scale = ]]..mass_scale..[[;
float mass(float u) {
	return 1.0 + u * mass_scale;
}

void effect() {
	vec4 me = Texel(MainTex, VaryingTexCoord.xy);
	float my_mass = mass(VaryingTexCoord.x);
	//get our position
	vec2 pos = me.xy;
	vec2 vel = me.zw;

	float dt_proper = dt * timescale;

	float sample_accum = sampling_percent_offset;

	//iterate all particles
	for (int y = 0; y < dim; y++) {
		for (int x = 0; x < dim; x++) {
			sample_accum = sample_accum + sampling_percent;
			if (sample_accum >= 1.0) {
				sample_accum -= 1.0;

				vec2 ouv = (vec2(x, y) + vec2(0.5, 0.5)) / float(dim);
				vec4 other = Texel(MainTex, ouv);
				vec2 d = other.xy - pos;
				
				float mass_ratio = (mass(ouv.x) / my_mass);

				//length squared
				float l = max(0.0001, (d.x * d.x) + (d.y * d.y));
				vel += (d / l) * dt_proper * force_scale * mass_ratio / sampling_percent;
			}
		}
	}
	//integrate
	pos += vel * dt_proper;
	//store
	me.xy = pos;
	me.zw = vel;
	//apply force
	love_PixelColor = me;
}
#endif
]])

local render_shader = lg.newShader([[
uniform Image MainTex;
const int dim = ]]..dim..[[;
#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
	vec4 sample = Texel(MainTex, VertexTexCoord.xy);
	vertex_position.xy = sample.rg;
	//derive colour
	float it = length(sample.zw) * 0.05;
	float clamped_it = clamp(it, 0.0, 1.0);

	float i = (VertexTexCoord.x + VertexTexCoord.y * float(dim)) / float(dim);
	i *= 3.14159 * 2.0;

	VaryingColor.rgb = mix(
		vec3(
			(cos(i + 0.0) + 1.0) / 2.0,
			(cos(i + 2.0) + 1.0) / 2.0,
			(cos(i + 4.0) + 1.0) / 2.0
		) * clamped_it,
		vec3(1.0),
		it * 0.05
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

local points = {}
for y = 1, dim do
	for x = 1, dim do
		table.insert(points, {
			--position
			x,
			y,
			--uv
			(x - 0.5) / dim,
			(y -0.5) / dim
		})
	end
end
local render_mesh = lg.newMesh(points, "points", "static")

local rw, rh = lg.getDimensions()
local rs = 1 / downres
rw = rw * rs
rh = rh * rs
local render_cv = lg.newCanvas(rw, rh, {format="rgba16f"})

local update_time = 0
local draw_time = 0
local function update_timer(current_timer, lerp_amount, f)
	local time_start = love.timer.getTime()
	f()
	local time_end = love.timer.getTime()
	return current_timer * (1 - lerp_amount) + (time_end - time_start) * lerp_amount

end

function love.draw()
	draw_time = update_timer(draw_time, 0.99, function()
		lg.setCanvas(render_cv)
		lg.setColor(0,0,0, basic_fade_amount)
		lg.rectangle("fill", 0, 0, rw, rh)
		lg.setColor(1,1,1,1)
		
		lg.push()

		lg.translate(rw * 0.5, rh * 0.5)
		lg.scale(zoom, zoom)
		lg.setShader(render_shader)
		
		lg.setBlendMode("add", "alphamultiply")
		render_mesh:setTexture(current_particles)
		lg.draw(render_mesh)

		lg.setShader()
		lg.pop()

		lg.setCanvas()
		lg.setBlendMode("alpha", "premultiplied")
		lg.setColor(1,1,1,1)
		lg.draw(
			render_cv,
			0, 0,
			0,
			downres, downres
		)
		lg.setBlendMode("alpha", "alphamultiply")
	end)

	--debug
	if love.keyboard.isDown("`") then
		lg.print(string.format("fps: %4d\nupdate: %02.2fms\ndraw:  %02.2fms", love.timer.getFPS(), update_time * 1e3, draw_time * 1e3), 10, 10)
	end
end

function love.update(dt)
	--swap double buffer
	current_particles, old_particles = old_particles, current_particles
	--render next state
	update_time = update_timer(update_time, 0.99, function()
		lg.setBlendMode("replace", "premultiplied")
		lg.setShader(integrate_shader)
		integrate_shader:send("dt", dt)
		integrate_shader:send("sampling_percent", sampling_percent)
		integrate_shader:send("sampling_percent_offset", love.math.random())

		lg.setCanvas(current_particles)
		lg.draw(old_particles)
		lg.setBlendMode("alpha", "alphamultiply")
		lg.setShader()
		lg.setCanvas()
	end)
end

function love.keypressed(k)
	if k == "s" then
		love.graphics.captureScreenshot(function(id)
			local f = io.open(string.format("%d.png", os.time()), "w")
			if f then
				f:write(id:encode("png"):getString())

				f:close()
			end
		end)
	elseif k == "r" then
		if love.keyboard.isDown("lctrl") then
			love.event.quit("restart")
		else
			love.load()
		end
	elseif k == "q" or k == "escape" then
		love.event.quit()
	end
end
