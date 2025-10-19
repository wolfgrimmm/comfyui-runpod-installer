'use client';

import { useRef, useMemo } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';

const GlassShader = () => {
  const meshRef = useRef<THREE.Mesh>(null);
  const { viewport } = useThree();

  const glassMaterial = useMemo(() => {
    return new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 },
        uResolution: { value: new THREE.Vector2(viewport.width, viewport.height) },
        uMouse: { value: new THREE.Vector2(0, 0) },
        uRefractionStrength: { value: 0.1 },
        uDistortion: { value: 0.3 },
        uThickness: { value: 0.5 },
        uRoughness: { value: 0.1 },
        uFresnelPower: { value: 2.0 },
        uTransmission: { value: 0.9 },
        uThicknessMap: { value: null },
        uNormalMap: { value: null },
        uEnvMap: { value: null },
      },
      vertexShader: `
        varying vec2 vUv;
        varying vec3 vNormal;
        varying vec3 vPosition;
        varying vec3 vWorldPosition;
        varying vec3 vViewPosition;
        
        void main() {
          vUv = uv;
          vNormal = normalize(normalMatrix * normal);
          vPosition = position;
          
          vec4 worldPosition = modelMatrix * vec4(position, 1.0);
          vWorldPosition = worldPosition.xyz;
          
          vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
          vViewPosition = -mvPosition.xyz;
          
          gl_Position = projectionMatrix * mvPosition;
        }
      `,
      fragmentShader: `
        uniform float uTime;
        uniform vec2 uResolution;
        uniform vec2 uMouse;
        uniform float uRefractionStrength;
        uniform float uDistortion;
        uniform float uThickness;
        uniform float uRoughness;
        uniform float uFresnelPower;
        uniform float uTransmission;
        
        varying vec2 vUv;
        varying vec3 vNormal;
        varying vec3 vPosition;
        varying vec3 vWorldPosition;
        varying vec3 vViewPosition;
        
        // Noise function for realistic glass imperfections
        float noise(vec2 p) {
          return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
        }
        
        // Smooth noise
        float smoothNoise(vec2 p) {
          vec2 i = floor(p);
          vec2 f = fract(p);
          f = f * f * (3.0 - 2.0 * f);
          
          float a = noise(i);
          float b = noise(i + vec2(1.0, 0.0));
          float c = noise(i + vec2(0.0, 1.0));
          float d = noise(i + vec2(1.0, 1.0));
          
          return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
        }
        
        // Fresnel effect
        float fresnel(vec3 viewDirection, vec3 normal, float power) {
          return pow(1.0 - max(dot(viewDirection, normal), 0.0), power);
        }
        
        // Refraction calculation
        vec3 calculateRefraction(vec3 incident, vec3 normal, float ior) {
          float cosI = -dot(normal, incident);
          float sinT2 = ior * ior * (1.0 - cosI * cosI);
          
          if (sinT2 > 1.0) {
            return reflect(incident, normal);
          }
          
          float cosT = sqrt(1.0 - sinT2);
          return ior * incident + (ior * cosI - cosT) * normal;
        }
        
        void main() {
          vec2 uv = vUv;
          vec3 normal = normalize(vNormal);
          vec3 viewDirection = normalize(vViewPosition);
          
          // Animated distortion based on time and mouse
          vec2 distortion = vec2(
            sin(uv.x * 10.0 + uTime) * 0.02,
            cos(uv.y * 8.0 + uTime * 0.5) * 0.02
          );
          
          // Mouse interaction
          vec2 mouseInfluence = (uMouse - 0.5) * 0.1;
          distortion += mouseInfluence * 0.05;
          
          // Add noise for realistic glass imperfections
          float noiseValue = smoothNoise(uv * 20.0 + uTime * 0.1) * 0.01;
          distortion += vec2(noiseValue);
          
          // Apply distortion to UV coordinates
          vec2 distortedUV = uv + distortion * uDistortion;
          
          // Calculate fresnel effect
          float fresnelFactor = fresnel(viewDirection, normal, uFresnelPower);
          
          // Refraction calculation
          vec3 refractedDirection = calculateRefraction(viewDirection, normal, 1.0 / 1.5);
          
          // Sample background with refraction
          vec2 refractionUV = distortedUV + refractedDirection.xy * uRefractionStrength;
          refractionUV = clamp(refractionUV, 0.0, 1.0);
          
          // Create glass color with realistic properties
          vec3 glassColor = vec3(0.9, 0.95, 1.0);
          
          // Add subtle color variation based on thickness
          float thicknessVariation = sin(uv.x * 5.0) * sin(uv.y * 3.0) * 0.1;
          glassColor += vec3(thicknessVariation * 0.1);
          
          // Mix reflection and transmission based on fresnel
          vec3 reflectionColor = mix(vec3(0.1), vec3(0.9), fresnelFactor);
          vec3 transmissionColor = glassColor * uTransmission;
          
          vec3 finalColor = mix(transmissionColor, reflectionColor, fresnelFactor * 0.3);
          
          // Add subtle caustics effect
          float caustics = sin(refractedDirection.x * 20.0) * sin(refractedDirection.y * 20.0);
          caustics = pow(caustics, 2.0) * 0.1;
          finalColor += vec3(caustics);
          
          // Add rim lighting
          float rimLight = 1.0 - max(dot(normal, viewDirection), 0.0);
          rimLight = pow(rimLight, 2.0);
          finalColor += vec3(rimLight * 0.2);
          
          // Calculate alpha based on fresnel and thickness
          float alpha = mix(0.1, 0.8, fresnelFactor) * uThickness;
          
          gl_FragColor = vec4(finalColor, alpha);
        }
      `,
      transparent: true,
      side: THREE.DoubleSide,
    });
  }, [viewport]);

  useFrame((state) => {
    if (meshRef.current) {
      const material = meshRef.current.material as THREE.ShaderMaterial;
      material.uniforms.uTime.value = state.clock.elapsedTime;
      
      // Update mouse position
      const mouse = state.mouse;
      material.uniforms.uMouse.value.set(mouse.x, mouse.y);
    }
  });

  return (
    <mesh ref={meshRef} position={[0, 0, 0]}>
      <planeGeometry args={[viewport.width, viewport.height, 32, 32]} />
      <primitive object={glassMaterial} />
    </mesh>
  );
};

export default GlassShader;
