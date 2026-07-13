import { http, HttpResponse } from 'msw'
import { api, ApiError } from './api'
import { server } from '../test/server'

describe('api client', () => {
  it('sends JSON and the Rails CSRF token for mutations', async () => {
    const meta = document.createElement('meta')
    meta.name = 'csrf-token'
    meta.content = 'test-token'
    document.head.append(meta)

    let receivedBody: unknown
    let receivedCsrf: string | null = null
    server.use(
      http.patch(
        'http://localhost:3000/api/v1/settings',
        async ({ request }) => {
          receivedBody = await request.json()
          receivedCsrf = request.headers.get('x-csrf-token')
          return HttpResponse.json({ saved: true })
        },
      ),
    )

    const result = await api.patch<{ saved: boolean }>('/api/v1/settings', {
      settings: { max_price_percentage: '125.00' },
    })

    expect(result).toEqual({ saved: true })
    expect(receivedCsrf).toBe('test-token')
    expect(receivedBody).toEqual({
      settings: { max_price_percentage: '125.00' },
    })
  })

  it('turns the API error envelope into a typed error', async () => {
    server.use(
      http.get('http://localhost:3000/api/v1/products', () =>
        HttpResponse.json(
          {
            error: {
              code: 'shopify_unavailable',
              message: 'Shopify is not configured.',
            },
          },
          { status: 503 },
        ),
      ),
    )

    const error = await api.get('/api/v1/products').catch((caught) => caught)
    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({
      name: 'ApiError',
      status: 503,
      code: 'shopify_unavailable',
      message: 'Shopify is not configured.',
    })
  })

  it('reports invalid and unreachable responses consistently', async () => {
    server.use(
      http.get(
        'http://localhost:3000/api/v1/broken',
        () => new HttpResponse('<html>bad gateway</html>', { status: 502 }),
      ),
      http.get('http://localhost:3000/api/v1/offline', () =>
        HttpResponse.error(),
      ),
    )

    await expect(api.get('/api/v1/broken')).rejects.toMatchObject({
      code: 'invalid_response',
    })
    await expect(api.get('/api/v1/offline')).rejects.toMatchObject({
      code: 'network_error',
      status: 0,
    })
  })
})
