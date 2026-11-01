import { useCountUp } from '../hooks/useScroll'

const stats = [
  { value: 151, unit: 'MB/s', label: 'Write into mount', detail: '2 GB copied in 14.18 s' },
  { value: 153, unit: 'MB/s', label: 'Read from mount', detail: '2 GB copied in 13.98 s' },
  { value: 5, unit: '%', label: 'CPU during transfer', detail: 'Measured on Apple Silicon' },
  { value: 150, unit: 'ms', prefix: '< ', label: 'File open latency', detail: 'With 8 MB initial chunks' },
]

function Row({ stat }) {
  const [ref, value] = useCountUp(stat.value)
  return (
    <div className="metric" ref={ref}>
      <div className="metric__text">
        <dt>{stat.label}</dt>
        <dd>{stat.detail}</dd>
      </div>
      <div className="metric__value">
        {stat.prefix}
        {Math.round(value)}
        <span>{stat.unit}</span>
      </div>
    </div>
  )
}

export default function Benchmarks() {
  return (
    <section className="section" id="performance">
      <div className="container perf">
        <header className="perf__head" data-reveal>
          <span className="eyebrow">Performance</span>
          <h2>Fast enough to forget it&rsquo;s the cloud.</h2>
          <p>
            Verified during Stage 1 validation: multi-gigabyte copies, smooth playback in QuickTime
            and VLC, and clean recovery from a forced kill without Finder stalls.
          </p>
        </header>
        <dl className="metrics" data-reveal style={{ '--delay': '100ms' }}>
          {stats.map((s) => (
            <Row key={s.label} stat={s} />
          ))}
        </dl>
      </div>
    </section>
  )
}
