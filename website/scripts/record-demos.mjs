import { chromium } from '@playwright/test'
import { copyFile, mkdir } from 'node:fs/promises'
import { join } from 'node:path'

const baseURL = process.env.PARCEL_SITE_URL ?? 'http://127.0.0.1:4173'
const output = new URL('../public/media/', import.meta.url).pathname
const studioCSS = `
  body { background: #dfe5de !important; overflow: hidden !important; }
  .topbar, .hero, .demo-section > .section-heading, .demo-footnote,
  .proof-section, .features-section, .keyboard-section, .access-section,
  .final-cta, footer { display: none !important; }
  .demo-section { width: 100vw !important; height: 100vh !important; margin: 0 !important; padding: 18px !important; }
  .demo-desktop { width: 100% !important; height: calc(100vh - 36px) !important; min-height: 0 !important; border-radius: 28px !important; }
`

await mkdir(output, { recursive: true })
const browser = await chromium.launch()

async function capture(name, run) {
  const videoDir = join(output, `.record-${name}`)
  await mkdir(videoDir, { recursive: true })
  const context = await browser.newContext({ viewport: { width: 1100, height: 700 }, recordVideo: { dir: videoDir, size: { width: 1100, height: 700 } }, reducedMotion: 'no-preference' })
  const page = await context.newPage()
  await page.goto(baseURL, { waitUntil: 'networkidle' })
  await page.addStyleTag({ content: studioCSS })
  await page.waitForTimeout(900)
  const video = page.video()
  await run(page)
  await page.waitForTimeout(1000)
  await context.close()
  await copyFile(await video.path(), join(output, `${name}.webm`))
}

await capture('parcel-link-demo', async page => {
  const demo = page.getByLabel('Interactive Parcel product demo')
  await demo.getByRole('button', { name: 'Clipboard' }).click()
  await page.waitForTimeout(850)
  await page.screenshot({ path: join(output, 'parcel-link-demo.png') })
  await demo.getByLabel('Shorten a link').fill('https://example.com/projects/parcel/launch-review/november')
  await page.waitForTimeout(450)
  await demo.getByRole('button', { name: 'Shorten' }).click()
  await demo.getByText('Short link copied and added to Clipboard.').waitFor({ timeout: 15_000 })
  await page.waitForTimeout(1400)
})

await capture('parcel-magnetic-demo', async page => {
  const demo = page.getByLabel('Interactive Parcel product demo')
  const file = demo.getByRole('button', { name: /Hero artwork/ })
  const trash = demo.getByRole('button', { name: 'Delete item' })
  const from = await file.boundingBox()
  const to = await trash.boundingBox()
  if (!from || !to) throw new Error('Could not locate magnetic demo targets')
  const dataTransfer = await page.evaluateHandle(() => new DataTransfer())
  await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2)
  await file.dispatchEvent('dragstart', { dataTransfer })
  await page.mouse.move(to.x - 80, to.y + to.height / 2, { steps: 28 })
  await trash.dispatchEvent('dragenter', { dataTransfer })
  await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, { steps: 12 })
  await page.waitForTimeout(900)
  await page.screenshot({ path: join(output, 'parcel-magnetic-demo.png') })
  await trash.dispatchEvent('drop', { dataTransfer })
  await demo.getByText('Hero artwork.png moved to Bin.').waitFor()
  await page.waitForTimeout(900)
  await demo.getByRole('button', { name: 'New parcel' }).click()
  await page.waitForTimeout(700)
})

await browser.close()
console.log('Recorded clean Parcel demos in public/media')
