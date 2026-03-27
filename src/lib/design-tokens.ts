// GardenOS Design System — Organic Biophilic
// Generated from UI/UX Pro Max analysis
// Typography: Lora (headings) + Raleway (body)
// Style: Organic, natural, rounded, flowing

export const colors = {
  // Brand
  primary: '#15803D',       // Forest green
  primaryLight: '#22C55E',  // Leaf green
  primaryDark: '#14532D',   // Deep forest

  // Accent
  accent: '#EC4899',        // Floral pink (for highlights)
  accentWarm: '#F97316',    // Amber (for urgent items)

  // Surfaces
  background: '#F0FDF4',    // Mint cream
  backgroundWarm: '#FEFCE8', // Warm cream
  card: '#FFFFFF',
  cardHover: '#F7FEE7',     // Lime tint on hover

  // Text
  foreground: '#14532D',    // Deep forest
  muted: '#64748B',         // Slate
  mutedLight: '#94A3B8',    // Light slate

  // Borders
  border: '#BBF7D0',        // Soft green
  borderMuted: '#E2E8F0',   // Gray

  // Semantic
  success: '#22C55E',
  warning: '#F59E0B',
  error: '#DC2626',
  info: '#3B82F6',

  // Destructive
  destructive: '#DC2626',
  destructiveLight: '#FEF2F2',
} as const

export const typography = {
  fontHeading: "'Lora', serif",
  fontBody: "'Raleway', system-ui, sans-serif",
  // Scale
  xs: '0.75rem',    // 12px
  sm: '0.875rem',   // 14px
  base: '1rem',     // 16px
  lg: '1.125rem',   // 18px
  xl: '1.25rem',    // 20px
  '2xl': '1.5rem',  // 24px
  '3xl': '2rem',    // 32px
} as const

export const effects = {
  radiusSm: '8px',
  radiusMd: '12px',
  radiusLg: '16px',
  radiusXl: '24px',    // Organic, flowing
  radiusFull: '9999px',

  shadowSm: '0 1px 3px rgba(21, 128, 61, 0.06)',
  shadowMd: '0 4px 12px rgba(21, 128, 61, 0.08)',
  shadowLg: '0 8px 24px rgba(21, 128, 61, 0.12)',

  transition: 'all 200ms ease-out',
  transitionFast: 'all 150ms ease-out',
} as const
