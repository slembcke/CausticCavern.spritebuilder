varying vec2 clipFrag;
varying vec2 segmentAFrag;
varying vec2 segmentBFrag;

float penumbra(vec2 delta, float clipped){
	float p = clamp(delta.x/delta.y, -1.0, 1.0);
	
	// Soften using a cubic curve.
	p = p*(3.0 - p*p)*0.25 + 0.5;
	
	// Clip the output to 
	return mix(clipped, p, step(0.0, delta.y));
}

void main(){
	float occlusionA = penumbra(segmentAFrag, 1.0);
	float occlusionB = penumbra(segmentBFrag, 0.0);
	
	float clip = step(clipFrag.x, clipFrag.y);
	gl_FragColor = vec4(clip*(occlusionA - occlusionB));
//		gl_FragColor = clip*vec4(0.25, 0.0, 0.0, 1.0);
}
