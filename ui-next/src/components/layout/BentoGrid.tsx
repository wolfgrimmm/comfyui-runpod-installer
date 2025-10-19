'use client';
import { useInView } from 'react-intersection-observer';
import CardGlow from '@/components/animations/CardGlow';
import type { Feature } from '@/types';

const features: Feature[] = [
  { title: 'GPU Status', icon: '🎮', desc: 'Real-time monitoring', span: 'col-span-2 row-span-2' },
  { title: 'Model Manager', icon: '📦', desc: 'HuggingFace integration', span: 'col-span-1' },
  { title: 'Output Browser', icon: '🖼️', desc: 'Browse generated images', span: 'col-span-1' },
  { title: 'User Management', icon: '👥', desc: 'Multi-user support', span: 'col-span-1' },
  { title: 'Drive Sync', icon: '☁️', desc: 'Auto backup to Google Drive', span: 'col-span-2' },
];

export default function BentoGrid() {
  return (
    <section className="mt-16">
      <h2 className="text-4xl font-bold mb-8 text-center">Features</h2>
      
      <div className="grid grid-cols-3 gap-6 max-w-7xl mx-auto">
        {features.map((feature, i) => (
          <FeatureCard key={i} {...feature} />
        ))}
      </div>
    </section>
  );
}

function FeatureCard({ title, icon, desc, span }: Feature) {
  const { ref, inView } = useInView({
    threshold: 0.1,
    triggerOnce: true,
  });

  return (
    <div
      ref={ref}
      className={`${span} card-glass p-8 relative overflow-hidden
        transform transition-all duration-700 ease-out
        ${inView ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-12'}`}
    >
      {/* Rive glow effect */}
      <CardGlow isVisible={inView} intensity={0.6} />
      
      {/* Card content */}
      <div className="relative z-10">
        <div className="text-6xl mb-4">{icon}</div>
        <h3 className="text-2xl font-bold mb-2">{title}</h3>
        <p className="text-gray-400">{desc}</p>
      </div>
    </div>
  );
}

