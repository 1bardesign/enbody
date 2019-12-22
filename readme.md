# Enbody

Enbody is a real-time multi-function n-body sim on the gpu in 500-odd lines of lua and glsl, made with [love](http://love2d.org).

It features multiple different attractor functions to generate lots of different visually interesting animations.

# Explanation

Storage:
- 2x texture buffer for particles
- 1x mesh used as uv storage
- 1x half resolution half float framebuffer

- initialise the particles with a random walk
- integrate with a pixel shader
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
