import { useParallax } from '../hooks/useScroll'
import { REPO_URL, RELEASES_URL } from '../links'
import Icon from './Icon'
import MenuBarMock from './MenuBarMock'

export default function Hero() {
  const stageRef = useParallax()

  return (
    <section className="hero" id="top">
      <div className="hero__glow" aria-hidden="true" />
      <div className="hero__stars" aria-hidden="true" />

      <div className="container hero__content">
        <a className="pill hero__pill" href={REPO_URL}>
          <span className="pill__dot" />
          Native macOS · Open source · Powered by rclone
          <Icon name="arrow" size={14} />
        </a>

        <h1 className="hero__title">
          Your cloud,
          <br />
          <span className="text-gradient">mounted like it&rsquo;s local.</span>
        </h1>

        <p className="hero__lede">
          Horizon lives in your menu bar and mounts Google Drive, Dropbox and OneDrive straight
          into Finder. Stream 4K video on demand, edit files in place, and let uploads sync quietly
          in the background.
        </p>

        <div className="hero__ctas">
          <a className="btn btn--primary btn--lg" href={RELEASES_URL}>
            <Icon name="download" size={18} />
            Download for macOS
          </a>
          <a className="btn btn--ghost btn--lg" href={REPO_URL}>
            <Icon name="github" size={18} />
            View on GitHub
          </a>
        </div>
        <p className="hero__meta">Requires macOS Sonoma 14.0 or later · Apple Silicon</p>
      </div>

      <div className="hero__stage container" ref={stageRef}>
        <MenuBarMock />
      </div>
    </section>
  )
}
