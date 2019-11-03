#version 330

uniform sampler2D textureSrc;

in vec2 pass_texture_coordinates;

out vec2 outColour;

void main() {
    float c0 = 0.0;
    float c1 = 0.0;

    // TODO: Use four texture() calls to use hardware filtering for each 2x2 patch?
    for(int y = 0; y < 16; y++) {
        for(int x = 0; x < 16; x++) {
            float d = texelFetch(textureSrc, ivec2(pass_texture_coordinates) + ivec2(x, y), 0).r;
            
            c0 += d;
            c1 += d*d;
        }
    }
    outColour = vec2(c0, c1) / vec2(16.0*16.0);
}
