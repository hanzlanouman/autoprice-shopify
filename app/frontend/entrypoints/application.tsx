import React from 'react'
import { createRoot } from 'react-dom/client'
import '@shopify/polaris/build/esm/styles.css'
import '../styles/application.css'
import App from '../App'

const container = document.getElementById('root')
if (container) {
  createRoot(container).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>,
  )
}
