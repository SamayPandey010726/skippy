import { expect, test } from '@playwright/test'

test('waitlist validates consent and shows a safe service message', async ({ page }) => {
  await page.goto('http://127.0.0.1:4173')
  await page.getByRole('button', { name: 'Join waitlist' }).first().click()
  await expect(page.getByRole('heading', { name: 'Make your Mac feel easier.' })).toBeVisible()
  await page.getByRole('textbox', { name: 'Email', exact: true }).fill('person@example.com')
  const consent = page.getByLabel(/Email me about Parcel/)
  await expect(consent).not.toBeChecked()
  expect(await consent.evaluate((input: HTMLInputElement) => input.checkValidity())).toBe(false)
  await consent.check()
  await page.getByRole('button', { name: 'Join waitlist' }).last().click()
  await expect(page.getByRole('alert')).toContainText('waitlist is being connected')
})
