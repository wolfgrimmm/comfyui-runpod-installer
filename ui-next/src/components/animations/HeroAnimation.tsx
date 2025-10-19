'use client';
import { useEffect, useState } from 'react';

interface Props {
  mousePosition: { x: number; y: number };
}

export default function HeroAnimation({ mousePosition }: Props) {
  const [particles, setParticles] = useState<Array<{
    id: number;
    x: number;
    y: number;
    color: string;
    size: number;
    delay: number;
  }>>([]);

  // Generate CSS particles on component mount
  useEffect(() => {
    const newParticles = Array.from({ length: 60 }, (_, i) => ({
      id: i,
      x: Math.random() * 100,
      y: Math.random() * 100,
      color: ['bg-red-500', 'bg-purple-500', 'bg-blue-500'][Math.floor(Math.random() * 3)],
      size: Math.random() * 3 + 1,
      delay: Math.random() * 8,
    }));
    setParticles(newParticles);
  }, []);

  return (
    <div className="fixed inset-0 -z-10 opacity-60 pointer-events-none overflow-hidden">
      {/* Stunning CSS particle system */}
      <div className="relative w-full h-full">
        {particles.map((particle) => (
          <div
            key={particle.id}
            className={`absolute ${particle.color} rounded-full opacity-70
              animate-particle-drift transform-gpu will-change-transform`}
            style={{
              left: `${particle.x}%`,
              top: `${particle.y}%`,
              width: `${particle.size}px`,
              height: `${particle.size}px`,
              animationDelay: `${particle.delay}s`,
              transform: `translate(${(mousePosition.x - 50) * 0.1}px, ${(mousePosition.y - 50) * 0.1}px)`,
            }}
          />
        ))}
        
        {/* Connection lines */}
        {particles.slice(0, 20).map((particle, i) => {
          const nextParticle = particles[(i + 1) % 20];
          const distance = Math.sqrt(
            Math.pow(particle.x - nextParticle.x, 2) + 
            Math.pow(particle.y - nextParticle.y, 2)
          );
          
          if (distance < 30) {
            return (
              <div
                key={`line-${i}`}
                className="absolute bg-gradient-to-r from-white/10 to-transparent h-px opacity-30"
                style={{
                  left: `${Math.min(particle.x, nextParticle.x)}%`,
                  top: `${Math.min(particle.y, nextParticle.y)}%`,
                  width: `${distance}%`,
                  transform: `rotate(${Math.atan2(nextParticle.y - particle.y, nextParticle.x - particle.x)}rad)`,
                  transformOrigin: 'left center',
                }}
              />
            );
          }
          return null;
        })}
      </div>
    </div>
  );
}