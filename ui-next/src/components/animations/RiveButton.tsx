'use client';
import { useState } from 'react';

interface Props {
  children: React.ReactNode;
  onClick?: () => void;
  variant?: 'primary' | 'secondary';
  disabled?: boolean;
}

export default function RiveButton({ 
  children, 
  onClick, 
  variant = 'primary',
  disabled = false 
}: Props) {
  const [isHovered, setIsHovered] = useState(false);
  const [isPressed, setIsPressed] = useState(false);

  const handleMouseEnter = () => {
    if (disabled) return;
    setIsHovered(true);
  };

  const handleMouseLeave = () => {
    setIsHovered(false);
    setIsPressed(false);
  };

  const handleMouseDown = () => {
    if (disabled) return;
    setIsPressed(true);
  };

  const handleMouseUp = () => {
    setIsPressed(false);
  };

  const handleClick = () => {
    if (!disabled && onClick) onClick();
  };

  // Stunning CSS animations with GPU acceleration
  const baseClasses = `relative overflow-hidden px-8 py-4 rounded-xl font-semibold text-white
    transition-all duration-300 ease-out transform-gpu will-change-transform
    ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`;

  const variantClasses = variant === 'primary' 
    ? 'bg-gradient-to-br from-red-500 via-red-600 to-purple-600 shadow-lg shadow-red-500/20'
    : 'bg-gradient-to-br from-gray-600 via-gray-700 to-gray-800 border border-white/10';

  const hoverClasses = isHovered && !disabled 
    ? 'scale-105 shadow-2xl shadow-red-500/40 brightness-110' 
    : '';

  const pressClasses = isPressed && !disabled 
    ? 'scale-95 brightness-95' 
    : '';

  return (
    <button
      className={`${baseClasses} ${variantClasses} ${hoverClasses} ${pressClasses}`}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      onMouseDown={handleMouseDown}
      onMouseUp={handleMouseUp}
      onClick={handleClick}
      disabled={disabled}
    >
      {/* Stunning shimmer effect */}
      {isHovered && !disabled && (
        <div className="absolute inset-0 overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent 
            animate-shimmer transform -skew-x-12" />
          <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/10 to-transparent 
            animate-shimmer-delayed transform -skew-x-12" />
        </div>
      )}
      
      {/* Glow effect */}
      {isHovered && !disabled && (
        <div className="absolute -inset-1 bg-gradient-to-r from-red-500/50 via-purple-500/50 to-red-500/50 
          rounded-xl blur-sm opacity-75 animate-pulse" />
      )}
      
      {/* Button text */}
      <span className="relative z-10">{children}</span>
    </button>
  );
}



