import { useCountUp } from '../hooks/useScroll'

const stats = [
  { value: 151, unit: 'MB/s', label: 'Write into mount', detail: '2 GB copied in 14.18 s' },
  { value: 153, unit: 'MB/s', label: 'Read from mount', detail: '2 GB copied in 13.98 s' },
  { value: 5, unit: '%', label: 'CPU during transfer', detail: 'Measured on Apple Silicon' },
  { value: 150, unit: 'ms', prefix: '<', label: 'File open latency', detail: 'With 8 MB initial chunks' },
]

function Stat({ stat, index }) {
  const [ref, value] = useCountUp(stat.value)
  return (
    <div className="card stat" ref={ref} data-reveal style={{ '--delay': `${index * 100}ms` }}>
      <div className="stat__value">
        {stat.prefix}
        {Math.round(value)}
        <span>{stat.unit}</span>
      </div>
      <div className="stat__label">{stat.label}</div>
      <div className="stat__detail">{stat.detail}</div>
    </div>
  )
}

export default function Benchmarks() {
  return (
    <section className="section" id="performance">
      <div className="container">
        <header className="section__head" data-reveal>
          <span className="eyebrow">Performance</span>
          <h2>Fast enough to forget it&rsquo;s the cloud.</h2>
          <p>
            Verified during Stage 1 validation: multi-gigabyte copies, smooth playback in QuickTime
            and VLC, and clean recovery from a forced kill without Finder stalls.
          </p>
        </header>
        <div className="stats">
          {stats.map((s, i) => (
            <Stat key={s.label} stat={s} index={i} />
          ))}
        </div>
      </div>
    </section>
  )
}
