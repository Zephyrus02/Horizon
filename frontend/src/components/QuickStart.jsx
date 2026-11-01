import { RELEASES_URL } from '../links'
import Icon from './Icon'

const steps = [
  {
    title: 'Download and install',
    body: 'Download the latest Horizon release, open the disk image and drag Horizon into your Applications folder. Everything it needs is bundled.',
  },
  {
    title: 'Open Horizon',
    body: 'Launch it once and the Horizon icon appears in your menu bar. Click it to open the control panel.',
  },
  {
    title: 'Connect your drive',
    body: 'Choose Google Drive, Dropbox or OneDrive and sign in through your browser. Flip the toggle and your drive shows up in Finder.',
  },
]

export default function QuickStart() {
  return (
    <section className="section section--alt" id="get-started">
      <div className="container">
        <header className="section__head" data-reveal>
          <span className="eyebrow">Get started</span>
          <h2>Up and running in under a minute.</h2>
          <p>No terminal and no extra software. Just install the app and sign in.</p>
        </header>

        <ol className="steps">
          {steps.map((s, i) => (
            <li key={s.title} className="step" data-reveal style={{ '--delay': `${i * 120}ms` }}>
              <span className="step__num">{String(i + 1).padStart(2, '0')}</span>
              <h3>{s.title}</h3>
              <p>{s.body}</p>
            </li>
          ))}
        </ol>

        <div className="cta" data-reveal>
          <div className="cta__glow" aria-hidden="true" />
          <img src="/logo.png" alt="" width="64" height="64" />
          <h2>Bring your cloud home to Finder.</h2>
          <p>Free and open source. Built natively in SwiftUI for macOS.</p>
          <a className="btn btn--primary btn--lg" href={RELEASES_URL}>
            <Icon name="download" size={18} />
            Download Horizon
          </a>
        </div>
      </div>
    </section>
  )
}
