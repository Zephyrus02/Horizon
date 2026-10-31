import driveLogo from '../assets/drive_64.png'
import dropboxLogo from '../assets/dropbox_64.png'
import onedriveLogo from '../assets/onedrive_64.png'

const providers = [
  { name: 'Google Drive', logo: driveLogo },
  { name: 'Dropbox', logo: dropboxLogo },
  { name: 'OneDrive', logo: onedriveLogo },
]

export default function Providers() {
  return (
    <section className="providers" aria-label="Supported providers">
      <div className="container">
        <p className="providers__label" data-reveal>
          Connect every account you use, side by side
        </p>
        <ul className="providers__list">
          {providers.map((p, i) => (
            <li key={p.name} data-reveal style={{ '--delay': `${i * 90}ms` }}>
              <img src={p.logo} alt="" width="32" height="32" />
              {p.name}
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
