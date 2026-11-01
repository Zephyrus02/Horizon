import { REPO_URL } from '../links'

export default function Footer() {
  return (
    <footer className="footer">
      <div className="container footer__inner">
        <a href="/" className="brand">
          <img src="/logo.png" alt="" width="22" height="22" />
          <span>Horizon</span>
        </a>
        <nav className="footer__links" aria-label="Footer">
          <a href={REPO_URL}>GitHub</a>
          <a href={`${REPO_URL}/issues`}>Issues</a>
          <a href={`${REPO_URL}#readme`}>Docs</a>
          <a href="/privacy">Privacy</a>
          <a href="/terms">Terms</a>
        </nav>
        <p>© {new Date().getFullYear()} Horizon · MIT License</p>
      </div>
    </footer>
  )
}
