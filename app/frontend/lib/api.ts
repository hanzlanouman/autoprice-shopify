// Single entry point for all API calls. Handles the error envelope, JSON
// parsing, and CSRF. Components/hooks never call fetch directly.

export interface ApiErrorShape {
  code: string
  message: string
  details?: Record<string, string[]>
}

export class ApiError extends Error {
  code: string
  details?: Record<string, string[]>
  status: number

  constructor(status: number, body: ApiErrorShape) {
    super(body.message)
    this.name = 'ApiError'
    this.status = status
    this.code = body.code
    this.details = body.details
  }
}

function csrfToken(): string {
  return (
    document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
      ?.content ?? ''
  )
}

async function request<T>(
  method: string,
  path: string,
  body?: unknown,
  signal?: AbortSignal,
): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  if (method !== 'GET') headers['X-CSRF-Token'] = csrfToken()

  let response: Response
  try {
    response = await fetch(new URL(path, window.location.origin), {
      method,
      headers,
      credentials: 'same-origin',
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    })
  } catch {
    throw new ApiError(0, {
      code: 'network_error',
      message:
        'Could not reach the server. Check your connection and try again.',
    })
  }

  const text = await response.text()
  let payload: unknown = null
  if (text) {
    try {
      payload = JSON.parse(text)
    } catch {
      throw new ApiError(response.status, {
        code: 'invalid_response',
        message: 'The server returned an invalid response. Please try again.',
      })
    }
  }

  if (!response.ok) {
    const envelope: ApiErrorShape =
      payload &&
      typeof payload === 'object' &&
      'error' in payload &&
      payload.error &&
      typeof payload.error === 'object' &&
      'message' in payload.error
        ? (payload.error as ApiErrorShape)
        : {
            code: 'unknown_error',
            message: `Request failed (${response.status})`,
          }
    throw new ApiError(response.status, envelope)
  }

  return payload as T
}

export const api = {
  get: <T>(path: string, options?: { signal?: AbortSignal }) =>
    request<T>('GET', path, undefined, options?.signal),
  post: <T>(path: string, body?: unknown) => request<T>('POST', path, body),
  patch: <T>(path: string, body?: unknown) => request<T>('PATCH', path, body),
}
