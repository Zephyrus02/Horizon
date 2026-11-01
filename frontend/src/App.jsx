import { useRevealOnScroll } from './hooks/useScroll'
import Nav from './components/Nav'
import Hero from './components/Hero'
import Providers from './components/Providers'
import Features from './components/Features'
import HowItWorks from './components/HowItWorks'
import Benchmarks from './components/Benchmarks'
import QuickStart from './components/QuickStart'
import Footer from './components/Footer'
import Privacy from './pages/Privacy'
import Terms from './pages/Terms'

export default function App() {
  useRevealOnScroll()

  const path = window.location.pathname.replace(/\/+$/, '')
  const Legal = path === '/privacy' ? Privacy : path === '/terms' ? Terms : null

  if (Legal) {
    return (
      <>
        <Nav />
        <main>
          <Legal />
        </main>
        <Footer />
      </>
    )
  }

  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Providers />
        <Features />
        <HowItWorks />
        <Benchmarks />
        <QuickStart />
      </main>
      <Footer />
    </>
  )
}
