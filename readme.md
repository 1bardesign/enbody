# Enbody

Enbody is a real-time multi-function n-body sim on the gpu in under 700 lines of lua and glsl, made with [love](http://love2d.org).

It features multiple different attractor functions to generate lots of different visually interesting animations.

Easy-to-run packaged builds are available on [itch.io](https://1bardesign.itch.io/enbody).

# Explanation

Storage:

- 3x 32 bit float texture buffer for particles (position, velocity, acceleration; rgb as 3d vector, alpha unused for now)
- 1x mesh used as uv storage
- 1x half resolution 16 bit float framebuffer

Procedure:

- initialise the particles with a random walk
- update acceleration with a pixel shader
	- sample all particle positions in order
	- calculate force from each other body based on attractor function
	- scale by computed particle mass
- update velocity and position with simple additive rendering and alpha
	- apply acceleration to velocity
	- apply velocity to position
- render particles with another shader into hdr framebuffer texture
	- fade existing rendering by some amount
	- render mesh as points
	- look up the position for the point from the texture
	- generate a nice colour based on the velocity
- render framebuffer with sharpen shader
	- generate pixel-based outlines on bright particles

# License

See [the license file](license.txt); MIT.
