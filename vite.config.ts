import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': path.resolve(__dirname, 'src') }
  },
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:4567',
      '/uploads': 'http://localhost:4567',
      // Legacy routes that aren't under /api yet
      '/beds': 'http://localhost:4567',
    }
  },
  publicDir: 'static',  // avoid conflict with Sinatra's public/
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  }
})
