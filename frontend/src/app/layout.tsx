import type { Metadata } from "next";
import { Outfit, DM_Sans, JetBrains_Mono } from "next/font/google";
import { ThirdwebProvider } from "thirdweb/react";
import "./globals.css";

const heading = Outfit({
  variable: "--font-heading",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800", "900"],
});

const body = DM_Sans({
  variable: "--font-body",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

const mono = JetBrains_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000"),
  title: "OSZILLOR | Autonomous Risk-Managed Yield",
  description: "The first autonomous, risk-managed yield protocol powered by Chainlink CRE and embedded AI intelligence.",
  openGraph: {
    title: "OSZILLOR | Autonomous Risk-Managed Yield",
    description: "DeFi that thinks for itself. AI-powered yield with real-time risk management.",
    images: [{ url: "/og-image.png" }], // Replace with absolute URL on production deploy
  },
  twitter: {
    card: "summary_large_image",
    title: "OSZILLOR | Autonomous Risk-Managed Yield",
    description: "DeFi that thinks for itself. AI-powered yield with real-time risk management.",
    images: ["/og-image.png"], // Replace with absolute URL on production deploy
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${heading.variable} ${body.variable} ${mono.variable} antialiased`}>
        <ThirdwebProvider>
          {children}
        </ThirdwebProvider>
        <div className="grain-overlay" aria-hidden="true" />
      </body>
    </html>
  );
}
