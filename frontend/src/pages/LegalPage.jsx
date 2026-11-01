import { useEffect } from 'react'

export default function LegalPage({ title, updated, children }) {
  useEffect(() => {
    document.title = `${title} · Horizon`
    window.scrollTo(0, 0)
    return () => {
      document.title = 'Horizon'
    }
  }, [title])

  return (
    <section className="legal">
      <div className="container legal__inner">
        <a href="/" className="legal__back">← Back to home</a>
        <h1>{title}</h1>
        <p className="legal__updated">Last updated: {updated}</p>
        {children}
      </div>
    </section>
  )
}
