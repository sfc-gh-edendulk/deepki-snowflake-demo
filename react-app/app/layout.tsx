import type { Metadata } from "next"
import type React from "react"
import { ThemeProvider } from "@/components/theme-provider"
import { QueryProvider } from "@/components/query-provider"
import { APP_TITLE, LOGO_SRC } from "@/lib/constants"
import "./globals.css"

export const metadata: Metadata = {
  title: APP_TITLE,
  description:
    "Portfolio copilot for Deepki: CRREM pathway exposure, stranded floor area and retrofit priorities, answered by a Snowflake Cortex Agent.",
  icons: { icon: LOGO_SRC },
}

/*
 * The theme provider defaults to "system", which would open the demo in dark
 * mode on a laptop set that way. Seed the stored preference to light before
 * hydration so the brand skin shows as designed; the toggle still overwrites it.
 */
const SEED_LIGHT_THEME = `try{if(!localStorage.getItem("theme")){localStorage.setItem("theme","light")}if(localStorage.getItem("theme")!=="dark"){document.documentElement.classList.remove("dark")}}catch(e){}`

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: SEED_LIGHT_THEME }} />
      </head>
      <body className="antialiased">
        <ThemeProvider>
          <QueryProvider>{children}</QueryProvider>
        </ThemeProvider>
      </body>
    </html>
  )
}
