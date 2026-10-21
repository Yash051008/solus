import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Solus Distribution',
  description: 'FMCG distribution management: manufacturer, distributor, agent, retailer.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en-NG">
      <body>{children}</body>
    </html>
  );
}
