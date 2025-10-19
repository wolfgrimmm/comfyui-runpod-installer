'use client';

import Lottie from 'lottie-react';
import loaderAnimation from '@/public/animations/loader.json';

interface Props {
  show: boolean;
  message?: string;
}

export default function LottieLoader({ show, message = 'Loading...' }: Props) {
  if (!show) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div className="card-glass p-8 flex flex-col items-center gap-4">
        <Lottie
          animationData={loaderAnimation}
          loop={true}
          autoplay={true}
          style={{
            width: 120,
            height: 120,
          }}
        />
        <p className="text-white text-lg font-medium">{message}</p>
      </div>
    </div>
  );
}

