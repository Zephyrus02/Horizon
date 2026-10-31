import Icon from './Icon'

const features = [
  {
    icon: 'menubar',
    title: 'Lives in your menu bar',
    body: 'No Dock icon, no Cmd-Tab clutter. Horizon stays out of the way until you need it.',
  },
  {
    icon: 'finder',
    title: 'Native NFS mounting',
    body: 'Uses the NFS client built into macOS over localhost. No kernel extensions, no FUSE drivers.',
  },
  {
    icon: 'play',
    title: 'Stream on demand',
    body: 'Only the bytes you read are fetched, with read-ahead caching that keeps 4K scrubbing responsive.',
  },
  {
    icon: 'sync',
    title: 'Edit in place, sync later',
    body: 'Saves land instantly in a local chunk cache and upload to the cloud in the background.',
  },
  {
    icon: 'toggle',
    title: 'One-click control',
    body: 'Flip a toggle to connect, watch live status and transfers, and jump straight into Finder.',
  },
  {
    icon: 'shield',
    title: 'Safe teardown & recovery',
    body: 'Graceful unmounts, stale mounts cleared on launch, and no orphaned processes left behind.',
  },
]

export default function Features() {
  return (
    <section className="section" id="features">
      <div className="container">
        <header className="section__head" data-reveal>
          <span className="eyebrow">Features</span>
          <h2>Cloud storage that behaves like a disk.</h2>
          <p>
            Open, save and drag files exactly as you would on your Mac. Horizon handles the
            mounting, caching and syncing for you.
          </p>
        </header>

        <div className="features">
          {features.map((f, i) => (
            <article
              key={f.title}
              className="card feature"
              data-reveal
              style={{ '--delay': `${(i % 3) * 110}ms` }}
              onPointerMove={(e) => {
                const r = e.currentTarget.getBoundingClientRect()
                e.currentTarget.style.setProperty('--mx', `${e.clientX - r.left}px`)
                e.currentTarget.style.setProperty('--my', `${e.clientY - r.top}px`)
              }}
            >
              <span className="feature__icon">
                <Icon name={f.icon} size={22} />
              </span>
              <h3>{f.title}</h3>
              <p>{f.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}
