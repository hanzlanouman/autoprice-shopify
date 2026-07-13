import { defineConfig } from 'vitest/config'
import RubyPlugin from 'vite-plugin-ruby'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [RubyPlugin(), react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./test/setup.ts'],
    include: ['**/*.test.{ts,tsx}'],
    globals: true,
    clearMocks: true,
    restoreMocks: true,
  },
})
