import Icon from './Icon'

const steps = [
  {
    icon: 'finder',
    title: 'Finder & your apps',
    body: 'QuickTime, VLC, editors — anything that reads files works unchanged.',
  },
  {
    icon: 'disk',
    title: 'Built-in macOS support',
    body: 'Your Mac treats your cloud as just another drive.',
  },
  {
    icon: 'cpu',
    title: 'Horizon',
    body: 'Fetches files in pieces and keeps recent ones nearby for speed.',
  },
  {
    icon: 'cloud',
    title: 'Your cloud',
    body: 'Files travel securely, straight to and from your provider.',
  },
]

const specs = [
  { term: 'Files open instantly', desc: 'Horizon grabs just the first few megabytes, so documents and videos open in under a fifth of a second.' },
  { term: 'Video plays smoothly', desc: 'It loads ahead of your player, so scrubbing through 4K footage never stutters.' },
  { term: 'Your disk stays in check', desc: 'Recently used files are kept for 24 hours, using at most 50 GB of space.' },
  { term: 'Saves happen in the background', desc: 'Changes upload a few seconds after you save, so you never wait on the network.' },
]

export default function HowItWorks() {
  return (
    <section className="section section--alt" id="how-it-works">
      <div className="container">
        <header className="section__head" data-reveal>
          <span className="eyebrow">How it works</span>
          <h2>A thin, native layer over a proven engine.</h2>
          <p>
            Horizon connects your cloud account to Finder using technology already built into your
            Mac. Your files never pass through anyone else&rsquo;s servers.
          </p>
        </header>

        <ol className="pipeline" data-reveal>
          {steps.map((s, i) => (
            <li key={s.title} className="pipeline__step" style={{ '--i': i }}>
              <span className="pipeline__node">
                <Icon name={s.icon} size={22} />
              </span>
              <h3>{s.title}</h3>
              <p>{s.body}</p>
            </li>
          ))}
        </ol>

        <div className="split">
          <div className="split__text" data-reveal>
            <h3>Tuned for you, out of the box.</h3>
            <p>
              Horizon comes pre-configured for fast opens, smooth video playback and gentle use of
              your cloud account. There is nothing to set up and no settings to tweak.
            </p>
          </div>
          <dl className="specs" data-reveal style={{ '--delay': '120ms' }}>
            {specs.map((x) => (
              <div key={x.term} className="specs__row">
                <dt>{x.term}</dt>
                <dd>{x.desc}</dd>
              </div>
            ))}
          </dl>
        </div>
      </div>
    </section>
  )
}
