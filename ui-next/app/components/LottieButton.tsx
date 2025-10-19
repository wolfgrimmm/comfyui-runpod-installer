'use client';

import React, { useRef, useState } from 'react';
import Lottie, { LottieRefCurrentProps } from 'lottie-react';
import rippleAnimation from '@/public/animations/button-ripple.json';

interface Props {
  children: React.ReactNode;
  onClick?: () => void;
  variant?: 'primary' | 'secondary' | 'success';
  disabled?: boolean;
  className?: string;
}

export default function LottieButton({
  children,
  onClick,
  variant = 'primary',
  disabled = false,
  className = '',
}: Props) {
  const lottieRef = useRef<LottieRefCurrentProps>(null);
  const [isHovered, setIsHovered] = useState(false);

  const handleClick = (e: React.MouseEvent<HTMLButtonElement>) => {
    if (disabled) return;

    // Play ripple animation
    if (lottieRef.current) {
      lottieRef.current.goToAndPlay(0, true);
    }

    onClick?.();
  };

  const variantStyles = {
    primary: 'bg-gradient-to-br from-red-500 via-red-600 via-purple-600 to-blue-600 shadow-2xl shadow-red-500/50',
    secondary: 'bg-gradient-to-br from-gray-600 via-gray-700 to-gray-800 border-2 border-white/20 shadow-xl',
    success: 'bg-gradient-to-br from-green-500 via-green-600 to-emerald-600 shadow-2xl shadow-green-500/50',
  };

  return (
    <button
      className={`
        relative overflow-hidden px-10 py-5 rounded-2xl font-bold text-xl text-white
        gpu-accelerated ${variantStyles[variant]}
        ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer hover:scale-105 hover:-translate-y-1'}
        transition-all duration-300
        ${className}
      `}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      onClick={handleClick}
      disabled={disabled}
    >
      {/* Lottie Ripple Animation */}
      {!disabled && (
        <div className="absolute inset-0 pointer-events-none flex items-center justify-center">
          <Lottie
            lottieRef={lottieRef}
            animationData={rippleAnimation}
            loop={false}
            autoplay={false}
            style={{
              width: '100%',
              height: '100%',
              opacity: 0.6,
            }}
          />
        </div>
      )}

      {/* Hover Glow */}
      {isHovered && !disabled && (
        <div 
          className="absolute inset-0 bg-white/10 rounded-2xl animate-pulse"
          style={{ animationDuration: '2s' }}
        />
      )}

      <span className="relative z-10">{children}</span>
    </button>
  );
}

