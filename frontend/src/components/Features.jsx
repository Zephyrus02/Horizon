import Icon from './Icon'

const features = [
  {
    icon: 'menubar',
    title: 'Lives in your menu bar',
    body: 'No Dock icon and no window to manage. Horizon stays out of the way until you need it.',
  },
  {
    icon: 'finder',
    title: 'Native NFS mounting',
    body: 'Built on the NFS client included with macOS. No kernel extensions or FUSE drivers to install.',
  },
  {
    icon: 'play',
    title: 'Stream on demand',
    body: 'Only the parts of a file you open are downloaded, with read-ahead that keeps 4K scrubbing responsive.',
  },
  {
    icon: 'sync',
    title: 'Edit in place, sync later',
    body: 'Saves land instantly in a local cache and upload to the cloud in the background.',
  },
  {
    icon: 'toggle',
    title: 'One-click control',
    body: 'Connect with a toggle, watch live transfer status, and jump straight into Finder.',
  },
  {
    icon: 'shield',
    title: 'Safe teardown and recovery',
    body: 'Graceful unmounts, stale mounts cleared on launch, and no orphaned processes left behind.',
  },
]

export default function Features() {
  return (
    <section className="section" id="features">
      <div className="container features-layout">
        <header className="features-head" data-reveal>
          <span className="eyebrow">Features</span>
          <h2>Cloud storage that behaves like a disk.</h2>
          <p>
            Open, save and drag files exactly as you would on your Mac. Horizon handles the
            mounting, caching and syncing for you.
          </p>
        </header>

        <ul className="features" data-reveal style={{ '--delay': '100ms' }}>
          {features.map((f) => (
            <li key={f.title} className="feature">
              <Icon name={f.icon} size={20} className="feature__icon" />
              <div>
                <h3>{f.title}</h3>
                <p>{f.body}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
