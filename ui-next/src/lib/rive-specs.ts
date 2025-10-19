/**
 * Rive Animation Specifications
 * 
 * Create these animations in Rive Editor following specifications below.
 * Each animation is a separate .riv file with defined state machines and inputs.
 * 
 * Workflow:
 * 1. Design components in Figma (see FIGMA_GUIDE.md) - OPTIONAL
 * 2. Create directly in Rive Editor OR export from Figma as SVG
 * 3. Create state machines and animations per spec below
 * 4. Export as .riv file to public/animations/
 * 5. Components will automatically load and use the .riv files
 */

export const RIVE_SPECS = {
  // 1. Hero Particle System (Most Complex)
  heroParticles: {
    file: 'hero-particles.riv',
    artboard: 'ParticleSystem',
    stateMachine: 'Main',
    canvas: { width: 1920, height: 1080 },
    inputs: [
      { name: 'MouseX', type: 'Number', range: [0, 100] },
      { name: 'MouseY', type: 'Number', range: [0, 100] }
    ],
    implementation: `
      Create in Rive:
      
      1. Create 80 Circle shapes (2-4px radius)
      2. Randomize positions across canvas
      3. Add Fill: Solid colors from palette
         - 30% #E7331D (red)
         - 35% #8B5CF6 (purple)
         - 35% #3B82F6 (blue)
      
      4. Animate particle movement:
         - Add "Continuous" animation
         - Keyframe random X/Y positions (0s → 10s)
         - Loop type: Loop
         - Easing: Linear
      
      5. Add motion blur:
         - Effects → Motion Blur
         - Samples: 8
         - Shutter angle: 180°
      
      6. Create State Machine "Main":
         - Inputs: MouseX (Number 0-100), MouseY (Number 0-100)
         - Listener: On MouseX/MouseY change
         - Action: Attract particles toward cursor
           (Use formula: newX = x + (mouseX - x) * 0.05)
      
      7. Add particle connections:
         - For each particle pair < 100px apart
         - Draw Line (0.5px stroke, rgba(255,255,255,0.1))
         - Fade opacity based on distance
      
      Export Size: ~15-20KB
    `
  },

  // 2. Button Hover Animation
  buttonPrimary: {
    file: 'button-primary.riv',
    artboard: 'Button',
    stateMachine: 'ButtonStates',
    canvas: { width: 200, height: 60 },
    inputs: [
      { name: 'isHovered', type: 'Boolean' },
      { name: 'isPressed', type: 'Boolean' }
    ],
    implementation: `
      Create in Rive:
      
      1. Create rounded rectangle (200x60px, radius: 12px)
      2. Fill: Linear gradient
         - Start: #E7331D
         - End: #8B5CF6
         - Angle: 135°
      
      3. Add glow effect:
         - Duplicate rectangle
         - Scale: 1.1x
         - Blur: 60px
         - Opacity: 0
         - Send to back
      
      4. Create State Machine "ButtonStates":
         
         States:
         - Idle: Scale 1.0, glow opacity 0
         - Hover: Scale 1.05, glow opacity 0.6
         - Press: Scale 0.98, glow opacity 1.0
         
         Transitions:
         - Idle → Hover: When isHovered = true (duration: 0.3s, ease: Cubic)
         - Hover → Idle: When isHovered = false (duration: 0.3s)
         - Hover → Press: When isPressed = true (duration: 0.1s)
         - Press → Hover: When isPressed = false (duration: 0.1s)
      
      5. Add shimmer effect:
         - Create white rectangle (20x60px)
         - Rotate: 45°
         - Opacity: 20%
         - Animate: X position -50 → 250 (1.5s)
         - Trigger: On Hover state enter
      
      Export Size: ~8-12KB
    `
  },

  // 3. Card Glow Effect
  cardGlow: {
    file: 'card-glow.riv',
    artboard: 'Glow',
    stateMachine: 'GlowEffect',
    canvas: { width: 400, height: 400 },
    inputs: [
      { name: 'isVisible', type: 'Boolean' },
      { name: 'intensity', type: 'Number', range: [0, 1] }
    ],
    implementation: `
      Create in Rive:
      
      1. Create large ellipse (400x400px)
      2. Fill: Radial gradient
         - Center: #E7331D at 100% opacity
         - Edge: #E7331D at 0% opacity
      3. Blur: 100px
      4. Initial opacity: 0
      
      5. Create Animation "Pulse":
         - 0s: Opacity 0, Scale 1.0
         - 1s: Opacity 0.8, Scale 1.2
         - 2s: Opacity 0, Scale 1.0
         - Loop: Yes
      
      6. Create State Machine "GlowEffect":
         - Input: isVisible (Boolean)
         - Input: intensity (Number 0-1)
         
         States:
         - Hidden: Opacity 0
         - Visible: Play "Pulse" animation
         
         Transitions:
         - Hidden → Visible: When isVisible = true
         - Visible → Hidden: When isVisible = false
         
         Bindings:
         - intensity input → Glow max opacity (0-0.8 range)
      
      Export Size: ~6-10KB
    `
  },

  // 4. Status Indicator Dot
  statusDot: {
    file: 'status-dot.riv',
    artboard: 'StatusIndicator',
    stateMachine: 'States',
    canvas: { width: 24, height: 24 },
    inputs: [
      { name: 'status', type: 'Number', range: [0, 3] }
    ],
    implementation: `
      Create in Rive:
      
      1. Create circle (12px diameter)
      2. Create 4 color states:
         - 0 (Idle): #666666, no animation
         - 1 (Loading): #3B82F6, pulsing
         - 2 (Ready): #10B981, subtle glow
         - 3 (Error): #E7331D, shake
      
      3. Create State Machine "States":
         - Input: status (Number 0-3)
         
         States:
         - Idle: Gray, static
         - Loading: Blue with scale pulse (1.0 ↔ 1.3, 0.8s loop)
         - Ready: Green with opacity pulse (0.8 ↔ 1.0, 2s loop)
         - Error: Red with shake X offset (-2 ↔ 2px, 0.1s, 5 times)
         
         Transitions:
         - Switch state when status input changes
         - Instant transition (0s duration)
      
      4. Add glow for Ready/Error states:
         - Duplicate circle
         - Scale: 2x
         - Blur: 8px
         - Opacity: 30%
      
      Export Size: ~5-8KB
    `
  }
} as const;

export type RiveAnimationKey = keyof typeof RIVE_SPECS;



