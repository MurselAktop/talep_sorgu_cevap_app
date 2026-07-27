import type { Config } from 'tailwindcss'

export default {
  darkMode: 'class',
  content: [
    './app/components/**/*.{js,vue,ts}',
    './app/layouts/**/*.vue',
    './app/pages/**/*.vue',
    './app/app.vue',
    './app/plugins/**/*.{js,ts}',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
      colors: {
        status: {
          acik: '#F59E0B',
          cozuldu: '#3B82F6',
          onaylandi: '#14B8A6',
          reddedildi: '#EF4444',
          iptal: '#9CA3AF',
        },
      },
      boxShadow: {
        soft: '0 1px 2px rgba(15,23,42,0.05), 0 8px 24px rgba(15,23,42,0.07)',
        puff: '0 2px 4px rgba(15,23,42,0.06), 0 10px 22px rgba(15,23,42,0.08), inset 0 1px 0 rgba(255,255,255,0.65)',
      },
    },
  },
  plugins: [],
} satisfies Config
