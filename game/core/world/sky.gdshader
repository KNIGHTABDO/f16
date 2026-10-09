shader_type sky;

// Analytic single-scattering sky for a plane-parallel exponential atmosphere (Rayleigh + Mie),
// integrated in closed form along the view ray (no per-pixel marching, cheap on the A15).
// WorldSky.gd mirrors scatter() exactly to get the horizon colour for aerial perspective.

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);      // towards the sun, world space
uniform vec3 sun_color = vec3(1.0);              // transmittance-tinted sun colour
uniform float sun_energy = 14.0;                 // scattering irradiance scale (tuned, see sky.gd)
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);     // towards the moon, world space
uniform float moon_energy = 0.0;
uniform float night = 0.0;                       // 0 day .. 1 night (stars, moon disk)
uniform float turbidity = 1.0;                   // aerosol multiplier: 1 clear, 3+ haze
uniform float cloud_cover = 0.0;                 // 0..1, greys the sky under overcast
uniform vec3 ground_tint = vec3(0.2);            // colour below the horizon, linear

const vec3 BETA_R = vec3(0.0058, 0.0135, 0.0331); // Rayleigh scattering, per km (sea level)
const float H_R = 8.5;                            // Rayleigh scale height, km
const float BETA_M = 0.0167;                      // Mie extinction per km (clear), times turbidity
const float H_M = 1.2;                            // Mie scale height, km
const float MIE_G = 0.8;

float airmass(float sin_elev) {
	// Kasten-Young airmass (spherical-earth correction, finite at the horizon). Below the horizon the
	// path is long enough that almost nothing reaches the eye, so use a fixed large value.
	if (sin_elev <= 0.0) {
		return 40.0;
	}
	float e = degrees(asin(min(sin_elev, 1.0)));
	return 1.0 / (sin_elev + 0.50572 * pow(e + 6.07995, -1.6364));
}

// (1 - exp(-d)) / d, with the limit 1 at d = 0.
vec3 g_term(vec3 d) {
	bvec3 small_d = lessThan(abs(d), vec3(1e-4));
	vec3 safe = mix(d, vec3(1.0), small_d);
	return mix((1.0 - exp(-safe)) / safe, vec3(1.0), small_d);
}

vec3 scatter(vec3 v, vec3 l, float energy, float turb) {
	float vy = max(v.y, 0.002);
	float mu = dot(v, l);
	float mv = airmass(vy);
	float ms = airmass(l.y);
	// Closed form of the single-scattering integral for an exponential atmosphere (see sky.gd notes).
	vec3 aR = BETA_R * H_R * mv;
	vec3 cR = BETA_R * H_R * ms;
	vec3 IR = H_R * mv * exp(-aR) * g_term(cR - aR);
	float bm = BETA_M * turb;
	float aM = bm * H_M * mv;
	float cM = bm * H_M * ms;
	float IM = H_M * mv * exp(-aM) * g_term(vec3(cM - aM)).x;

	// Rayleigh phase 3/(16 pi) (1 + mu^2); Cornette-Shanks Mie phase 3/(8 pi) (1-g^2)/(2+g^2) (1+mu^2)/(1+g^2-2g mu)^1.5.
	float pr = 0.75 * (1.0 + mu * mu) / (4.0 * 3.14159265);
	float g2 = MIE_G * MIE_G;
	float pm = 1.5 * (1.0 - g2) / (2.0 + g2) * (1.0 + mu * mu) / pow(1.0 + g2 - 2.0 * MIE_G * mu, 1.5) / (4.0 * 3.14159265);
	vec3 L = energy * (BETA_R * pr * IR + bm * pm * IM * vec3(1.0));
	return L;
}

// Transmittance of the sun's light reaching the surface (sun disk brightness).
vec3 sun_transmittance(vec3 l, float turb) {
	float ms = airmass(l.y);
	return exp(-(BETA_R * H_R * ms + BETA_M * turb * H_M * ms));
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 v = normalize(EYEDIR);
	vec3 l = normalize(sun_dir);
	vec3 col = scatter(v, l, sun_energy, turbidity);

	// Sun disk, extinguished by the air it shines through near the horizon.
	float cos_sun = dot(v, l);
	float disk = smoothstep(0.99985, 0.99995, cos_sun);
	col += sun_color * sun_transmittance(l, turbidity) * disk * 400.0;
	// Soft sun halo on top of the Mie forward lobe.
	col += sun_color * pow(max(cos_sun, 0.0), 220.0) * 6.0 * sun_transmittance(l, turbidity);

	if (night > 0.0 || moon_energy > 0.0) {
		vec3 m = normalize(moon_dir);
		vec3 lm = scatter(v, m, moon_energy, turbidity);
		col += lm * vec3(0.75, 0.85, 1.0);
		float moon_disk = smoothstep(0.99955, 0.99975, dot(v, m));
		col += vec3(0.9, 0.93, 1.0) * moon_disk * 3.0 * clamp(m.y * 4.0, 0.0, 1.0);

		// Stars: a jittered cell grid on the sky sphere, twinkling slightly.
		vec3 p = v * 260.0;
		vec3 cell = floor(p);
		float h = hash3(cell);
		vec3 f = fract(p) - 0.5;
		float star = step(0.985, h) * smoothstep(0.32, 0.0, length(f));
		float twinkle = 0.75 + 0.25 * sin(TIME * (1.5 + 3.0 * h) + h * 40.0);
		float above = smoothstep(0.02, 0.18, v.y);
		col += vec3(0.85, 0.9, 1.0) * star * twinkle * 2.2 * night * above;
	}

	// Below the horizon the sky shows the horizon colour (the terrain and sea cover it anyway).
	if (v.y < 0.0) {
		col = mix(col, ground_tint, smoothstep(0.0, -0.05, v.y));
	}

	// Overcast greys the whole dome towards its own luminance.
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(lum) * vec3(0.98, 1.0, 1.04), cloud_cover * 0.6);

	COLOR = col;
}
