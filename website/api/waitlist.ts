import { joinWaitlist } from './_waitlist.js'

type ApiRequest = { method?: string; body?: unknown }
type ApiResponse = { status(code: number): ApiResponse; json(body: unknown): void; setHeader(name: string, value: string): void }

export default async function handler(request: ApiRequest, response: ApiResponse) {
  response.setHeader('Cache-Control', 'no-store')
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST')
    return response.status(405).json({ message: 'Method not allowed.' })
  }
  const result = await joinWaitlist(request.body, process.env)
  return response.status(result.status).json(result.body)
}
