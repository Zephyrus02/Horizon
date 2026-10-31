import { useState } from 'react'
import { RELEASES_URL } from '../links'
import Icon from './Icon'

const steps = [
  {
    title: 'Install rclone',
    body: 'Horizon drives rclone under the hood. One Homebrew command and you are set.',
    code: 'brew install rclone',
  },
  {
    title: 'Add a remote',
    body: 'Authenticate in your browser — or let the Horizon setup flow do it for you.',
    code: 'rclone config create gdrive drive scope="drive"',
  },
  {
    title: 'Flip the switch',
    body: 'Open Horizon from the menu bar and toggle Connect. Your drive appears under Locations.',
    code: 'open ~/GDrive',
  },
]

function CopyButton({ text }) {
  const [copied, setCopied] = useState(false)
  return (
    <button
      type="button"
      className="copy"
      aria-label={copied ? 'Copied' : 'Copy command'}
      onClick={() => {
        navigator.clipboard?.writeText(text).then(() => {
          setCopied(true)
          setTimeout(() => setCopied(false), 1600)
        })
      }}
    >
      <Icon name={copied ? 'check' : 'copy'} size={15} />
    </button>
  )
}

export default function QuickStart() {
  return (
    <section className="section section--alt" id="get-started">
      <div className="container">
        <header className="section__head" data-reveal>
          <span className="eyebrow">Get started</span>
          <h2>Up and running in under a minute.</h2>
        </header>

        <ol className="steps">
          {steps.map((s, i) => (
            <li key={s.title} className="card step" data-reveal style={{ '--delay': `${i * 120}ms` }}>
              <span className="step__num">{String(i + 1).padStart(2, '0')}</span>
              <h3>{s.title}</h3>
              <p>{s.body}</p>
              <div className="step__code">
                <code>
                  <span className="tok-prompt">$</span> {s.code}
                </code>
                <CopyButton text={s.code} />
              </div>
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
