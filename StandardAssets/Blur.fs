#version 330

uniform sampler2D textureSrc;

in vec2 pass_texture_coordinates;
flat in vec2 inverseSize;

out vec2 outColour;

void main() {
    float c0 = 0.0;
    float c1 = 0.0;

    for(int y = 0; y < 16; y+=2) {
        for(int x = 0; x < 16; x+=2) {
            float d = texture(textureSrc, pass_texture_coordinates + (vec2(x, y) + vec2(0.5)) * inverseSize).r;
            
            c0 += d;
            c1 += d*d;
        }
    }
    outColour = vec2(c0, c1) / vec2(8.0*8.0);
}
