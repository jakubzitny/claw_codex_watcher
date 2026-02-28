import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')

  return {
    plugins: [react()],
    define: {
      __WATCHER_API_BASE__: JSON.stringify(env.VITE_API_BASE_URL ?? '/api/v1'),
      __WATCHER_WS_BASE__: JSON.stringify(env.VITE_WS_BASE_URL ?? ''),
      __WATCHER_TOKEN__: JSON.stringify(env.VITE_WATCHER_TOKEN ?? ''),
    },
    server: {
      proxy: {
        '/api': {
          target: 'http://127.0.0.1:18000',
          changeOrigin: true,
        },
        '/ws': {
          target: 'ws://127.0.0.1:18000',
          ws: true,
        },
      },
    },
  }
})
