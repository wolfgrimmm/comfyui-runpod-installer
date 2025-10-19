# Rive Animations Directory

Place your .riv animation files here.

## Required Files

Create these animations in Rive Editor (see `/public/design/FIGMA_GUIDE.md`):

- **hero-particles.riv** - Interactive particle system (15-20KB)
- **button-primary.riv** - Primary button with hover/press states (8-12KB)
- **button-secondary.riv** - Secondary button variant (8-12KB)
- **card-glow.riv** - Radial glow effect for cards (6-10KB)
- **status-dot.riv** - 4-state status indicator (5-8KB)

## Specifications

Detailed specifications for each animation are in:
`src/lib/rive-specs.ts`

## Creating Animations

1. Design components in Figma
2. Export as SVG
3. Import into Rive Editor
4. Create state machines per spec
5. Test at 60 FPS
6. Export as .riv
7. Place files in this directory

## Using Rive MCP

You can use Rive MCP in Cursor to programmatically generate these animations:

Example prompts:
- "Create a state machine for hero particles with MouseX and MouseY inputs"
- "Build a button animation with hover and press states"
- "Design a pulsing glow effect with intensity control"

See Rive MCP documentation for more details.



