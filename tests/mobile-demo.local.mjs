import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { chromium } from '../tooling/node_modules/playwright-core/index.mjs'

const demo = JSON.parse(readFileSync(new URL('../.playwright-cli/demo-fixtures.json', import.meta.url)))
const origin = new URL(demo.appOrigin).origin
assert.equal(origin, 'http://127.0.0.1:3000')
const browser = await chromium.launch({ channel: 'chrome' })

function marketResponse(page, operation, action = 'orders') {
  return page.waitForResponse((response) => {
    const request = response.request()
    if (response.url() !== origin + '/api/market' || request.method() !== 'POST') return false
    const data = request.postDataJSON()
    return data?.action === action && data.operation === operation
  })
}

async function pageFor(session) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true })
  await context.addInitScript(({ origin, session }) => {
    if (location.origin === origin) sessionStorage.setItem('dondepido.session', JSON.stringify(session))
  }, { origin, session })
  return context.newPage()
}

async function decision(page, businessId, orderId, outcome) {
  await page.goto(origin + '/gestion/pedidos?comercio=' + businessId)
  const card = page.getByText('Pedido ' + orderId.slice(0, 8) + ' · Recibido', { exact: true })
  await card.click()
  const details = card.locator('..')
  await details.getByLabel('Decisión').selectOption(outcome)
  if (outcome === 'rejected') await details.getByLabel('Motivo').fill('Prueba móvil de rechazo')
  const response = marketResponse(page, 'decide')
  await details.getByRole('button', { name: 'Guardar decisión' }).click()
  assert.equal((await response).status(), 200)
}

try {
  const buyer = await pageFor(demo.buyer)
  await buyer.goto(origin + '/explorar?rubro=kioscos&comercio=' + demo.kiosk)
  await buyer.getByRole('button', { name: new RegExp('Agregar ' + demo.label) }).click()
  await buyer.goto(origin + '/explorar?rubro=gastronomia&comercio=' + demo.kitchen)
  await buyer.getByRole('button', { name: /Agregar Empanada demo/ }).click()
  await buyer.getByRole('link', { name: /^Carrito/ }).click()
  const pickup = buyer.getByLabel('Modalidad').first()
  assert.equal(await pickup.inputValue(), 'pickup')
  await buyer.getByLabel('Modalidad').last().selectOption('delivery')
  await buyer.getByLabel('Dirección de entrega').fill('Calle de prueba móvil 390, Deán Funes')
  const quoteResponse = marketResponse(buyer, 'quote')
  await buyer.getByRole('button', { name: 'Revisar pedido' }).click()
  const quote = await quoteResponse
  assert.equal(quote.status(), 200)
  assert.equal((await quote.json()).data.total, 380000)
  const submitResponse = marketResponse(buyer, 'submit')
  await buyer.getByRole('button', { name: 'Enviar solicitudes' }).click()
  const submit = await submitResponse
  assert.equal(submit.status(), 200)
  const group = (await submit.json()).data
  assert.equal(group.orders.length, 2)
  const kiosk = group.orders.find((order) => order.business_id === demo.kiosk)
  const kitchen = group.orders.find((order) => order.business_id === demo.kitchen)
  assert.ok(kiosk && kitchen)
  const owner = await pageFor(demo.owner)
  await decision(owner, demo.kiosk, kiosk.id, 'rejected')
  await decision(owner, demo.kitchen, kitchen.id, 'confirmed')

  await buyer.goto(origin + '/pedidos')
  const history = buyer.locator('article').filter({ has: buyer.getByRole('heading', { name: 'Pedido ' + group.groupId.slice(0, 8), exact: true }) })
  await history.locator('summary').filter({ hasText: /· Confirmado$/ }).waitFor()
  await history.locator('summary').filter({ hasText: /· Rechazado$/ }).waitFor()
  assert.equal(await buyer.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true)

  const output = execFileSync(process.execPath, ['scripts/dispatch-notices-local.mjs', '--order', kitchen.id],
    { encoding: 'utf8', timeout: 30_000 })
  assert.match(output, /Capturados: 1/)
  const inbox = new URL('http://127.0.0.1:55424/api/v1/search')
  inbox.searchParams.set('query', 'to:whatsapp-local@example.invalid subject:' + kitchen.id)
  const { messages } = await (await fetch(inbox)).json()
  const found = messages.find((message) => message.Subject === 'DondePido WhatsApp local ' + kitchen.id)
  assert.ok(found, 'Mailpit debe tener el aviso de esta entrega')
  const mail = await (await fetch('http://127.0.0.1:55424/api/v1/message/' + encodeURIComponent(found.ID))).json()
  assert.match(mail.Text, /Calle de prueba móvil 390/)
  assert.match(mail.Text, /Empanada demo/)
  console.log('PASS móvil 390 px: catálogo, retiro y entrega, confirmación, rechazo, historial y aviso capturado en Mailpit')
} finally {
  await browser.close()
}
