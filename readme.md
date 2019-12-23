# Enbody

Enbody is a real-time multi-function n-body sim on the gpu in under 600 lines of lua and glsl, made with [love](http://love2d.org).

It features multiple different attractor functions to generate lots of different visually interesting animations.

Easy-to-run packaged builds are available on [itch.io](https://1bardesign.itch.io/enbody).

# Explanation

Storage:

- 2x 32 bit float texture buffer for particles (1 pixel = 1 particle, red/green channels = position, blue/alpha channels = velocity)
- 1x mesh used as uv storage
- 1x half resolution 16 bit float framebuffer

Procedure:

- initialise the particles with a random walk
- update with a pixel shader
	- sample all pixels in texture
	- calculate force from each other body
	- apply force to velocity
	- apply velocity to position
- render with another shader into float texture
	- fade existing rendering by some amount
	- render mesh as points
	- look up the position for the point from the texture
	- generate a nice colour based on the velocity

# License

See [the license file](license.txt); MIT.
