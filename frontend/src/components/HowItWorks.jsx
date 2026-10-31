import Icon from './Icon'

const steps = [
  {
    icon: 'finder',
    title: 'Finder & your apps',
    body: 'QuickTime, VLC, editors — anything that reads files works unchanged.',
  },
  {
    icon: 'disk',
    title: 'macOS NFS client',
    body: 'The built-in client talks to a local server on 127.0.0.1.',
  },
  {
    icon: 'cpu',
    title: 'rclone + VFS cache',
    body: 'Chunked reads, read-ahead and write-back, supervised by Horizon.',
  },
  {
    icon: 'cloud',
    title: 'Your cloud',
    body: 'Data flows over HTTPS range requests, straight to the provider.',
  },
]

export default function HowItWorks() {
  return (
    <section className="section section--alt" id="how-it-works">
      <div className="container">
        <header className="section__head" data-reveal>
          <span className="eyebrow">How it works</span>
          <h2>A thin, native layer over a proven engine.</h2>
          <p>
            Horizon supervises a tuned <code>rclone nfsmount</code> process and the macOS NFS
            client does the rest. Your files never pass through anyone else&rsquo;s servers.
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
            <h3>Tuned defaults, out of the box.</h3>
            <p>
              Every mount ships with flags tuned for instant opens, smooth sequential playback
              and burst-friendly API usage — no config files to hand-edit.
            </p>
            <ul className="checklist">
              <li>
                <Icon name="check" size={16} /> 8 MB initial chunks for sub-150 ms opens
              </li>
              <li>
                <Icon name="check" size={16} /> 256 MB read-ahead for 4K video
              </li>
              <li>
                <Icon name="check" size={16} /> 50 GB capped disk cache, retained for 24 h
              </li>
              <li>
                <Icon name="check" size={16} /> 5 s write-back before uploads begin
              </li>
            </ul>
          </div>
          <div className="code-window" data-reveal style={{ '--delay': '120ms' }}>
            <div className="code-window__bar">
              <i />
              <i />
              <i />
              <span>rclone nfsmount</span>
            </div>
            <pre>
              <code>
                <span className="tok-cmd">rclone nfsmount</span> gdrive: ~/GDrive \{'\n'}
                {'  '}<span className="tok-flag">--vfs-cache-mode</span> full \{'\n'}
                {'  '}<span className="tok-flag">--vfs-read-chunk-size</span> 8M \{'\n'}
                {'  '}<span className="tok-flag">--vfs-read-chunk-streams</span> 4 \{'\n'}
                {'  '}<span className="tok-flag">--vfs-read-ahead</span> 256M \{'\n'}
                {'  '}<span className="tok-flag">--vfs-cache-max-size</span> 50G \{'\n'}
                {'  '}<span className="tok-flag">--vfs-write-back</span> 5s \{'\n'}
                {'  '}<span className="tok-flag">--dir-cache-time</span> 72h \{'\n'}
                {'  '}<span className="tok-flag">--drive-chunk-size</span> 64M \{'\n'}
                {'  '}<span className="tok-flag">--rc</span> 127.0.0.1:5572
              </code>
            </pre>
          </div>
        </div>
      </div>
    </section>
  )
}
