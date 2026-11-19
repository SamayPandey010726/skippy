import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { joinWaitlist } from './api/_waitlist.js'

function waitlistDevRoute() {
  return {
    name: 'parcel-waitlist-dev-route',
    configureServer(server: { middlewares: { use(route: string, handler: (request: import('node:http').IncomingMessage, response: import('node:http').ServerResponse) => void): void } }) {
      server.middlewares.use('/api/waitlist', (request, response) => {
        if (request.method !== 'POST') { response.statusCode = 405; response.end(JSON.stringify({ message: 'Method not allowed.' })); return }
        let body = ''
        request.on('data', chunk => { body += chunk; if (body.length > 16_384) request.destroy() })
        request.on('end', async () => {
          let parsed: unknown
          try { parsed = JSON.parse(body) } catch { parsed = null }
          const result = await joinWaitlist(parsed, process.env)
          response.statusCode = result.status
          response.setHeader('Content-Type', 'application/json')
          response.setHeader('Cache-Control', 'no-store')
          response.end(JSON.stringify(result.body))
        })
      })
    },
  }
}

export default defineConfig({
  plugins: [react(), waitlistDevRoute()],
  server: {
    host: '0.0.0.0',
    port: 4173,
    proxy: {
      '/api/shorten': {
        target: 'https://da.gd',
        changeOrigin: true,
        rewrite: path => `/s${path.replace('/api/shorten', '')}`,
      },
    },
  },
})
