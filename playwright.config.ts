import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './apps/web/tests/e2e',
  timeout: 30_000,
  fullyParallel: true,
  use: {
    baseURL: 'http://127.0.0.1:4173',
    headless: true,
  },
  webServer: [
    {
      command:
        'cd apps/api && CODEX_HOME=./tests/fixtures/codex_home REPO_SCOPE=/repo/fixture uvicorn --app-dir src codex_watcher.main:app --host 127.0.0.1 --port 18000',
      port: 18000,
      reuseExistingServer: false,
      timeout: 60_000,
    },
    {
      command: 'corepack pnpm --filter @watcher/web dev --host 127.0.0.1 --port 4173',
      port: 4173,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
  ],
})
