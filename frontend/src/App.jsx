import { useRevealOnScroll } from './hooks/useScroll'
import Nav from './components/Nav'
import Hero from './components/Hero'
import Providers from './components/Providers'
import Features from './components/Features'
import HowItWorks from './components/HowItWorks'
import Benchmarks from './components/Benchmarks'
import QuickStart from './components/QuickStart'
import Footer from './components/Footer'

export default function App() {
  useRevealOnScroll()

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
