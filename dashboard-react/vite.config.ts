/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react-swc'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'
import fs from 'fs'

/** Serve /data/*.json from dashboard/data/ when backend is not running. */
function serveDataPlugin() {
  const dataDir = path.resolve(__dirname, '../dashboard/data')
  return {
    name: 'serve-data',
    configureServer(server: import('vite').ViteDevServer) {
      server.middlewares.use('/data', (req, res, next) => {
        const name = req.url ? path.basename(new URL(req.url, 'http://x').pathname) : ''
        if (!name.endsWith('.json')) return next()
        const file = path.join(dataDir, name)
        if (!fs.existsSync(file)) return next()
        res.setHeader('Content-Type', 'application/json')
        fs.createReadStream(file).pipe(res)
      })
    },
  }
}

export default defineConfig({
  plugins: [react(), tailwindcss(), serveDataPlugin()],
  build: {
    rollupOptions: {
      output: {
        // Split heavy vendors into their own long-term-cacheable chunks so they
        // load in parallel and aren't re-downloaded on every app deploy.
        manualChunks(id: string) {
          if (!id.includes('node_modules')) return
          if (id.includes('recharts') || id.includes('victory-vendor') || id.includes('/d3-')) return 'charts'
          if (id.includes('jspdf') || id.includes('html2canvas')) return 'pdf'
          if (id.includes('xlsx')) return 'xlsx'
          if (id.includes('react-dom') || id.includes('/react/') || id.includes('scheduler')) return 'react-vendor'
        },
      },
    },
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      // Local Flask data-entry app (launch.json pins it to 5050; macOS AirPlay owns 5000).
      // Dev must NOT proxy to prod: /api is JWT-gated there (architecture/API_AUTH.md)
      // and dev previously read/wrote production data by accident.
      '/api': {
        target: process.env.VITE_FLASK_API_URL || 'http://localhost:5050',
        changeOrigin: true,
      },
      '/cubejs-api': 'http://localhost:4000',
    },
    // /data served directly by serveDataPlugin from dashboard/data/ (no backend needed)
    watch: {
      // Ignore dashboard/data so refresh_data.py writing JSON files doesn't trigger HMR/reload
      ignored: ['**/dashboard/data/**'],
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test-setup.ts',
    include: ['src/**/*.test.{ts,tsx}'],
  },
})
