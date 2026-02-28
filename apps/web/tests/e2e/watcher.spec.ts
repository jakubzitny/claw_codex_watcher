import { expect, test } from '@playwright/test'

test('shows codex-like layout and live detail', async ({ page }) => {
  await page.goto('/')

  await expect(page.getByRole('heading', { name: 'Threads' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'New thread' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Running fixture thread' })).toBeVisible()
  await expect(page.getByText('Plan Progress')).toBeVisible()
  await expect(page.getByText('Conversation')).toBeVisible()
  await expect(page.getByText('approval required')).toBeVisible()
  await expect(page.getByText(/Read-only watcher/)).toBeVisible()
  await expect(page.getByText('Live updates disconnected. Reconnecting...')).not.toBeVisible()
})
