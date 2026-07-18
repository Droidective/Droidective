#include <metal_stdlib>
using namespace metal;

/// Static film grain for the translucent window: a hash of the pixel position
/// becomes a gray speck at the strength SwiftUI passes in. Drawn over a clear
/// layer, so if the shader can't run the overlay stays invisible instead of
/// flashing a solid fill. No time input — the grain is frozen, so it costs
/// nothing between redraws.
[[ stitchable ]] half4 grain(float2 position, half4 color, float intensity) {
    float2 cell = floor(position);
    float noise = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
    // Premultiplied, matching what colorEffect expects back.
    return half4(half3(noise) * half(intensity), half(intensity));
}
