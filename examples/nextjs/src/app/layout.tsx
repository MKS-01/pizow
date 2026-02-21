import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'PiZoW Monitor',
  description: 'Real-time health monitoring dashboard for Raspberry Pi Zero W',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className="bg-zinc-950">{children}</body>
    </html>
  )
}
