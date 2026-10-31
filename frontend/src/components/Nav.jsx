import { useScrollState } from '../hooks/useScroll'
import { REPO_URL, RELEASES_URL } from '../links'
import Icon from './Icon'

const links = [
  { href: '#features', label: 'Features' },
  { href: '#how-it-works', label: 'How it works' },
  { href: '#performance', label: 'Performance' },
  { href: '#get-started', label: 'Get started' },
]

export default function Nav() {
  const { progress, scrolled } = useScrollState()

  return (
    <header className={`nav ${scrolled ? 'nav--scrolled' : ''}`}>
      <div className="nav__inner container">
        <a href="#top" className="brand" aria-label="Horizon home">
          <img src="/logo.png" alt="" width="28" height="28" />
          <span>Horizon</span>
        </a>
        <nav className="nav__links" aria-label="Primary">
          {links.map((l) => (
            <a key={l.href} href={l.href}>
              {l.label}
            </a>
          ))}
        </nav>
        <div className="nav__actions">
          <a className="icon-link" href={REPO_URL} aria-label="Horizon on GitHub">
            <Icon name="github" />
          </a>
          <a className="btn btn--sm btn--primary" href={RELEASES_URL}>
            Download
          </a>
        </div>
      </div>
      <div className="nav__progress" style={{ transform: `scaleX(${progress})` }} />
    </header>
  )
}
