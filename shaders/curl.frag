#version 440
// Page curl: the source page rolls up around a cylinder whose axis sweeps
// across the page, showing the paper's back (print faintly bleeding
// through) and casting a shadow on whatever lies beneath.
//
// Geometry is worked out in "turn space", where the page always lifts at
// its right edge and the fold travels left; dir < 0 mirrors it for
// right-to-left reading.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;    // 0 = flat, 1 = turned away
    float dir;         // +1 lifts the right edge, -1 the left
    float tilt;        // fold slope; > 0 lifts the bottom corner first
    float radius;      // curl radius in pixels
    float shadow;      // strength of the cast shadow, 0..1
    vec2 viewSize;     // item size in pixels
    vec4 pageRect;     // the page within the item: x, y, w, h (pixels)
};

layout(binding = 1) uniform sampler2D source;

const float PI = 3.14159265;

vec2 toItem(vec2 q) {
    return dir < 0.0 ? vec2(viewSize.x - q.x, q.y) : q;
}

vec4 sampleAt(vec2 q) {
    vec2 uv = toItem(q) / viewSize;
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0)
        return vec4(0.0);
    return texture(source, uv);
}

// The back of the sheet: paper, with the print showing through faintly.
vec4 backSide(vec4 c, float light) {
    vec3 paper = vec3(c.a) * 0.96;
    vec3 rgb = mix(c.rgb, paper, 0.84) * light;
    return vec4(rgb, c.a);
}

void main() {
    vec2 p = qt_TexCoord0 * viewSize;
    vec4 pg = pageRect;
    if (dir < 0.0) {
        p.x = viewSize.x - p.x;
        pg.x = viewSize.x - (pageRect.x + pageRect.z);
    }

    // Unit vector the fold travels along.
    vec2 n = normalize(vec2(-1.0, -tilt));
    float R = radius;
    // The fold starts just touching the far bottom corner and ends past the
    // near top corner, so every point of the page has rolled over.
    float tStart = dot(pg.xy + pg.zw, n) - 1.0;
    float tEnd = dot(pg.xy, n) + R;
    float tFold = mix(tStart, tEnd, progress);
    // > 0: still flat (ahead of the fold); < 0: lifted (behind it).
    float d = dot(p, n) - tFold;

    vec4 col = vec4(0.0);

    if (d > 0.0) {
        // Part of the sheet that has gone over the top lies flat above here.
        vec4 back = sampleAt(p - n * (2.0 * d + PI * R));
        if (back.a > 0.01) {
            col = backSide(back, 0.93 - 0.08 * exp(-d / R));
        } else {
            vec4 front = sampleAt(p);
            // The rising curl shades the flat page just ahead of the fold.
            float shade = 1.0 - 0.28 * exp(-d / (R * 0.9));
            col = vec4(front.rgb * shade, front.a);
        }
    } else {
        float x = -d;
        if (x < R) {
            // Over the cylinder: the upper half shows the back of the sheet.
            float th2 = PI - asin(x / R);
            vec4 back = sampleAt(p - n * (R * th2 - x));
            if (back.a > 0.01) {
                col = backSide(back, 0.72 + 0.28 * sin(th2));
            } else {
                // Otherwise the lower half, still the printed side, curving away.
                float th1 = asin(x / R);
                vec4 front = sampleAt(p - n * (R * th1 - x));
                if (front.a > 0.01) {
                    float shade = 1.0 - 0.4 * (th1 / (PI * 0.5));
                    col = vec4(front.rgb * shade, front.a);
                } else {
                    col = vec4(0.0, 0.0, 0.0, shadow * 0.6);
                }
            }
        } else {
            // Uncovered: the page beneath, darkened near the curl.
            float a = shadow * exp(-(x - R) / (R * 1.4));
            col = vec4(0.0, 0.0, 0.0, a);
        }
    }

    fragColor = col * qt_Opacity;
}
