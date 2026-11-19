import { expect, test } from '@playwright/test'

test.beforeEach(async ({ page }) => {
  await page.goto('http://127.0.0.1:4173')
})

test('public pages contain no source repository links', async ({ page }) => {
  await expect(page.locator('a[href*="github.com"]')).toHaveCount(0)
  await page.goto('http://127.0.0.1:4173/pricing')
  await expect(page.locator('a[href*="github.com"]')).toHaveCount(0)
})

test('interactive shelf preserves files through search and supports core actions', async ({ page }) => {
  await expect(page.getByRole('heading', { name: 'Your Mac is fast. Moving things is not.' })).toBeVisible()
  const demo = page.getByLabel('Interactive Skippy product demo')
  await demo.scrollIntoViewIfNeeded()
  await expect(demo.getByRole('button', { name: /Campaign brief/ })).toBeVisible()

  await demo.getByRole('button', { name: 'Search parcel' }).click()
  const search = demo.getByPlaceholder('Try “metrics” or “png”')
  await search.fill('metrics')
  await expect(demo.getByRole('button', { name: /Launch metrics/ })).toBeVisible()
  await expect(demo.getByRole('button', { name: /Campaign brief/ })).toHaveCount(0)
  await demo.getByRole('button', { name: 'Close Search' }).click()
  await demo.getByRole('button', { name: 'Search parcel' }).click()
  await search.fill('')
  await expect(demo.getByRole('button', { name: /Campaign brief/ })).toBeVisible()

  await demo.getByRole('button', { name: /Hero artwork/ }).dragTo(demo.getByRole('button', { name: 'Delete item' }))
  await expect(demo.getByRole('button', { name: /Hero artwork/ })).toHaveCount(0)
  await expect(demo.getByText('Hero artwork.png moved to Bin.')).toBeVisible()

  await demo.getByRole('button', { name: 'New parcel' }).click()
  await expect(demo.getByRole('heading', { name: 'Name your new parcel' })).toBeVisible()
  await demo.getByLabel('Skippy name').fill('Client delivery')
  await demo.getByRole('button', { name: 'Create & pin' }).click()
  await expect(demo.getByText('Created and pinned “Client delivery”.')).toBeVisible()
})

test('cinematic journey is scroll-driven and directly controllable', async ({ page }) => {
  const cinematic = page.locator('#top')
  await cinematic.getByRole('button', { name: /02 Prepare/ }).click()
  await expect(page.getByRole('heading', { name: 'Change the thing. Keep the flow.' })).toBeVisible()
  await cinematic.getByRole('button', { name: /04 Send/ }).click()
  await expect(page.getByRole('heading', { name: 'Drop it anywhere. Done.' })).toBeVisible()
})

test('clipboard opens, searches and uses the live shortener', async ({ page }) => {
  const demo = page.getByLabel('Interactive Skippy product demo')
  await demo.scrollIntoViewIfNeeded()
  await demo.getByRole('button', { name: 'Clipboard' }).click()
  await expect(demo.getByRole('complementary', { name: 'Clipboard' })).toBeVisible()
  await demo.getByLabel('Search clipboard').fill('review')
  await expect(demo.getByText('Design review')).toBeVisible()
  await demo.getByLabel('Search clipboard').fill('')
  await demo.getByLabel('Shorten a link').fill('https://example.com/parcel-demo')
  await demo.getByRole('button', { name: 'Shorten' }).click()
  await expect(demo.getByText('Short link copied and added to Clipboard.')).toBeVisible({ timeout: 15_000 })
  await expect(demo.getByText('Shortened link')).toBeVisible()
})

test('keyboard controls and responsive layout work', async ({ page }) => {
  const demo = page.getByLabel('Interactive Skippy product demo')
  await demo.scrollIntoViewIfNeeded()
  await demo.focus()
  await page.keyboard.press('Meta+P')
  await expect(demo.getByText(/Packed 4 items/)).toBeVisible()
  await page.keyboard.press('/')
  await expect(demo.getByPlaceholder('Try “metrics” or “png”')).toBeFocused()

  await page.setViewportSize({ width: 390, height: 844 })
  await page.reload()
  await page.waitForTimeout(1_200)
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow).toBeLessThanOrEqual(1)
  await page.screenshot({ path: 'test-results/mobile-home.png', fullPage: true })
})

test('desktop visual capture has no page errors', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.reload()
  await page.waitForTimeout(1_200)
  await page.screenshot({ path: 'test-results/desktop-home.png', fullPage: true })
  expect(errors).toEqual([])
})

test('pricing is complete and responsive', async ({ page }) => {
  await page.goto('http://127.0.0.1:4173/pricing')
  await expect(page.getByRole('heading', { name: 'Pay once. Use it every day.' })).toBeVisible()
  await expect(page.getByText('$2.49', { exact: true })).toBeVisible()
  await expect(page.getByText('$4.99', { exact: true })).toBeVisible()
  await expect(page.getByText('$9.99', { exact: true })).toBeVisible()
  await expect(page.getByText('No payment is collected yet.')).toBeVisible()
  await page.screenshot({ path: 'test-results/pricing-desktop.png', fullPage: true })
  await page.setViewportSize({ width: 390, height: 844 })
  await page.reload()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(1)
  await page.screenshot({ path: 'test-results/pricing-mobile.png', fullPage: true })
})
