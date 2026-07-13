import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { server } from './server'

class ResizeObserverStub {
  disconnect() {
    // jsdom test stub
  }
  observe() {
    // jsdom test stub
  }
  unobserve() {
    // jsdom test stub
  }
}

class IntersectionObserverStub {
  readonly root = null
  readonly rootMargin = '0px'
  readonly thresholds = [0]

  disconnect() {
    // jsdom test stub
  }
  observe() {
    // jsdom test stub
  }
  takeRecords(): IntersectionObserverEntry[] {
    return []
  }
  unobserve() {
    // jsdom test stub
  }
}

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
})

vi.stubGlobal('ResizeObserver', ResizeObserverStub)
vi.stubGlobal('IntersectionObserver', IntersectionObserverStub)
HTMLElement.prototype.scrollIntoView = vi.fn()
Object.defineProperty(window, 'scroll', { value: vi.fn(), writable: true })

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => {
  cleanup()
  server.resetHandlers()
  document.head.querySelector('meta[name="csrf-token"]')?.remove()
})
afterAll(() => server.close())
