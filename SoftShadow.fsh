varying vec4 positionFrag;
varying vec4 clipFrag;
varying vec2 segmentAFrag;
varying vec2 segmentBFrag;
varying mat2 edgeAFrag;
varying mat2 edgeBFrag;

float soften(float t){
	return t*(3.0 - t*t)*0.25 + 0.5;
}

float edge(mat2 m, vec2 delta, float clipped){
	vec2 v = m*delta;
	return (v[0] > 0.0 ? soften(clamp(v[1]/v[0], -1.0, 1.0)) : clipped);
}

void main(){
	vec2 position = positionFrag.xy/positionFrag.w;
	float occlusionA = edge(edgeAFrag, position - segmentAFrag, 1.0);
	float occlusionB = edge(edgeBFrag, position - segmentBFrag, 0.0);
	gl_FragColor = vec4(step(dot(position, clipFrag.xy), clipFrag.w)*(occlusionA - occlusionB));
}
