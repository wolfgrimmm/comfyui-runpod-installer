'use client';

import { useEffect, useRef } from 'react';
import Lottie, { LottieRefCurrentProps } from 'lottie-react';
import animationData from '@/public/animations/hero-particles.json';

export default function LottieHero() {
  const lottieRef = useRef<LottieRefCurrentProps>(null);

  useEffect(() => {
    // Ensure animation loops
    if (lottieRef.current) {
      lottieRef.current.setSpeed(0.5); // Slow, ambient movement
    }
  }, []);

  return (
    <div className="fixed inset-0 pointer-events-none" style={{ zIndex: 0, opacity: 0.3 }}>
      <Lottie
        lottieRef={lottieRef}
        animationData={animationData}
        loop={true}
        autoplay={true}
        style={{
          width: '100%',
          height: '100%',
        }}
      />
    </div>
  );
}

