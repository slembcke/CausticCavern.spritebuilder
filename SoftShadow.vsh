varying vec2 clipFrag;
varying vec2 segmentAFrag;
varying vec2 segmentBFrag;

mat2 penumbraMatrix(vec2 d, float r){
	float a = 1.0/dot(d, d);
	float b = 1.0/(r*length(d) + 1e-15);
	return mat2(
		-b*d.y, a*d.x,
		 b*d.x, a*d.y
	);
}

void main(){
	// Unpack the vertex data.
	vec2 lightPosition = cc_Position.xy;
	vec2 segmentA = cc_TexCoord1;
	vec2 segmentB = cc_TexCoord2;
	vec2 segmentCoords = cc_Color.xy;
	float projectionOffset = cc_Color[2];
	float radius = cc_Color[3];
	
	vec2 segmentPosition = mix(segmentA, segmentB, segmentCoords.x);
	vec2 lightDirection = normalize(segmentPosition - lightPosition);
	
	// Calculate the point to project the shadow edge from the light's position/size.
	vec2 projectionPosition = lightPosition + projectionOffset*radius*vec2(lightDirection.y, -lightDirection.x);
	vec2 projectedPosition = segmentPosition - projectionPosition*segmentCoords.y;
	
	vec2 segmentTangent = normalize(segmentB - segmentA);
	vec2 segmentNormal = vec2(-segmentTangent.y, segmentTangent.x);
	
	float projectedCoord = 1.0 - segmentCoords.y;
	gl_Position = vec4(projectedPosition, 0.0, projectedCoord);
	
	// Output fragment data!
	clipFrag = vec2(dot(gl_Position.xy, segmentNormal), gl_Position.w*dot(segmentNormal, segmentA + segmentB)*0.5);
	segmentAFrag = penumbraMatrix(segmentA - lightPosition, radius)*(gl_Position.xy - segmentA*projectedCoord);
	segmentBFrag = penumbraMatrix(segmentB - lightPosition, radius)*(gl_Position.xy - segmentB*projectedCoord);
}
